import Foundation
import SwiftData

@Model
final class BreakRecord {
    @Attribute(.unique) var id: UUID
    var blockSession: BlockSession?
    var startTime: Date
    var endTime: Date?
    /// Encoded `ApplicationToken` when `targetKind == .app`, encoded
    /// `ActivityCategoryToken` when `targetKind == .category`. Stored as
    /// opaque bytes so the model stays SwiftData-friendly.
    var appTokenData: Data
    /// "app" or "category". Defaults to "app" so existing rows keep the
    /// per-app interpretation across the additive schema change.
    var targetKindRaw: String = TargetKind.app.rawValue
    var wasOverage: Bool
    var plannedDuration: TimeInterval

    init(
        id: UUID = UUID(),
        blockSession: BlockSession?,
        startTime: Date,
        endTime: Date? = nil,
        appTokenData: Data,
        targetKind: TargetKind = .app,
        wasOverage: Bool = false,
        plannedDuration: TimeInterval = BreakQuotaEngine.quotaCap
    ) {
        self.id = id
        self.blockSession = blockSession
        self.startTime = startTime
        self.endTime = endTime
        self.appTokenData = appTokenData
        self.targetKindRaw = targetKind.rawValue
        self.wasOverage = wasOverage
        self.plannedDuration = plannedDuration
    }

    enum TargetKind: String {
        case app
        case category
    }

    var targetKind: TargetKind {
        get { TargetKind(rawValue: targetKindRaw) ?? .app }
        set { targetKindRaw = newValue.rawValue }
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
