# Plan — Issue #12: Travel mode

## Context

Travel mode is a global gate on schedules. When active, `ScheduleEngine.applyCurrentUnion` must treat *schedules* as empty — but leave *one-shot blocks* untouched per spec. The cleanest integration point is the single place that already computes `activeSchedules`.

The model + logic split:
- **Data**: one `TravelPeriod` at a time. Two shapes — `startDate..endDate` (dated, auto-ends) and `startDate + nil` (toggle, manual-only). Active is a function of `startDate <= now && (endDate == nil || now < endDate)`. No separate `isActive` flag — it's derived, which avoids drift.
- **Engine gate**: `ScheduleEngine.applyCurrentUnion` fetches the current `TravelPeriod`; if active, zero the `activeSchedules` array before union. One-shots pass through.
- **Auto-resume (dated)**: register a one-off `DeviceActivitySchedule` named `brick.travel.<id>` that fires `intervalDidEnd` at the `endDate`. The monitor extension's existing `intervalDidEnd` path already calls `applyCurrentUnion` + `reconcileBlockSessions`, and since the travel period's `endDate` has passed, it no longer gates schedules. Clean.
- **Nudge escalation (toggle)**: iOS `UNUserNotificationCenter` with a daily trigger, plus an extra escalated copy when `daysActive >= 7`. Cancel on deactivate.
- **Banner + screen**: TravelBanner on HomeTab; TravelModeView in Settings.

## Approach

### Data model

`Shared/Models/TravelPeriod.swift`:

```swift
@Model final class TravelPeriod {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var createdAt: Date

    init(id: UUID = UUID(), startDate: Date, endDate: Date? = nil, createdAt: Date = .now) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }

    func isActive(at instant: Date = .now) -> Bool {
        guard startDate <= instant else { return false }
        if let endDate { return instant < endDate }
        return true  // toggle mode
    }

    var isDated: Bool { endDate != nil }
}
```

Schema += `TravelPeriod.self` in `BrickApp.sharedModelContainer` and `InMemoryStore`.

### Store

`Brick/Models/TravelPeriodStore.swift`:

```swift
struct TravelPeriodStore {
    let context: ModelContext

    func current() throws -> TravelPeriod?  // most recent, regardless of active status
    func activeNow(at: Date) throws -> TravelPeriod?
    func startDated(from: Date, to: Date) throws -> TravelPeriod
    func startToggle() throws -> TravelPeriod
    func end(_ period: TravelPeriod) throws
}
```

`start*` ends any pre-existing active/future period first (spec: only one at a time). `end` sets `endDate = .now` (so `isActive` flips false immediately), reruns `ScheduleEngine.sync()` to re-register schedules, and cancels nudges.

### ScheduleEngine gate

In `applyCurrentUnion`:

```swift
let activeTravel = try context.fetch(FetchDescriptor<TravelPeriod>())
    .first(where: { $0.isActive(at: instant) })
let suspendSchedules = activeTravel != nil

let activeSchedules: [Schedule]
if suspendSchedules {
    activeSchedules = []
} else {
    activeSchedules = schedules.filter { /* existing predicate */ }
}
```

One-shots and extension-tail sessions remain as-is. Result: shield unions only from one-shots + tails while travel mode is on.

In `sync()`: when starting/ending a travel period, the store calls `sync()` which re-registers the monitor lineup. When travel is *active*, leave the existing schedule registrations intact — they're harmless because `applyCurrentUnion` returns empty schedule selections. The monitor's `intervalStart` callback will hit `applyCurrentUnion` which correctly no-ops. Simpler than `stopMonitoring` + re-`startMonitoring` dances.

### Dated auto-resume DA registration

`ScheduleEngine.registerTravelEndReminder(_ period: TravelPeriod) throws`:

- Stops `brick.travel.<id>`.
- If dated and `endDate > now`, starts a one-off `DeviceActivitySchedule` with `intervalEnd` at `endDate`.
- `intervalDidEnd` in the monitor extension already runs `applyCurrentUnion` + `reconcileBlockSessions`, which picks up that the travel period is no longer active and naturally resumes schedule-based blocking.

Called from `startDated` and `end`.

### Nudge scheduler

`Shared/Services/TravelNudgeScheduler.swift`:

```swift
enum TravelNudgeScheduler {
    static let dailyID = "brick.travel.daily"
    static let escalatedID = "brick.travel.escalated"

    static func scheduleDaily(startedAt: Date) async
    static func cancelAll() async
    // Daily: UNCalendarNotificationTrigger, hour 9, repeats.
    // Escalated: UNCalendarNotificationTrigger scheduled once at startedAt + 7 days, hour 9.
    // Both cancelled on deactivate.
}
```

Requests auth via `UNUserNotificationCenter.requestAuthorization(options: [.alert, .sound])` lazily. If denied, no-op — travel mode still works silently.

### Views

`Brick/Views/Travel/TravelModeView.swift` — accessible from Settings tab and from the Home banner. Shows status + controls.

```swift
// Inactive state: two cards
//   - "Plan a trip" — date range DatePicker + Save
//   - "I'm traveling now" — button that starts toggle mode
// Active state:
//   - Mode + dates/since
//   - "End travel mode" button
```

`Brick/Views/Travel/TravelBanner.swift` — compact banner for HomeTab top. "Travel mode active" + subtitle ("Ends Apr 30" or "Since Apr 22") + "Disable" button.

### HomeTab integration

Add `@Query private var travelPeriods: [TravelPeriod]` and a computed `activeTravel: TravelPeriod?`. Render `TravelBanner` at the top of the main `VStack` when non-nil, above the FocusNudgeCard and ActiveBlockCard. "Disable" calls `TravelPeriodStore.end(...)`.

`SettingsTab` adds a new row "Travel mode" with status chip, routing to `TravelModeView`.

### BlockNowSheet untouched

One-shot `Block Now` uses `OneShotBlockStore.start`, which goes through `ScheduleEngine.start(oneShot:)` and `applyCurrentUnion`. Travel mode only zeroes schedules — one-shots still union into the shield. No changes needed.

## File plan

```
Shared/Models/
└── TravelPeriod.swift                # new model + derived isActive

Shared/Services/
├── ScheduleEngine.swift              # travel gate on activeSchedules
│                                      # registerTravelEndReminder
└── TravelNudgeScheduler.swift        # new — UNUserNotificationCenter

Brick/Models/
└── TravelPeriodStore.swift           # new — start/end helpers

Brick/Views/Travel/
├── TravelModeView.swift              # new — status + controls
└── TravelBanner.swift                # new — HomeTab banner

Brick/BrickApp.swift                  # schema += TravelPeriod
Brick/Views/Home/HomeTab.swift        # banner above existing content
Brick/Views/SettingsTab.swift         # "Travel mode" row

BrickTests/
├── TestSupport/InMemoryStore.swift   # schema += TravelPeriod
└── TravelModeTests.swift             # new — engine + model behavior
```

## Key code shapes

```swift
// Store — start toggle
func startToggle() throws -> TravelPeriod {
    try endAnyExisting()
    let period = TravelPeriod(startDate: .now, endDate: nil)
    context.insert(period)
    try context.save()
    try ScheduleEngine(context: context).sync()
    Task { await TravelNudgeScheduler.scheduleDaily(startedAt: period.startDate) }
    return period
}

func startDated(from: Date, to: Date) throws -> TravelPeriod {
    try endAnyExisting()
    let period = TravelPeriod(startDate: from, endDate: to)
    context.insert(period)
    try context.save()
    let engine = ScheduleEngine(context: context)
    try engine.sync()
    try engine.registerTravelEndReminder(period)
    return period
}

func end(_ period: TravelPeriod) throws {
    period.endDate = .now
    try context.save()
    let engine = ScheduleEngine(context: context)
    try engine.sync()
    try engine.registerTravelEndReminder(period)  // no-op if endDate <= now
    Task { await TravelNudgeScheduler.cancelAll() }
}
```

```swift
// Engine — gate
@discardableResult
func applyCurrentUnion(at instant: Date = .now) throws -> ActiveSources {
    let schedules = try context.fetch(FetchDescriptor<Schedule>())
    let oneShots = try context.fetch(FetchDescriptor<OneShotBlock>())
    let travel = try context.fetch(FetchDescriptor<TravelPeriod>())
        .first(where: { $0.isActive(at: instant) })
    let suspendSchedules = travel != nil

    let activeSchedules = suspendSchedules ? [] : schedules.filter { s in
        s.enabled && !s.isExpired
            && ScheduleClock.isActive(…, at: instant)
    }
    // one-shots + tails unchanged
    …
}
```

## Tests

`BrickTests/TravelModeTests.swift`:

- `testSchedulesSuspendedWhenTravelActive` — seed active schedule + active TravelPeriod (toggle), assert `applyCurrentUnion().schedules.isEmpty`.
- `testOneShotStillActiveDuringTravel` — seed a one-shot + toggle travel, assert `applyCurrentUnion().oneShots.count == 1`.
- `testDatedTravelAutoEndsAtEndDate` — seed dated period ending 1s ago (`endDate: now - 1`), assert `isActive(at: now) == false` and schedules re-resolve.
- `testOnlyOneActivePeriod` — `startDated` twice; only the most recent is active; prior one's `endDate` was set to now-ish.
- `testEndTravelReactivatesSchedules` — seed toggle travel + active schedule; `store.end(period)`; assert `applyCurrentUnion().schedules.count == 1`.

Nudge scheduler is not unit-tested (depends on `UNUserNotificationCenter` system state).

## Edge cases

- **User sets dated travel with `endDate` in the past.** Store validates `endDate > .now`; throws.
- **User sets dated travel with `startDate` in the future.** Allowed; `isActive(at: now)` returns false until `startDate` arrives. DA reminder fires at `endDate` regardless. Start-date activation happens passively via `applyCurrentUnion` being called on scene-active or the next monitor tick. Good enough.
- **User overlaps a new dated period with an existing toggle period.** Store `endAnyExisting` closes the prior one first — only one at a time.
- **App cold-starts during an active dated period.** On launch, `ScheduleEngine.sync()` runs; `applyCurrentUnion` sees travel active and applies no schedule selections. Banner renders.
- **Notification authorization denied.** `scheduleDaily` silently returns; travel mode still works — user just doesn't get nudges.
- **Scheduled `brick.travel.<id>` DA registration lost** (e.g. iOS reboot edge case). On app foreground, `ScheduleEngine.sync()` re-calls `registerTravelEndReminder` for any active/future dated period. Recoverable.
- **"Disable" tapped on banner during active block** from one-shot. Disabling travel doesn't cancel the one-shot — they're independent. Verified by test.

## Verification plan

1. `xcodegen generate` succeeds; tests compile + pass.
2. Manual (on-device):
   - Activate toggle travel → banner appears on Home, "Since ..." subtitle, schedule toggles stop firing, one-shot `Block Now` still shields.
   - Disable via banner → banner disappears, scheduled blocks resume on next tick.
   - Create dated travel ending in 2 minutes → wait 2 minutes → schedules auto-resume (confirm via Schedules tab that they're live again).
   - Notification auth granted → toggle travel → daily nudge fires at 9am next day (observed in a later session).

## Out of scope

- UI toggle for "resume schedules but leave travel mode on" (not in spec).
- Timezone changes during travel (dates are stored as UTC `Date`; DA uses local components — acceptable for MVP).
- Multiple concurrent travel periods.
- Travel mode blocking *one-shots* too (spec is explicit: one-shots stay).
- Dated mode's auto-activation at future `startDate` via DA registration. The engine re-evaluates on each tick; acceptable lag is bounded by monitor interval + scene-active refreshes.
