# Issue #36 — Quota: minute-ceiling, refund on early end

## Decisions (confirmed)
- **Option B**: refund the unused portion when the user ends a break early.
- **B1**: `ceil(actual_seconds / 60)` minutes are charged. No floor.

## Behavior

| Break planned | Break ended after | Charged |
|---|---|---|
| 3 min | 1 min 20 s | 2 min |
| 3 min | 59 s | 1 min |
| 3 min | 0 s | 0 min |
| 3 min | 2 min 0 s | 2 min |
| 3 min | 3 min 0 s | 3 min |
| 3 min | 3 min 30 s (timer jitter) | 3 min — capped at planned |

## Implementation

**`Shared/Services/BreakQuotaEngine.swift` — `endBreak(_:at:)`**

```swift
func endBreak(_ record: BreakRecord, at instant: Date? = nil) throws {
    let rawEnd = instant ?? clock.now
    // Ceiling to the next whole minute, then cap at the planned end so
    // timer-jitter past plannedEnd doesn't over-charge.
    let rawDuration = max(0, rawEnd.timeIntervalSince(record.startTime))
    let roundedDuration = ceil(rawDuration / 60) * 60
    let rounded = record.startTime.addingTimeInterval(roundedDuration)
    let endTime = min(rounded, record.plannedEnd)
    record.endTime = endTime
    let duration = endTime.timeIntervalSince(record.startTime)
    if let session = record.blockSession {
        session.totalBreakTime += duration
        if record.wasOverage {
            let clamped = min(session.overageTime + duration, Self.overageHardCap)
            session.overageTime = clamped
            session.extensionApplied = clamped * Self.overagePenaltyMultiplier
        }
    }
    try context.save()
}
```

`BreakRecord.overlap(in:now:)` already uses `endTime` and a window — no changes needed downstream. `recordsInWindow`, `totalOverlap`, `earliestDecay` all see the rounded data automatically.

## Tests
Existing tests use clean minute boundaries (e.g., `clock.advance(by: 4 * 60)`), so they continue to pass with no math change. Add three new tests:

1. End 1 s into break → charged 1 min.
2. End 1 min 20 s into break → charged 2 min.
3. Stop at exactly `plannedEnd + 0.5s` (jitter) → charged exactly `plannedDuration`.

## Out of scope
- Display rounding (UI countdowns still show m:ss for liveness — the rounding is purely accounting).
- Overage-quota rounding rules (kept consistent: overage time also rounds up per the same formula since it flows through the same code path).
