import Foundation
import SwiftUI

/// Bridges `BreakIntent.consume()` to SwiftUI views via `@EnvironmentObject`.
/// HomeTab observes `pending` and presents the break sheet preselecting
/// the app the user chose on the shield.
@MainActor
final class BreakIntentInbox: ObservableObject {
    @Published private(set) var pending: BreakIntent?

    func checkForIntent() {
        if let intent = BreakIntent.consume() {
            pending = intent
        }
    }

    func handle(url: URL) {
        if let intent = BreakIntent.fromURL(url) {
            pending = intent
        }
    }

    func clear() {
        pending = nil
    }
}
