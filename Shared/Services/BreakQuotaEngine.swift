import Foundation
import SwiftData

enum BreakAvailability: Equatable {
    case allowed(remainingQuota: TimeInterval)
    case coldStart(endsAt: Date)
    case quotaExhausted(availableAt: Date)
    case overageLockout
    case noActiveBlock
}

struct BreakQuotaEngine {
    /// PRD values — used in production and in unit tests.
    static let productionWindowDuration: TimeInterval = 60 * 60
    static let productionQuotaCap: TimeInterval = 10 * 60
    static let productionColdStartDuration: TimeInterval = 25 * 60
    static let productionOverageHardCap: TimeInterval = 15 * 60

    /// Scaled values for manual debug testing on a real device — keep the
    /// shape of the PRD spec but compress the timeline so a full break +
    /// cold-start + window-decay cycle plays out in minutes.
    static let debugWindowDuration: TimeInterval = 3 * 60
    static let debugQuotaCap: TimeInterval = 2 * 60
    static let debugColdStartDuration: TimeInterval = 2 * 60
    static let debugOverageHardCap: TimeInterval = 3 * 60

    /// Live values consulted at every decision point. Mutated only by
    /// `applyDebugTimings(_:)` at app launch (DEBUG builds) — production
    /// always reads the PRD values.
    static var windowDuration: TimeInterval = productionWindowDuration
    static var quotaCap: TimeInterval = productionQuotaCap
    static var coldStartDuration: TimeInterval = productionColdStartDuration
    static var overageHardCap: TimeInterval = productionOverageHardCap
    static let overagePenaltyMultiplier: Double = 2

    /// UserDefaults key for the DEBUG-only Settings toggle. Reading is
    /// safe in production; the toggle UI is only built in DEBUG.
    static let debugFastTimingsKey = "brick.debug.fastBreakTimings"

    /// Swap the live constants between production and debug values. Call
    /// once at app launch after reading the persisted preference.
    static func applyDebugTimings(_ enabled: Bool) {
        windowDuration = enabled ? debugWindowDuration : productionWindowDuration
        quotaCap = enabled ? debugQuotaCap : productionQuotaCap
        coldStartDuration = enabled ? debugColdStartDuration : productionColdStartDuration
        overageHardCap = enabled ? debugOverageHardCap : productionOverageHardCap
    }

    let context: ModelContext
    let clock: Clock

    init(context: ModelContext, clock: Clock = SystemClock()) {
        self.context = context
        self.clock = clock
    }

    func canStartBreak(at instant: Date? = nil) throws -> BreakAvailability {
        let now = instant ?? clock.now
        guard let session = try openSession() else { return .noActiveBlock }

        if !overageAllowed(for: session) { return .overageLockout }
        if let coldEnd = session.coldStartEnd, now < coldEnd {
            return .coldStart(endsAt: coldEnd)
        }

        let records = try recordsInWindow(at: now)
        let used = totalOverlap(records: records, at: now)
        let remaining = Self.quotaCap - used
        if remaining > 0 {
            return .allowed(remainingQuota: remaining)
        }
        return .quotaExhausted(availableAt: earliestDecay(records: records, at: now))
    }

    func remainingQuota(at instant: Date? = nil) throws -> TimeInterval {
        let now = instant ?? clock.now
        let used = try totalOverlap(records: recordsInWindow(at: now), at: now)
        return max(0, Self.quotaCap - used)
    }

    @discardableResult
    func startBreak(
        appTokenData: Data,
        targetKind: BreakRecord.TargetKind = .app,
        plannedDuration: TimeInterval = BreakQuotaEngine.quotaCap,
        isOverage: Bool = false,
        at instant: Date? = nil
    ) throws -> BreakRecord {
        let now = instant ?? clock.now
        let session = try openSession()
        let record = BreakRecord(
            blockSession: session,
            startTime: now,
            appTokenData: appTokenData,
            targetKind: targetKind,
            wasOverage: isOverage,
            plannedDuration: plannedDuration
        )
        context.insert(record)
        try context.save()
        return record
    }

    func endBreak(_ record: BreakRecord, at instant: Date? = nil) throws {
        let now = instant ?? clock.now
        // Charge quota at minute-ceiling precision: a 1-second break costs
        // 1 min, 1m 20s costs 2 min, 2m 0s costs 2 min. Capped at the
        // planned end so timer-jitter past plannedEnd doesn't over-charge.
        // Decision: refund unused minutes when ending early. (#36)
        let rawDuration = max(0, now.timeIntervalSince(record.startTime))
        let roundedDuration = ceil(rawDuration / 60) * 60
        let rounded = record.startTime.addingTimeInterval(roundedDuration)
        let endTime = min(rounded, record.plannedEnd)
        record.endTime = endTime
        let duration = endTime.timeIntervalSince(record.startTime)

        if let session = record.blockSession {
            session.totalBreakTime += duration
            if record.wasOverage {
                let clamped = min(session.overageTime + duration, Self.overageHardCap)
                session.overageTime = clamped
                session.extensionApplied = clamped * Self.overagePenaltyMultiplier
            }
        }
        try context.save()
    }

    func overageAllowed(for session: BlockSession) -> Bool {
        session.overageTime < Self.overageHardCap
    }

    // MARK: - Internal helpers

    func openSession() throws -> BlockSession? {
        var descriptor = FetchDescriptor<BlockSession>(
            predicate: #Predicate { $0.actualEnd == nil },
            sortBy: [SortDescriptor(\.actualStart, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func recordsInWindow(at now: Date) throws -> [BreakRecord] {
        let windowStart = now.addingTimeInterval(-Self.windowDuration)
        let sentinel = Date.distantFuture
        let descriptor = FetchDescriptor<BreakRecord>(
            predicate: #Predicate { record in
                (record.endTime ?? sentinel) >= windowStart
            }
        )
        return try context.fetch(descriptor)
    }

    func totalOverlap(records: [BreakRecord], at now: Date) -> TimeInterval {
        let windowStart = now.addingTimeInterval(-Self.windowDuration)
        return records.reduce(0) { $0 + $1.overlap(in: windowStart, now: now) }
    }

    func earliestDecay(records: [BreakRecord], at now: Date) -> Date {
        // When the oldest-in-window break falls out of the window.
        let windowStart = now.addingTimeInterval(-Self.windowDuration)
        let ends = records
            .map { $0.endTime ?? now }
            .filter { $0 >= windowStart }
            .sorted()
        guard let oldest = ends.first else { return now }
        return oldest.addingTimeInterval(Self.windowDuration)
    }
}
