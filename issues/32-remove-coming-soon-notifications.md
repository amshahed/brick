# Issue #32 — Remove stale "Coming soon" section in Settings

## Problem
`SettingsTab.swift:61-64` shows a "Coming soon" section listing "Notifications", but notifications shipped in #13 / #26 / #27 / #28. The section is now misleading.

## Fix
Delete the section. Notification permission is already requested at app launch (`BrickApp.swift:38`). A real notifications-settings page (system deep-link, per-category toggles) is its own future ticket if we want one.

## Acceptance
- [ ] Section removed
- [ ] Build green
