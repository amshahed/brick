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

    /// Regression for #22: swipe-to-delete used to hang because
    /// `.onDelete(perform:)` composed badly with the row's transparent
    /// NavigationLink, and `ScheduleEngine.sync()` blocked on
    /// FamilyControls calls on the simulator. Now uses explicit
    /// `.swipeActions` and the sync gates on auth.
    func testSwipeToDeleteScheduleRemovesIt() {
        launchInResetMainApp()

        // Seed via the template path so we have a real schedule.
        switchToTab("Schedules")
        tap(app.buttons["Start from template"].firstMatch)
        tap(app.staticTexts["Morning Focus"])
        tap(app.buttons["Create"])

        // Schedule row contains both the schedule name and the blocklist
        // name (same text) — use firstMatch so the swipe target is
        // unambiguous.
        let row = app.staticTexts["Morning Focus"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 4))

        // Swipe left to reveal the trailing Delete swipe action.
        row.swipeLeft()
        let deleteBtn = app.buttons["Delete"]
        XCTAssertTrue(
            deleteBtn.waitForExistence(timeout: 2),
            "Trailing swipe should reveal the Delete action."
        )
        deleteBtn.tap()

        // After delete: the Schedules list is empty again so the empty
        // state's "Start from template" CTA returns. The acceptance is
        // "no hang" — verified by the test completing in normal time —
        // plus the row being gone.
        XCTAssertTrue(
            app.buttons["Start from template"].waitForExistence(timeout: 4),
            "After deleting the only schedule, the empty state should return."
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
