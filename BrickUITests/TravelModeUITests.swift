import XCTest

/// Covers PRD user stories 32 ("activate travel mode with a quick toggle"),
/// 35 ("visible banner in the main UI when travel mode is active"), and
/// the inverse — disabling brings the home screen back to its idle state.
final class TravelModeUITests: BrickUITestCase {
    func testToggleTravelOnShowsBannerAndOffHides() {
        launchInResetMainApp()

        // Settings → Travel mode → "I'm traveling now" toggle.
        switchToTab("Settings")
        let travelRow = app.buttons.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Travel mode"
        )).firstMatch
        tap(travelRow)
        tap(app.buttons["I'm traveling now"])

        // Back to Home — the banner reads "Travel mode active".
        switchToTab("Home")
        XCTAssertTrue(
            app.staticTexts["TRAVEL MODE ACTIVE"].waitForExistence(timeout: 4),
            "Home should show the travel banner once toggle travel is on."
        )

        // Tap the banner's Disable button. It's labelled "Disable" — both
        // it and any other "Disable" on the screen should resolve to the
        // banner's button at this point in the flow.
        tap(app.buttons["Disable"])

        // Banner gone, idle hero back.
        let banner = app.staticTexts["TRAVEL MODE ACTIVE"]
        XCTAssertFalse(
            banner.waitForExistence(timeout: 2),
            "Banner should disappear once travel mode is disabled."
        )
    }
}
