import XCTest

/// #35 home redesign: when a block is active, the home screen renders a
/// tappable progress row (ActiveBlockTimerRow) and drops the separate
/// "Take a break" / "View break" buttons. This test pins those visual
/// contracts.
final class HomeProgressRowUITests: BrickUITestCase {
    func testActiveBlockShowsProgressRowAndNoBreakButton() {
        launchInResetMainApp(extraArgs: ["--ui-test-seed-active-schedule"])
        switchToTab("Home")

        // ActiveBlockTimerRow renders a "BLOCK ACTIVE" eyebrow + the
        // seeded schedule's name. (The seed creates a schedule named
        // "Always On" — see BrickApp.applyUITestPostContainerFlags.)
        XCTAssertTrue(
            app.staticTexts["BLOCK ACTIVE"].waitForExistence(timeout: 4),
            "Home should show the BLOCK ACTIVE eyebrow when a schedule is active."
        )
        XCTAssertTrue(
            app.staticTexts["Always On"].exists,
            "Schedule name should render in the active block row."
        )

        // No separate break button on home — the row is the tap target.
        XCTAssertFalse(
            app.buttons["Take a break"].exists,
            "After #35, 'Take a break' button should not be on home."
        )
        XCTAssertFalse(
            app.buttons["View break"].exists,
            "After #35, 'View break' button should not be on home."
        )
    }

    func testIdleHomeShowsBlockNowAffordance() {
        launchInResetMainApp()
        switchToTab("Home")

        // Idle hero copy + the primary Block now button.
        XCTAssertTrue(
            app.staticTexts["TODAY"].waitForExistence(timeout: 3),
            "Idle home should show the TODAY eyebrow."
        )
        XCTAssertTrue(
            app.buttons["Block now"].exists,
            "Idle home should expose the 'Block now' button."
        )
        XCTAssertFalse(
            app.staticTexts["BLOCK ACTIVE"].exists,
            "Idle home must not show BLOCK ACTIVE."
        )
    }
}
