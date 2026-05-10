import XCTest

/// Schedules-tab template flow. Verifies:
///   - The template picker is reachable from the Schedules tab (was moved
///     here from the Blocklists tab during the IA cleanup).
///   - Picking a template creates a schedule + matching blocklist.
///   - The DEBUG-only "Test (now ±2h)" template is present in debug builds
///     so devs can exercise active-block UI without waiting for a window
///     to open.
final class ScheduleFlowUITests: BrickUITestCase {
    func testTemplatePickerIsOnSchedulesTab() {
        launchInResetMainApp()
        switchToTab("Schedules")

        // Empty state on first run shows "Start from template" as the
        // primary action — the IA contract this test pins down.
        XCTAssertTrue(
            app.buttons["Start from template"].waitForExistence(timeout: 3),
            "Schedules empty state must surface the template entry."
        )

        // And the Blocklists tab must NOT advertise templates anymore.
        switchToTab("Blocklists")
        XCTAssertFalse(
            app.buttons["Start from template"].exists,
            "Templates should no longer live on the Blocklists tab."
        )
    }

    func testDebugTestNowTemplateIsAvailable() {
        launchInResetMainApp()
        switchToTab("Schedules")
        tap(app.buttons["Start from template"])

        // The DEBUG-only template's name is "Test (now ±2h)".
        let testTemplate = app.staticTexts["Test (now ±2h)"]
        XCTAssertTrue(
            testTemplate.waitForExistence(timeout: 3),
            "DEBUG builds should expose the now ±2h test template so devs can exercise active-block UI."
        )
    }

    func testTemplateCreatesScheduleAndBlocklist() {
        launchInResetMainApp()
        switchToTab("Schedules")
        tap(app.buttons["Start from template"])

        tap(app.staticTexts["Morning Focus"])
        tap(app.buttons["Create"])

        // Back on the Schedules list, the new schedule should be visible.
        XCTAssertTrue(
            app.staticTexts["Morning Focus"].waitForExistence(timeout: 3),
            "Applying a template should produce a schedule with the template's name."
        )

        // And the matching blocklist on the Blocklists tab.
        switchToTab("Blocklists")
        XCTAssertTrue(
            app.staticTexts["Morning Focus"].waitForExistence(timeout: 3),
            "Applying a template should also create the paired blocklist."
        )
    }
}
