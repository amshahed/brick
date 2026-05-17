import SwiftData
import SwiftUI

struct HomeTab: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var controller: BreakSessionController
    @EnvironmentObject private var intentInbox: BreakIntentInbox
    @Query private var blocklists: [Blocklist]
    @Query(sort: \TravelPeriod.createdAt, order: .reverse)
    private var travelPeriods: [TravelPeriod]
    @Query(filter: #Predicate<BlockSession> { $0.actualEnd != nil })
    private var completedSessions: [BlockSession]
    @Query(
        filter: #Predicate<BlockSession> { $0.actualEnd == nil },
        sort: \BlockSession.actualStart,
        order: .forward
    )
    private var openSessions: [BlockSession]
    @State private var showingBlockNow = false
    @State private var showingBreak = false
    @State private var breakPreselect: Data?
    @State private var now: Date = .now
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
                    if let active = controller.active {
                        // Break running: the break row owns the home screen;
                        // block rows are hidden so attention is on the
                        // remaining break time. (#35)
                        ActiveBreakCard(active: active) {
                            breakPreselect = nil
                            showingBreak = true
                        }
                    } else if !openSessions.isEmpty {
                        // One progress row per active block (schedule or
                        // one-shot). Tapping any row opens the break sheet,
                        // which surfaces cold-start / quota / no-break-
                        // possible state inline — so there's no separate
                        // "Take a break" button on home.
                        ForEach(openSessions) { session in
                            ActiveBlockTimerRow(
                                name: blockName(for: session),
                                actualStart: session.actualStart,
                                scheduledEnd: session.effectiveEnd
                                    ?? session.scheduledEnd
                                    ?? now.addingTimeInterval(60),
                                subtitle: blockSubtitle(for: session),
                                onCancel: cancelHandler(for: session),
                                onTap: {
                                    breakPreselect = nil
                                    showingBreak = true
                                }
                            )
                        }
                        addAnotherBlockButton
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

    // MARK: - Block row helpers

    private func blockName(for session: BlockSession) -> String {
        session.schedule?.name
            ?? session.oneShotBlock?.blocklist?.name
            ?? "Block"
    }

    private func blockSubtitle(for session: BlockSession) -> String {
        session.schedule?.blocklist?.selectionSummary
            ?? session.oneShotBlock?.blocklist?.selectionSummary
            ?? ""
    }

    /// Only one-shots are user-cancellable from the home row — schedules
    /// are managed from the Schedules tab. Returns nil for schedule-backed
    /// sessions so the row hides the `×`.
    private func cancelHandler(for session: BlockSession) -> (() -> Void)? {
        guard let oneShot = session.oneShotBlock else { return nil }
        return { requestCancel(oneShot) }
    }

    @ViewBuilder
    private var addAnotherBlockButton: some View {
        Button {
            showingBlockNow = true
        } label: {
            Label("Add another block", systemImage: "plus")
        }
        .buttonStyle(.brickSecondary)
        .disabled(blocklists.isEmpty)
        .opacity(blocklists.isEmpty ? 0.4 : 1)
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
