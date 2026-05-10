# Brick — iOS App Blocker PRD

## Problem Statement

Existing iOS app blockers (primarily Opal) have two critical design failures that undermine their core purpose:

1. **Always-available "take a break" encourages impulse breaks.** There is no commitment gate, no quota, and no penalty. The user can unblock everything instantly, which makes the blocker a speedbump rather than a real barrier. The result is that users take breaks constantly and the blocker provides little actual value.

2. **Blocking is all-or-nothing for communication.** When a block is active, important people can't reach you. Users are forced to choose between focus and reachability, which leads them to disable blocks entirely during times when they expect calls — defeating the purpose.

Brick solves both problems with a structured break budget (rolling quota + cold-start + overage penalties) and critical call passthrough via iOS Focus integration.

## Solution

A native iOS app (Swift/SwiftUI) that blocks distracting apps using Apple's `FamilyControls` / `ManagedSettings` / `DeviceActivity` frameworks, with two key differentiators:

**Structured break budget**: Instead of unlimited "take a break," Brick enforces a rolling 10-minute quota within any 60-minute window. Each block begins with a 25-minute cold-start period where no breaks are allowed. Breaks require picking a single app to unshield — no app-hopping. Exceeding the quota requires a deliberate overage ritual (typed justification + wait) and incurs a 2x time penalty extending the block. After 15 minutes of overage in a single block, the user is fully locked out for the remainder.

**Critical call passthrough**: The user pairs Brick with a companion iOS Focus mode (named "Brick") that they create themselves and populate with allowed contacts. iOS does not allow third-party apps to activate Focus modes programmatically, so the user wires Focus on/off via either the Focus's own Schedule (mirroring their Brick schedule) or a Shortcuts Personal Automation triggered by Brick's app open. Brick's role is teaching the user how to set this up; once configured, iOS handles the toggling. Focus is optional — blocks work as a pure shield without it.

The app is fully local (no backend), targets iOS 17+, and uses SwiftData for persistence. FamilyControls authorization is requested in `.individual` mode (the path for self-management on a personal device; `.child` mode requires a Family Sharing parent–child relationship that does not exist on a typical personal device). Lockdown is a two-passcode model: a Brick app passcode (stored locally) gates in-app actions during active blocks, and the user is guided to set up iOS itself to block uninstallation — by enabling the Screen Time passcode plus turning on Settings → Screen Time → Content & Privacy Restrictions → "Deleting Apps: Don't Allow." This is the iOS-supported mechanism for preventing app deletion without a passcode. The two passcode values can match for simplicity or differ for stronger commitment.

## User Stories

1. As a user, I want to create named blocklists of apps and app categories, so that I can define reusable groups of distracting apps.
2. As a user, I want to pick apps for a blocklist using Apple's system picker, so that I can select from my installed apps and system categories.
3. As a user, I want to create recurring schedules tied to blocklists with a weekday mask (e.g., Mon-Fri), so that blocks fire automatically on the days I choose.
4. As a user, I want to create bounded recurring schedules with start and end dates, so that I can set up temporary blocking periods (e.g., exam weeks).
5. As a user, I want to create perpetual recurring schedules with no end date, so that my daily blocks run indefinitely without maintenance.
6. As a user, I want to start a one-shot "block now for N hours" block from a prominent home button, so that I can quickly enter focus mode without configuring a schedule.
7. As a user, I want one-shot blocks to use an existing blocklist, so that I don't have to re-pick apps every time.
8. As a user, I want one-shot blocks to layer on top of active scheduled blocks (union of blocklists), so that I can add extra apps to an ongoing block.
9. As a user, I want a one-shot block's apps to stay shielded even if a scheduled block ends before the one-shot expires, so that the one-shot duration is respected.
10. As a user, I want overlapping schedules to union their blocklists, so that all relevant apps are blocked regardless of which schedule triggered them.
11. As a user, I want a 25-minute cold-start period at the beginning of every block where no breaks are allowed, so that I'm forced to settle into focus before any temptation.
12. As a user, I want the cold-start to only arm on transition from "no active block" to "active block," so that overlapping schedule starts don't re-trigger the cold-start.
13. As a user, I want a rolling 60-minute window with a 10-minute break cap, so that my break usage is bounded without rigid per-block resets.
14. As a user, I want the rolling quota to be continuous across blocks and gaps, so that I can't game the system by ending and restarting blocks.
15. As a user, I want to pick one specific app when starting a break, so that only that app unshields and I can't doomscroll across multiple apps.
16. As a user, I want the rest of my blocklist to remain shielded during a break, so that a break on Instagram doesn't also unblock Twitter and TikTok.
17. As a user, I want to exceed my break quota by completing an overage ritual (typing a justification of at least 80 characters and waiting 20 seconds), so that going over requires genuine deliberation rather than a quick tap.
18. As a user, I want overage time to extend my block's end by 2x the overage duration (e.g., 5 min overage = +10 min extension), so that there is a real cost to exceeding the quota.
19. As a user, I want a hard lockout after 15 minutes of overage in a single block, so that there is an absolute ceiling on how much I can override the system.
20. As a user, I want to see a shield overlay when I open a blocked app, so that the block is clearly enforced.
21. As a user, I want the shield overlay to offer a "Take a break" option that routes to the main app, so that the break flow is discoverable.
22. As a user, I want to optionally pair Brick with a companion iOS Focus mode (containing my allowed contacts), so that important people can call me during a block.
23. As a user, I want Focus to be optional and not gate any blocking functionality, so that I can use Brick as a pure shield if I prefer.
24. As a user, I want Brick to walk me through Focus setup honestly — explaining that iOS controls Focus activation via either a Focus Schedule or a Shortcuts Personal Automation — so that I can pick the path that fits my schedules.
25. As a user, I want Brick to nudge me about Focus setup after N blocks without it configured, so that I'm reminded of the feature without being pressured on first use.
26. As a user, I want emergency bypass (Apple's repeated-call rule) to always be active, so that truly urgent calls get through regardless of Focus configuration.
27. As a user, I want to set a Brick passcode at onboarding (required, no skip), so that I can't impulsively disable blocks from inside the app during an active block.
28. As a user, I want the option to pick my own Brick passcode or have the app generate a random one I store somewhere inconvenient, so that I can choose my commitment level.
29. As a user, I want onboarding to walk me through (a) setting an iOS Screen Time passcode and (b) turning on Content & Privacy Restrictions → "Deleting Apps: Don't Allow," so that uninstalling Brick during a block requires the Screen Time passcode — Brick alone cannot block uninstallation.
30. As a user, I want lockdown during an active block to prevent uninstalling, disabling the block, or editing the active blocklist, so that the block is truly enforced.
31. As a user, I want to still be able to edit future schedules, other blocklists, and view stats during an active block, so that lockdown is minimal and non-frustrating.
32. As a user, I want to activate travel mode with a manual date range or a quick toggle, so that all schedules are suspended while I'm traveling.
33. As a user, I want dated travel mode to automatically resume schedules when the travel period ends, so that I don't forget to re-enable blocking.
34. As a user, I want toggle-based travel mode to nudge me daily and escalate after 7 days, so that I don't accidentally leave it on forever.
35. As a user, I want a visible banner in the main UI when travel mode is active, so that I'm always aware my blocks are suspended.
36. As a user, I want to see blocked time today and this week on the home screen, so that I have a quick sense of how much focus time I've accumulated.
37. As a user, I want to see my break quota usage (X/10 min) on the home screen, so that I know how much break time I have left.
38. As a user, I want to see my current streak of on-quota days on the home screen, so that I'm motivated to maintain good behavior.
39. As a user, I want to be notified when a block starts with cold-start information, so that I know my block is active and when breaks become available.
40. As a user, I want to be notified when a block ends with a summary of blocked time, so that I get positive reinforcement.
41. As a user, I want to be notified 1 minute before a break expires, so that I can wrap up and return to the blocked app gracefully.
42. As a user, I want to be notified when an overage penalty extends my block, so that I understand the consequence immediately.
43. As a user, I want starter templates at onboarding (Morning Focus, Deep Work, Night Wind-Down, Exam Mode, Vacation Light), so that I can get started quickly without designing schedules from scratch.
44. As a user, I want templates to create a scaffold (name + schedule) that I fill in with apps via the system picker, so that templates are useful starting points rather than rigid presets.
45. As a user, I want to browse templates post-onboarding from the "New blocklist" flow, so that I can use them any time, not just at first launch.

## Implementation Decisions

### Architecture: Shield + User-Configured Focus
- **Shield layer**: `FamilyControls` + `ManagedSettings` + `DeviceActivity` for app blocking.
- **Focus layer (user-configured, not app-driven)**: iOS does not allow third-party apps to programmatically activate a Focus mode. Brick's Focus integration is therefore documentation-only: onboarding teaches the user to (1) create a "Brick" Focus in iOS Settings with their allowed contacts, and (2) wire activation via either the Focus's own Schedule (mirroring their Brick schedule — recommended for recurring blocks) or a Shortcuts Personal Automation triggered by Brick's app open (recommended for one-shot blocks). Brick code does nothing about Focus state; iOS handles the toggling once the user has configured the trigger. Optional — blocks function without it.
- iOS does not let third-party apps read other apps' notifications; Focus is the only path to contact-level call passthrough.

### Major Modules

1. **BlocklistStore** — CRUD for named blocklists wrapping `FamilyActivitySelection`. Persisted via SwiftData.

2. **ScheduleEngine** — Manages schedule definitions (recurring, bounded, one-shot), resolves which schedules are active at any given moment, computes the union of active blocklists. Handles travel mode suspension. Responsible for overlap resolution and cold-start arming logic (only on transition from no-active-block to active-block).

3. **ShieldManager** — Thin wrapper over `FamilyControls` / `ManagedSettings`. Takes a set of app tokens, applies or removes the shield. No business logic — all decisions come from ScheduleEngine.

4. **BreakQuotaEngine** — Core state machine for the break budget. Implements: rolling 60-min window with 10-min cap, 25-min cold-start, single-app unshield, overage gate (>=80 char justification + 20s wait), 2x block extension penalty, 15-min overage hard lockout. Operates on `BreakRecord` history. The rolling quota is global — continuous across blocks and gaps, never reset.

5. **FocusOnboarding** — Documentation-only flow that walks the user through creating a "Brick" Focus and wiring activation via Focus Schedule or Shortcuts Personal Automation. No runtime service component — iOS handles Focus toggling once the user has configured the trigger.

6. **LockdownManager** — Two-passcode model. Brick's app passcode (stored locally, not Keychain) gates in-app actions during active blocks: edits to active blocklist, disabling active block, canceling an active one-shot. Uninstall protection is OS-level: onboarding walks the user through enabling the iOS Screen Time passcode and turning on Content & Privacy Restrictions → "Deleting Apps: Don't Allow." Once configured, iOS requires the Screen Time passcode to delete any app (Brick included). Brick cannot enforce uninstall protection on its own and does not use `.child` FamilyControls mode (which requires Family Sharing). Does not gate: future schedules, other blocklists, stats, settings.

7. **NotificationService** — Schedules the four notification types: block starting (with cold-start info), block ending (with time summary), break expiring (1 min warning), overage penalty applied. Does NOT notify on cold-start ending (inviting breaks is counter-productive).

8. **DeviceActivity Extensions** — Three required app extensions:
   - `DeviceActivityMonitor` — fires on schedule start/end, break timer events, cold-start expiry.
   - `ShieldConfiguration` — customizes the shield overlay UI.
   - `ShieldAction` — handles taps on the shield (e.g., "Take a break" routes to main app).

9. **UI Layer** — SwiftUI views: Home (stats + one-shot quick-start), Blocklist editor (with `FamilyActivityPicker`), Schedule editor, Break flow (app picker + timer), Overage ritual, Onboarding (templates + passcode setup + Focus nudge), Travel mode, Settings.

### Data Models (SwiftData, fully local)
- `Blocklist` — name, encoded `FamilyActivitySelection`, created date.
- `Schedule` — name, blocklist reference, weekday mask, start/end time, optional start/end date, repeats flag.
- `BreakRecord` — start time, end time, app token, was-overage flag.
- `BlockSession` — schedule reference, actual start/end, total break time, overage time, extension applied.
- `TravelPeriod` — start date, nullable end date (for toggle mode), active flag.
- `AppSettings` — Focus onboarding completed flag, passcode mode, completed blocks count.

### Key Design Decisions
- **Brick passcode not stored in Keychain** — stored locally via SwiftData or UserDefaults. It is a commitment device, not a credential.
- **FamilyControls authorization is `.individual`**, not `.child`. `.child` mode requires Family Sharing parent–child setup that doesn't exist on a typical personal device — requesting it fails immediately without any system dialog. `.individual` is the mode for self-management.
- **Uninstall protection is OS-level**: not handled by FamilyControls auth mode at all. Onboarding walks the user through (a) enabling the Screen Time passcode and (b) turning on Content & Privacy Restrictions → "Deleting Apps: Don't Allow." This iOS-level setting blocks deletion of any app (Brick included) without the Screen Time passcode. Recommended: same passcode value as Brick passcode for simplicity, or a different value for stronger commitment.
- **Focus integration is user-configured, not app-driven**. Brick teaches; iOS toggles. No runtime Focus state is managed by Brick.
- **One-shot blocks pick from existing blocklists** and union with any active scheduled blocks.
- **Rolling quota is truly global** — never resets between blocks. A break at 2:00pm during Block A counts against Block B if it starts within 60 minutes.
- **Cold-start only arms on transition** from no-active-block to active-block (overlapping schedule starts don't re-trigger).
- **Overage hard lockout** — after 15 min of overage in a block, no more breaks at all for the remainder, not just no more overage.
- **Stats are simple numbers at v1** — no charts.
- **Minimum iOS 17.0** for stable FamilyControls + SwiftData support.

## Testing Decisions

### Testing Philosophy
- Test external behavior through module interfaces, not implementation details.
- Pure logic modules (no iOS framework dependencies) are the highest-value test targets.
- On-device manual testing covers the integration with iOS frameworks (`FamilyControls`, `ManagedSettings`, Focus) since these cannot be meaningfully unit-tested in a simulator.

### Modules Under Test

1. **BreakQuotaEngine** (priority) — The most complex pure-logic module. Test cases:
   - Rolling window math: breaks decay out of the window correctly, cap enforced at boundary.
   - Cold-start state machine: no breaks allowed during cold-start, cold-start only arms on block transition, overlapping starts don't re-arm.
   - Overage gate: justification length validation, wait timer, 2x extension calculation.
   - Hard lockout: no breaks after 15 min overage, lockout scoped to single block.
   - Cross-block continuity: quota is not reset when a new block starts, breaks from previous block count if within window.
   - Edge cases: break active when block ends, break spanning the window boundary, simultaneous quota expiry and cold-start end.

2. **ScheduleEngine** — Test cases:
   - Overlap resolution: union of blocklists from concurrent schedules.
   - One-shot layering: one-shot unions with scheduled block, one-shot survives scheduled block ending, scheduled block survives one-shot ending.
   - Travel mode: all schedules suspended, dated travel auto-resumes, toggle travel nudge escalation.
   - Bounded schedule auto-disable after end date.
   - Weekday mask correctness.

### Not Unit-Tested (Manual On-Device Testing)
- Shield appearing on blocked apps (`FamilyControls` integration).
- Focus on/off behavior (user-configured via Focus Schedule or Shortcuts; verify allowed contacts ring through during a block).
- Notification delivery timing.
- `FamilyActivityPicker` app selection flow.
- Lockdown / `.child` mode enforcement, including uninstall blocked by Screen Time passcode.
- Brick passcode gate for in-app actions.

## Out of Scope

- **Android app** — deferred to a future version. The architecture and data model are designed to transfer 1:1.
- **Beeminder / Stickk integration** — listed in the plan as a v2 deterrent for overage.
- **Backend / sync / multi-device** — fully local, single device.
- **Charts or detailed analytics** — v1 stats are simple numbers only.
- **Social features** — no sharing, leaderboards, or accountability partners.
- **Per-app break costs** — all apps count 1:1 against the quota (uniform cost).
- **Notification for cold-start ending** — deliberately excluded as counter-productive.

## Further Notes

- **Known ceiling on lockdown**: Apple ID reset of Screen Time passcode is always available (~5-10 min process). This is accepted as an inherent platform limitation.
- **FamilyActivityPicker constraint**: iOS provides no API to enumerate installed apps or pre-select categories. All app selection must go through Apple's picker UI.
- **iOS does not allow third-party Focus activation**: `INSetFocusStatusIntent` reports an app's own focus state; it does not flip a system Focus. There is no AppIntents or SiriKit path for an app to activate a user's Focus mode. The only triggers iOS accepts are user-driven (manual toggle, Focus Schedule, or a Personal Automation in Shortcuts). Brick's Focus integration is therefore documentation-only.
- **Focus onboarding is count-based**: nudge appears after N blocks without Focus configured. No nudge on first block to avoid overwhelming new users.
- **Template schedules**: Morning Focus (6-10am Mon-Fri), Deep Work (9-5 Mon-Fri), Night Wind-Down (10pm-7am daily), Exam Mode (8am-10pm bounded dates), Vacation Light (10am-8pm bounded dates).
