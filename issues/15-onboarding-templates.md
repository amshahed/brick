# Issue #15 — Onboarding + templates

## Goal
First-launch onboarding: welcome → FC auth → Brick passcode → Screen Time passcode coaching → template selection → apps per template. Track `hasCompletedOnboarding`. Templates browsable post-onboarding.

## Why two passcodes are coached separately
Brick's local passcode (set in step 3) gates in-app actions during active blocks. Uninstall protection is a separate, OS-level mechanism: the user must (a) set an iOS Screen Time passcode and (b) turn on Settings → Screen Time → Content & Privacy Restrictions → "Deleting Apps: Don't Allow." Together those make iOS itself require the Screen Time passcode to delete any app — Brick included.

This is **not** related to FamilyControls auth mode. Brick uses `.individual` auth (the only mode that works on a personal device — `.child` requires Family Sharing parent–child setup and fails immediately otherwise).

Step 4 is a coaching step that deep-links to Settings and explains both toggles. It's a self-report — Brick can't verify the user actually flipped the iOS settings.

## Design

### `AppSettings` — add flag
- `hasCompletedOnboarding: Bool = false` property + init default.
- Matching `AppSettingsStore.markOnboardingComplete()` helper.

### `Template` + `TemplateLibrary` (Shared/Models)
```
struct Template: Identifiable, Hashable {
    let id: String          // stable slug, e.g. "morning-focus"
    let name: String        // display name
    let description: String // one-line pitch
    let startMinute: Int
    let endMinute: Int
    let weekdayMask: WeekdayMask
    let requiresDateRange: Bool  // Exam, Vacation
}
enum TemplateLibrary {
    static let all: [Template] = [...5 entries...]
}
```

Values:
- Morning Focus — 6:00–10:00, Mon–Fri
- Deep Work — 9:00–17:00, Mon–Fri
- Night Wind-Down — 22:00–07:00 (wraps), daily
- Exam Mode — 8:00–22:00, daily, requiresDateRange
- Vacation Light — 10:00–20:00, daily, requiresDateRange

### `TemplateApplier` (Brick/Models)
`applyTemplate(_:selection:startDate:endDate:)` creates `Blocklist` (named after template) and `Schedule` via existing stores. Unique-name conflicts → append "2", "3"...

### `OnboardingView`
NavigationStack with discrete pages. State machine:
1. Welcome (continue button)
2. FamilyControls auth (button triggers `.child` auth request)
3. Brick passcode (inline reuse of PasscodeSetupView — on complete, advance)
4. **Screen Time passcode + uninstall lockdown coaching** — two sub-steps, both done in iOS Settings:
   - Set the Screen Time passcode (Settings → Screen Time → Lock Screen Time Settings).
   - Turn on Content & Privacy Restrictions and disallow deleting apps (Settings → Screen Time → Content & Privacy Restrictions → ON → iTunes & App Store Purchases → Deleting Apps → Don't Allow).
   Copy explains the trade-off (this affects all apps, not just Brick — that's iOS's design). Recommends same passcode value as Brick passcode for simplicity, or different for stronger commitment. Button: "Open Settings" → `UIApplication.openSettingsURLString`. Toggle: "I've finished both steps" (self-report) enables Continue. A "Skip for now" button is allowed — Brick cannot verify and does not block onboarding on this step.
5. Templates (multi-select list; date pickers for bounded templates; Skip advances to Done)
6. Apps (for each selected template: show picker via `familyActivityPicker`; "Skip this one" button)
7. Done (marks `hasCompletedOnboarding = true`, dismisses)

Presented as `fullScreenCover` from RootView so the user can't tab past.

### RootView rewiring
- Replace passcode-only gate with a combined check: if `!hasCompletedOnboarding` → show OnboardingView; else if `!hasPasscode` → fall back to existing PasscodeSetupView sheet. (Completed onboarding implies passcode exists.)

### Template browsing post-onboarding
- `BlocklistsListView`: toolbar overflow or second button "Start from template" → presents `TemplatePickerSheet` (single-select), which opens the apply flow and creates the scaffold.
- Simpler scope: put a "Start from template" row in the empty-state CTA and as a secondary toolbar button.

### Tests
`TemplateLibraryTests`:
- 5 entries, ids unique, expected times for each.
- Wrap-detection for Night Wind-Down (startMinute > endMinute).

`TemplateApplierTests`:
- Apply creates both Blocklist and Schedule
- Duplicate name is suffixed
- Bounded template respects provided dates

## Files touched
- EDIT `Shared/Models/AppSettings.swift` (add `hasCompletedOnboarding`)
- EDIT `Brick/Models/AppSettingsStore.swift` (`markOnboardingComplete`)
- NEW `Shared/Models/Template.swift`
- NEW `Brick/Models/TemplateApplier.swift`
- NEW `Brick/Views/Onboarding/OnboardingView.swift`
- NEW `Brick/Views/Onboarding/TemplatePickerSheet.swift`
- EDIT `Brick/RootView.swift`
- EDIT `Brick/Views/Blocklists/BlocklistsListView.swift` (template CTA)
- NEW `BrickTests/TemplateLibraryTests.swift`
- NEW `BrickTests/TemplateApplierTests.swift`
