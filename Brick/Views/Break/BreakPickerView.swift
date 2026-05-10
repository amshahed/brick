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
    private let ticker = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private static let presetMinutes: [Int] = [1, 2, 3, 5]

    var body: some View {
        List {
            Section { availabilityBanner }

            if case .allowed = availability, hasAnyTarget {
                if !blockedTokens.isEmpty {
                    Section("Pick one app") {
                        ForEach(blockedTokens, id: \.self) { tokenData in
                            Button {
                                selectedAppToken = tokenData
                                selectedCategoryToken = nil
                            } label: {
                                HStack {
                                    appLabel(for: tokenData)
                                    Spacer()
                                    if selectedAppToken == tokenData {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                if !blockedCategoryTokens.isEmpty {
                    Section(blockedTokens.isEmpty ? "Pick a category" : "Or a whole category") {
                        ForEach(blockedCategoryTokens, id: \.self) { tokenData in
                            Button {
                                selectedCategoryToken = tokenData
                                selectedAppToken = nil
                            } label: {
                                HStack {
                                    categoryLabel(for: tokenData)
                                    Spacer()
                                    if selectedCategoryToken == tokenData {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section("Duration") {
                    Picker("Minutes", selection: $durationMinutes) {
                        ForEach(durationOptions, id: \.self) { m in
                            Text("\(m) min").tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } else if case .allowed = availability {
                Section {
                    ContentUnavailableView(
                        "Nothing to break from",
                        systemImage: "square.stack.3d.up.slash",
                        description: Text("Your active blocklist has no apps or categories that can be unshielded.")
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
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
        .onReceive(ticker) { instant in
            now = instant
            refresh()
        }
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
        activeUnion.applicationTokens.compactMap {
            try? PropertyListEncoder().encode($0)
        }
    }

    private var blockedCategoryTokens: [Data] {
        activeUnion.categoryTokens.compactMap {
            try? PropertyListEncoder().encode($0)
        }
    }

    private var hasAnyTarget: Bool {
        !blockedTokens.isEmpty || !blockedCategoryTokens.isEmpty
    }

    private var remainingMinutes: Int {
        if case .allowed(let r) = availability {
            return max(1, Int(r / 60))
        }
        return 0
    }

    private var durationOptions: [Int] {
        Self.presetMinutes.filter { $0 <= remainingMinutes }
    }

    private var canStart: Bool {
        guard case .allowed = availability, durationMinutes > 0 else { return false }
        return selectedAppToken != nil || selectedCategoryToken != nil
    }

    // MARK: - Actions

    private func refresh() {
        availability = (try? controller.availability()) ?? .noActiveBlock
        if durationMinutes > remainingMinutes {
            durationMinutes = max(1, remainingMinutes)
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
        switch availability {
        case .allowed(let remaining):
            Label(
                "\(Int(remaining / 60)) min available this hour",
                systemImage: "hourglass"
            )
            .foregroundStyle(.secondary)
        case .coldStart(let endsAt):
            banner(
                title: "Cold start",
                detail: "Breaks unlock in \(formatCountdown(to: endsAt)).",
                systemImage: "snowflake"
            )
        case .quotaExhausted(let availableAt):
            VStack(alignment: .leading, spacing: 8) {
                banner(
                    title: "Break quota used",
                    detail: "More time available in \(formatCountdown(to: availableAt)).",
                    systemImage: "gauge.with.dots.needle.0percent"
                )
                Button("Override (extends block)", action: onOverride)
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
            }
        case .overageLockout:
            banner(
                title: "Locked out",
                detail: "Too much overage this block. No more breaks until it ends.",
                systemImage: "lock.fill"
            )
        case .noActiveBlock:
            banner(
                title: "Nothing is blocked",
                detail: "Start a schedule or block now to take breaks.",
                systemImage: "checkmark.circle"
            )
        }
    }

    private func banner(title: String, detail: String, systemImage: String) -> some View {
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
