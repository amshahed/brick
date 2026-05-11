import SwiftData
import SwiftUI

struct HomeTab: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var controller: BreakSessionController
    @EnvironmentObject private var intentInbox: BreakIntentInbox
    @Query private var oneShots: [OneShotBlock]
    @Query private var schedules: [Schedule]
    @Query private var blocklists: [Blocklist]
    @Query(sort: \TravelPeriod.createdAt, order: .reverse)
    private var travelPeriods: [TravelPeriod]
    @Query(filter: #Predicate<BlockSession> { $0.actualEnd != nil })
    private var completedSessions: [BlockSession]
    @State private var showingBlockNow = false
    @State private var showingBreak = false
    @State private var breakPreselect: Data?
    @State private var now: Date = .now
    @State private var availability: BreakAvailability = .noActiveBlock
    @State private var pendingCancelOneShot: OneShotBlock?
    @State private var showCancelGate = false
    @State private var settings: AppSettings?
    @State private var nudgeDismissed = false
    @State private var showFocusOnboarding = false
    @State private var showTravelMode = false
    @State private var todayBlocked: TimeInterval = 0
    @State private var weekBlocked: TimeInterval = 0
    @State private var quotaUsed: TimeInterval = 0
    @State private var streak: Int = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    if let travel = activeTravel {
                        TravelBanner(
                            period: travel,
                            now: now,
                            onDisable: {
                                try? TravelPeriodStore(context: context).end(travel)
                            },
                            onTapDetails: { showTravelMode = true }
                        )
                    }
                    if shouldShowFocusNudge {
                        FocusNudgeCard(
                            onSetUp: { showFocusOnboarding = true },
                            onDismiss: { nudgeDismissed = true }
                        )
                    }
                    if hasActiveBlock {
                        ActiveBlockCard(
                            oneShots: activeOneShots,
                            now: now,
                            onAddAnother: { showingBlockNow = true },
                            onCancelOneShot: requestCancel
                        )
                        breakButton
                    } else {
                        idleHero
                    }
                    StatsCard(
                        today: todayBlocked,
                        week: weekBlocked,
                        quotaUsed: quotaUsed,
                        streak: streak
                    )
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.top, Theme.Space.md)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Brick")
            .task {
                loadSettings()
                refreshStats(at: now)
            }
            .onReceive(timer) { instant in
                now = instant
                refreshAvailability()
                refreshStats(at: instant)
            }
            .sheet(isPresented: $showFocusOnboarding, onDismiss: loadSettings) {
                NavigationStack { FocusOnboardingView() }
            }
            .sheet(isPresented: $showTravelMode) {
                NavigationStack { TravelModeView() }
            }
            .sheet(isPresented: $showingBlockNow) {
                BlockNowSheet()
            }
            .sheet(isPresented: $showingBreak, onDismiss: { breakPreselect = nil }) {
                BreakSheet(preselectedTokenData: breakPreselect)
                    .environmentObject(controller)
            }
            .onChange(of: intentInbox.pending) { _, pending in
                if let pending {
                    breakPreselect = pending.appTokenData
                    showingBreak = true
                    intentInbox.clear()
                }
            }
            .onChange(of: controller.active) { _, _ in
                if controller.active != nil { showingBreak = true }
            }
            .passcodeGate(
                title: "Cancel active block",
                reason: "This block is currently active. Enter your passcode to cancel it early.",
                isPresented: $showCancelGate
            ) {
                if let oneShot = pendingCancelOneShot {
                    try? OneShotBlockStore(context: context).cancel(oneShot)
                }
                pendingCancelOneShot = nil
            }
        }
    }

    private var activeOneShots: [OneShotBlock] {
        oneShots
            .filter { $0.startedAt <= now && now < $0.expiresAt }
            .sorted(by: { $0.expiresAt < $1.expiresAt })
    }

    private var activeSchedules: [Schedule] {
        schedules.filter { schedule in
            guard schedule.enabled else { return false }
            return ScheduleClock.isActive(
                weekdayMask: schedule.weekdayMask,
                startMinute: schedule.startMinute,
                endMinute: schedule.endMinute,
                startDate: schedule.startDate,
                endDate: schedule.endDate,
                at: now
            )
        }
    }

    private var hasActiveBlock: Bool {
        !activeOneShots.isEmpty || !activeSchedules.isEmpty
    }

    private func refreshAvailability() {
        availability = (try? controller.availability()) ?? .noActiveBlock
    }

    private func refreshStats(at instant: Date) {
        let engine = StatsEngine(context: context)
        todayBlocked = engine.blockedToday(now: instant)
        weekBlocked = engine.blockedThisWeek(now: instant)
        quotaUsed = engine.quotaUsed(now: instant)
        streak = engine.onQuotaStreak(now: instant)
    }

    private func loadSettings() {
        settings = try? AppSettingsStore(context: context).loadOrCreate()
    }

    private var shouldShowFocusNudge: Bool {
        !nudgeDismissed
            && completedSessions.count >= 3
            && settings?.focusOnboardingCompleted != true
    }

    private var activeTravel: TravelPeriod? {
        travelPeriods.first { $0.isActive(at: now) }
    }

    private func requestCancel(_ oneShot: OneShotBlock) {
        let lockdown = LockdownManager(context: context)
        if lockdown.isLocked(.cancelOneShot(oneShot)) {
            pendingCancelOneShot = oneShot
            showCancelGate = true
        } else {
            try? OneShotBlockStore(context: context).cancel(oneShot)
        }
    }

    @ViewBuilder
    private var breakButton: some View {
        VStack(spacing: Theme.Space.sm) {
            Button {
                breakPreselect = nil
                showingBreak = true
            } label: {
                Label(breakButtonLabel, systemImage: "pause.circle.fill")
            }
            .buttonStyle(.brickPrimary)
            .opacity(isBreakAllowed ? 1.0 : 0.4)
            .disabled(!isBreakAllowed)

            if let note = breakHintNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var breakButtonLabel: String {
        // Brick has no pause/resume model — the button just re-opens the
        // active-break sheet. "View break" reflects that without the
        // misleading "Resume" word. (#19)
        if controller.active != nil { return "View break" }
        return "Take a break"
    }

    private var isBreakAllowed: Bool {
        if controller.active != nil { return true }
        if case .allowed = availability { return true }
        return false
    }

    private var breakHintNote: String? {
        switch availability {
        case .allowed, .noActiveBlock: return nil
        case .coldStart(let endsAt):
            return "Cold start ends in \(formatShort(to: endsAt))."
        case .quotaExhausted(let availableAt):
            return "More break time in \(formatShort(to: availableAt))."
        case .overageLockout:
            return "Locked out until this block ends."
        }
    }

    private func formatShort(to date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private var idleHero: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            // Eyebrow + headline. Big rounded type does the heavy lifting;
            // the eyebrow gives the screen a quiet sense of place.
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionEyebrow(text: "Today")
                Text("Nothing is\nblocked right now.")
                    .font(Theme.display(34, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineSpacing(-2)
                Text(idleSubcopy)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.Space.xs)
            }

            Button {
                showingBlockNow = true
            } label: {
                Label("Block now", systemImage: "bolt.fill")
            }
            .buttonStyle(.brickPrimary)
            .opacity(blocklists.isEmpty ? 0.4 : 1)
            .disabled(blocklists.isEmpty)

            if blocklists.isEmpty {
                Text("Create a blocklist first in the Blocklists tab.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.lg)
    }

    private var idleSubcopy: String {
        if blocklists.isEmpty {
            return "Once you have a blocklist, you can start a one-off block or let a schedule kick in."
        }
        return "Start a one-off block, or let a schedule kick in."
    }
}
