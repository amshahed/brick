# Issue #34 — Debug "Fast break timings" not honored by extension

## Problem
With Fast break timings ON, the test schedule fires from a closed app (after #33). But the cold-start on the resulting BlockSession is 25 min, not the debug 2 min.

## Root cause
Process-isolation, two chained:

1. `UserDefaults.standard` is per-process. Main app writes the flag, extension can't see it.
2. `BreakQuotaEngine.applyDebugTimings(_:)` is called only in `BrickApp.init`. The extension's `coldStartDuration` static stays at the production value.

When the extension opens a BlockSession at T+2, it computes `coldStartEnd = actualStart + 25*60`. The app reads that value next time.

## Plan

### 1. Add a shared-defaults accessor
`Shared/SharedContainer.swift`:
```swift
enum SharedDefaults {
    static var shared: UserDefaults {
        UserDefaults(suiteName: SharedContainer.appGroup) ?? .standard
    }
}
```

Fallback to `.standard` keeps simulator / no-entitlement contexts working.

### 2. Route the debug flag through it
Update reads/writes:
- `Brick/BrickApp.swift:21` — initial read at launch
- `Brick/Views/SettingsTab.swift:122,124` — toggle binding
- `Shared/Models/Template.swift:88` — template generation

### 3. Apply debug timings in the extension
`DeviceActivityMonitorExtension.reconcile()`:
```swift
BreakQuotaEngine.applyDebugTimings(
    SharedDefaults.shared.bool(forKey: BreakQuotaEngine.debugFastTimingsKey)
)
```

Call before constructing `ScheduleEngine`. Idempotent.

## Acceptance
- [ ] With Fast timings ON, closed-app trigger records `coldStartEnd - actualStart == 120s`
- [ ] Toggling off restores 1500s on next session
- [ ] Existing UI still reflects toggle state correctly
