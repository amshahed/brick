# Issue #38 — UI test audit and gap fill

## Audit summary

| File | State | Action |
|---|---|---|
| `BlocklistFlowUITests` | OK | none |
| `ScheduleFlowUITests` | stale (template-name regression from #33/#34) | fix name assertion + reset SharedDefaults |
| `OneShotBlockUITests` | OK (passes through ActiveBlockTimerRow's `Cancel <name>` accessibility label) | none |
| `PasscodeGateUITests` | OK | none |
| `ActiveBlockLockdownUITests` | OK | none |
| `TravelModeUITests` | OK | none |
| `ScreenshotsForVerification` | OK (non-assertive) | none |

## Plan

### Test-case helper fix
`BrickUITestCase.launchInResetMainApp`: when `--ui-test-reset-store` is set, also clear all keys under the app-group `SharedDefaults` suite so the debug-fast-timings flag (and any future shared keys) don't leak across runs. Implement via a new launch arg `--ui-test-reset-shared-defaults` handled in `BrickApp.applyUITestPreContainerFlags`.

### Existing-test fix
`ScheduleFlowUITests.testDebugTestNowTemplateIsAvailable`: assert that some `"Test (...)"` template exists rather than pinning to a specific name. Names are display strings tuned for the dev workflow and shouldn't be the contract.

### New tests

1. `SettingsTabUITests.testNoComingSoonSection` (#32) — assert no static text containing "Coming soon".
2. `SettingsTabUITests.testFastTimingsToggleChangesTestTemplateName` (#34) — toggle on → Schedules → template picker → see the fast-variant name; toggle off → see the slow-variant name.
3. `HomeProgressRowUITests.testActiveScheduleShowsTimerRow` (#35) — seed active schedule, assert "BLOCK ACTIVE" eyebrow + schedule name on home; no "Take a break" button.
4. `SwipeDeletePasscodeGatingUITests.testCancelGateKeepsScheduleVisible` (cleanup commit) — seed active schedule, swipe-delete, tap Delete, cancel the passcode gate, assert the row is still on screen.
5. Same pattern for an active blocklist.

## Acceptance
- [ ] Stale template-name assertion removed
- [ ] New launch arg resets SharedDefaults
- [ ] 5 new UI tests, each passing in CI sim
- [ ] No regression in existing tests
