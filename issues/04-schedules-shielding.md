# Plan — Issue #4: Recurring schedules + shield activation

## Context

This slice makes the blocker actually block. Before it, we have data (blocklists). After it, a schedule starts at the right time, a shield overlay appears on the configured apps, the shield clears when the schedule ends, and overlapping schedules correctly union their apps. One-shot blocks (#5), break flow (#7), overage ritual (#8) all hang off the `BlockSession` records created here. Shield customization (#9) and notifications (#13) slot onto the same event hooks.

The hard part is the main-app-to-extension handoff: `DeviceActivityMonitor` runs in a separate 6 MB process, so shared logic has to live in files included in both targets, operating on the same App Group SwiftData store.

## Approach

**Code sharing via a `Shared/` folder.** Move `Blocklist`, `SharedContainer`, new `Schedule` / `BlockSession` models, plus `ShieldManager` and `ScheduleEngine` into `Shared/`, then include that folder in both the app target and the `DeviceActivityMonitorExtension` target in `project.yml`. No framework or Swift Package — just compiled-into-both-targets sources. Easiest and lightest given iOS extension memory limits.

**DeviceActivity registration.** For each enabled schedule and each weekday bit set, register one `DeviceActivitySchedule` with `DeviceActivityCenter`. Activity name = `"brick.<scheduleID>.<weekday>"`. Using one registration per (schedule, weekday) keeps the mapping on `intervalDidStart` trivial and avoids fighting Apple's weekday/repeat model.

**Union logic lives in the extension.** On any interval event, the extension fetches all schedules from SwiftData, computes which are active *now* (weekday + time-of-day + optional date range), unions their `FamilyActivitySelection`s, and applies that to a single `.default` `ManagedSettingsStore`. Single store means the shield surface is always the current union — simple, correct, and cheap to reason about. Ending one schedule re-runs the same logic: whatever is still active becomes the new shield; if nothing is active, the store is cleared.

**BlockSession lifecycle.** Created on the first `intervalDidStart` for a given schedule run; closed on `intervalDidEnd`. Stored via SwiftData in the shared App Group store so the main app can display history.

**Bounded schedule auto-disable.** `ScheduleEngine.sync()` runs on app foreground and after any edit. It checks each schedule's `endDate`; if passed, flips `enabled = false` and removes its DeviceActivity registrations.

**UI.** `SchedulesTab` becomes a list (via `@Query`), each row shows name, blocklist name, next fire description (e.g. "Mon-Fri 9:00-17:00"). Editor form: name, blocklist picker (segmented list of existing blocklists), 7 weekday toggles, start/end time pickers, optional date-range section, enabled toggle. On save, `ScheduleEngine.sync()` is called.

**Blocklist deletion guard.** `BlocklistStore.delete(_:)` now checks for schedules referencing the blocklist. If any, throws `.referencedBySchedules([names])`. The list view catches and presents a confirmation alert that offers to delete both the blocklist and the schedules, or cancel.

## File plan

```
Shared/                                         # included in both Brick + DeviceActivityMonitor targets
├── SharedContainer.swift                       # moved from Brick/
├── Models/
│   ├── Blocklist.swift                         # moved from Brick/Models
│   ├── Schedule.swift                          # new
│   └── BlockSession.swift                      # new
├── Services/
│   ├── ShieldManager.swift                     # new — wraps ManagedSettingsStore
│   ├── ScheduleEngine.swift                    # new — registration + active-union + BlockSession
│   └── ActivityNaming.swift                    # new — encodes/decodes DeviceActivityName
└── Time/
    └── ScheduleTime.swift                      # new — weekday mask, active-now, next-fire

Brick/
├── Models/
│   ├── BlocklistStore.swift                    # extended: deletion guard + listing referencing schedules
│   └── ScheduleStore.swift                     # new — CRUD wrapping ModelContext; triggers ScheduleEngine.sync()
└── Views/
    ├── SchedulesTab.swift                      # rewired
    └── Schedules/
        ├── SchedulesListView.swift             # new
        └── ScheduleEditorView.swift            # new

DeviceActivityMonitorExtension/
└── DeviceActivityMonitorExtension.swift        # rewritten: delegates to ScheduleEngine
```

Move operations:
- `Brick/SharedContainer.swift` → `Shared/SharedContainer.swift`
- `Brick/Models/Blocklist.swift` → `Shared/Models/Blocklist.swift`

## Key decisions + edge cases

- **Single `ManagedSettingsStore` (`.default`)**: easier than per-schedule stores. Since the extension recomputes the full union on every interval event, granular per-store removal isn't needed. A future per-store model can be revisited if a feature needs selective clearing (e.g., break flow in #7 uses a separate store for the unshielded single app).
- **Cold-start logic stays out of this slice**: break gating is #6. Here, `BlockSession` is created/closed and its `actualStart` timestamp is set, which is the only ingredient #6 needs.
- **Midnight-crossing schedules** (e.g. 22:00-07:00, Night Wind-Down template): represented as `startTime > endTime` on the same day. The active-now check handles this with a "wraps past midnight" branch. Registration: register two DeviceActivitySchedule intervals per weekday pair — one for `startTime` → `24:00` on day N, one for `00:00` → `endTime` on day N+1 — each as a separate activity name. Acceptance handled here.
- **Concurrent overlapping shields with the same app**: union is set-based, so duplicates collapse naturally.
- **Extension memory**: store only token sets + ids in memory, no SwiftUI or Foundation date-heavy work. `PropertyListDecoder` for selection data; no per-event allocations beyond the union Set.
- **SwiftData from extension**: same `ModelContainer` configuration as the app (App Group URL, same schema). Extensions must NOT leave the container open across events — construct, use, dispose.
- **Enable/disable toggle**: flipping calls `ScheduleEngine.sync()` which removes just the disabled schedule's registrations and, if it was currently active, recomputes the shield.

## Schedule data model

```swift
@Model final class Schedule {
    @Attribute(.unique) var id: UUID
    var name: String
    var blocklist: Blocklist?                   // nullable to allow SwiftData relationship delete rules
    var weekdayMask: Int                        // OptionSet: bit 0 = Sun ... bit 6 = Sat
    var startMinute: Int                        // 0..1439  (hour*60 + minute)
    var endMinute: Int                          // 0..1439
    var startDate: Date?
    var endDate: Date?
    var repeats: Bool                           // always true for schedules created in this slice
    var enabled: Bool
    var createdDate: Date
}

@Model final class BlockSession {
    @Attribute(.unique) var id: UUID
    var schedule: Schedule?                     // nil for one-shot (#5)
    var actualStart: Date
    var actualEnd: Date?
    var totalBreakTime: TimeInterval            // filled by #6/#7
    var overageTime: TimeInterval               // filled by #8
    var extensionApplied: TimeInterval          // filled by #8
}
```

Minutes-since-midnight over DateComponents keeps the active-now math as plain integer comparisons and sidesteps calendar/timezone edge cases for scheduling logic (registration still uses `DateComponents` as required by Apple).

## Verification plan

1. `xcodegen generate && xcodebuild -target Brick -sdk iphoneos18.2 ...` builds with no errors or warnings.
2. Unit-level sanity (not full tests — those come with #6): compile-time verified signatures for `ScheduleEngine.activeSchedulesNow()` and `ScheduleEngine.sync()`.
3. On device:
   - Create blocklist "Social" with Instagram + TikTok.
   - Create schedule: "Evening", Mon-Sun, 19:00-20:00 (set times for a near-future window to test quickly), blocklist=Social, enabled.
   - Wait for 19:00: blocked apps show the shield when opened.
   - At 20:00: shield disappears; blocked apps open normally.
   - Create second schedule "Overlap" 19:30-19:45 with a different blocklist that shares Instagram and adds Twitter. At 19:30, Twitter is also shielded. At 19:45, Twitter unshields, Instagram + TikTok stay shielded until 20:00.
   - Disable "Evening" via toggle mid-block → its apps unshield; "Overlap" apps stay if still active.
   - Set "Overlap" `endDate` to yesterday → after `ScheduleEngine.sync()` runs on app foreground, `enabled` flips to false.
4. Confirm `BlockSession` rows written (visible via a debug dump in Settings tab or directly via lldb).
