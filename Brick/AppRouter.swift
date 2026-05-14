import Foundation
import SwiftUI

/// Drives programmatic navigation triggered by notification taps. The
/// notification delegate hands a `NotificationRoute` to `handle`, which
/// mutates `selectedTab` (and per-route flags) so the view tree responds.
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Int, Hashable {
        case home, blocklists, schedules, settings
    }

    @Published var selectedTab: Tab = .home
    /// Set true when a `.travel` route fires; SettingsTab observes this and
    /// pushes TravelModeView, then resets the flag on dismiss. Wired in #28.
    @Published var presentTravelMode: Bool = false

    func handle(_ route: NotificationService.NotificationRoute) {
        switch route {
        case .activeBreak:
            // ActiveBreakView auto-presents from `breakController.active` —
            // selecting Home is enough.
            selectedTab = .home
        case .schedules:
            selectedTab = .schedules
        case .travel:
            selectedTab = .settings
            presentTravelMode = true
        }
    }
}
