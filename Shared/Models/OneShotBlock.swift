import Foundation
import SwiftData

@Model
final class OneShotBlock {
    @Attribute(.unique) var id: UUID
    var blocklist: Blocklist?
    var startedAt: Date
    var expiresAt: Date

    init(
        id: UUID = UUID(),
        blocklist: Blocklist,
        startedAt: Date = .now,
        duration: TimeInterval
    ) {
        self.id = id
        self.blocklist = blocklist
        self.startedAt = startedAt
        self.expiresAt = startedAt.addingTimeInterval(duration)
    }

    var isActive: Bool { Date.now < expiresAt }

    var remaining: TimeInterval {
        max(0, expiresAt.timeIntervalSinceNow)
    }
}
