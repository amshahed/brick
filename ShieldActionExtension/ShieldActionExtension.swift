import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    // Breaks are started from inside Brick, not from the shield. The shield
    // only shows iOS's default Close button now, so every action just
    // dismisses — but we still drop any stale break intent so the main app
    // doesn't unexpectedly pop the break sheet on next open.
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        BreakIntent.clearPending()
        completionHandler(.close)
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
