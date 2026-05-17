# Issue #29 — Ongoing break card on home

## Problem
While a break is running, the home screen has no live countdown. The "View break" button is the only affordance, and it doesn't show the time. The user has to open the break sheet to see how much break time remains.

## Solution
Add a compact `ActiveBreakCard` above `ActiveBlockCard` on the home screen, visible only when `controller.active != nil`. Tapping the card opens the break sheet.

## Design
```
┌─────────────────────────────────────────┐
│ ⏸  BREAK RUNNING                        │
│    Tap to view what's unblocked  4:23 › │
└─────────────────────────────────────────┘
```

- Pause icon in an accent-muted circle (mirrors `ActiveBlockCard`'s icon treatment).
- "BREAK RUNNING" eyebrow + secondary hint line.
- Big monospaced countdown on the right.
- Chevron on the far right as a tap-target affordance.
- `cardSurface()` background to match the rest of the home cards.
- Whole card is a `.plain` Button — tap opens `BreakSheet`.

## Implementation

### New file
- `Brick/Views/Home/ActiveBreakCard.swift` — already drafted in this branch. Wraps a `TimelineView(.periodic(from: active.startedAt, by: 1))` so the countdown ticks without re-creating a `Timer.publish` subscription (same pattern as `ActiveBreakView` after #25).

### Edits in `HomeTab.swift`
Around line 52-62 (current `if hasActiveBlock { ActiveBlockCard …; breakButton } else { idleHero }`):

```swift
if hasActiveBlock {
    if let active = controller.active {
        ActiveBreakCard(active: active) {
            breakPreselect = nil
            showingBreak = true
        }
    }
    ActiveBlockCard(...)
    if controller.active == nil {
        breakButton
    }
} else {
    idleHero
}
```

The conditional around `breakButton` removes the duplicate "View break" affordance while the card is showing. When the break ends, `controller.active` becomes nil and the regular `breakButton` returns (so the user can start another break if quota allows).

## Acceptance
- [x] `ActiveBreakCard` component exists
- [ ] Wired into `HomeTab` above `ActiveBlockCard`
- [ ] "View break" button hidden while card is showing
- [ ] Build succeeds for the Brick scheme

## Out of scope
- Cosmetic changes to the break sheet itself.
- Any change to the active-break view (`ActiveBreakView`) — the card is purely a home-screen surface.
