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

    /// Duration of this break charged against the rolling window.
    ///
    /// For closed records we count the full [startTime, endTime] span, even
    /// when `endTime` is in the future. `endBreak()` rounds an early end up
    /// to the next minute (#36), so a 5-s actual break sets endTime to
    /// startTime + 60s and charges 60s to the session. Clamping to `now`
    /// here would have undercounted that charge until the wall-clock caught
    /// up — letting the user start another break against quota that had
    /// already been spent.
    func overlap(in windowStart: Date, now: Date) -> TimeInterval {
        let effectiveStart = max(startTime, windowStart)
        let effectiveEnd: Date
        if let endTime {
            effectiveEnd = endTime
        } else {
            effectiveEnd = now
        }
        return max(0, effectiveEnd.timeIntervalSince(effectiveStart))
    }
}
