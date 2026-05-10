import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var showingSetup = false
    @State private var showingOnboarding = false

    var body: some View {
        TabView {
            HomeTab()
                .tabItem { Label("Home", systemImage: "house.fill") }
            BlocklistsTab()
                .tabItem { Label("Blocklists", systemImage: "square.stack.fill") }
            SchedulesTab()
                .tabItem { Label("Schedules", systemImage: "calendar") }
            SettingsTab()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .task { checkLaunchState() }
        .fullScreenCover(isPresented: $showingOnboarding, onDismiss: checkLaunchState) {
            OnboardingView()
        }
        .sheet(isPresented: $showingSetup) {
            PasscodeSetupView(purpose: .firstTime) {
                checkLaunchState()
            }
        }
    }

    private func checkLaunchState() {
        let current = try? AppSettingsStore(context: context).loadOrCreate()
        let onboardingDone = current?.hasCompletedOnboarding == true
            || UserDefaults.standard.bool(forKey: AppSettingsStore.onboardingCompletedDefaultsKey)
        if !onboardingDone {
            showingOnboarding = true
            showingSetup = false
        } else {
            showingOnboarding = false
            showingSetup = !(current?.hasPasscode ?? false)
        }
    }
}

#Preview {
    RootView()
}
