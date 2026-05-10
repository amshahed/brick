# Brick — iOS App Blocker Plan

## Context

Build a personal iOS app blocker that improves on Opal in two key ways:
1. **Structured break budget** — instead of Opal's always-available "take a break" (which encourages impulse breaks), enforce a rolling quota with a cold-start commitment gate and overage penalties.
2. **Critical call passthrough** — important people can reach you during a block via iOS Focus integration, without disabling the block.

**Platform strategy**: iOS-first in native Swift. Ship, use personally, validate the design. Android (native Kotlin) comes later as a separate app — the blocking layer is 100% platform-specific so there's no throwaway work. The architecture and data model transfer 1:1.

Target user: the author, on personal iPhone. Single device, fully local data, no backend. Goal is also to ship publicly on the App Store.

---

## Architecture

**Shield + user-configured Focus:**
- **Shield layer**: `FamilyControls` + `ManagedSettings` + `DeviceActivity` for app blocking on schedules.
- **Focus layer (user-configured, not app-driven)**: iOS does not allow third-party apps to programmatically activate a Focus mode. The user creates a companion "Brick" Focus in iOS Settings with allowed contacts and wires activation themselves via either (a) the Focus's own Schedule, mirroring their Brick schedule (recommended for recurring blocks), or (b) a Shortcuts Personal Automation triggered by Brick's app open (recommended for one-shot blocks). Brick code does nothing about Focus state. Focus is **optional** — blocks work as a pure shield without it.
- **Why this layer at all**: iOS does not let third-party apps read other apps' notifications. The Focus layer is the only iOS path to contact-level call passthrough. UI frames this as "allowed contacts", not "app notifications."

## Core Mechanics

### Named Blocklists
- Primary unit of configuration. Each wraps a `FamilyActivitySelection` (Apple category tokens + individual app tokens).
- Schedules reference blocklists by name. Reusable across multiple schedules.
- User picks apps via `FamilyActivityPicker` (iOS constraint: no API to enumerate installed apps or pre-select categories).

### Schedules
- **Recurrence**: weekday mask (e.g., "Mon-Fri") + optional date range bounding (`startDate`, `endDate`).
  - Perpetual recurring: weekday mask, no date range. Runs forever.
  - Bounded recurring: weekday mask + date range (e.g., "Mon-Fri, Dec 1-15"). Auto-disables after end date.
  - One-shot: "block now for N hours" — first-class feature with a prominent home button. Non-repeating.
- **Overlap handling**: union of all active blocklists. Cold-start does NOT re-arm for overlapping schedule starts — it only arms on transition from "no active block" to "active block."

### Break Mechanic: Pick-One Unshield
- Starting a break requires choosing **one specific app** from the active blocklist. Only that app unshields; the rest stay blocked.
- Prevents the doomscroll app-hopping failure mode (Insta -> Twitter -> TikTok).

### Break Quota: Rolling Window + Cold-Start
- **Rolling 60-min window**, capped at **10 minutes** of total break time.
- **25-min cold-start**: at the beginning of every block, no breaks are allowed for the first 25 minutes. Re-arms for each block.
- **No cooldown** between breaks (beyond what the rolling window naturally implies).
- **No reset on new block** — the rolling quota is continuous across blocks and gaps.
- **Uniform cost**: all apps count 1:1 against the quota.

### Overage Penalty: Ritual + Block Extension
- **Entry gate**: to exceed the quota, type a free-form justification (>=80 chars) and wait 20 seconds.
- **Usage tax**: overage time extends the block's end by 2x the overage (5 min over -> +10 min).
- **Overage cap**: max 15 min of overage per block.
- Future: Beeminder/Stickk integration as a v2 third deterrent.

### Lockdown — two passcodes
- **FamilyControls `.individual` authorization**: required for the shield to function (apply category/app blocks via `ManagedSettings`). Granted via the system permission dialog at onboarding. We do **not** use `.child` mode — that requires the device to be enrolled as a child in a Family Sharing arrangement, which fails immediately on a personal device.
- **Brick passcode (local, in-app)**: required at onboarding (no skip). Stored as salted SHA-256 in SwiftData. User chooses:
  - Pick your own passcode (lighter commitment).
  - App generates a random passcode — user saves it somewhere inconvenient (stronger commitment).
- **iOS Screen Time passcode + "Don't Allow Deleting Apps" (system-level)**: onboarding deep-links to Settings → Screen Time and walks the user through two steps:
  1. Set the Screen Time passcode (Settings → Screen Time → Lock Screen Time Settings).
  2. Settings → Screen Time → Content & Privacy Restrictions → on → iTunes & App Store Purchases → Deleting Apps → Don't Allow.
  Brick cannot set either of these programmatically — the user does it in iOS Settings. Recommended: same passcode value as Brick passcode for simplicity, or a different value for stronger commitment. The "Don't Allow Deleting Apps" toggle is what actually blocks uninstall; the Screen Time passcode is what unlocks it.
- **Trade-off**: "Don't Allow Deleting Apps" applies to *all* apps, not just Brick. That's iOS's design — there's no per-app uninstall lock outside of Family Sharing's `.child` mode.
- **Scope during active block (minimal)**:
  - **In-app actions** gated by Brick passcode: disable active schedule, edit active blocklist, cancel active one-shot.
  - **Uninstall** gated by iOS Screen Time passcode (when "Don't Allow Deleting Apps" is on).
  - Everything else (future schedules, other blocklists, stats) remains editable.
- **Known ceiling**: Apple ID reset of Screen Time passcode is always available (~5-10 min). Accepted.

### Travel Mode
- **Activation**: manual date range (enter start/end before trip), or quick toggle ("I'm traveling now").
- **Effect**: suspends ALL schedules. No blocks fire. For lighter travel blocking, user creates a separate bounded "vacation" schedule.
- **End**: dated travel auto-resumes schedules. Toggle-based nudges daily, escalates after 7 days. Visible banner in main UI.

### Focus Onboarding (documentation-only)
- **Optional, not gated.** Blocks work without Focus.
- **Repeated-use nudge** (count-based): after N blocks without Focus configured, show a nudge card. No first-block nudge.
- **Setup flow** — three ordered steps in `FocusOnboardingView`:
  1. **Create the Focus.** Deep-link to iOS Settings → Focus → "+" → name it "Brick" → add Allowed People (family, on-call, partner).
  2. **Choose how Focus turns on.** Two paths, framed by use case:
     - *For recurring blocks (recommended)*: in the Brick Focus → Add Schedule, mirror the days/times of the user's Brick schedule. iOS handles on/off automatically.
     - *For one-shot blocks*: in the Shortcuts app, create a Personal Automation: "When App is Opened: Brick" → "Set Focus: Brick — Turn On." Open Shortcuts deep-link.
  3. **Emergency bypass** (Apple's repeated-call-within-3-min rule) is automatic — no setup.
- **Tracking**: `AppSettings.focusOnboardingCompleted` flips on user confirmation ("I've set up Focus" toggle). Brick does not verify the user actually configured iOS — the flag is a self-report.
- **No runtime FocusManager**. Brick code never touches Focus state. iOS toggles Focus based on whichever trigger the user chose in step 2.

## UX

### Templates
- 3-5 starter templates at onboarding: Morning Focus (6-10am Mon-Fri), Deep Work (9-5 Mon-Fri), Night Wind-Down (10pm-7am daily), Exam Mode (8am-10pm bounded dates), Vacation Light (10am-8pm bounded dates).
- Templates create scaffold (name + schedule); user fills in apps via `FamilyActivityPicker` with guidance text.
- Also browsable post-onboarding from "New blocklist" flow.

### Stats (Home Screen)
- Blocked time today/week.
- Break quota usage (X/10 min).
- Current streak of on-quota days.
- Simple numbers, no charts at v1.

### Notifications
- **Block starting**: "Your Deep Work block started. 25-min cold-start active."
- **Block ending**: "Block ended. 2h 15m blocked today."
- **Break expiring**: "1 min left on your break." (during active break)
- **Overage penalty applied**: "Block extended by 10 min (5 min overage x 2)."
- NOT sent: cold-start ended (inviting breaks is counter-productive).

## Tech Stack

- **Language**: Swift
- **UI**: SwiftUI
- **Blocking**: `FamilyControls`, `ManagedSettings`, `DeviceActivity` frameworks
- **Focus integration**: documentation-only (user wires Focus Schedule or a Shortcuts Personal Automation in iOS — no Brick code path)
- **Persistence**: SwiftData (on-device, no backend)
- **Notifications**: `UNUserNotificationCenter`
- **Minimum iOS**: 17.0 (for stable FamilyControls + SwiftData)

### Required App Extensions
- `DeviceActivityMonitor` extension — fires on schedule start/end, break timer events, cold-start expiry.
- `ShieldConfiguration` extension — customizes the shield overlay UI when a blocked app is opened.
- `ShieldAction` extension — handles user taps on the shield (e.g., "Take a break" button routes to main app).

### Key Data Models (SwiftData)
- `Blocklist` — name, `FamilyActivitySelection` (encoded), created date.
- `Schedule` — name, reference to `Blocklist`, weekday mask, start/end time, optional start/end date, `repeats` flag.
- `BreakRecord` — start time, end time, app token, was-overage flag.
- `BlockSession` — schedule reference, actual start/end, total break time, overage time, extension applied.
- `TravelPeriod` — start date, end date (nullable for toggle mode), active flag.
- `AppSettings` — Focus onboarding completed flag, passcode mode, completed blocks count.

## Verification Plan

1. **Unit tests**: quota calculator (rolling window math, cold-start state machine, overage extension calculation), schedule overlap union logic, travel mode suspension.
2. **On-device testing**: install on personal iPhone, create blocklists, verify shield appears when opening blocked apps, test break flow (pick app -> timer -> re-shield), verify cold-start prevents early breaks, test overage ritual + extension.
3. **Edge cases**: overlapping schedules with different blocklists, block ending mid-break, travel mode toggled during active block, passcode bypass flow, one-shot block with overage extending past next scheduled block.
4. **Notifications**: verify all 4 notification types fire at correct moments.
5. **Onboarding**: walk through template selection -> app picking -> first block -> first break cycle end-to-end.
