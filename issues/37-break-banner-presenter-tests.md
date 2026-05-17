# Issue #37 — Unit tests for break-sheet gating logic

## Problem
#35 shipped without unit tests for the banner-decision logic. Pure-logic gaps:

- `blockEnd` computation
- `maxMinutes = min(quota, blockRemaining)` clamping
- "Block ends before quota refreshes" / "Block ending" banner triggers

## Plan
Extract the decision into a pure presenter and unit-test it.

### New file
`Shared/Services/BreakBannerPresenter.swift`:

```swift
enum BreakBanner: Equatable {
    case allowed(maxMinutes: Int)
    case coldStart(endsAt: Date)
    case quotaExhausted(availableAt: Date)
    case blockEnding(blockEnd: Date)
    case overageLockout
    case noActiveBlock
}

enum BreakBannerPresenter {
    static func banner(
        availability: BreakAvailability,
        blockEnd: Date?,
        now: Date
    ) -> BreakBanner
}
```

Logic:
- `.allowed(remaining)` with `blockEnd` < 1 min → `.blockEnding(blockEnd!)`
- `.allowed(remaining)` otherwise → `.allowed(maxMinutes: min(quotaMin, blockRemainingMin))`
- `.quotaExhausted(at)` where `at > blockEnd` → `.blockEnding(blockEnd!)`
- `.quotaExhausted(at)` otherwise → pass-through
- `.coldStart`, `.overageLockout`, `.noActiveBlock` → pass-through

### View edit
`BreakPickerView`:
- Drop private `blockEnd` / `blockRemainingMinutes` / `maxMinutes`.
- Add a derived `banner` that calls into the presenter using a `blockEnd` helper.
- `availabilityBanner` and `maxMinutes` consume the `BreakBanner` enum.

### Tests
`BrickTests/BreakBannerPresenterTests.swift`:
1. allowed, no blockEnd → `.allowed` unclamped
2. allowed, plenty of block time, quota smaller → `.allowed` clamped to quota
3. allowed, block has < 1 min left → `.blockEnding`
4. quotaExhausted, availableAt before blockEnd → `.quotaExhausted` pass-through
5. quotaExhausted, availableAt after blockEnd → `.blockEnding`
6. quotaExhausted, no blockEnd → `.quotaExhausted` pass-through
7. coldStart → pass-through
8. overageLockout → pass-through
9. noActiveBlock → pass-through

## Acceptance
- [ ] All 9 tests pass
- [ ] BreakPickerView contains no banner logic (just enum-to-view mapping)
- [ ] Existing test suites unchanged
