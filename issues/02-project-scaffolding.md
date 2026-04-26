# Plan — Issue #2: Project scaffolding + FamilyControls entitlement

## Context

Brick is a personal iOS app blocker (see `PRD.md`, `PLAN.md`) designed to improve on Opal with a structured break budget and critical-call passthrough via iOS Focus. The repo currently contains only the PRD and PLAN — no code. Every subsequent issue (#3 through #15) depends on a working Xcode project with the main app plus three `FamilyControls` extensions. This slice lays that foundation: a buildable project, SwiftData container initialized, FamilyControls authorization requested, and a TabView shell the later UI slices can populate.

**Decisions already made:**
- Project generation: **XcodeGen** (declarative `project.yml`, reproducible, diff-friendly).
- Bundle ID prefix: **`com.amshahedhasan.brick`**.
- FamilyControls entitlement: **development-tier** for now (production approval from Apple is pending). Production entitlement swaps in before App Store submission.

## Approach

Generate a four-target Xcode project via XcodeGen, driven by a single `project.yml` at the repo root. Source files live in per-target folders; entitlements, Info.plist keys, and the shared App Group are declared in YAML. The generated `Brick.xcodeproj` is gitignored — only the YAML + sources are committed. This lets me iterate on project structure without hand-editing `pbxproj`.

**Bundle IDs:**
- App: `com.amshahedhasan.brick`
- Extensions: `com.amshahedhasan.brick.DeviceActivityMonitor`, `.ShieldConfiguration`, `.ShieldAction`
- App Group: `group.com.amshahedhasan.brick` (shared by all four targets)

**FamilyControls entitlement value:** `com.apple.developer.family-controls` = `true` on all four targets. This is the development-tier key; when Apple grants distribution, no code change is needed — only the provisioning profile updates.

## Repo layout after this slice

```
brick/
├── project.yml                         # XcodeGen config — declares all 4 targets
├── .gitignore                          # ignores Brick.xcodeproj, DerivedData, xcuserdata
├── Brick/
│   ├── BrickApp.swift                  # @main, SwiftData container, FamilyControls auth
│   ├── RootView.swift                  # TabView shell
│   ├── Views/
│   │   ├── HomeTab.swift               # placeholder
│   │   ├── BlocklistsTab.swift         # placeholder
│   │   ├── SchedulesTab.swift          # placeholder
│   │   └── SettingsTab.swift           # placeholder
│   ├── SharedContainer.swift           # App Group URL helper used by app + extensions
│   ├── Info.plist                      # minimal; most keys via project.yml
│   ├── Brick.entitlements              # family-controls + App Groups
│   └── Assets.xcassets/                # AppIcon + AccentColor (empty sets)
├── DeviceActivityMonitorExtension/
│   ├── DeviceActivityMonitorExtension.swift  # subclass, stubs for intervalDidStart/End
│   ├── Info.plist                      # NSExtension dict for DeviceActivityMonitor
│   └── DeviceActivityMonitorExtension.entitlements
├── ShieldConfigurationExtension/
│   ├── ShieldConfigurationExtension.swift    # ShieldConfigurationDataSource, default config
│   ├── Info.plist                      # NSExtension dict for ShieldConfiguration
│   └── ShieldConfigurationExtension.entitlements
└── ShieldActionExtension/
    ├── ShieldActionExtension.swift     # ShieldActionDelegate, .close response stub
    ├── Info.plist                      # NSExtension dict for ShieldAction
    └── ShieldActionExtension.entitlements
```

## Key file contents

**`project.yml`** — declares:
- `options.deploymentTarget.iOS: "17.0"`, Swift 5.9
- 4 targets with matching bundle IDs, entitlement files, and Info.plists
- App Group capability on all 4, FamilyControls on all 4
- Main app embeds all 3 extensions (`dependencies: [{target: ..., embed: true}]`)
- Per-target `settings.base.DEVELOPMENT_TEAM` left empty (user sets in Xcode once, persists in xcconfig)

**`Brick/BrickApp.swift`:**
- `@main struct BrickApp: App`
- `init()` — kicks off a `Task` that calls `AuthorizationCenter.shared.requestAuthorization(for: .individual)` and logs the result
- `.modelContainer(for: [], ...)` with a `ModelConfiguration(url:)` pointing at the App Group container URL so extensions can read the same SwiftData store (schema intentionally empty — added in #3+)

**`Brick/SharedContainer.swift`:**
- `static let appGroup = "group.com.amshahedhasan.brick"`
- `static var storeURL: URL` — resolves App Group container + `Brick.sqlite`
- Used by main app and extensions for consistent SwiftData URLs

**`Brick/RootView.swift`:** `TabView` with four tabs, each showing a placeholder `Text` view with the tab name so it's visually obvious the shell renders.

**Extension source files:** each subclass has a single method override returning/logging defaults — just enough to compile and register with the system. No business logic.

**Entitlements files** (all four): `com.apple.developer.family-controls: true` + `com.apple.security.application-groups: [group.com.amshahedhasan.brick]`.

## Critical files to create

1. `/Users/sh/workspace/brick/project.yml`
2. `/Users/sh/workspace/brick/.gitignore`
3. `/Users/sh/workspace/brick/Brick/BrickApp.swift`
4. `/Users/sh/workspace/brick/Brick/RootView.swift`
5. `/Users/sh/workspace/brick/Brick/SharedContainer.swift`
6. `/Users/sh/workspace/brick/Brick/Views/{Home,Blocklists,Schedules,Settings}Tab.swift`
7. `/Users/sh/workspace/brick/Brick/Info.plist`, `Brick.entitlements`
8. Three extension folders, each with `.swift`, `Info.plist`, `.entitlements`

## Tooling steps

1. `sudo xcode-select -s /Applications/Xcode.app` — command-line tools are selected now; Xcode must be the active developer dir for `xcodebuild`.
2. `brew install xcodegen` — install the generator.
3. `xcodegen generate` from repo root — creates `Brick.xcodeproj` from `project.yml`.
4. `xcodebuild -project Brick.xcodeproj -scheme Brick -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO` — smoke-test that all four targets compile. (Signing is skipped in CI; you'll sign with your dev team in Xcode.)

## Verification plan

1. **Compile check (automated):** `xcodebuild ... CODE_SIGNING_ALLOWED=NO build` succeeds for all four targets with no errors. This confirms structure is correct and all FamilyControls APIs are referenced correctly.
2. **Open in Xcode:** Xcode opens the project, all four targets appear, "Signing & Capabilities" shows FamilyControls + App Groups on each. User sets their Apple Developer team once per target.
3. **Install on device:** physical iPhone on iOS 17+ (simulator can't exercise FamilyControls meaningfully). App launches, FamilyControls authorization prompt appears, tapping "Allow" returns success to the log.
4. **Verify shell:** TabView with four tabs (Home, Blocklists, Schedules, Settings) renders; each shows its placeholder text.
5. **SwiftData container:** app launches without any SwiftData initialization errors in the log (schema is empty at this slice — just verifying the container URL and App Group access).
6. **App Group access:** add a one-time debug log in both `BrickApp.init()` and the `DeviceActivityMonitorExtension`'s stub `intervalDidStart` that writes a timestamp to the App Group container; confirm both can read/write (the extension log is visible via Console.app filtering by the extension process). Remove the log before closing the issue.

## Out of scope for this slice

- Any SwiftData models (`Blocklist`, `Schedule`, etc.) — those come with the issues that use them (#3+).
- Any business logic in the extensions — only stubs that compile.
- Notifications setup (`UNUserNotificationCenter` request) — belongs to #13.
- CI / test targets — not requested; add when #6 (`BreakQuotaEngine` tests) needs them.
- Production FamilyControls entitlement swap — waits on Apple approval.
