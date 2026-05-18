import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var router: AppRouter
    @State private var showingSetup = false
    @State private var showingOnboarding = false

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeTab()
                .tag(AppRouter.Tab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }
            BlocklistsTab()
                .tag(AppRouter.Tab.blocklists)
                .tabItem { Label("Blocklists", systemImage: "square.stack.fill") }
            SchedulesTab()
                .tag(AppRouter.Tab.schedules)
                .tabItem { Label("Schedules", systemImage: "calendar") }
            SettingsTab()
                .tag(AppRouter.Tab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        // Pair with the opaque UITabBarAppearance set in `BrickApp.init()`
        // so the bar reads as flat warm cream at every scroll position
        // (iOS 26 otherwise flips to translucent glass on scroll-edge).
        .toolbarBackground(.visible, for: .tabBar)
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
        .environmentObject(AppRouter())
}
