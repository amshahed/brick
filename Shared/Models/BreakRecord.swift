import Foundation
import SwiftData

@Model
final class BreakRecord {
    @Attribute(.unique) var id: UUID
    var blockSession: BlockSession?
    var startTime: Date
    var endTime: Date?
    var appTokenData: Data
    var wasOverage: Bool
    var plannedDuration: TimeInterval

    init(
        id: UUID = UUID(),
        blockSession: BlockSession?,
        startTime: Date,
        endTime: Date? = nil,
        appTokenData: Data,
        wasOverage: Bool = false,
        plannedDuration: TimeInterval = BreakQuotaEngine.quotaCap
    ) {
        self.id = id
        self.blockSession = blockSession
        self.startTime = startTime
        self.endTime = endTime
        self.appTokenData = appTokenData
        self.wasOverage = wasOverage
        self.plannedDuration = plannedDuration
    }

    var plannedEnd: Date { startTime.addingTimeInterval(plannedDuration) }

    var isOpen: Bool { endTime == nil }

    /// Duration of this break that falls inside [windowStart, now].
    func overlap(in windowStart: Date, now: Date) -> TimeInterval {
        let end = endTime ?? now
        let effectiveStart = max(startTime, windowStart)
        let effectiveEnd = min(end, now)
        return max(0, effectiveEnd.timeIntervalSince(effectiveStart))
    }
}
