# Issue #15 — Onboarding + templates

## Goal
First-launch onboarding: welcome → FC auth → passcode → template selection → apps per template. Track `hasCompletedOnboarding`. Templates browsable post-onboarding.

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
2. FamilyControls auth (button triggers request)
3. Passcode (inline reuse of PasscodeSetupView — on complete, advance)
4. Templates (multi-select list; date pickers for bounded templates; Skip advances to Done)
5. Apps (for each selected template: show picker via `familyActivityPicker`; "Skip this one" button)
6. Done (marks `hasCompletedOnboarding = true`, dismisses)

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
