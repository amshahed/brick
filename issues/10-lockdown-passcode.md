# Plan — Issue #10: Lockdown mode + passcode

## Context

The current app requests FamilyControls `.individual` authorization (see `BrickApp.init`) which is sufficient for the shield but does *not* enable uninstall protection. The issue requires `.child` mode — that's what tells the OS to require the user's Screen Time passcode before uninstalling the app, and it lets Brick gate Screen Time setting changes.

The blocking machinery already knows when a schedule or one-shot is active: `ScheduleEngine.applyCurrentUnion(at:)` returns `ActiveSources { schedules, oneShots }`. A lighter, read-only predicate is all we need for "is this resource currently enforced?" — that lets us decide when to gate mutations.

"Lockdown" in this issue is split into two mechanisms:
- **OS-level**: `.child` FamilyControls authorization (uninstall + Screen Time changes).
- **App-level**: our own passcode gate on three mutations that would functionally disable an active block: toggling off / deleting an active schedule, canceling an active one-shot, and editing the blocklist an active source is using.

All three app-level gates share one `PasscodeGate` UI primitive with its own 3-attempt cooldown. The passcode is a *commitment device*, not a credential (per spec), so it lives in SwiftData with a salted SHA-256 hash — not Keychain.

Onboarding per se is issue #15; for this slice, passcode setup is required on first launch if `AppSettings.passcodeHash == nil`, via a blocking sheet presented over `RootView`. That same setup view is reused from Settings for passcode change.

## Approach

### Data model

New SwiftData model in `Shared/Models/AppSettings.swift`:

```swift
@Model final class AppSettings {
    @Attribute(.unique) var singletonKey: String   // always "default"
    var passcodeHash: String?                      // SHA-256 hex, nil until set
    var passcodeSalt: String?                      // random 16-byte hex
    var passcodeModeRaw: String                    // "user" | "generated"
    var focusOnboardingCompleted: Bool
    var completedBlocksCount: Int
    var createdAt: Date
}
```

The `singletonKey` unique attribute ensures one row; a fetch helper creates it on demand. `completedBlocksCount` is wired up in this slice too (incremented from `ScheduleEngine.reconcileBlockSessions` when a session closes) so later issues can reuse it. `focusOnboardingCompleted` is just stored — the actual onboarding flow lands in #11/#15.

Add `AppSettings.self` to the schema in `BrickApp.sharedModelContainer`.

### Passcode service

`Shared/Services/PasscodeService.swift` — pure, no SwiftData:

```swift
enum PasscodeService {
    static func generateRandom() -> String      // 6 digits
    static func isValidUserChosen(_ code: String) -> Bool  // 4-6 digits
    static func makeSalt() -> String            // 16 random bytes, hex
    static func hash(_ code: String, salt: String) -> String  // SHA-256 hex of salt||code
    static func verify(_ code: String, hash: String, salt: String) -> Bool
}
```

Uses `CryptoKit` + `SecRandomCopyBytes`. Timing-safe compare via constant-time byte compare on the hex strings.

### Lockdown manager

`Shared/Services/LockdownManager.swift`:

```swift
enum LockedAction {
    case editBlocklist(Blocklist)
    case deleteBlocklist(Blocklist)
    case disableSchedule(Schedule)
    case deleteSchedule(Schedule)
    case cancelOneShot(OneShotBlock)
}

struct LockdownManager {
    let context: ModelContext
    func isLocked(_ action: LockedAction, at instant: Date = .now) -> Bool
}
```

The predicate uses the same "is active" logic as `ScheduleEngine.applyCurrentUnion` but read-only and cheap:
- Schedule locked iff `enabled && ScheduleClock.isActive(…, at: now)`.
- One-shot locked iff `startedAt <= now < expiresAt`.
- Blocklist locked iff any active schedule or active one-shot references it.

The manager does not enforce — it only *reports*. Views call it, and if locked they present the passcode gate before proceeding.

### Passcode gate UI

`Brick/Views/Lockdown/PasscodeGateView.swift` — a modal sheet view that:
- Accepts a title, a short explanation string, and a success callback.
- Shows a numeric-only `TextField` styled like a passcode entry (secure, 6 boxes max).
- Tracks `attempts: Int` and `cooldownUntil: Date?`.
- On submit: verifies via `PasscodeService.verify` against the stored hash/salt. On success → dismiss + callback. On fail → increment `attempts`; after 3 wrong attempts, set `cooldownUntil = now + 30s` and disable the field + show countdown.
- Cancel button returns without executing the action.

`PasscodeGateModifier`:

```swift
extension View {
    func passcodeGate(
        title: String,
        reason: String,
        isPresented: Binding<Bool>,
        onUnlocked: @escaping () -> Void
    ) -> some View
}
```

### Passcode setup UI

`Brick/Views/Lockdown/PasscodeSetupView.swift`. Two paths:
1. **Pick your own**: enter digits, confirm by re-entering. 4-6 digits allowed.
2. **Generate random**: app shows a generated 6-digit code; user taps "I wrote this down" to confirm. Shown exactly once.

On complete → writes `AppSettings.passcodeHash/salt/modeRaw`. Reused for first-time setup and for change-passcode (the change flow first shows a `PasscodeGateView` asking for the current code, then presents `PasscodeSetupView`).

### First-launch gate

In `BrickApp.body`, wrap `RootView` with an `.onAppear`/`.task` that loads or creates the `AppSettings` singleton and presents `PasscodeSetupView` as a non-dismissible sheet when `passcodeHash == nil`. A lightweight `@StateObject var settingsBox: AppSettingsBox` holds the singleton and re-publishes changes.

### `.child` authorization

Swap `AuthorizationCenter.shared.requestAuthorization(for: .individual)` → `for: .child` in `BrickApp.init`. The spec is explicit that this is what enables uninstall protection. `.child` requires the Screen Time passcode to revoke, so the user commits by granting it.

### Wiring gates into views

Three gate points, each a small addition that wraps an existing action:

- `Brick/Views/Schedules/SchedulesListView.swift`:
  - `ScheduleRow` toggle setter: if `LockdownManager.isLocked(.disableSchedule(schedule))` and the user is turning it *off*, show passcode gate first; on unlock, perform `setEnabled(false)`.
  - Swipe-to-delete: if `isLocked(.deleteSchedule(schedule))`, gate; else delete directly.
- `Brick/Views/Blocklists/BlocklistsListView.swift`:
  - Swipe-to-delete: gate if `isLocked(.deleteBlocklist(blocklist))`.
- `Brick/Views/Blocklists/BlocklistEditorView.swift`:
  - On `.onAppear` in `.edit` mode, check `isLocked(.editBlocklist(blocklist))`. If locked, present a passcode gate immediately; on cancel, dismiss the editor; on unlock, set `unlocked = true` and allow Save.
- `Brick/Views/Home/ActiveBlockCard.swift` + add a "Cancel" affordance per one-shot:
  - Already shows active one-shots, so a red "Cancel" button with a passcode gate is the natural place to land the `cancelOneShot` gate. This also gives the user a way to end a one-shot early (which the spec implies — "cannot disable active block without passcode"). Add `onCancel: (OneShotBlock) -> Void` callback.

Schedule editor (`ScheduleEditorView`): the spec says *editing* an active schedule should be gated, but "edit" here is broad. Practical rule: gate only mutations that would end/weaken the block — toggling `enabled` off, deleting, changing blocklist, or changing time range *such that now is no longer inside it*. For MVP, wrap the entire edit Save action: if schedule is currently active and the new values either flip `enabled=false` or exclude `now`, require passcode. Simpler and defensible.

### Settings: change passcode

`SettingsTab.swift` replaces its `ContentUnavailableView` with a Form:
- Section "Security": `NavigationLink("Change passcode")` → shows `PasscodeGateView` for current, then `PasscodeSetupView` for new.
- (Keep placeholder rows for Lockdown/Focus/Travel as "coming soon" so the tab looks real.)

## File plan

```
Shared/Models/
└── AppSettings.swift                  # new model + schema entry

Shared/Services/
├── PasscodeService.swift              # hash/verify/generate
└── LockdownManager.swift              # isLocked(action:)

Brick/Models/
└── AppSettingsStore.swift             # fetch-or-create singleton, update helpers

Brick/Views/Lockdown/
├── PasscodeGateView.swift             # gate modal with 3-attempt cooldown
├── PasscodeSetupView.swift            # setup (user + generated) + reused for change
└── PasscodeGateModifier.swift         # .passcodeGate(...) view modifier

Brick/BrickApp.swift                   # .child auth + schema += AppSettings
                                        # + first-launch setup gate
Brick/RootView.swift                   # host first-launch setup sheet
Brick/Views/SettingsTab.swift          # change-passcode row
Brick/Views/Schedules/SchedulesListView.swift   # gate toggle-off + delete
Brick/Views/Blocklists/BlocklistsListView.swift # gate delete
Brick/Views/Blocklists/BlocklistEditorView.swift# gate edit-on-open
Brick/Views/Schedules/ScheduleEditorView.swift  # gate Save for weakening edits
Brick/Views/Home/ActiveBlockCard.swift          # add onCancel per one-shot
Brick/Views/Home/HomeTab.swift                  # wire onCancel + gate

BrickTests/
├── PasscodeServiceTests.swift         # round-trip, mismatched salt, timing-safe
└── LockdownManagerTests.swift         # active schedule/one-shot/blocklist detection
```

## Key code shapes

```swift
// PasscodeService
import CryptoKit

enum PasscodeService {
    static func generateRandom() -> String {
        (0..<6).map { _ in String(Int.random(in: 0...9)) }.joined()
    }

    static func isValidUserChosen(_ code: String) -> Bool {
        (4...6).contains(code.count) && code.allSatisfy(\.isNumber)
    }

    static func makeSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ code: String, salt: String) -> String {
        let input = Data((salt + code).utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    static func verify(_ code: String, hash expected: String, salt: String) -> Bool {
        let computed = hash(code, salt: salt)
        guard computed.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(computed.utf8, expected.utf8) { diff |= a ^ b }
        return diff == 0
    }
}
```

```swift
// LockdownManager
struct LockdownManager {
    let context: ModelContext

    func isLocked(_ action: LockedAction, at instant: Date = .now) -> Bool {
        switch action {
        case .disableSchedule(let s), .deleteSchedule(let s):
            return isScheduleActive(s, at: instant)
        case .cancelOneShot(let o):
            return o.startedAt <= instant && instant < o.expiresAt
        case .editBlocklist(let b), .deleteBlocklist(let b):
            return isBlocklistEnforced(b, at: instant)
        }
    }

    private func isScheduleActive(_ s: Schedule, at i: Date) -> Bool {
        guard s.enabled, !s.isExpired else { return false }
        return ScheduleClock.isActive(
            weekdayMask: s.weekdayMask, startMinute: s.startMinute,
            endMinute: s.endMinute, startDate: s.startDate,
            endDate: s.endDate, at: i
        )
    }

    private func isBlocklistEnforced(_ b: Blocklist, at i: Date) -> Bool {
        let schedules = (try? context.fetch(FetchDescriptor<Schedule>())) ?? []
        if schedules.contains(where: { $0.blocklist?.persistentModelID == b.persistentModelID && isScheduleActive($0, at: i) }) {
            return true
        }
        let oneShots = (try? context.fetch(FetchDescriptor<OneShotBlock>())) ?? []
        return oneShots.contains {
            $0.blocklist?.persistentModelID == b.persistentModelID
                && $0.startedAt <= i && i < $0.expiresAt
        }
    }
}
```

```swift
// PasscodeGateView (simplified)
struct PasscodeGateView: View {
    let title: String
    let reason: String
    let settings: AppSettings
    var onUnlocked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var attempts = 0
    @State private var cooldownUntil: Date?
    @State private var now = Date.now
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View { /* numeric field, error, cooldown countdown, cancel */ }

    private func submit() {
        if let h = settings.passcodeHash, let s = settings.passcodeSalt,
           PasscodeService.verify(code, hash: h, salt: s) {
            onUnlocked(); dismiss()
        } else {
            attempts += 1
            code = ""
            if attempts >= 3 {
                cooldownUntil = now.addingTimeInterval(30)
                attempts = 0
            }
        }
    }
}
```

## Tests

- `PasscodeServiceTests` — valid/invalid user codes, random is 6 digits, hash stable, salt changes hash, `verify` rejects wrong code, constant-time path exercised.
- `LockdownManagerTests` — seed a schedule with current time inside its window → `.disableSchedule` locked; outside → unlocked. Similarly for one-shot. Blocklist with no active ref → unlocked; blocklist referenced by active schedule → locked. Uses `InMemoryStore` + `MockClock` harness already present.

No tests for UI gate (SwiftUI-only behavior, deferred to manual verification).

## Edge cases

- **User enters wrong passcode, waits out the cooldown, gets 3 more tries.** Attempts counter resets after cooldown expires (state-based).
- **User quits app mid-gate.** Gate state is lost — re-presenting starts fresh. Acceptable.
- **Schedule that transitions from active → inactive mid-edit.** The gate check happens on Save; if the user is lucky, the schedule is no longer active and the gate is skipped. That matches user intent.
- **AppSettings row missing at first launch.** `AppSettingsStore.singleton(context:)` creates a row with all defaults (`passcodeHash == nil`) and the first-launch sheet is shown.
- **Authorization for `.child` denied.** Log + continue. Uninstall protection is an OS-level bonus; the in-app gates still function. Do not block the UI on auth.
- **Passcode change flow cancelled at second step.** Nothing persisted — old passcode remains.
- **User cancels the first-launch setup sheet.** Sheet must be non-dismissible (`interactiveDismissDisabled(true)` + no cancel button).

## Verification plan

1. `xcodegen generate` succeeds; `BrickTests` compile; new tests pass.
2. Manual (on-device):
   - Fresh install → setup sheet appears → pick user-chosen 1234 → confirm → lands on Home.
   - Create a schedule covering now → Home shows active block.
   - Toggle schedule off in Schedules tab → passcode prompt → enter wrong 3× → 30-second cooldown visible → wait → enter right code → schedule disables.
   - Try to delete active blocklist via swipe → passcode prompt.
   - Open "Edit blocklist" for the active blocklist → passcode prompt on open.
   - Start a one-shot block → Home → tap "Cancel" on the row → passcode prompt → cancels.
   - Settings → Change passcode → enter current → enter new → verify next gate accepts new.
   - From Home with no active block: toggle a non-active schedule off → no prompt. Edit an inactive blocklist → no prompt.

## Out of scope

- Full onboarding flow (#15). Just the blocking setup sheet.
- Focus integration (#11) — lockdown doesn't care about Focus state.
- Travel mode (#12).
- Biometric fallback for passcode entry.
- Persisting the 3-attempt cooldown across app relaunches (state-based reset on cold start is acceptable).
- UI showing remaining cooldown across multiple gates simultaneously (one gate at a time; each has its own state).
