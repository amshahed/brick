import XCTest

/// Regression coverage for the passcode gate's "Incorrect — N attempts left"
/// hint. Previously the `code = ""` reset after a wrong attempt fired the
/// SecureField's onChange handler, which cleared `errorText` immediately —
/// so the user saw nothing happen.
final class PasscodeGateUITests: BrickUITestCase {
    func testWrongPasscodeShowsIncorrectHint() {
        launchInResetMainApp(extraArgs: ["--ui-test-passcode", "1234"])

        // Drive the gate from Settings → Change passcode. The Settings tab
        // is the most stable trigger because it doesn't depend on any
        // active block / schedule state.
        switchToTab("Settings")
        let changeBtn = app.buttons.containing(NSPredicate(
            format: "label BEGINSWITH %@", "Change passcode"
        )).firstMatch
        tap(changeBtn)

        let field = app.secureTextFields.matching(identifier: "passcode.gate.field").firstMatch
        tap(field)
        field.typeText("9999")
        tap(app.buttons["passcode.gate.unlock"])

        let error = app.staticTexts["passcode.gate.error"]
        XCTAssertTrue(
            error.waitForExistence(timeout: 3),
            "Wrong passcode should surface an 'Incorrect' hint."
        )
        XCTAssertTrue(
            error.label.lowercased().contains("incorrect"),
            "Error text should explicitly say it was incorrect, got: \(error.label)"
        )
    }
}
