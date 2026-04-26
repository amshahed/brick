# Issue #13 — Notifications

## Goal
Four UN notifications fire at key block/break moments.

## Design

### NotificationService (Shared/Services)
- `requestAuthorization() async` — called once from `BrickApp.init` after FC auth.
- `blockStarted(scheduleName:)` — immediate, id `brick.block.started`
- `blockEnded(todayTotal: TimeInterval)` — immediate, id `brick.block.ended`
- `scheduleBreakExpiring(breakID: UUID, firesAt: Date)` — `UNTimeIntervalNotificationTrigger` at `max(1, firesAt - 60 - now)`, id `brick.break.expiring.<uuid>`
- `cancelBreakExpiring(breakID: UUID)` — `remove{Pending,Delivered}NotificationRequests(withIdentifiers:)`
- `overageApplied(overageMinutes: Int, extensionMinutes: Int)` — immediate, id `brick.overage.<uuid>`

All methods are no-ops when auth is denied (UN already swallows this).

### Wire-in points

1. **BrickApp.init** — fire-and-forget `await NotificationService.shared.requestAuthorization()`.
2. **ScheduleEngine.reconcileBlockSessions** — before mutating, record `preOpen = openSessions.count`. After all mutations + saves, count `postOpen`:
   - `preOpen == 0 && postOpen > 0` → `blockStarted(scheduleName: <first new source's name>)`
   - `preOpen > 0 && postOpen == 0` → compute today's total, call `blockEnded(...)`
3. **BreakSessionController.start** — `scheduleBreakExpiring(breakID: record.id, firesAt: record.plannedEnd)`.
4. **BreakSessionController.closeRecord** — always cancel break-expiring. If `wasOverage`, fire `overageApplied` using `session.overageTime` and `session.extensionApplied`.

### Today's total helper
In `NotificationService` (or a `BlockSessionStats` util): fetch all BlockSessions that overlap today, sum `(actualEnd ?? .now - actualStart)` clamped to today's midnight boundaries.

### Copy
- Block started: `"Your <name> block started. 25-min cold-start active."`
- Block ended: `"Block ended. <H>h <M>m blocked today."`
- Break expiring: `"1 min left on your break."`
- Overage: `"Block extended by <X> min (<Y> min overage × 2)."`

### Tests
- `NotificationServiceTests` — format helpers (todayTotal text, overage text).
- No XCTest for UN delivery (no harness). Wiring validated by structure.

## Files touched
- NEW `Shared/Services/NotificationService.swift`
- EDIT `Shared/Services/ScheduleEngine.swift` (reconcile transition detection)
- EDIT `Shared/Services/BreakSessionController.swift` (schedule + cancel)
- EDIT `Brick/BrickApp.swift` (request authorization)
- NEW `BrickTests/NotificationFormattingTests.swift`

## Acceptance mapping
- Permission at launch → `BrickApp.init`
- Block starting/ending → reconcile transitions
- Break expiring + cancel on early end → controller start + closeRecord
- Overage notification → closeRecord when `wasOverage`
- No cold-start notification → not implemented (deliberate)
