# Issue #30 — Test template: start T+2, run 10 min (end T+12)

## Problem
Fast variant of the "Test (now)" template currently starts T+7 and runs to T+17. The 7-minute pre-start wait is too long for iterative debugging.

## Solution
Two-line change in `Shared/Models/Template.swift`:
- `startOffset` 7 → 2
- `endOffset` 17 → 12

Update the name + description to reflect the new T+2 / T+12 window. Update the corresponding footnote in `Brick/Views/SettingsTab.swift:130`.

## Notes
- The 5-min-before-start notification has a 300s lead. With a 120s start offset, `leadInterval` (NotificationService.swift:202-205) returns nil and the notification is silently skipped. That's expected — user already validated that notification on the prior T+7 window.
- The 1-min-before-end notification still fires at T+11 (60s before T+12).

## Acceptance
- [ ] `testNowTemplate` uses offsets 2 / 12
- [ ] Template name + description match
- [ ] Settings → Debug footnote matches
- [ ] Build green
