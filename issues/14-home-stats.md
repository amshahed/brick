# Issue #14 — Home screen stats

## Goal
4 stats on the Home tab: today, this week, quota used, on-quota streak.

## Design

### `StatsEngine` (Brick/Models)
Pure SwiftData queries + calendar math. No published state — views own the refresh cadence.

```
struct StatsEngine {
    let context: ModelContext

    func blockedToday(now: Date = .now) -> TimeInterval
    func blockedThisWeek(now: Date = .now) -> TimeInterval
    func quotaUsed(now: Date = .now) throws -> TimeInterval   // 0...600
    func onQuotaStreak(now: Date = .now) -> Int
}
```

- `blockedToday/Week` reuses the clamping approach from `NotificationService.totalBlockedToday`: iterate `BlockSession`s, compute overlap with the day/week window.
- `quotaUsed` = `quotaCap - BreakQuotaEngine.remainingQuota(at:)`. If no open session → 0.
- `onQuotaStreak`: walk backward from today. For each day D:
  - Fetch `BreakRecord`s where `startTime` falls on D.
  - A day is "overage" if any record has `wasOverage == true`.
  - A day is "on-quota" if it has no overage records. (Days with zero records count as on-quota — neutral.)
  - Break the walk on the first overage day. Streak length = number of consecutive on-quota days ending today (or yesterday if today has no records yet).

### `StatsCard` (Brick/Views/Home)
- 2×2 grid of stat tiles using `LazyVGrid`:
  - "Today" → hr/min
  - "This week" → hr/min
  - "Break quota" → `Xm / 10m`
  - "Streak" → `<N> day<s>`
- Refresh on `TimelineView(.periodic(from: .now, by: 60))` OR reuse `HomeTab`'s existing 1s timer — prefer 1s since HomeTab already ticks.
- Passes computed values from HomeTab so the engine is instantiated once.

### HomeTab wiring
- Keep StatsCard visible regardless of active-block state (it shows zero otherwise).
- Place below idleHero / ActiveBlockCard row, above any nudges.

### Tests
`StatsEngineTests`:
- `testBlockedTodayWithOpenSession` — open session → counts up to `now`
- `testBlockedThisWeekClampsToWeekStart`
- `testQuotaUsedReflectsClosedBreaks`
- `testStreakCountsConsecutiveOnQuotaDays`
- `testStreakResetsAfterOverage`
- `testStreakIgnoresDaysWithoutBlocks` (neutral)

## Files touched
- NEW `Brick/Models/StatsEngine.swift`
- NEW `Brick/Views/Home/StatsCard.swift`
- EDIT `Brick/Views/Home/HomeTab.swift` (wire in)
- NEW `BrickTests/StatsEngineTests.swift`
