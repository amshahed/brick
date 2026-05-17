import Foundation

/// What the break sheet should display about availability. Decoupled from
/// the view so the banner-decision tree can be unit-tested without
/// constructing a SwiftData context or a SwiftUI environment. (#37)
enum BreakBanner: Equatable {
    /// A break can start. `maxMinutes` is the upper bound for the duration
    /// stepper, already clamped to whichever is smaller — the user's
    /// remaining hourly quota or the time left in the active block.
    case allowed(maxMinutes: Int)

    case coldStart(endsAt: Date)
    case quotaExhausted(availableAt: Date)

    /// The block is about to end (or has < 1 min left) — no useful break
    /// can be taken. Covers two paths:
    /// 1. Quota *is* available but the block ends so soon there's no time.
    /// 2. Quota is exhausted and refreshes only after the block ends.
    case blockEnding(blockEnd: Date)

    case overageLockout
    case noActiveBlock
}

enum BreakBannerPresenter {
    /// Fold the engine's raw availability + the latest block-end into a
    /// single banner state. Pure; no side effects.
    static func banner(
        availability: BreakAvailability,
        blockEnd: Date?,
        now: Date
    ) -> BreakBanner {
        // Whole-minute count of remaining block time. `Int.max` when there's
        // no active block — equivalent to "no upper bound from this dim".
        let blockRemainingMin: Int = {
            guard let blockEnd else { return Int.max }
            return max(0, Int(blockEnd.timeIntervalSince(now) / 60))
        }()

        switch availability {
        case .allowed(let remainingQuota):
            // < 1 min of block left → no break is meaningful.
            if let blockEnd, blockRemainingMin < 1 {
                return .blockEnding(blockEnd: blockEnd)
            }
            let quotaMin = max(1, Int(remainingQuota / 60))
            return .allowed(maxMinutes: min(quotaMin, blockRemainingMin))

        case .quotaExhausted(let availableAt):
            // Quota refreshes only after the block ends → no break possible.
            if let blockEnd, availableAt > blockEnd {
                return .blockEnding(blockEnd: blockEnd)
            }
            return .quotaExhausted(availableAt: availableAt)

        case .coldStart(let endsAt):
            return .coldStart(endsAt: endsAt)
        case .overageLockout:
            return .overageLockout
        case .noActiveBlock:
            return .noActiveBlock
        }
    }
}
