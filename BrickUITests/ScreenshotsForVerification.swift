import XCTest

/// Non-assertive "test" that walks the major surfaces and attaches a
/// screenshot of each. Used for visual verification of the redesign
/// before handing off to manual review. Run with:
///
///   xcodebuild test -only-testing:BrickUITests/ScreenshotsForVerification
///
/// Then export attachments from the .xcresult bundle.
final class ScreenshotsForVerification: BrickUITestCase {
    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureKeyScreens() {
        launchInResetMainApp(extraArgs: ["--ui-test-seed-active-schedule"])

        // Home with active block seeded — should show ActiveBlockCard.
        shoot("home-active")

        switchToTab("Blocklists")
        shoot("blocklists-with-test-block")

        switchToTab("Schedules")
        shoot("schedules-with-always-on")

        // Tap the template entry to see the picker sheet.
        if app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "template")).firstMatch.waitForExistence(timeout: 2) {
            // Skip — there's already an active schedule so the picker
            // affordance is in the toolbar Menu rather than the empty
            // state. Just go to Settings.
        }

        switchToTab("Settings")
        shoot("settings-with-debug")
    }
}
