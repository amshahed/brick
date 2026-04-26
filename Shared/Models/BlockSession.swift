import Foundation
import SwiftData

@Model
final class BlockSession {
    @Attribute(.unique) var id: UUID
    var schedule: Schedule?
    var oneShotBlock: OneShotBlock?
    var actualStart: Date
    var actualEnd: Date?
    var coldStartEnd: Date?
    var scheduledEnd: Date?
    var totalBreakTime: TimeInterval
    var overageTime: TimeInterval
    var extensionApplied: TimeInterval

    init(
        id: UUID = UUID(),
        schedule: Schedule? = nil,
        oneShotBlock: OneShotBlock? = nil,
        actualStart: Date = .now,
        actualEnd: Date? = nil,
        coldStartEnd: Date? = nil,
        scheduledEnd: Date? = nil,
        totalBreakTime: TimeInterval = 0,
        overageTime: TimeInterval = 0,
        extensionApplied: TimeInterval = 0
    ) {
        self.id = id
        self.schedule = schedule
        self.oneShotBlock = oneShotBlock
        self.actualStart = actualStart
        self.actualEnd = actualEnd
        self.coldStartEnd = coldStartEnd
        self.scheduledEnd = scheduledEnd
        self.totalBreakTime = totalBreakTime
        self.overageTime = overageTime
        self.extensionApplied = extensionApplied
    }

    var isOpen: Bool { actualEnd == nil }

    /// Natural end + any extension accrued from overage breaks.
    var effectiveEnd: Date? {
        scheduledEnd.map { $0.addingTimeInterval(extensionApplied) }
    }

    /// True when the source's natural window has ended but the session's
    /// extension tail has not. Used by reconcile + union to keep shield on.
    func isInExtensionTail(at instant: Date) -> Bool {
        guard let scheduledEnd, let effectiveEnd else { return false }
        return instant >= scheduledEnd && instant < effectiveEnd
    }
}
