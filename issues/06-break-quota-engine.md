# Plan — Issue #6: Cold-start + break quota engine

## Context

This is the engine at the heart of Brick's thesis: a rolling break budget + cold-start gate that make "take a break" commit the user rather than dissolve the block. Slice #7 (break flow UI), #8 (overage ritual), and #13 (notifications) all call into this engine — nothing about breaks lives in UI-land, it all funnels through one interface. That makes the engine the single highest-value test target in the app, so it must be pure logic with an injectable clock and an in-memory SwiftData store for tests.

## Approach

**Pure-logic module with no iOS-framework dependencies.** `BreakQuotaEngine` imports only `Foundation` + `SwiftData`. `BreakRecord` stores the app token as opaque `Data` — the engine never reifies it to `ApplicationToken`. This lets tests run on any Apple platform via an in-memory `ModelContainer` and lets the engine be exercised without `FamilyControls` entitlements.

**Clock abstraction.** A `Clock` protocol with a `now: Date` property. `SystemClock` for production; a `MockClock` test helper for tests. Every public API takes `at instant: Date = clock.now` so a caller (or test) can supply an override.

**Cold-start lives on `BlockSession`.** Add `coldStartEnd: Date?`. `ScheduleEngine.reconcileBlockSessions` already opens new sessions — extend it so that a session only gets `coldStartEnd = actualStart + 25min` when there is no *other* open session at the moment of creation (no-active-block → active-block transition). Overlapping starts pass through as `coldStartEnd = actualStart` (immediately expired, never gates).

**Rolling window math.** Sum `overlap(break, [now-3600, now])` for every `BreakRecord` where the overlap is non-zero. Open (unclosed) breaks count elapsed time from `startTime` to `min(now, startTime + window)`. Remaining quota = `max(0, 600 - sum)`.

**Overage lockout gate.** `canStartBreak` inspects the *currently-open* `BlockSession` (if any) and returns `.overageLockout` when `overageTime >= 15*60`. Ritual UI is #8; the engine is just the gate.

## Files

```
Shared/Models/
└── BreakRecord.swift                 # new
Shared/Models/BlockSession.swift      # add coldStartEnd

Shared/Services/
├── Clock.swift                       # protocol + SystemClock
├── BreakQuotaEngine.swift            # new — canStart / remaining / start / end / overage
└── ScheduleEngine.swift              # reconcileBlockSessions sets coldStartEnd correctly

BrickTests/
├── BreakQuotaEngineTests.swift       # rolling window, cold-start, overage, cross-block
├── ScheduleEngineColdStartTests.swift # arming behavior across overlapping sessions
└── TestSupport/
    ├── MockClock.swift
    └── InMemoryStore.swift
```

## Data model

```swift
@Model final class BreakRecord {
    @Attribute(.unique) var id: UUID
    var blockSession: BlockSession?
    var startTime: Date
    var endTime: Date?              // nil while active
    var appTokenData: Data          // opaque; encoded ApplicationToken (set by #7)
    var wasOverage: Bool
}

// BlockSession gains:
var coldStartEnd: Date?             // nil if never armed; <= actualStart if overlap transition
```

## `BreakAvailability`

```swift
enum BreakAvailability: Equatable {
    case allowed(remainingQuota: TimeInterval)
    case coldStart(endsAt: Date)
    case quotaExhausted(availableAt: Date)     // earliest decay time
    case overageLockout
    case noActiveBlock                         // nothing to break from
}
```

Note the extra `.noActiveBlock` — the engine needs to handle the UI calling it when nothing is blocked.

## Engine interface

```swift
protocol Clock { var now: Date { get } }
struct SystemClock: Clock { var now: Date { .now } }

struct BreakQuotaEngine {
    static let windowDuration: TimeInterval = 60 * 60
    static let quotaCap: TimeInterval = 10 * 60
    static let coldStartDuration: TimeInterval = 25 * 60
    static let overageHardCap: TimeInterval = 15 * 60

    let context: ModelContext
    let clock: Clock

    func canStartBreak(at: Date? = nil) throws -> BreakAvailability
    func remainingQuota(at: Date? = nil) throws -> TimeInterval
    @discardableResult
    func startBreak(appTokenData: Data, isOverage: Bool, at: Date? = nil) throws -> BreakRecord
    func endBreak(_ record: BreakRecord, at: Date? = nil) throws
    func overageAllowed(for session: BlockSession) -> Bool
}
```

Implementation highlights:
- `canStartBreak` fetches open session → overage check → cold-start check → quota check → allowed.
- `remainingQuota` does a single `FetchDescriptor` for `BreakRecord` with `startTime >= now - windowDuration`, computes overlap math in-memory (predicate arithmetic across dates is cleaner in Swift).
- `.quotaExhausted(availableAt:)` returns the earliest time the window frees up — the moment the oldest-in-window break's `endTime` falls out. This lets the UI show "Next break in 2m 14s" without a second call.
- `endBreak` closes the record, increments `BlockSession.totalBreakTime`, and if `wasOverage` adds to `BlockSession.overageTime` + computes `extensionApplied = overageTime * 2`. (Shield-extension application to schedule end is #8's job; the engine just does the math on the session.)

## ScheduleEngine: cold-start arming change

Before (current):
```swift
for schedule in active.schedules where !coveredScheduleIDs.contains(schedule.id) {
    context.insert(BlockSession(schedule: schedule, actualStart: instant))
}
```

After:
```swift
let hadPriorOpenSession = !openSessions.isEmpty
for schedule in active.schedules where !coveredScheduleIDs.contains(schedule.id) {
    let session = BlockSession(schedule: schedule, actualStart: instant)
    session.coldStartEnd = hadPriorOpenSession
        ? instant                                       // overlap: already warm
        : instant.addingTimeInterval(BreakQuotaEngine.coldStartDuration)
    context.insert(session)
}
```

Same logic for one-shots. "Had a prior open session" is evaluated against the snapshot *before* we opened new ones this tick — so two simultaneous starts in the same reconcile arm once (the first one), not zero or two. This matches user intent: "any first-run transition into blocked state arms the cold-start."

## Unit tests

All tests use in-memory SwiftData + `MockClock`. Core cases drawn from the issue:

- **Rolling window decay**: two 5-min breaks 45 min apart → only the recent one counts.
- **Window partial overlap**: break from T-62m..T-58m (4 min, 2 min in window) → 2 min counted.
- **Cap enforcement**: three 4-min breaks within window → remaining = 0, not -2 min.
- **Cold-start**: attempt at +10m after session start → `.coldStart`; at +26m → `.allowed`.
- **Cold-start non-re-arm**: open session A at T. Open session B at T+5m. B's `coldStartEnd <= actualStart` (no re-arm), verified via `ScheduleEngine.reconcileBlockSessions`.
- **Cross-block continuity**: 5-min break at T-20m during block A; block A closes at T-15m; block B opens at T-10m with cold-start long since expired via mock; remaining quota at T = 5 min.
- **Overage lockout**: session with `overageTime = 14*60` → `overageAllowed = true`; at `15*60` → `false`; engine returns `.overageLockout`.
- **Active break in quota math**: open break since T-3m → counts 3 min against the window.
- **quotaExhausted.availableAt**: three 4-min breaks ending at T-5, T-15, T-25 → `availableAt = (oldest endTime) + 60min`.

## Verification

1. `xcodegen generate && xcodebuild -target Brick -sdk iphoneos18.2 … build` — app still builds.
2. `xcodebuild -target BrickTests -sdk iphoneos18.2 … build` — test target compiles.
3. Running the tests requires an iOS simulator runtime, which isn't installed on this machine. User can run `xcodebuild test -scheme Brick -destination 'platform=iOS Simulator,name=<installed simulator>'` once a runtime is downloaded, or run in Xcode.
