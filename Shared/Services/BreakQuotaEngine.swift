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
    static let windowDuration: TimeInterval = 60 * 60
    static let quotaCap: TimeInterval = 10 * 60
    static let coldStartDuration: TimeInterval = 25 * 60
    static let overageHardCap: TimeInterval = 15 * 60
    static let overagePenaltyMultiplier: Double = 2

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
            wasOverage: isOverage,
            plannedDuration: plannedDuration
        )
        context.insert(record)
        try context.save()
        return record
    }

    func endBreak(_ record: BreakRecord, at instant: Date? = nil) throws {
        let now = instant ?? clock.now
        let endTime = now
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
        let descriptor = FetchDescriptor<BreakRecord>(
            predicate: #Predicate { record in
                record.endTime == nil || record.endTime! >= windowStart
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
