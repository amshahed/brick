import XCTest

/// Regression tests for the Settings screen — covers structural items
/// that have been added or removed over time and shouldn't silently
/// drift back.
final class SettingsTabUITests: BrickUITestCase {
    /// #32: the placeholder "Coming soon" section for Notifications was
    /// removed once notifications shipped (#13, #26-#28). Guard against
    /// it sneaking back during a future refactor.
    func testNoComingSoonSection() {
        launchInResetMainApp()
        switchToTab("Settings")

        XCTAssertFalse(
            app.staticTexts["Coming soon"].exists,
            "Settings should not show a 'Coming soon' section (#32)."
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(
                format: "label CONTAINS[c] %@", "coming soon"
            )).firstMatch.exists,
            "No section header containing 'coming soon' should be present."
        )
    }

    /// #34: SharedDefaults propagates the debug-fast-timings flag from
    /// the app's write path to its readers (TemplateLibrary, the engine
    /// statics). Verify the read side: when the flag is ON, the Test
    /// template renders its fast-window variant ("T+2 → T+18"); when
    /// OFF, the slow variant ("now ±2h").
    ///
    /// We seed the flag through a launch argument rather than driving
    /// the SwiftUI Toggle from XCUITest. The Toggle itself is exercised
    /// by manual on-device testing — under iOS 26 a custom-Binding
    /// Toggle inside a Form is unreliably hittable by XCUITest taps.
    func testFastTimingsFlagOnPicksFastTemplate() {
        launchInResetMainApp(extraArgs: ["--ui-test-fast-timings"])
        switchToTab("Schedules")
        tap(app.buttons["Start from template"])

        let fastVariant = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS[c] %@", "T+2"
        )).firstMatch
        XCTAssertTrue(
            fastVariant.waitForExistence(timeout: 4),
            "With Fast break timings ON, the T+2 → T+18 variant should render."
        )
        XCTAssertFalse(
            app.staticTexts["Test (now ±2h)"].exists,
            "The slow variant should not be shown once Fast break timings is ON."
        )
    }

    func testFastTimingsFlagOffPicksSlowTemplate() {
        // Reset clears SharedDefaults, so without the launch arg the flag
        // is OFF — the slow variant should appear.
        launchInResetMainApp()
        switchToTab("Schedules")
        tap(app.buttons["Start from template"])

        XCTAssertTrue(
            app.staticTexts["Test (now ±2h)"].waitForExistence(timeout: 4),
            "With Fast break timings OFF, the slow 'now ±2h' variant should render."
        )
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(
                format: "label CONTAINS[c] %@", "T+2"
            )).firstMatch.exists,
            "The fast variant should not be shown when the flag is OFF."
        )
    }
}
