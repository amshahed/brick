# Issue #27 — Schedule start/end notifications

## Goal
Notify the user 5 minutes before a scheduled block starts and 1 minute before it ends. Notifications are tappable (route to Schedules tab via the AppRouter from #26). One-shot ("Block Now") blocks are excluded — they're already immediate by design.

## Design

### ScheduleClock.upcomingOccurrences (new pure function)
Add to `Shared/Time/ScheduleTime.swift`:
```swift
struct UpcomingOccurrence: Equatable { let start: Date; let end: Date }

static func upcomingOccurrences(
    for schedule: Schedule,
    from now: Date,
    days: Int,
    calendar: Calendar = .current
) -> [UpcomingOccurrence]
```

Walk `0..<days` day offsets from `startOfDay(now)`. For each day in `schedule.weekdayMask` (and within `startDate`/`endDate` bounds), build `start = dayStart + startMinute`. If `startMinute >= endMinute` (wrap-past-midnight), `end = (dayStart + 1 day) + endMinute`; else `end = dayStart + endMinute`. Skip occurrences whose `end <= now` (entire occurrence in the past). Don't filter out occurrences with past `start` but future `end` — the END notification still applies. Disabled or expired schedules return `[]`.

### NotificationService methods
Identifier pattern embeds occurrence epoch so re-syncs map the same occurrence to the same id (idempotent), but a shifted occurrence produces a different id (and prefix-cancel removes the old):
```swift
static func blockStarting(scheduleID: UUID, occurrenceStart: Date) -> String
static func blockEnding(scheduleID: UUID, occurrenceEnd: Date) -> String
// "brick.block.starting.<uuid>.<epoch>", "brick.block.ending.<uuid>.<epoch>"
```

Methods (all use `UNTimeIntervalNotificationTrigger` + the existing `leadInterval` helper from #26 — silent skip when lead pushes into past):
```swift
func scheduleBlockStarting(scheduleID: UUID, scheduleName: String, startsAt: Date, now: Date = .now)
func scheduleBlockEnding(scheduleID: UUID, scheduleName: String, endsAt: Date, now: Date = .now)
func cancelBlockNotifications(scheduleID: UUID)
```
- `scheduleBlockStarting`: lead 300s. Body `"<name> starts in 5 min."` `userInfo = ["route": "schedules"]`.
- `scheduleBlockEnding`: lead 60s. Body `"<name> ends in 1 min."` `userInfo = ["route": "schedules"]`.
- `cancelBlockNotifications`: enumerates `getPendingNotificationRequests` + `getDeliveredNotifications` (both async-callback), filters identifiers by prefix `brick.block.starting.<uuid>.` and `brick.block.ending.<uuid>.`, removes them.

### ScheduleEngine.sync rescheduling pass
Add private `rescheduleNotifications(now:)` called at the end of `sync()` (after persistence + DA registration). For each enabled, non-expired `Schedule`:
1. `NotificationService.shared.cancelBlockNotifications(scheduleID:)` (idempotent).
2. For each `(start, end)` from `ScheduleClock.upcomingOccurrences(for: schedule, from: now, days: 3)`:
   - `scheduleBlockStarting(scheduleID:, scheduleName:, startsAt: start, now:)`
   - `scheduleBlockEnding(scheduleID:, scheduleName:, endsAt: end, now:)`

3-day window keeps total pending requests well under iOS's 64 ceiling: ~7 schedules × 3 days × 2 ≈ 42.

### Foreground re-roll
`BrickApp` already calls `resyncShield()` on `.active` (which only does `applyCurrentUnion`). Add a `try? engine.sync()` call alongside it so the notification window advances each foreground.

### Routing
Route `.schedules` from #26 already selects `AppRouter.Tab.schedules`. No change needed.

## Tests
- **`ScheduleOccurrenceTests.swift`** (new) — `ScheduleClock.upcomingOccurrences`:
  - Non-wrap, weekday match → one occurrence per matching day in window.
  - Wrap-past-midnight (e.g. 22:00→02:00) → end is on the following day.
  - Weekday mask filtering (Mon/Wed/Fri only) → only those days produce occurrences.
  - `endDate` cutoff → no occurrences after `endDate + 1 day` boundary.
  - Disabled or expired schedule → `[]`.
  - Past-end occurrences excluded (current-and-future only).
- Existing `NotificationLeadIntervalTests` already cover the 5-min and 24h leads via parameterized cases.

## Files touched
- EDIT `Shared/Time/ScheduleTime.swift` (`UpcomingOccurrence` struct + `upcomingOccurrences` function)
- EDIT `Shared/Services/NotificationService.swift` (identifiers, scheduleBlockStarting/Ending, cancelBlockNotifications)
- EDIT `Shared/Services/ScheduleEngine.swift` (`rescheduleNotifications` + call from `sync()`)
- EDIT `Brick/BrickApp.swift` (foreground `engine.sync()` call)
- NEW `BrickTests/ScheduleOccurrenceTests.swift`

## Acceptance mapping
- 5-min start banner → `scheduleBlockStarting` with lead 300.
- 1-min end banner → `scheduleBlockEnding` with lead 60.
- Edits cancel + re-add → `cancelBlockNotifications` then re-schedule inside `sync()` which is invoked by `ScheduleStore.create/update/delete`.
- Disabled schedule → `upcomingOccurrences` returns `[]` for disabled (and the cancel runs anyway).
- Wrap-past-midnight end → `upcomingOccurrences` rolls end to next day.
- Tap → schedules tab → AppRouter.handle from #26.
- One-shots excluded → loop only over `Schedule` entities, not `OneShotBlock`.
- Pending count under 64 → 3-day window cap.
