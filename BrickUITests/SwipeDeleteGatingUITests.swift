import XCTest

/// Regression for the cleanup commit's swipe-delete UX fix: when a row's
/// delete is gated behind the passcode (active schedule / blocklist),
/// cancelling the gate must NOT remove the row from the list.
///
/// Previously the swipe button used `role: .destructive`, which made
/// SwiftUI animate the row out as soon as it was tapped — before the
/// passcode resolved. Cancelling left the data intact but hid the row
/// until the next @Query refetch.
final class SwipeDeleteGatingUITests: BrickUITestCase {
    private let seedArgs = ["--ui-test-seed-active-schedule"]

    func testCancellingPasscodeOnScheduleSwipeKeepsRow() {
        launchInResetMainApp(extraArgs: seedArgs)
        switchToTab("Schedules")

        let row = app.staticTexts["Always On"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()

        // Passcode gate appears because the schedule is active.
        let gateField = app.secureTextFields["passcode.gate.field"]
        XCTAssertTrue(
            gateField.waitForExistence(timeout: 4),
            "Deleting an active schedule must surface the passcode gate."
        )

        // Cancel the gate. PasscodeGateView's toolbar Cancel button.
        tap(app.buttons["Cancel"])

        // The row must still be visible.
        XCTAssertTrue(
            app.staticTexts["Always On"].waitForExistence(timeout: 3),
            "Cancelling the gate must leave the row in place."
        )
    }

    func testCancellingPasscodeOnBlocklistSwipeKeepsRow() {
        launchInResetMainApp(extraArgs: seedArgs)
        switchToTab("Blocklists")

        let row = app.staticTexts["Test Block"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        row.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()

        let gateField = app.secureTextFields["passcode.gate.field"]
        XCTAssertTrue(
            gateField.waitForExistence(timeout: 4),
            "Deleting an active blocklist must surface the passcode gate."
        )

        tap(app.buttons["Cancel"])

        XCTAssertTrue(
            app.staticTexts["Test Block"].waitForExistence(timeout: 3),
            "Cancelling the gate must leave the row in place."
        )
    }
}
