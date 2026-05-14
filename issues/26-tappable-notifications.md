# Issue #26 — Tappable notifications + 30s break-ending warning

## Goal
Make notifications tappable (deep-link to in-app view) and replace the 60s break-end warning with a 30s warning that lands the user on the active break sheet.

## Design

### NotificationService (Shared/Services)
- Inherit `NSObject`, adopt `UNUserNotificationCenterDelegate`. Required because the protocol inherits `NSObjectProtocol` and the delegate needs Obj-C selector dispatch.
- Add cross-module route enum + closure handoff:
  ```swift
  enum NotificationRoute: Equatable {
      case activeBreak(UUID)
      case schedules
      case travel
  }
  var onTap: ((NotificationRoute) -> Void)?
  ```
- Add a pure helper for testable lead-time math (used here and reused in #27/#28):
  ```swift
  static func leadInterval(firesAt: Date, lead: TimeInterval, now: Date) -> TimeInterval?
  ```
  Returns `nil` (skip) if `firesAt - now - lead <= 0`, otherwise the trigger interval.
- Add a pure helper for userInfo decoding (testable without `UNNotificationResponse`):
  ```swift
  static func route(from userInfo: [AnyHashable: Any]) -> NotificationRoute?
  ```
- Replace `scheduleBreakExpiring`/`Identifier.breakExpiring` with the 30s variant:
  - Identifier: `brick.break.expiring30.<uuid>` (renamed from `brick.break.expiring.<uuid>`).
  - Lead: 30s (was 60s).
  - Body: `"30 sec left on your break."`
  - `content.userInfo = ["route": "break", "id": breakID.uuidString]`
- Implement delegate methods:
  - `userNotificationCenter(_:willPresent:withCompletionHandler:)` → return `[.banner, .sound]` so foreground notifications surface.
  - `userNotificationCenter(_:didReceive:withCompletionHandler:)` → call `Self.route(from: userInfo)` and dispatch via `onTap`.

### AppRouter (NEW: Brick/AppRouter.swift)
```swift
@MainActor final class AppRouter: ObservableObject {
    enum Tab: Int, Hashable { case home, blocklists, schedules, settings }
    @Published var selectedTab: Tab = .home
    @Published var presentTravelMode: Bool = false  // wired in #28

    func handle(_ route: NotificationService.NotificationRoute) {
        switch route {
        case .activeBreak:
            selectedTab = .home   // ActiveBreakView auto-presents from breakController.active
        case .schedules:
            selectedTab = .schedules
        case .travel:
            selectedTab = .settings
            presentTravelMode = true
        }
    }
}
```

### BrickApp wire-in
- Add `@StateObject private var router = AppRouter()`.
- In `init()` after `requestAuthorization()` (delegate registration must be synchronous before SwiftUI body so cold-launch taps are delivered):
  ```swift
  UNUserNotificationCenter.current().delegate = NotificationService.shared
  ```
- After `_breakController = ...`, wire up onTap on the main actor:
  ```swift
  let router = AppRouter()
  _router = StateObject(wrappedValue: router)
  NotificationService.shared.onTap = { route in
      Task { @MainActor in router.handle(route) }
  }
  ```
- Inject: `.environmentObject(router)` on `RootView`.

### RootView
- Add `@EnvironmentObject private var router: AppRouter`.
- `TabView(selection: $router.selectedTab)` with `.tag(AppRouter.Tab.home)` etc on each tab.

### BreakSessionController — no caller change
The lead time change is internal to `scheduleBreakExpiring`. Existing call site at line 151 stays as-is.

## Tests
- **`NotificationLeadIntervalTests.swift`** (new) — pure lead-time math: `leadInterval(firesAt: now+45s, lead: 30, now: now)` ≈ 15s; `leadInterval(firesAt: now+20s, lead: 30, now: now)` returns nil.
- **`NotificationRouteParsingTests.swift`** (new) — `route(from: ["route": "break", "id": uuid])` → `.activeBreak(uuid)`; `["route": "schedules"]` → `.schedules`; `["route": "travel"]` → `.travel`; bad input → nil.
- Update **`NotificationFormattingTests.swift`** — no change needed (formatting helpers untouched).

## Files touched
- EDIT `Shared/Services/NotificationService.swift` (NSObject + delegate, route enum, leadInterval, route(from:), 60→30, identifier rename, willPresent, didReceive)
- NEW `Brick/AppRouter.swift`
- EDIT `Brick/BrickApp.swift` (delegate set, router StateObject, onTap wire-up, environmentObject)
- EDIT `Brick/RootView.swift` (TabView selection)
- NEW `BrickTests/NotificationLeadIntervalTests.swift`
- NEW `BrickTests/NotificationRouteParsingTests.swift`

## Acceptance mapping
- Delegate registered → BrickApp.init.
- Tap (any state) routes to NotificationRoute → didReceive + onTap.
- 30s warning → leadInterval call inside `scheduleBreakExpiring`.
- Tap lands on Home + ActiveBreakView visible → router selects .home, HomeTab observes `controller.active != nil`.
- Foreground delivery shows banner → willPresent returns `[.banner, .sound]`.
- Early end cancels both pending+delivered → `cancelBreakExpiring` already does both (uses new identifier).
- Programmatic tab routing → `RootView` selection binding.
