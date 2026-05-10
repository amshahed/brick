import XCTest

/// Positive UI coverage for the active-block lockdown gate. Every PRD
/// story 27/30 path that locks during an active block — disabling a
/// schedule, editing a blocklist, editing a schedule's load-bearing
/// fields — must surface the passcode gate, not silently allow.
///
/// Each test seeds an always-on schedule + paired blocklist via the
/// `--ui-test-seed-active-schedule` launch arg, so we don't have to
/// time-travel into a real window.
final class ActiveBlockLockdownUITests: BrickUITestCase {
    private let seedArgs = ["--ui-test-seed-active-schedule"]

    func testTogglingOffActiveSchedulePromptsPasscode() {
        launchInResetMainApp(extraArgs: seedArgs)
        switchToTab("Schedules")

        let toggle = app.switches.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        // Toggle is on (schedule starts enabled). Tapping flips it off,
        // which should trigger the passcode gate because the schedule is
        // currently active.
        toggle.tap()

        let gateField = app.secureTextFields["passcode.gate.field"]
        XCTAssertTrue(
            gateField.waitForExistence(timeout: 4),
            "Disabling an active schedule must surface the passcode gate."
        )
    }

    func testEditingActiveBlocklistShowsLockBanner() {
        launchInResetMainApp(extraArgs: seedArgs)
        switchToTab("Blocklists")

        // The seeded blocklist is "Test Block" — open it.
        tap(app.staticTexts["Test Block"])

        // The editor should show the "currently enforcing a block" banner
        // and disable Save until unlocked. The unlock gate is presented
        // automatically on appear.
        let banner = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS[c] %@", "currently enforcing a block"
        )).firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 4),
            "Active blocklist editor must show the lock banner."
        )
    }

    func testEditingActiveScheduleFieldsShowsLockBanner() {
        launchInResetMainApp(extraArgs: seedArgs)
        switchToTab("Schedules")

        // Open the schedule editor by tapping the row (not the toggle).
        tap(app.staticTexts["Always On"])

        let banner = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS[c] %@", "currently active"
        )).firstMatch
        XCTAssertTrue(
            banner.waitForExistence(timeout: 4),
            "Active schedule editor must show the time/weekday/blocklist lock banner."
        )

        // Renaming should still be allowed — the Name section's TextField
        // is hittable and accepts input.
        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        XCTAssertTrue(
            nameField.isEnabled,
            "Rename should remain allowed during an active schedule."
        )
    }
}
