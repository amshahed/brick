import SwiftData
import SwiftUI

struct SettingsTab: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @Query(sort: \TravelPeriod.createdAt, order: .reverse)
    private var travelPeriods: [TravelPeriod]
    @State private var settings: AppSettings?
    @State private var showCurrentGate = false
    @State private var showSetup = false
    @State private var now: Date = .now
    private let tick = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    Button {
                        showCurrentGate = true
                    } label: {
                        HStack {
                            Label("Change passcode", systemImage: "lock.rotation")
                            Spacer()
                            Text(modeDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(settings?.hasPasscode != true)
                }

                Section("Integrations") {
                    NavigationLink {
                        FocusOnboardingView()
                    } label: {
                        HStack {
                            Label("Focus integration", systemImage: "moon.fill")
                            Spacer()
                            Text(focusStatusDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink {
                        TravelModeView()
                    } label: {
                        HStack {
                            Label("Travel mode", systemImage: "airplane")
                            Spacer()
                            Text(travelStatusDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationDestination(isPresented: $router.presentTravelMode) {
                    TravelModeView()
                }

                #if DEBUG
                debugSection
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .task { load() }
            .onReceive(tick) { now = $0 }
            .passcodeGate(
                title: "Confirm current passcode",
                reason: "Enter your current passcode before setting a new one.",
                isPresented: $showCurrentGate
            ) {
                showSetup = true
            }
            .sheet(isPresented: $showSetup, onDismiss: load) {
                PasscodeSetupView(purpose: .change) {
                    showSetup = false
                }
            }
        }
    }

    private var modeDescription: String {
        guard let settings else { return "Not set" }
        if !settings.hasPasscode { return "Not set" }
        switch settings.passcodeMode {
        case .userChosen: return "Custom"
        case .appGenerated: return "Random"
        }
    }

    private var focusStatusDescription: String {
        (settings?.focusOnboardingCompleted ?? false) ? "Configured" : "Not set up"
    }

    private var travelStatusDescription: String {
        guard let active = travelPeriods.first(where: { $0.isActive(at: now) }) else {
            return "Off"
        }
        if let endDate = active.endDate {
            return "On until \(endDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return "On"
    }

    private func load() {
        settings = try? AppSettingsStore(context: context).loadOrCreate()
    }

    #if DEBUG
    @ViewBuilder
    private var debugSection: some View {
        Section("Debug") {
            Toggle(isOn: Binding(
                get: { SharedDefaults.shared.bool(forKey: BreakQuotaEngine.debugFastTimingsKey) },
                set: { newValue in
                    SharedDefaults.shared.set(newValue, forKey: BreakQuotaEngine.debugFastTimingsKey)
                    BreakQuotaEngine.applyDebugTimings(newValue)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fast break timings")
                    Text("Cold start 2m · window 3m · cap 2m · overage cap 3m. The Test template starts 2 min from now and runs 16 min (ends T+18) — iOS DeviceActivity requires a ≥ 15-min window or schedules never fire. Off restores PRD values (25/60/10/15).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("settings.debug.fastTimings")
        }
    }
    #endif
}
