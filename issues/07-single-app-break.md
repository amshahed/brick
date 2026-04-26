# Plan — Issue #7: Single-app break flow

## Context

The break engine (#6) exposes `canStartBreak / startBreak / endBreak` and tracks records in a rolling window. This slice builds the user-facing flow that calls those APIs: pick one blocked app, unshield it, run a countdown, re-shield it. Every downstream slice (overage ritual #8, shield UI #9, notifications #13, home stats #14) reads `BreakRecord` or hooks this flow, so the data contract established here ripples forward.

The hard parts are (a) unshielding *exactly one* app token from the current union without disturbing the rest, and (b) the ShieldAction-to-main-app handoff, since iOS extensions cannot programmatically open their host app.

## Approach

**Per-app shield surgery via `apply(union:except:)`.** `ShieldManager` already applies the full union to the `.default` store. Add a second entry point that accepts an "except" `ApplicationToken` set and subtracts it from `applications` while passing it into the category-level `.specific(categories, except: apps)` form. This way a break app that happens to live inside a shielded category is also granted passage. Clearing the break reapplies the plain union and the app re-shields.

**`ApplicationToken` persistence.** `ApplicationToken` is `Codable` on iOS 15+ like `FamilyActivitySelection`. `BreakRecord.appTokenData` (already defined in #6) stores the property-list-encoded token; the controller encodes on start, decodes when applying the shield override.

**Shield → app handoff via App Group intent file.** ShieldAction extensions run in a 6 MB process that cannot call `UIApplication.shared.open` and have no `NSExtensionContext.open` affordance. Clean workaround: on `primaryButtonPressed`, write `{appTokenData, createdAt}` to `group.com.amshahedhasan.brick/Intents/break.plist` and return `.defer` (shield stays on screen). The shield copy invites the user to open Brick. When the main app's scene transitions to `.active`, it reads the intent; if within a 60 s freshness window, it auto-presents the break sheet with that app pre-selected and then deletes the file. Stale intents are discarded. This keeps the logic App Store-safe and avoids private APIs.

**`brick://` URL scheme** is registered for future entry points (notification taps, Focus integration) but is not the shield primary path. URL handler is the same `BreakIntent.consume()` path — the URL is parsed to populate the intent struct and forwarded.

**`BreakSessionController`** is the single object UI binds to. Wraps `BreakQuotaEngine` + `ShieldManager` + a `Timer`. Exposes:
- `availability(at:) -> BreakAvailability` — pass-through.
- `start(app: ApplicationToken, duration: TimeInterval)` — encodes token, calls engine, applies shield override, schedules end.
- `endEarly()` / internal `expire()` — calls engine, re-applies full union, clears timer.
- `active: ActiveBreak?` — published; drives the active-break UI.

Timer lives on the main app process only. If the app is backgrounded past expiry, `sync()`-on-foreground closes the break record and reapplies union (self-heal; mirrors the one-shot pattern).

**Break picker source.** Enumerates `applicationTokens` of the current union (not categories — tokens inside a category are opaque). If the user has only added categories to their blocklist, the picker shows an empty state with a message explaining that category-only blocks don't support per-app breaks yet. This is a known limitation and #9 / future slices can explore workarounds.

## File plan

```
Shared/Services/
├── ShieldManager.swift              # add apply(union:except:)
├── BreakIntent.swift                # new — intent file read/write + URL parse
└── BreakSessionController.swift     # new — binds engine+shield+UI

Brick/
├── BrickApp.swift                   # scenePhase handler, URL scheme handler
├── Info.plist                       # add CFBundleURLTypes for brick://
└── Views/
    ├── Home/HomeTab.swift           # "Take a break" button when block active
    └── Break/
        ├── BreakSheet.swift         # root of flow; reads controller + availability
        ├── BreakPickerView.swift    # app list, start button, availability banners
        └── ActiveBreakView.swift    # countdown + end-early

ShieldActionExtension/
└── ShieldActionExtension.swift      # primaryButtonPressed → BreakIntent.write
```

## Key code shapes

```swift
// ShieldManager.swift  (addition)
func apply(union selection: FamilyActivitySelection, except breakApps: Set<ApplicationToken>) {
    let apps = selection.applicationTokens.subtracting(breakApps)
    store.shield.applications = apps.isEmpty ? nil : apps
    let cats = selection.categoryTokens
    store.shield.applicationCategories = cats.isEmpty
        ? nil
        : .specific(cats, except: breakApps)
    store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    store.shield.webDomainCategories = cats.isEmpty ? nil : .specific(cats)
}
```

```swift
// BreakIntent.swift
struct BreakIntent: Codable {
    let appTokenData: Data
    let createdAt: Date
    static let freshness: TimeInterval = 60

    static var fileURL: URL { SharedContainer.containerURL
        .appendingPathComponent("Intents/break.plist") }

    static func write(appTokenData: Data) throws { ... }
    static func consume() -> BreakIntent?       // reads + deletes if fresh
    static func fromURL(_ url: URL) -> BreakIntent?
}
```

```swift
// BreakSessionController.swift  (MainActor ObservableObject)
@MainActor final class BreakSessionController: ObservableObject {
    @Published private(set) var active: ActiveBreak?
    struct ActiveBreak: Identifiable {
        let id: UUID
        let appTokenData: Data
        let startedAt: Date
        let endsAt: Date
    }

    init(context: ModelContext, engineClock: Clock = SystemClock()) { ... }

    func availability() throws -> BreakAvailability
    func start(app: ApplicationToken, duration: TimeInterval, isOverage: Bool = false) throws
    func endEarly()
    func refreshFromStore()    // called on foreground; self-heals expired breaks
}
```

Active break detection on launch: query `BreakRecord` with `endTime == nil`, `blockSession.actualEnd == nil`. If present, reconstruct `ActiveBreak` using the record's `startTime + expected duration` stored on the record. *Extending `BreakRecord`:* add `plannedDuration: TimeInterval` (immutable after start) so the controller knows when to fire expiry — this avoids needing a separate persisted timer.

```swift
// BreakRecord.swift  (addition)
var plannedDuration: TimeInterval   // user-chosen, ≤ remainingQuota
```

## Data model delta

- `BreakRecord.plannedDuration: TimeInterval` — added. Existing tests from #6 default this to `600` (full quota). New test covers "end at plannedDuration if timer fires, or earlier on endEarly, never later."

No other schema change.

## URL scheme

`Info.plist`:
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>brick</string></array>
    <key>CFBundleURLName</key>
    <string>com.amshahedhasan.brick</string>
  </dict>
</array>
```

Handlers: `BrickApp.onOpenURL` and `scenePhase == .active` both route to `BreakIntent.consume()`-like path, which pushes into a shared `BreakIntentInbox` observable that `RootView` watches and presents `BreakSheet`.

## UI flow

1. **Home, no block active.** Existing "Block Now" hero (unchanged).
2. **Home, block active (schedule or one-shot).** Existing ActiveBlockCard + new `"Take a break"` secondary button. Disabled unless `availability == .allowed`. Tapping presents `BreakSheet`.
3. **BreakSheet → BreakPickerView.**
   - Header shows `remainingQuota` (e.g. "7 min available").
   - Banner states for `.coldStart`, `.quotaExhausted`, `.overageLockout`, `.noActiveBlock` (no Start button).
   - List of blocked apps (from union's `applicationTokens`) with `Label` system images; tapping selects (single-select).
   - Duration stepper: 1 / 2 / 3 / 5 / custom, capped at `remainingQuota` (rounded down to nearest minute).
   - Start button disabled until an app is selected.
4. **ActiveBreakView.**
   - Big countdown `mm:ss`, selected app name, "End break early" button.
   - When countdown reaches zero, controller calls `endBreak` and dismisses.
   - Auto-dismisses with an explainer banner if the underlying block ends before the break does.

## Shield extension behavior

Primary button ("Take a break") → `BreakIntent.write(appTokenData:)` + `completionHandler(.defer)`. The shield stays visible until the user opens Brick; on next app activation the break flow resumes with the intended app preselected.

Secondary button ("Close") → `.close` (existing behavior).

## Edge cases

- **Intent written while app already foregrounded.** `BreakIntent` file write triggers no FS notification. App foreground polls on scenePhase transition and also on a 2 s timer while `BreakSheet` is presented, so a fresh intent from the shield is picked up within 2 s.
- **Two schedules blocking the same app.** Breaking it unshields across both sources. When break ends, union recomputes; still shielded by both sources → re-shields as expected.
- **Block ends while break is active.** `ScheduleEngine.applyCurrentUnion()` runs on any interval event. Break controller's `refreshFromStore` on app foreground sees the underlying session is closed → calls `endBreak` + clears local shield override. On a live device the DeviceActivityMonitor extension has already cleared the shield at block end, so no extra action needed.
- **App backgrounded past expiry.** On next foreground, `refreshFromStore` finds a record where `startTime + plannedDuration < now` and closes it.
- **Selected app is in a category-only blocklist.** Not supported for MVP — picker won't list it. If the user taps "Take a break" and no apps are available, picker shows empty state.

## Verification plan

1. `xcodegen generate && xcodebuild … build` succeeds.
2. On-device (Opal-style manual test):
   - Build blocklist "Social" = Instagram, TikTok, X.
   - Create a schedule covering now → +30 min. Shield appears.
   - From Home, tap "Take a break" → picker shows Instagram, TikTok, X with "10 min available."
   - Select Instagram, 2 min, Start. Instagram opens normally; TikTok and X still shielded. Timer counts down.
   - Force-quit app, relaunch. Active break view shown with correct remaining time.
   - "End break early" → Instagram re-shields immediately; `BreakRecord.endTime` recorded.
   - Start another break. Let it run to 0:00 → auto re-shield; record closed at the expected time.
   - Exhaust quota (three 4-min breaks). Picker shows `.quotaExhausted` with "Available in …".
   - Trigger cold-start gate (new schedule starts; immediately try to break). Picker shows `.coldStart` countdown.
   - Shield primary button path: while shielded, tap "Take a break" on the shield. App opens (user-initiated), break flow auto-presents preselected with the shielded app.
3. `BrickTests`:
   - `BreakSessionControllerTests` (new): start → verifies `ShieldManager.apply(union:except:)` called with expected set; end → verifies union reapplied; expiry path fires at `plannedDuration`.
   - Existing #6 tests continue to pass.

## Out of scope

- Per-app shield when app is covered only by a category token — requires a per-app→category resolution we don't yet have.
- Overage path (break after quota exhausted with penalty) — #8.
- Local notification pre-break-end — call site is left as a TODO; scheduling lives in #13.
- Shield UI customization (#9) — primary button title comes from Apple defaults until #9.
