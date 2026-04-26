# Plan — Issue #8: Overage ritual + block extension + hard lockout

## Context

The break engine from #6 already persists the whole overage data model: `BlockSession.overageTime`, `BlockSession.extensionApplied`, `BreakRecord.wasOverage`, the `.overageLockout` availability state, and `BreakQuotaEngine.overageAllowed(for:)` with a 15-minute hard cap and 2× multiplier. `BreakSessionController.start(…, isOverage: true)` already bypasses the quota-exhausted gate while still honoring `.overageLockout`. `endBreak` already recomputes `extensionApplied = overageTime × 2` when an overage break closes.

What's missing for this slice is:
1. The **UI** to enter that overage path — a secondary action on the picker when quota is gone but overage is still allowed, then a friction ritual (justification ≥80 chars + 20-second wait).
2. The **shield actually staying up past the schedule's natural end** to the extent of `extensionApplied` — right now `intervalDidEnd` fires, the monitor extension runs `reconcileBlockSessions`, which closes the session and clears the union. The session ends with no extension honored in practice.
3. A few small invariants around cumulative overage + hard lockout transitions the tests should pin down.

The hard part is #2, because a repeating `Schedule` can't just have its end bumped — the DA registration uses `DateComponents(hour, minute, weekday)` and `repeats: true`. Stopping it mid-block to extend only *this* occurrence would lose the weekly repeat. So extension needs to be a separate one-off DA registration layered on top.

## Approach

### Data model

Add one field on `BlockSession`:

```swift
var scheduledEnd: Date?   // natural end of this occurrence, stamped on session open
```

For one-shot-backed sessions, this is `oneShot.expiresAt`. For schedule-backed sessions, it's the end of the current occurrence, computed via a new `ScheduleClock.currentOccurrenceEnd(…, at:)` helper that mirrors `isActive` logic.

The *effective* end of the session is computed, not stored:

```swift
var effectiveEnd: Date? {
    guard let scheduledEnd else { return nil }
    return scheduledEnd.addingTimeInterval(extensionApplied)
}
```

No new stored fields beyond `scheduledEnd`. `extensionApplied` already exists and is the source of truth for the extension delta.

### Session lifecycle extensions

`ScheduleEngine.reconcileBlockSessions` currently closes any open session whose source is no longer in the active set. Change that rule to:

> A session is "still active" if either its source is active **or** `effectiveEnd != nil && now < effectiveEnd`.

When a session is in its *extension tail* (source inactive but `effectiveEnd > now`), `applyCurrentUnion` must still apply the source's blocklist to the store. Today `applyCurrentUnion` builds the union from the currently-active schedules and one-shots directly; extend it to additionally include blocklists from open sessions that are in their extension tail. Concretely: after computing `activeSchedules`/`activeOneShots`, fetch open `BlockSession` rows, and for any where `scheduledEnd < now < effectiveEnd`, add its linked schedule's or one-shot's selection to the union.

This keeps the shield on during the extension window with zero changes to the ShieldManager API.

### DeviceActivity extension registration

Because `intervalDidEnd` for the natural interval fires at `scheduledEnd` and won't fire again without a new registration, add a one-off `brick.extend.<sessionID>` monitor whenever the session accrues extension:

```swift
func registerExtension(for session: BlockSession) throws
```

- Stops any prior `brick.extend.<sessionID>` registration.
- If `effectiveEnd > now`, starts a new `DeviceActivitySchedule` from `max(now + 1s, scheduledEnd)` to `effectiveEnd`, `repeats: false`.
- The monitor's existing `intervalDidEnd` path runs `applyCurrentUnion` + `reconcileBlockSessions`, which now (with the new rule) sees `now >= effectiveEnd` and closes the session — clearing the shield.

`BreakSessionController.closeRecord` calls this after `engine.endBreak` whenever the closed record had `wasOverage == true`. No-ops when there's no session or the session has no `scheduledEnd`.

### Engine wiring

`BreakQuotaEngine.endBreak` already updates `overageTime` and `extensionApplied`. It does NOT know about DA. Keep it that way: the controller owns DA wiring. Signature stays the same. One behavior tweak: guard the overage additions with `!record.wasOverage` / `record.wasOverage` cleanly, and clamp `session.overageTime` to `overageHardCap` on write so a break that runs over the remaining allowance cannot blow past 15 min (e.g. user starts a 3-min overage with only 2 min of allowance left → only 2 min counts toward `overageTime`/`extensionApplied`).

Controller-side clamp on start: when `isOverage == true`, cap `plannedDuration` to `max(0, overageHardCap - session.overageTime)`. If the remaining allowance is 0, throw `.notAllowed(.overageLockout)`.

### UI

**BreakPickerView.** When `availability == .quotaExhausted(_)`, add an `"Override"` secondary button in the banner footer (small, tertiary style — not prominent). Tapping pushes `OverageRitualView` onto the navigation stack with the already-selected app (if any) and the remaining overage allowance. If no app is selected yet, the ritual screen lets the user pick from the same `blockedTokens` list.

**New `OverageRitualView`.**
- Header: "Override break quota" + subtitle "This will extend your block by 2× the time you take."
- App picker (if not preselected): single-select list of `blockedTokens`. Reuses the picker's row UI.
- Duration stepper: 1/2/3/5 min, capped at remaining allowance (rounded down to minutes; if allowance < 1 min, block the screen behind a `.overageLockout` banner).
- `TextEditor` with a ≥80-char minimum. Character counter updates live: `"42 / 80"`. Counter turns primary color once satisfied.
- 20-second countdown that starts on `onAppear` and runs in a timer. Cannot be reset, skipped, or paused by backgrounding (if user backgrounds, on return the timer restarts from 0 — keeps implementation simple and enforces the friction).
- "Confirm override" primary button. Disabled until: char count ≥80 **AND** countdown == 0 **AND** app selected **AND** duration > 0.
- Confirm → `controller.start(app:, duration:, isOverage: true)` → view dismisses back to the BreakSheet, which auto-routes to `ActiveBreakView` because `controller.active` now exists.

**BreakSheet** adds a navigation destination for the ritual. When `controller.active` becomes non-nil (overage confirmed), the existing `onChange(of: controller.active == nil)` path already transitions the sheet into `ActiveBreakView`, so we just need to pop the ritual off the stack.

**HomeTab.** No change needed — `breakHintNote` already covers `.overageLockout`. The "Take a break" button stays disabled in that state.

## File plan

```
Shared/Models/
└── BlockSession.swift            # add scheduledEnd: Date?, effectiveEnd computed

Shared/Time/
└── ScheduleTime.swift            # add ScheduleClock.currentOccurrenceEnd(...)

Shared/Services/
├── ScheduleEngine.swift          # stamp scheduledEnd on open, extend reconcile rule,
│                                 # include extension-tail sessions in union,
│                                 # new registerExtension(for:)
├── BreakQuotaEngine.swift        # clamp overageTime/extensionApplied to hard cap
└── BreakSessionController.swift  # cap overage plannedDuration, call registerExtension
                                  # after endBreak when wasOverage

Brick/Views/Break/
├── BreakPickerView.swift         # Override secondary action when .quotaExhausted
├── BreakSheet.swift              # route to OverageRitualView
└── OverageRitualView.swift       # new — ritual screen

BrickTests/
└── BreakQuotaEngineTests.swift   # add overage-clamping + cumulative-lockout tests
└── OverageExtensionTests.swift   # new — reconcile keeps session in extension tail;
                                  # applyCurrentUnion unions blocklist during tail;
                                  # cumulative overage flips to hardCap & lockout
```

## Key code shapes

```swift
// ScheduleClock — current occurrence end
static func currentOccurrenceEnd(
    weekdayMask: WeekdayMask,
    startMinute: Int,
    endMinute: Int,
    at instant: Date,
    calendar: Calendar = .current
) -> Date? {
    // If !isActive, return nil.
    // Otherwise find whether we're in the pre-midnight half (today) or
    // post-midnight half (yesterday started the occurrence); compute the
    // Date that corresponds to endMinute accordingly.
}
```

```swift
// BlockSession — additive only
var scheduledEnd: Date?
var effectiveEnd: Date? {
    scheduledEnd.map { $0.addingTimeInterval(extensionApplied) }
}
var isInExtensionTail: Bool {
    guard let scheduledEnd, let effectiveEnd else { return false }
    let now = Date.now
    return now >= scheduledEnd && now < effectiveEnd
}
```

```swift
// ScheduleEngine.reconcileBlockSessions — updated predicate
for session in openSessions {
    let sourceActive: Bool = /* existing check */
    let inExtensionTail = session.effectiveEnd.map { Date.now < $0 } ?? false
        && session.scheduledEnd.map { Date.now >= $0 } ?? false
    if !sourceActive && !inExtensionTail {
        session.actualEnd = instant
    }
}
```

```swift
// ScheduleEngine.applyCurrentUnion — updated union
// ... existing selections
let openSessions = try context.fetch(
    FetchDescriptor<BlockSession>(predicate: #Predicate { $0.actualEnd == nil })
)
let tailSelections: [FamilyActivitySelection] = openSessions.compactMap { s in
    guard let se = s.scheduledEnd, let ee = s.effectiveEnd,
          instant >= se, instant < ee else { return nil }
    return s.schedule?.blocklist?.selection ?? s.oneShotBlock?.blocklist?.selection
}
let union = FamilyActivitySelection.union(scheduleSelections + oneShotSelections + tailSelections)
```

```swift
// ScheduleEngine.registerExtension
func registerExtension(for session: BlockSession) throws {
    let name = DeviceActivityName("brick.extend.\(session.id.uuidString)")
    center.stopMonitoring([name])
    guard let effectiveEnd = session.effectiveEnd,
          let scheduledEnd = session.scheduledEnd,
          effectiveEnd > Date.now else { return }
    let cal = Calendar.current
    let start = max(Date.now.addingTimeInterval(1), scheduledEnd)
    let startComps = cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: start)
    let endComps   = cal.dateComponents([.year,.month,.day,.hour,.minute,.second], from: effectiveEnd)
    try center.startMonitoring(name, during: DeviceActivitySchedule(
        intervalStart: startComps, intervalEnd: endComps, repeats: false
    ))
}
```

```swift
// BreakSessionController — overage clamp + DA handoff
func start(app: ApplicationToken, duration: TimeInterval, isOverage: Bool = false) throws {
    let availability = try engine.canStartBreak()
    let cappedDuration: TimeInterval
    if isOverage {
        guard let session = try engine.openSession() else { throw … }
        let remaining = BreakQuotaEngine.overageHardCap - session.overageTime
        guard remaining > 0 else { throw .notAllowed(.overageLockout) }
        cappedDuration = min(duration, remaining)
    } else {
        /* existing non-overage path */
    }
    …
}

private func closeRecord(id: UUID) {
    …
    if record.wasOverage, let session = record.blockSession {
        try? scheduleEngine.registerExtension(for: session)
    }
    …
}
```

## UI state machine (BreakSheet)

```
                       [picker]
                          |
             tap Start (allowed)      tap Override (.quotaExhausted)
                 v                              v
           [active break]                 [overage ritual]
                 ^                              |
                 |  confirm (≥80 chars + 20s + app + dur)
                 +------------------------------+
```

## Data model delta

- `BlockSession.scheduledEnd: Date?` — new. Defaults nil on existing rows (no migration needed for SwiftData's additive case).
- No other schema change.

## DeviceActivity registrations

- `brick.sched.<scheduleID>.<weekday>[.pre|post]` — existing repeating schedule coverage.
- `brick.oneshot.<oneShotID>` — existing one-shot coverage.
- `brick.extend.<sessionID>` — new, one-off, re-registered whenever overage extension grows.

`ScheduleEngine.sync()` only touches the first two (that's fine; extension registrations are managed lazily as they accrue and cleaned up when the session closes via `reconcile`).

## Edge cases

- **User backgrounds the ritual screen.** 20-s timer resets on return (state-based, not persisted). Justification text may be retained only if the view isn't destroyed; if it is, that's fine — friction is the goal.
- **Overage exactly consumes the remaining allowance.** Next `canStartBreak()` returns `.overageLockout`. `overageTime` is clamped to exactly `overageHardCap`. UI shows locked banner.
- **User ends overage break early.** Works the same — `endBreak` uses actual elapsed time for both `overageTime` and `extensionApplied`. Less extension, cleaner outcome.
- **App backgrounded past the overage's planned end.** Existing `refreshFromStore` self-heal on foreground closes the record and, because `wasOverage == true`, now also re-registers the extension monitor so the shield stays up through `effectiveEnd`.
- **Schedule's next occurrence starts while still in extension tail.** Union recompute handles this: both the old session's tail selection and the new occurrence's selection are unioned (same blocklist or different, both get shielded).
- **Extension registration fails (e.g., FamilyControls authorization revoked).** Log + continue; session still closes at natural end via existing mechanics. Acceptable MVP degradation.

## Verification plan

1. `xcodegen generate && xcodebuild … build` succeeds.
2. `BrickTests`:
   - Existing `testOverageBreakUpdatesExtension` still passes.
   - New `testOverageClampsAtHardCap` — starting a 3-min overage when only 1 min of allowance remains closes with exactly 1 min overage, 2 min extension, and flips `canStartBreak` to `.overageLockout`.
   - New `testReconcileKeepsSessionOpenInExtensionTail` — seed a session with `scheduledEnd == now - 30s`, `extensionApplied == 120`, confirm `reconcileBlockSessions` leaves `actualEnd == nil` and fast-forwarding past `effectiveEnd` closes it.
   - New `testApplyCurrentUnionIncludesExtensionTail` — with a schedule that's no longer naturally active but a session in its tail, union returns the schedule's blocklist selection.
3. On-device manual:
   - Create schedule covering now → +10 min. Exhaust 10-min quota on Instagram (via several small breaks).
   - Try to start another break → banner says quota used, "Override" visible.
   - Tap Override. Try to tap Confirm immediately → disabled. Type 80+ chars before 20s → still disabled. Wait 20s without enough chars → still disabled. Satisfy both → enabled; confirm 2-min overage.
   - Break runs; closes; verify block end (shield) stays up 4 min past the schedule's 10-min end.
   - Accumulate overage to 15 min → picker now shows `.overageLockout` banner; Override button gone.

## Out of scope

- Persisting the 20-s countdown across backgroundings (friction reset is acceptable).
- Extending shield UI to display the ritual reason to the user mid-block (#9).
- Notifications warning the user before hitting lockout (#13).
- Recovering extension registrations that fail due to FamilyControls authorization races.
