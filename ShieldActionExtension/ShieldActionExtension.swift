import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    // Shield action extensions cannot open URLs — `ShieldActionResponse` only
    // exposes `.close` and `.defer`. The handoff to the main app is indirect:
    // write the ApplicationToken to a shared App Group plist, return `.close`
    // to dismiss the shield, and let the main app pick up the intent on its
    // next foreground (see BreakIntentInbox + BrickApp scenePhase wiring).
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            if let data = try? PropertyListEncoder().encode(application) {
                try? BreakIntent.write(appTokenData: data)
            }
            completionHandler(.close)
        case .secondaryButtonPressed:
            // "OK" — user is bailing out; drop any stale break intent so the
            // main app doesn't unexpectedly pop the break sheet on next open.
            BreakIntent.clearPending()
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.close)
    }
}
