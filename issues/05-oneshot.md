# Plan — Issue #5: One-shot "block now" flow

## Context

One-shot "block now for N hours" is the first-class impulse-control path: user taps once, picks duration + blocklist, the shield activates immediately. It must layer on top of any running scheduled blocks without interfering with their lifecycle. The union logic from #4 already handles overlap for scheduled blocks; this slice extends it to include one-shots so any concurrent source contributes to the single current shield.

## Approach

**Dedicated `OneShotBlock` model** rather than reusing `Schedule`. One-shots have a disjoint shape: no weekday mask, explicit `startedAt` + `expiresAt`, no editable recurrence. Forcing a `Schedule` to hold `repeats = false` would muddy queries and UI. A separate model keeps each type's logic tight.

**Union extension in `ScheduleEngine`.** `applyCurrentUnion()` already fetches schedules; extend it to also fetch `OneShotBlock`s that are still running (`expiresAt > now`). The union is the set sum of both sources. A scheduled block ending runs the same recompute; a one-shot ending runs the same recompute; the correct shield falls out for free.

**DeviceActivity registration for one-shots.** Register a single `DeviceActivitySchedule` with `intervalStart = now` components (year/month/day/hour/minute) and `intervalEnd = expiresAt` components, `repeats: false`. Activity name: `"brick.oneshot.<uuid>"`. On `intervalDidEnd` the extension runs the standard reconcile and the shield recomputes without the expired one-shot.

**BlockSession for one-shots.** Add a second optional relationship `oneShotBlock: OneShotBlock?` to `BlockSession`. A BlockSession has either `schedule` set or `oneShotBlock` set (exclusive, enforced by the code that creates them — not by the model).

**Auto-cleanup.** `ScheduleEngine.sync()` deletes `OneShotBlock` rows whose `expiresAt` is in the past, after ensuring their `BlockSession` is closed. This prevents unbounded growth of expired rows and trims DeviceActivity registrations.

## File plan

```
Shared/Models/
└── OneShotBlock.swift                  # new

Shared/Services/
└── ScheduleEngine.swift                # extended: union + registration + cleanup

Brick/Models/
└── OneShotBlockStore.swift             # new — start(duration:, blocklist:), activeBlock()

Brick/Views/Home/
├── HomeTab.swift                       # rewired (moved out of Views/)
├── BlockNowButton.swift                # prominent button, presents sheet
├── BlockNowSheet.swift                 # duration + blocklist picker
└── ActiveBlockCard.swift               # live countdown + blocklist name
```

Move `Brick/Views/HomeTab.swift` → `Brick/Views/Home/HomeTab.swift` for consistency with Blocklists/ and Schedules/.

## Data model

```swift
@Model final class OneShotBlock {
    @Attribute(.unique) var id: UUID
    var blocklist: Blocklist?
    var startedAt: Date
    var expiresAt: Date
}
```

Adds to `BlockSession`:
```swift
var oneShotBlock: OneShotBlock?       // nil when tied to a schedule
```

## UI behavior

- Home idle: `ContentUnavailableView`-style hero with a large "Block Now" `.borderedProminent` button.
- Tapping "Block Now" presents `BlockNowSheet`:
  - Duration segmented control: 30m / 1h / 2h / 3h / 4h, with a custom stepper row for other values.
  - Blocklist picker (required).
  - Disabled Start button until a blocklist is selected.
- While a one-shot is active: home screen swaps to `ActiveBlockCard` showing blocklist name, time remaining (tick every second via `Timer.publish`), and a plain "Add another block" button that reopens the sheet.
- Active check: `@Query` for `OneShotBlock`s where `expiresAt > now`. Takes the most-recent start (or concat all active one-shots if multiple stack).
- Multiple concurrent one-shots: allowed. Each contributes to the union. Card shows the shortest remaining time and "+N more" affordance.

## Engine additions

```swift
extension ScheduleEngine {
    func start(oneShot: OneShotBlock) throws {
        context.insert(oneShot)
        try context.save()
        try register(oneShot)
        let active = try applyCurrentUnion()
        try reconcileBlockSessions(active: active, activeOneShots: currentOneShots())
    }
}
```

`applyCurrentUnion()` signature stays but now also reads `OneShotBlock` rows and includes their blocklists in the union. `reconcileBlockSessions()` gains an `activeOneShots` parameter; opens a session per active one-shot without one, closes sessions whose one-shot has expired.

## Edge cases

- **One-shot overlapping its own expiry with a scheduled block start** — both recomputes run, shield is always the correct current union.
- **User creates one-shot with blocklist that overlaps an active schedule** — sets merge, duplicates collapse naturally. When the one-shot ends, the overlapping apps stay shielded via the schedule.
- **Device offline / extension missed `intervalDidEnd`** — `ScheduleEngine.sync()` on app foreground sees the expired one-shot, closes its `BlockSession`, and clears its shield if no other source is active. This is the self-healing path.
- **User kills the app during a one-shot** — DeviceActivityMonitor extension still fires the end event since it runs in its own process.

## Verification plan

1. Build clean.
2. On device:
   - From Home, tap "Block Now", pick 30m + "Social" blocklist, start. Shield appears on Social's apps immediately. Card shows countdown.
   - While running, create a scheduled block at the current time for "Work" with different apps. Shield union includes both sets.
   - Wait for schedule end → scheduled apps unshield, one-shot apps stay shielded.
   - Wait for one-shot end → all shields clear.
   - Start a one-shot, kill the app, wait past expiry. Reopen: no stale shield, BlockSession closed.
3. Verify `BlockSession` count matches expected sessions (one per run).
