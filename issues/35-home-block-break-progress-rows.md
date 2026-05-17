# Issue #35 — Home progress rows for block/break

## Decisions (confirmed)
- Q1: **Elapsed-forward** progress.
- Q2: **One row per active block** (no merging).
- Q3: When quota refreshes after the block ends, show **"Block ends in X — no break possible"** in place of the quota-exhausted countdown.
- Tap on any row → break sheet.
- No "Take a break" button on home.
- When a break is active, hide block rows; the break row owns the space.

## Layout

### Block active, no break
For each open `BlockSession`:
```
┌─────────────────────────────────────┐
│ Morning Focus                       │
│ ████░░░░░░░░░░░░  1:00:23           │
│ 2 apps · 1 category                 │
└─────────────────────────────────────┘
```
- Progress bar = `elapsed / (scheduledEnd - actualStart)`.
- Elapsed timer `h:mm:ss`.
- Subtitle: blocklist's `selectionSummary`.
- One-shots also get an `×` cancel button (preserves today's only-cancellation-affordance).

### Break active
Existing `ActiveBreakCard` stays (countdown + tap). Block rows are hidden.

### Break sheet (BreakPickerView)
- `.coldStart` / `.quotaExhausted` already render their countdowns inline — no change.
- **New banner case**: if `.quotaExhausted(availableAt:)` and `availableAt > blockEnd`, replace the existing banner with "Block ends in X — no break possible." Source the block end from max of active schedules' `currentOccurrenceEnd` and active one-shots' `expiresAt`.
- Cap `durationMinutes` upper bound to `min(quotaMinutes, floor((blockEnd - now) / 60))` so the picker never lets you pick a break longer than the block.

## Implementation

### New: `Brick/Views/Home/ActiveBlockTimerRow.swift`
- Props: `name`, `actualStart`, `scheduledEnd`, `subtitle`, `onCancel: (() -> Void)?`, `onTap`.
- `TimelineView(.periodic(from: actualStart, by: 1))` drives the redraw.
- Whole row is a `Button` (.plain style). Inner `×` is its own `Button` (.plain).

### Edits

**`Brick/Views/Home/HomeTab.swift`**
- Replace the `if hasActiveBlock` block:
  ```swift
  if let active = controller.active {
      ActiveBreakCard(active: active) { … }
  } else if !openSessions.isEmpty {
      ForEach(openSessions) { session in
          ActiveBlockTimerRow(
              name: session.schedule?.name ?? session.oneShotBlock?.blocklist?.name ?? "Block",
              actualStart: session.actualStart,
              scheduledEnd: session.effectiveEnd ?? Date.now.addingTimeInterval(60),
              subtitle: session.schedule?.blocklist?.selectionSummary
                  ?? session.oneShotBlock?.blocklist?.selectionSummary ?? "",
              onCancel: session.oneShotBlock.map { os in { requestCancel(os) } },
              onTap: { breakPreselect = nil; showingBreak = true }
          )
      }
  } else {
      idleHero
  }
  ```
- Drop `breakButton` entirely.
- Add a `@Query private var openSessions: [BlockSession]` filtered to `actualEnd == nil`.
- `refreshAvailability` and `breakHintNote` go away from home; they live on the break sheet now.

**`Brick/Views/Break/BreakPickerView.swift`**
- Compute `blockEnd: Date?` from active sources.
- New banner case for "block ends before quota refreshes".
- Clamp `maxMinutes` to also respect `blockEnd`.

### Removed
- `ActiveBlockCard.swift` no longer referenced from home. Leave the file (in case another caller appears later) or delete it — delete to keep things tidy.

## Out of scope
- Cosmetic redesign of the break sheet itself.
- Quota arithmetic (#36).

## Acceptance
- [ ] Block active → one progress-bar row per active block on home
- [ ] Elapsed timer ticks every second
- [ ] Tap → break sheet
- [ ] One-shot's `×` still cancels (with passcode gate when locked)
- [ ] Break active → block rows hidden, only break card shown
- [ ] Break sheet picker caps duration at `min(quota, block-remaining)`
- [ ] When quota refreshes after block ends, banner says "Block ends in X — no break possible"
