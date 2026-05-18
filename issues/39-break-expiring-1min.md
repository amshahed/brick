# Issue #39 — Restore break-expiring notification to 1-min lead per PRD

## Problem

PRD user story #41 specifies "notified 1 minute before a break expires". Issue #26 changed the lead from 60 s to 30 s as part of the tappable-notifications work. The 30 s lead has been shipped; the PRD never changed. We're treating the PRD as the source of truth and bringing the code back to 60 s.

## Design

### NotificationService (`Shared/Services/NotificationService.swift`)

- **Identifier** (line 15): rename `breakExpiring30(_:)` back to `breakExpiring(_:)`. The `30` suffix was a marker for the lead value; with the lead returning to 60 s, drop the suffix rather than introduce `breakExpiring60`. Existing identifier strings under the old name will not be cancellable after the rename, but they're per-break-UUID and expire on their own — no migration concern.
- **`scheduleBreakExpiring`** (lines 97–106):
  - Change `lead: 30` → `lead: 60`.
  - Change body from `"30 sec left on your break."` to `"1 min left on your break."`.
  - Update the identifier call to `Identifier.breakExpiring(breakID)`.
- **`cancelBreakExpiring`** (lines 108–112): update identifier reference.

### Call sites

- `Shared/Services/BreakSessionController.swift` — scheduling/cancellation call sites. No semantic change; just track the identifier rename.
- Verify there are no other references to `breakExpiring30` or `"30 sec"` (grep before editing).

### Tests

- `BrickTests/NotificationFormattingTests.swift` — no current body-string assertion for the expiring notification (verified). No change needed.
- `BrickTests/NotificationLeadIntervalTests.swift` — pure-math tests use arbitrary lead values (30, 300, 86400); they remain valid as-is.
- Add a new test in `NotificationLeadIntervalTests.swift` (or a small addition to `NotificationFormattingTests.swift`) that asserts the lead used by `scheduleBreakExpiring` is 60 s if/when we expose it. If we don't expose it directly, skip — the change is exercised by manual on-device testing.

## Acceptance

- [ ] `scheduleBreakExpiring` uses a 60-s lead.
- [ ] Notification body reads "1 min left on your break."
- [ ] Identifier renamed to `Identifier.breakExpiring(_:)` and all call sites updated.
- [ ] `xcodebuild test -scheme Brick` passes.
- [ ] Manual: start a break with planned duration > 60 s; verify the warning fires 60 s before expiry.

## Files touched

- EDIT `Shared/Services/NotificationService.swift`
- EDIT `Shared/Services/BreakSessionController.swift` (identifier rename only)
