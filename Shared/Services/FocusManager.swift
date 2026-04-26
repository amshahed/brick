import Foundation
import Intents

/// Donates an `INSetFocusStatusIntent` so a user-created Shortcuts
/// automation can react. Apps cannot directly toggle a user's Focus mode,
/// but donating an intent is a stable signal a Shortcut can hook into.
///
/// Silently no-ops on any failure — blocks work as pure shields without
/// Focus configured.
enum FocusManager {
    static func activate() async { await donate(isFocused: true) }
    static func deactivate() async { await donate(isFocused: false) }

    private static func donate(isFocused: Bool) async {
        let intent = INSetFocusStatusIntent()
        intent.focusStatus = INFocusStatus(isFocused: isFocused)
        let interaction = INInteraction(intent: intent, response: nil)
        do {
            try await interaction.donate()
        } catch {
            // No Siri/Shortcuts authorization, no user automation, or other
            // failure — blocks remain as pure shields. By design.
        }
    }
}
