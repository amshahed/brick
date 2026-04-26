import FamilyControls
import Foundation
import ManagedSettings
import SwiftData
import SwiftUI

/// Single binding target for the break flow UI. Coordinates:
/// - BreakQuotaEngine for gating + persistence
/// - ShieldManager for per-app shield override
/// - a local timer for countdown + auto-end
/// - ScheduleEngine.applyCurrentUnion for computing the underlying union
@MainActor
final class BreakSessionController: ObservableObject {

    struct ActiveBreak: Identifiable, Equatable {
        let id: UUID
        let appTokenData: Data
        let appToken: ApplicationToken
        let startedAt: Date
        let plannedEnd: Date
    }

    @Published private(set) var active: ActiveBreak?

    private let context: ModelContext
    private let engine: BreakQuotaEngine
    private let scheduleEngine: ScheduleEngine
    private let shield: ShieldManager
    private let clock: Clock
    private var expiryTask: Task<Void, Never>?

    init(
        context: ModelContext,
        clock: Clock = SystemClock(),
        shield: ShieldManager = ShieldManager()
    ) {
        self.context = context
        self.clock = clock
        self.shield = shield
        self.engine = BreakQuotaEngine(context: context, clock: clock)
        self.scheduleEngine = ScheduleEngine(context: context, shield: shield)
        refreshFromStore()
    }

    // MARK: - Queries

    func availability() throws -> BreakAvailability {
        try engine.canStartBreak()
    }

    // MARK: - Start

    func start(
        app: ApplicationToken,
        duration: TimeInterval,
        isOverage: Bool = false
    ) throws {
        let tokenData = try PropertyListEncoder().encode(app)
        let availability = try engine.canStartBreak()
        let cappedDuration: TimeInterval
        if isOverage {
            guard case .quotaExhausted = availability else {
                throw BreakControllerError.notAllowed(availability)
            }
            guard let session = try engine.openSession() else {
                throw BreakControllerError.notAllowed(.noActiveBlock)
            }
            let remaining = BreakQuotaEngine.overageHardCap - session.overageTime
            guard remaining > 0 else {
                throw BreakControllerError.notAllowed(.overageLockout)
            }
            cappedDuration = min(duration, remaining)
        } else {
            switch availability {
            case .allowed(let remaining):
                cappedDuration = min(duration, remaining)
            case .coldStart, .quotaExhausted, .noActiveBlock, .overageLockout:
                throw BreakControllerError.notAllowed(availability)
            }
        }
        guard cappedDuration > 0 else {
            throw BreakControllerError.notAllowed(availability)
        }

        let record = try engine.startBreak(
            appTokenData: tokenData,
            plannedDuration: cappedDuration,
            isOverage: isOverage
        )
        applyOverride(excluding: app)

        let active = ActiveBreak(
            id: record.id,
            appTokenData: tokenData,
            appToken: app,
            startedAt: record.startTime,
            plannedEnd: record.plannedEnd
        )
        self.active = active
        scheduleExpiry(at: active.plannedEnd, recordID: active.id)
        NotificationService.shared.scheduleBreakExpiring(
            breakID: active.id,
            firesAt: active.plannedEnd
        )
    }

    // MARK: - End

    func endEarly() {
        guard let active else { return }
        closeRecord(id: active.id)
    }

    /// Re-reads the store and reconciles local state with persistence.
    /// Call on scene activation and when the break sheet appears.
    func refreshFromStore() {
        expiryTask?.cancel()
        expiryTask = nil

        let open = try? context.fetch(
            FetchDescriptor<BreakRecord>(predicate: #Predicate { $0.endTime == nil })
        )
        guard let record = open?.first else {
            active = nil
            clearOverride()
            return
        }

        // Block ended under us? Close the record, clear override.
        if record.blockSession?.actualEnd != nil {
            closeRecord(id: record.id)
            return
        }
        // Past planned end? Close now (self-heal).
        if clock.now >= record.plannedEnd {
            closeRecord(id: record.id)
            return
        }

        guard let token = try? PropertyListDecoder()
            .decode(ApplicationToken.self, from: record.appTokenData) else {
            closeRecord(id: record.id)
            return
        }
        let active = ActiveBreak(
            id: record.id,
            appTokenData: record.appTokenData,
            appToken: token,
            startedAt: record.startTime,
            plannedEnd: record.plannedEnd
        )
        self.active = active
        applyOverride(excluding: token)
        scheduleExpiry(at: active.plannedEnd, recordID: active.id)
    }

    // MARK: - Internals

    private func scheduleExpiry(at date: Date, recordID: UUID) {
        expiryTask?.cancel()
        let delay = max(0, date.timeIntervalSince(clock.now))
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.closeRecord(id: recordID) }
        }
    }

    private func closeRecord(id: UUID) {
        expiryTask?.cancel()
        expiryTask = nil
        NotificationService.shared.cancelBreakExpiring(breakID: id)
        let descriptor = FetchDescriptor<BreakRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let record = try? context.fetch(descriptor).first, record.endTime == nil {
            try? engine.endBreak(record)
            if record.wasOverage, let session = record.blockSession {
                try? scheduleEngine.registerExtension(for: session)
                NotificationService.shared.overageApplied(
                    breakID: record.id,
                    overage: session.overageTime,
                    extensionApplied: session.extensionApplied
                )
            }
        }
        active = nil
        clearOverride()
    }

    private func applyOverride(excluding app: ApplicationToken) {
        guard let active = try? scheduleEngine.applyCurrentUnion() else { return }
        let selections = active.schedules.compactMap { $0.blocklist?.selection }
            + active.oneShots.compactMap { $0.blocklist?.selection }
        let union = FamilyActivitySelection.union(selections)
        shield.apply(union: union, except: [app])
    }

    private func clearOverride() {
        _ = try? scheduleEngine.applyCurrentUnion()
    }
}

enum BreakControllerError: Error, Equatable {
    case notAllowed(BreakAvailability)
}
