# Plan — Issue #11: Focus integration + onboarding nudge (revised)

## Context

The original implementation of this issue introduced a `FocusManager` service that donated `INSetFocusStatusIntent` from `ScheduleEngine.applyCurrentUnion(at:)`, framed as activating a companion "Brick" Focus. **That approach does not work on iOS.** Verified against Apple's API surface:

- `INSetFocusStatusIntent` is for an app to *report* its own focus state, not to flip a system Focus.
- Donating an `INInteraction` does not trigger Shortcuts personal automations — those fire on user-defined triggers (app open, time, location, focus change), not on intent donations.
- There is no public AppIntents or SiriKit path for a third-party app to activate a user's Focus mode.
- The only iOS-supported triggers for activating a Focus are user-driven: manual toggle, the Focus's own Schedule, or a Shortcuts Personal Automation the user creates themselves.

`FocusManager` therefore never had a measurable effect; it was theatre. Worse, it broke the build whenever the file leaked into an app-extension target's compile unit (because `INSetFocusStatusIntent` is unavailable in the `iOSApplicationExtension` compilation environment).

This revised plan **removes the runtime service entirely** and re-shapes Focus integration as a documentation-only flow. Brick teaches the user how to wire iOS to do the toggling; Brick code never touches Focus state.

User-visible surfaces:
1. **Onboarding guide** in Settings — three step-by-step sections explaining the real mechanism (Focus + activation trigger + emergency bypass), ending in a "I've set up Focus" toggle that flips `AppSettings.focusOnboardingCompleted = true`.
2. **Nudge card** on Home — shown when 3+ blocks have completed and `focusOnboardingCompleted` is false. Dismissible per app session.

`AppSettings.focusOnboardingCompleted` and the completed-blocks count are unchanged from the original landing of this issue.

## Approach

### No FocusManager service

Delete `Shared/Services/FocusManager.swift`. Remove the two `Task.detached { await FocusManager.activate/deactivate() }` calls inside `ScheduleEngine.applyCurrentUnion(at:)`. There is no replacement service — Brick has no business touching Focus state because iOS won't let it.

This also fixes the cross-target compile error: the file no longer exists, so no extension target can fail on `INSetFocusStatusIntent` being unavailable in its compilation environment.

### Onboarding view (rewritten)

`Brick/Views/Focus/FocusOnboardingView.swift` — a `Form` with three sections, plus a confirmation toggle. The sections frame the two real activation paths and are upfront about iOS limits:

- **Section 1 — Create the Focus**: copy explains the user creates a Focus called "Brick" in iOS Settings → Focus and adds Allowed People (family, on-call, partner). Button: `Open Settings` → `UIApplication.openSettingsURLString`.

- **Section 2 — Choose how Focus turns on**: two sub-blocks framed by use case.
  - **For recurring blocks (recommended)**: tells the user to add a Schedule inside their Brick Focus that mirrors their Brick schedule's days/times. iOS handles on/off automatically. Button: `Open Settings`.
  - **For one-shot blocks**: tells the user to open Shortcuts → Automation → "+" → "When App is Opened: Brick" → action "Set Focus: Brick — Turn On." Button: `Open Shortcuts` → `shortcuts://`.

- **Section 3 — Emergency bypass**: copy explains repeated calls within 3 minutes bypass Focus automatically (iOS feature). No setup needed.

- **Section 4 — confirmation**: `Toggle("I've set up Focus", isOn: $done)`. On change to true, calls `AppSettingsStore.markFocusOnboardingComplete()` and dismisses. The toggle is a self-report; Brick does not verify the user's iOS state.

Accessible from Settings tab via the existing "Focus integration" row.

### Home nudge (unchanged)

`Brick/Views/Focus/FocusNudgeCard.swift` stays as-is. Display rule in `HomeTab` is unchanged: show when `completedSessions.count >= 3 && settings?.focusOnboardingCompleted != true && !nudgeDismissed`. Tap "Set up" presents `FocusOnboardingView`.

## File plan

```
Shared/Services/
└── FocusManager.swift              # DELETE

Shared/Services/ScheduleEngine.swift # remove Task.detached FocusManager
                                      # calls in applyCurrentUnion union branch

Brick/Views/Focus/
└── FocusOnboardingView.swift       # rewrite per new sections
```

No model changes. No new files. `FocusNudgeCard.swift` and `HomeTab.swift` integration are unchanged.

## Tests

No unit tests. Both before and after: there's no testable runtime behavior — onboarding is a self-report toggle and the nudge is a derived predicate.

## Edge cases

- **User confirms "I've set up Focus" but skipped step 2.** Self-report; iOS will simply never turn Focus on during blocks. Acceptable — Focus is optional.
- **User picks the Shortcuts path but never creates the matching "off" trigger.** Focus stays on after the block ends until they manually toggle it off or the Focus's own Schedule kicks in. Acceptable for v1; the help copy mentions adding a corresponding off-trigger.
- **User dismisses the nudge, restarts the app, completes no new block.** Nudge reappears because dismissal is session-scoped. Acceptable per spec.
- **User completes blocks but `completedSessions.count` query is slow.** The query fetches only `actualEnd != nil`. Even with hundreds of rows this is fast.
- **User toggles "I've set up Focus" back off.** Not supported. The setting is a one-way flip.

## Verification plan

1. `xcodegen generate` succeeds. `BrickTests` compile. All targets build (extensions no longer fail on `INSetFocusStatusIntent`).
2. Manual (on-device):
   - Settings → Focus integration → all three sections render with correct deep-links.
   - Toggle "I've set up Focus" → row subtitle in Settings reads "Configured" on next visit.
   - Complete three blocks → Home shows nudge card. Dismiss → stays gone this session. Relaunch → nudge returns. Finish onboarding → relaunch → nudge gone.
   - With a real "Brick" Focus + a Focus Schedule matching a Brick schedule: start the Brick schedule → iOS status bar shows the Focus icon at the configured time. End → Focus turns off.
   - With a real "Brick" Focus + a Shortcuts "App opened: Brick → Set Focus On" automation: open Brick → Focus turns on (after the first time the user approves the automation).
   - Without any Focus config: blocks still shield correctly; no crash; no notification weirdness.

## Out of scope

- Programmatically activating a Focus (Apple forbids — confirmed in this revision).
- Reading the user's Focus state to surface "are we in a Focus right now?" indicators.
- Auto-creating Focus, allowed contact lists, schedules, or Shortcuts automations on the user's behalf (no API for any of these).
- Verifying the user actually configured iOS after toggling "I've set up Focus."
- Beeminder/Stickk integration (v2).

## Why this is the right structure

- **Honest with the user**: the onboarding copy describes how iOS actually works. No invisible donation that the user wonders about.
- **Honest with the codebase**: no service file pretending to do work it can't do, and no extension-target compile failures from API availability mismatches.
- **Achievable**: the user can reach the same end state ("Focus turns on with my Brick block, allowed contacts ring through") via mechanisms iOS does support.
