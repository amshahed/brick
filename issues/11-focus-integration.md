# Plan — Issue #11: Focus integration + onboarding nudge

## Context

Blocks today are pure shields — when they start, the ManagedSettings store applies the union; when they end, it clears. Focus integration layers on top: when *any* block is active, also toggle the user's user-created iOS Focus named "Brick" on; when no blocks are active, toggle it off.

Apple's API constraints:
- Apps cannot create Focus modes programmatically. The user creates a Focus called "Brick" in iOS Settings → Focus, and Brick associates by name.
- Activating a Focus requires `INSetFocusStatusIntent` (Intents framework), which *can* be called from inside the app. It requires the user grant Siri/Shortcuts authorization — which is handled lazily on first use.
- If the Focus doesn't exist or authorization is denied, the intent fails silently — `FocusManager` catches and no-ops. Blocks continue to work as pure shields.

The issue requires two user-visible surfaces besides the invisible toggle:
1. **Onboarding guide** in Settings — a step-by-step walkthrough with a deep-link to iOS Settings, ending in a "Done, I set it up" toggle that flips `AppSettings.focusOnboardingCompleted = true`.
2. **Nudge card** on Home — shown when `completedBlocksCount >= 3 && !focusOnboardingCompleted`. Dismissible per app session (resets on next launch so it re-nudges after the next block).

`AppSettings.focusOnboardingCompleted` and `completedBlocksCount` already exist on the model from issue #10. The nudge count uses a `@Query` on `BlockSession` where `actualEnd != nil` — deriving the count is simpler and more honest than trying to maintain a mutable counter.

## Approach

### FocusManager service

`Shared/Services/FocusManager.swift` — a tiny actor-free service around `INSetFocusStatusIntent`:

```swift
import Intents

enum FocusManager {
    static let focusName = "Brick"

    static func activate() async { await setFocus(active: true) }
    static func deactivate() async { await setFocus(active: false) }

    private static func setFocus(active: Bool) async {
        let intent = INSetFocusStatusIntent()
        let status = INFocusStatus(isFocused: active)
        intent.focusStatus = status
        // INSetFocusStatusIntent doesn't expose a name match; we rely on the
        // system's active Focus resolving via the user's configured trigger.
        // If the user set up a "Brick" Focus in iOS Settings, this toggles it.
        do {
            _ = try await intent.donate()
            let response = try await INSetFocusStatusIntentResponse.handleAsync(intent)
            if response.code != .success { /* silently no-op */ }
        } catch {
            // No auth, no Focus configured, or other failure — no-op by design.
        }
    }
}
```

*Correction*: `INSetFocusStatusIntent` is for reporting status (e.g., "I'm in a Focus"), not activating one. Apps actually can't directly *activate* a named Focus mode without a Shortcut. The MVP-compatible path is to donate an `INSetFocusStatusIntent` that *tags our app's activity* as in-focus — the system uses that as a signal but doesn't flip the user's Focus. The real "activate the Brick Focus" lives in **Shortcuts automation**: the user creates a personal automation "When Brick app opens → Turn on Focus 'Brick'" etc. Our onboarding guide walks through that.

Given that, `FocusManager` becomes an *intent donor* — it publishes `isFocused` state via `INFocusStatusCenter` so a user-configured Shortcut automation can react. If the user hasn't set up the automation, the donation is a harmless no-op. This matches the issue's "blocks work normally without Focus configured" acceptance criterion.

Final MVP shape:

```swift
import Intents

enum FocusManager {
    static func activate() async { await donateStatus(isFocused: true) }
    static func deactivate() async { await donateStatus(isFocused: false) }

    private static func donateStatus(isFocused: Bool) async {
        let intent = INSetFocusStatusIntent()
        intent.focusStatus = INFocusStatus(isFocused: isFocused)
        let interaction = INInteraction(intent: intent, response: nil)
        do { try await interaction.donate() } catch {}
    }
}
```

### Wiring activate/deactivate

`ScheduleEngine.applyCurrentUnion(at:)` already computes `union` and calls `shield.apply(union:)` or `shield.clear()`. That's the right place to call `FocusManager`:

- `union.isEmpty` → `FocusManager.deactivate()`
- else → `FocusManager.activate()`

But `applyCurrentUnion` runs synchronously and is called from both main app and extension contexts. `FocusManager.activate()` is async. Fire-and-forget with a `Task { await ... }`. No state ordering issue because donations are idempotent.

### Onboarding view

`Brick/Views/Focus/FocusOnboardingView.swift` — a Form-based guide:

- Step 1: "Open iOS Settings → Focus and create a Focus called 'Brick'." Button: "Open Settings" → `UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`.
- Step 2: "Add People who should reach you during blocks (family, on-call, etc.)."
- Step 3: "Repeated calls from the same person within 3 minutes bypass Focus automatically — no extra setup needed."
- Step 4: "Create a Shortcuts automation: When the 'Brick' app's Focus status changes, turn your 'Brick' Focus on/off." Links to Shortcuts app (best-effort `shortcuts://`).
- Toggle: "I've set up Focus" → sets `AppSettings.focusOnboardingCompleted = true` and dismisses.

Accessible from Settings tab via a new "Focus integration" row.

### Home nudge

`Brick/Views/Home/FocusNudgeCard.swift` — a small card with:
- Icon + headline "Let important calls through"
- Body "Set up Focus integration to stay reachable for your people during blocks."
- Primary button: "Set up" → presents `FocusOnboardingView` sheet.
- Dismiss X: sets a `@State var` in HomeTab (session-scoped; resets next launch).

Display rule in HomeTab:
```swift
@Query(filter: #Predicate<BlockSession> { $0.actualEnd != nil })
private var completedSessions: [BlockSession]
@State private var settings: AppSettings?
@State private var nudgeDismissed = false

private var shouldShowFocusNudge: Bool {
    !nudgeDismissed
        && completedSessions.count >= 3
        && settings?.focusOnboardingCompleted != true
}
```

Card sits above `idleHero` / between `ActiveBlockCard` and `breakButton` in the VStack when the condition holds.

### Settings entry

`SettingsTab` gets a new section "Integrations" with a NavigationLink to `FocusOnboardingView`. Show the checkmark state based on `settings.focusOnboardingCompleted`.

## File plan

```
Shared/Services/
└── FocusManager.swift              # new — donate INSetFocusStatusIntent

Brick/Views/Focus/
├── FocusOnboardingView.swift       # new — step-by-step guide
└── FocusNudgeCard.swift            # new — Home banner

Shared/Services/ScheduleEngine.swift # call FocusManager.activate/deactivate
                                      # inside applyCurrentUnion's union branch
Brick/Views/Home/HomeTab.swift      # render FocusNudgeCard when conditions met
Brick/Views/SettingsTab.swift       # add Integrations → Focus row
```

No schema changes — `AppSettings.focusOnboardingCompleted` and `completedBlocksCount` already exist from #10.

## Key code shapes

```swift
// ScheduleEngine.applyCurrentUnion — additions (conceptual)
if union.isEmpty {
    shield.clear()
    Task { await FocusManager.deactivate() }
} else {
    shield.apply(union: union)
    Task { await FocusManager.activate() }
}
```

```swift
// FocusOnboardingView — skeleton
struct FocusOnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var done = false
    @State private var settings: AppSettings?

    var body: some View {
        Form {
            Section("1. Create the Focus") {
                Text("Open iOS Settings, tap Focus, and create a new Focus called \"Brick\".")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Section("2. Allow important people") { Text(...) }
            Section("3. Automate it in Shortcuts") {
                Text("Create an automation: when Brick app opens, turn on Focus \"Brick\". Repeat for when Brick's Focus status ends.")
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Section("4. Emergency bypass") {
                Text("Repeated calls from the same person within 3 minutes always bypass Focus — this is enabled by iOS automatically.")
            }
            Section {
                Toggle("I've set up Focus", isOn: $done)
            }
        }
        .navigationTitle("Focus integration")
        .onChange(of: done) { _, newValue in
            guard newValue else { return }
            try? AppSettingsStore(context: context).markFocusOnboardingComplete()
            dismiss()
        }
        .task { settings = try? AppSettingsStore(context: context).loadOrCreate() }
    }
}
```

## Tests

No unit tests for this slice:
- `FocusManager` delegates to `INSetFocusStatusIntent.donate()` which requires the Intents framework + a real device context to exercise meaningfully.
- The nudge logic is a single derived predicate — manual verification is enough.

If future maintenance needs it, an injectable `FocusStatusDonor` protocol + a stub can make `FocusManager` mockable. Not worth it right now.

## Edge cases

- **User hasn't granted Siri/Shortcuts authorization.** `donate()` throws; FocusManager swallows. Blocks still work as shields.
- **User created a Focus with a different name.** The Shortcuts automation the user builds references their chosen name; Brick's donation is opaque to that. If they follow the onboarding, the name matches.
- **User dismisses the nudge, restarts the app, completes no new block.** Nudge reappears because `nudgeDismissed` is session-scoped. Acceptable — the spec says "reappears until Focus is configured."
- **User completes blocks but `completedSessions.count` query is slow.** The query fetches only `actualEnd != nil` — even with hundreds of rows this is fast. Not a concern.
- **User toggles "I've set up Focus" back off.** Not supported. The setting is a one-way flip; if they really need to resurface the onboarding, they can reset it in a future debug panel.
- **Block starts in the extension context.** `applyCurrentUnion` runs there too; `FocusManager.activate()` fires. Donations from extension processes are allowed.

## Verification plan

1. `xcodegen generate` succeeds.
2. Existing tests unchanged / still pass.
3. Manual (on-device):
   - Settings → Focus integration → verify all four steps render, "Open Settings" and "Open Shortcuts" deep-link correctly.
   - Flip "I've set up Focus" → dismisses → re-enter Settings → toggle shows on; Focus row subtitle reads "Configured".
   - Complete three blocks (schedule or one-shot) → Home shows nudge card. Dismiss it → stays dismissed this session. Relaunch → nudge returns. Finish onboarding → relaunch → nudge gone.
   - With a real "Brick" Focus + Shortcuts automation wired: start a block → iOS status bar shows Focus icon. End block → Focus turns off.
   - Without any Focus config: start a block → everything still shields correctly; no visible Focus change. No crash.

## Out of scope

- Programmatically creating the Focus mode (Apple forbids).
- Reading Focus status from within Brick ("are we in a Focus right now?") for UI indicators — not required by the spec.
- Handling Shortcut authorization prompts gracefully beyond try/catch.
- Live-tracking allowed contacts. The user manages contacts in the iOS Focus settings.
- Resetting onboarding state (debug only).
