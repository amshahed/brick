# Issue #28 — Vacation ending notification (24h)

## Goal
Single notification fires 24 hours before a dated travel period ends. Tap routes to TravelModeView via the AppRouter from #26. Open-ended (toggle) periods don't trigger this — only `startDated` flows.

## Design

### NotificationService methods
Singleton identifier (only one travel period active at a time; last write wins):
```swift
static let travelEnding = "brick.travel.ending24h"

func scheduleTravelEnding(periodEndsAt: Date, now: Date = .now)
func cancelTravelEnding()
```
- `scheduleTravelEnding`: lead = 86400s (24h). Body `"Your vacation ends in 24 hours."` `userInfo = ["route": "travel"]`. Uses existing `leadInterval` helper — silent skip when end <24h out.
- `cancelTravelEnding`: removes pending + delivered for the singleton id.

### TravelPeriodStore hooks
- `startDated(from:to:)` after `engine.registerTravelEndReminder(period)`:
  ```swift
  NotificationService.shared.scheduleTravelEnding(periodEndsAt: end)
  ```
- `end(_ period:)` and `endAnyCurrent()`:
  ```swift
  NotificationService.shared.cancelTravelEnding()
  ```
- `startToggle()` does NOT schedule (no end date) but should still cancel any leftover from a prior `startDated` period — `endAnyCurrent()` runs first, handles it.

### SettingsTab routing
- Add `@EnvironmentObject private var router: AppRouter`.
- Add `.navigationDestination(isPresented: $router.presentTravelMode) { TravelModeView() }` on the `Form` (or a parent inside the existing NavigationStack). Keep the existing `NavigationLink { TravelModeView() }` for manual tap — both paths render the same view.
- Two-way binding: when the user taps Back, SwiftUI flips the binding back to false → router state resets automatically.

### Routing (already wired in #26)
`AppRouter.handle(.travel)` sets `selectedTab = .settings` and `presentTravelMode = true`.

## Tests
- **`TravelNotificationTests.swift`** (new) — using the existing `leadInterval` helper:
  - `scheduleTravelEnding(periodEndsAt: now+25h, now:)` → existing lead helper test already covers this case (25h ahead, lead 86400 → ~1h interval).
  - End time 12h out → silent skip (covered by leadInterval test).
  - `Identifier.travelEnding` is the singleton string `"brick.travel.ending24h"`.
- Manual smoke: pending request inspection during simulator run.

(No additional unit tests for `cancelTravelEnding` beyond confirming the identifier — `removePendingNotificationRequests(withIdentifiers:)` is fire-and-forget and not productively unit-testable without a center mock, which we don't have.)

## Files touched
- EDIT `Shared/Services/NotificationService.swift` (`scheduleTravelEnding`, `cancelTravelEnding`, `Identifier.travelEnding`)
- EDIT `Brick/Models/TravelPeriodStore.swift` (call schedule + cancel at the right hook points)
- EDIT `Brick/Views/SettingsTab.swift` (env router + navigationDestination binding)

## Acceptance mapping
- 24h lead schedule → `scheduleTravelEnding` with lead 86400.
- <24h periods skip silently → `leadInterval` returns nil.
- Manual end cancels → `end()`/`endAnyCurrent()` call `cancelTravelEnding`.
- Edit reschedules → existing edit path goes through `startDated` again (or update flow); cancel-then-add is idempotent at id level (singleton id replaces).
- Open-ended periods skip → `startToggle()` doesn't call schedule.
- Tap routes → AppRouter.handle(.travel) → SettingsTab navigationDestination.
- Dismiss resets flag → two-way binding handles it.
