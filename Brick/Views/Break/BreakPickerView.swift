import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

/// Lists the apps currently shielded by the active union, lets the user
/// pick exactly one and a duration, and surfaces availability state as a
/// banner so the user understands why the start button is disabled.
struct BreakPickerView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var controller: BreakSessionController
    @Query private var schedules: [Schedule]
    @Query private var oneShots: [OneShotBlock]

    let preselectedTokenData: Data?
    let onStartApp: (ApplicationToken, TimeInterval) -> Void
    let onStartCategory: (ActivityCategoryToken, TimeInterval) -> Void
    let onOverride: () -> Void
    let onCancel: () -> Void

    @State private var selectedAppToken: Data?
    @State private var selectedCategoryToken: Data?
    @State private var durationMinutes: Int = 2
    @State private var availability: BreakAvailability = .noActiveBlock
    @State private var now: Date = .now

    // Duration is now a stepper instead of presets (#18) — kept this slot
    // as a comment so future contributors don't reintroduce the segmented
    // picker without thinking through scaling.

    var body: some View {
        // TimelineView drives the per-second redraw and the availability
        // re-query — `Timer.publish(...).autoconnect()` stored as a `let`
        // silently stopped firing once SwiftUI re-created the View struct
        // (same root cause as ActiveBreakView's #25).
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content
                .onChange(of: context.date) { _, newDate in
                    now = newDate
                    refresh()
                }
        }
    }

    /// Splits the layout in two: when a break is actually available the
    /// existing left-aligned picker stays unchanged; for every other state
    /// (cold-start, quota used, lockout, block ending, no active block)
    /// the screen becomes a centered hero with an icon plate, a countdown
    /// ring where applicable, and a one-sentence rationale — the picker
    /// rows are hidden in those cases so the page was just a tiny banner
    /// floating in a sea of whitespace.
    private var content: some View {
        Group {
            if case .allowed = banner {
                allowedContent
            } else {
                heroContent
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle("Take a break")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") { startIfPossible() }
                    .disabled(!canStart)
            }
        }
        .onAppear {
            refresh()
            if let preselectedTokenData, blockedTokens.contains(preselectedTokenData) {
                selectedAppToken = preselectedTokenData
            }
        }
    }

    private var allowedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionEyebrow(text: "Break")
                    Text("Take a short\nbreak.")
                        .font(Theme.display(30, weight: .semibold))
                        .lineSpacing(-2)
                }

                availabilityBanner

                if hasAnyTarget {
                    if !blockedTokens.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            SectionEyebrow(text: "Pick one app")
                            VStack(spacing: Theme.Space.sm) {
                                ForEach(blockedTokens, id: \.self) { tokenData in
                                    targetRow(
                                        isSelected: selectedAppToken == tokenData,
                                        icon: "app.fill"
                                    ) {
                                        appLabel(for: tokenData)
                                    } action: {
                                        selectedAppToken = tokenData
                                        selectedCategoryToken = nil
                                    }
                                }
                            }
                        }
                    }

                    if !blockedCategoryTokens.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            SectionEyebrow(
                                text: blockedTokens.isEmpty
                                    ? "Pick a category"
                                    : "Or a whole category"
                            )
                            VStack(spacing: Theme.Space.sm) {
                                ForEach(blockedCategoryTokens, id: \.self) { tokenData in
                                    targetRow(
                                        isSelected: selectedCategoryToken == tokenData,
                                        icon: "square.stack.3d.up.fill"
                                    ) {
                                        categoryLabel(for: tokenData)
                                    } action: {
                                        selectedCategoryToken = tokenData
                                        selectedAppToken = nil
                                    }
                                }
                            }
                        }
                    }

                    durationStepper
                } else {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        SectionEyebrow(text: "Nothing to break from")
                        Text("Your active blocklist has no apps or categories that can be unshielded.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .cardSurface()
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroContent: some View {
        ScrollView {
            VStack(alignment: .center, spacing: Theme.Space.xl) {
                IconPlate(symbol: heroSymbol, size: 72)
                    .padding(.top, Theme.Space.xl)

                heroCountdownRing

                VStack(alignment: .center, spacing: Theme.Space.sm) {
                    Text(heroEyebrow.uppercased())
                        .font(Theme.label)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text(heroHeadline)
                        .font(Theme.display(28, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineSpacing(-2)
                    Text(heroBody)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Theme.Space.xs)
                }
                .frame(maxWidth: 360)

                if case .quotaExhausted = banner {
                    Button("Override (extends block)", action: onOverride)
                        .buttonStyle(.brickSecondary)
                        .padding(.top, Theme.Space.sm)
                        .padding(.horizontal, Theme.Space.lg)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var heroCountdownRing: some View {
        switch banner {
        case .coldStart(let endsAt):
            ringWithCenter(
                start: endsAt.addingTimeInterval(-BreakQuotaEngine.coldStartDuration),
                end: endsAt,
                caption: "Until breaks"
            )
        case .quotaExhausted(let availableAt):
            ringWithCenter(
                start: availableAt.addingTimeInterval(-BreakQuotaEngine.windowDuration),
                end: availableAt,
                caption: "Until refresh"
            )
        case .blockEnding, .overageLockout, .noActiveBlock, .allowed:
            EmptyView()
        }
    }

    private func ringWithCenter(start: Date, end: Date, caption: String) -> some View {
        CountdownRing(start: start, end: end, lineWidth: 10) {
            VStack(spacing: 2) {
                Text(formatCountdown(to: end))
                    .font(Theme.statNumber(36))
                    .foregroundStyle(.primary)
                Text(caption.uppercased())
                    .font(Theme.label)
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
    }

    private var heroSymbol: String {
        switch banner {
        case .coldStart: return "snowflake"
        case .quotaExhausted: return "gauge.with.dots.needle.0percent"
        case .blockEnding: return "clock.badge.xmark"
        case .overageLockout: return "lock.fill"
        case .noActiveBlock: return "checkmark.circle"
        case .allowed: return "hourglass"
        }
    }

    private var heroEyebrow: String {
        switch banner {
        case .coldStart: return "Cold start"
        case .quotaExhausted: return "Quota used"
        case .blockEnding: return "Block ending"
        case .overageLockout: return "Locked out"
        case .noActiveBlock: return "All clear"
        case .allowed: return "Break"
        }
    }

    private var heroHeadline: String {
        switch banner {
        case .coldStart: return "Settling in."
        case .quotaExhausted: return "Out of break\nfor now."
        case .blockEnding: return "Almost done."
        case .overageLockout: return "No more breaks\nthis block."
        case .noActiveBlock: return "Nothing\nis blocked."
        case .allowed: return ""
        }
    }

    private var heroBody: String {
        switch banner {
        case .coldStart: return "The first 25 minutes of a block are committed time. Breaks unlock automatically when the cold-start ends."
        case .quotaExhausted: return "You've used your 10 minutes of break in the last hour. More opens up as older breaks decay out of the window."
        case .blockEnding: return "Not enough block time left for a meaningful break."
        case .overageLockout: return "Too much overage already this block — locked out until it ends."
        case .noActiveBlock: return "Start a schedule or block now to take breaks."
        case .allowed: return ""
        }
    }

    /// Stepper-style duration picker. Scales cleanly to any cap (PRD's
    /// 10 min, debug's 2 min, future custom budgets). Replaces the
    /// segmented control that didn't survive past ~5 options. (#18)
    @ViewBuilder
    private var durationStepper: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionEyebrow(text: "Duration")
            HStack(alignment: .center, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(durationMinutes)")
                        .font(Theme.statNumber(40, weight: .semibold))
                    Text("MIN")
                        .font(Theme.label)
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Theme.Space.sm) {
                    stepperButton("minus", enabled: durationMinutes > 1) {
                        durationMinutes = max(1, durationMinutes - 1)
                    }
                    stepperButton("plus", enabled: durationMinutes < maxMinutes) {
                        durationMinutes = min(maxMinutes, durationMinutes + 1)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func stepperButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(enabled ? Theme.accent : .secondary.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(enabled ? Theme.accentMuted : Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Card-style row for an app or category target. Selected state gets
    /// a clay-tinted background and an accent check. (#20)
    @ViewBuilder
    private func targetRow<Label: View>(
        isSelected: Bool,
        icon: String,
        @ViewBuilder label: () -> Label,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Theme.accent : Theme.accentMuted)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.accent)
                }
                label()
                    .font(Theme.display(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: Theme.Space.sm)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .cardSurface(padding: Theme.Space.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Derived

    private var activeUnion: FamilyActivitySelection {
        let activeSchedules = schedules.filter(\.enabled).filter { schedule in
            ScheduleClock.isActive(
                weekdayMask: schedule.weekdayMask,
                startMinute: schedule.startMinute,
                endMinute: schedule.endMinute,
                startDate: schedule.startDate,
                endDate: schedule.endDate,
                at: now
            )
        }
        let activeOneShots = oneShots.filter { $0.startedAt <= now && now < $0.expiresAt }
        let selections = activeSchedules.compactMap { $0.blocklist?.selection }
            + activeOneShots.compactMap { $0.blocklist?.selection }
        return FamilyActivitySelection.union(selections)
    }

    private var blockedTokens: [Data] {
        Self.stableEncodedOrder(activeUnion.applicationTokens)
    }

    private var blockedCategoryTokens: [Data] {
        Self.stableEncodedOrder(activeUnion.categoryTokens)
    }

    /// Apple's tokens are opaque `Set` members — iteration order changes
    /// per access, which made the picker rows reshuffle on every tick.
    /// Encode them all and sort by their byte representation so the order
    /// is the same across every render. (#17)
    /// Internal (not private) so unit tests can pin down the stability
    /// invariant.
    static func stableEncodedOrder<T: Encodable>(_ tokens: Set<T>) -> [Data] {
        tokens
            .compactMap { try? PropertyListEncoder().encode($0) }
            .sorted { $0.lexicographicallyPrecedes($1) }
    }

    private var hasAnyTarget: Bool {
        !blockedTokens.isEmpty || !blockedCategoryTokens.isEmpty
    }

    /// End of the latest active block (schedule or one-shot). A break can
    /// never run past this — the shield drops and there's nothing to take
    /// a break *from*. (#35)
    private var blockEnd: Date? {
        let scheduleEnds: [Date] = schedules
            .filter(\.enabled)
            .compactMap { schedule in
                ScheduleClock.currentOccurrenceEnd(
                    weekdayMask: schedule.weekdayMask,
                    startMinute: schedule.startMinute,
                    endMinute: schedule.endMinute,
                    startDate: schedule.startDate,
                    endDate: schedule.endDate,
                    at: now
                )
            }
        let oneShotEnds = oneShots
            .filter { $0.startedAt <= now && now < $0.expiresAt }
            .map(\.expiresAt)
        return (scheduleEnds + oneShotEnds).max()
    }

    /// Banner state, derived once and consumed by both the renderer and
    /// the stepper. Pure decision logic lives in BreakBannerPresenter so
    /// it can be unit-tested without a SwiftUI environment. (#37)
    private var banner: BreakBanner {
        BreakBannerPresenter.banner(
            availability: availability,
            blockEnd: blockEnd,
            now: now
        )
    }

    /// Upper bound for the duration stepper. Drives both the `+` button's
    /// disabled state and the clamp in `refresh()`.
    private var maxMinutes: Int {
        if case .allowed(let m) = banner { return m }
        return 0
    }

    private var canStart: Bool {
        guard case .allowed = availability, durationMinutes > 0 else { return false }
        return selectedAppToken != nil || selectedCategoryToken != nil
    }

    // MARK: - Actions

    private func refresh() {
        availability = (try? controller.availability()) ?? .noActiveBlock
        if durationMinutes > maxMinutes {
            durationMinutes = max(1, maxMinutes)
        }
    }

    private func startIfPossible() {
        let duration = TimeInterval(durationMinutes * 60)
        if let tokenData = selectedAppToken,
           let token = try? PropertyListDecoder()
            .decode(ApplicationToken.self, from: tokenData) {
            onStartApp(token, duration)
            return
        }
        if let tokenData = selectedCategoryToken,
           let token = try? PropertyListDecoder()
            .decode(ActivityCategoryToken.self, from: tokenData) {
            onStartCategory(token, duration)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var availabilityBanner: some View {
        switch banner {
        case .allowed(let maxMinutes):
            Label(
                "\(maxMinutes) min available",
                systemImage: "hourglass"
            )
            .foregroundStyle(.secondary)
        case .coldStart(let endsAt):
            bannerView(
                title: "Cold start",
                detail: "Breaks unlock in \(formatCountdown(to: endsAt)).",
                systemImage: "snowflake"
            )
        case .quotaExhausted(let availableAt):
            VStack(alignment: .leading, spacing: 8) {
                bannerView(
                    title: "Break quota used",
                    detail: "More time available in \(formatCountdown(to: availableAt)).",
                    systemImage: "gauge.with.dots.needle.0percent"
                )
                Button("Override (extends block)", action: onOverride)
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
            }
        case .blockEnding(let blockEnd):
            bannerView(
                title: "Block ending",
                detail: "Block ends in \(formatCountdown(to: blockEnd)) — no break possible.",
                systemImage: "clock.badge.xmark"
            )
        case .overageLockout:
            bannerView(
                title: "Locked out",
                detail: "Too much overage this block. No more breaks until it ends.",
                systemImage: "lock.fill"
            )
        case .noActiveBlock:
            bannerView(
                title: "Nothing is blocked",
                detail: "Start a schedule or block now to take breaks.",
                systemImage: "checkmark.circle"
            )
        }
    }

    private func bannerView(title: String, detail: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func appLabel(for data: Data) -> some View {
        if let token = try? PropertyListDecoder()
            .decode(ApplicationToken.self, from: data) {
            Label(token)
                .lineLimit(1)
        } else {
            Text("Unknown app")
        }
    }

    @ViewBuilder
    private func categoryLabel(for data: Data) -> some View {
        if let token = try? PropertyListDecoder()
            .decode(ActivityCategoryToken.self, from: data) {
            Label(token)
                .lineLimit(1)
        } else {
            Text("Unknown category")
        }
    }

    private func formatCountdown(to date: Date) -> String {
        let remaining = max(0, Int(date.timeIntervalSince(now)))
        let m = remaining / 60
        let s = remaining % 60
        return String(format: "%d:%02d", m, s)
    }
}
