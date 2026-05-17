# Issue #33 — Schedules don't fire when app is closed (iOS 15-min minimum)

## Problem
Reproduced: started the "Test" template (T+2 → T+12, 10 min total), closed the app, waited. Nothing happened at T+2. Opened app at T+3 — block was "ongoing" and "Block started" notification fired at that moment, not at T+2.

## Root cause
`DeviceActivitySchedule` requires `intervalEnd - intervalStart >= 15 minutes`. iOS silently rejects shorter schedules. The 10-minute test template never wakes the `DeviceActivityMonitorExtension`. When the user re-opens the app, `applyCurrentUnion` evaluates the schedule by wall-clock and engages the shield + fires "Block started" at app-open time — masking the missing extension wake-up.

## Plan

### 1. Bump test template to ≥ 15 min
`Shared/Models/Template.swift` — fast variant offsets:
- `startOffset` 2 → 2
- `endOffset` 12 → 18

16-minute window (T+2 → T+18) clears the 15-min minimum with a small buffer. The 1-min-before-end notification fires at T+17.

Update template name + description and the `Brick/Views/SettingsTab.swift` footnote.

### 2. Loud registration logging
`Shared/Services/ScheduleEngine.swift` — at the top of `register(_:Schedule)` and inside `Schedule.register(on:name:start:end:)`, compute the actual interval and `print` it. Also emit a clear warning if the window is `< 15 * 60` seconds. Won't prevent the bad registration (Apple already throws), but makes the silent-failure path noisy.

### 3. Extension wake-up trace
`DeviceActivityMonitorExtension/DeviceActivityMonitorExtension.swift` — `print` on each `intervalDidStart` / `intervalDidEnd` with the activity name and timestamp. Visible via `idevicesyslog -p DeviceActivityMonitorExtension`.

### 4. Document for the user
Add a one-line note to the Settings → Debug footnote: "Real schedules of any length work; the system requires a 15-min minimum, so this test window is set to 16."

## Out of scope
- Sub-15-min schedules. iOS doesn't permit it for content-blocking apps; there's no usable foreground workaround.

## Acceptance
- [ ] Test template fires via the extension at T+2 (verifiable in idevicesyslog) with the app closed
- [ ] "Block started" notification arrives at T+2, not at app-open time
- [ ] Registration logs the computed window and warns on < 15 min
- [ ] Extension logs each wake-up
