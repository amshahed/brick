import XCTest

/// End-to-end happy path for PRD user stories 6 ("start a block now") and
/// 7 ("uses an existing blocklist"). We seed a blocklist via the UI, kick
/// off a one-shot from Home, then verify the active card replaces the
/// idle hero. Cancellation is exercised by tapping the row's accessibility
/// "Cancel <name>" affordance from `ActiveBlockCard`.
final class OneShotBlockUITests: BrickUITestCase {
    func testStartAndCancelOneShotFromHome() {
        launchInResetMainApp()

        // Seed a blocklist so Block Now has something to reference. We can't
        // drive the FamilyActivityPicker (system UI) so the blocklist is
        // empty — the one-shot still creates and shows on the Home card.
        switchToTab("Blocklists")
        tap(app.buttons["New blocklist"].firstMatch)
        let nameField = app.textFields.firstMatch
        tap(nameField)
        nameField.typeText("Focus")
        tap(app.buttons["Save"])

        // Back to Home. The idle hero's "Block now" CTA should be enabled
        // now that there's a blocklist to point at.
        switchToTab("Home")
        let blockNow = app.buttons["Block now"]
        XCTAssertTrue(blockNow.waitForExistence(timeout: 3))
        XCTAssertTrue(blockNow.isEnabled, "Block now should enable once a blocklist exists.")
        blockNow.tap()

        // BlockNowSheet appears. The Form-style Picker exposes its label
        // ("Blocklist") and current value ("Select…") combined into a
        // single button. We can reach it by either piece — try both, fall
        // back to the static text.
        XCTAssertTrue(
            app.staticTexts["Block Now"].waitForExistence(timeout: 3),
            "BlockNowSheet should appear after tapping Block now."
        )
        let pickerCandidates: [XCUIElement] = [
            app.buttons.containing(NSPredicate(
                format: "label CONTAINS[c] %@", "Blocklist"
            )).element(boundBy: 1),  // [0] is the section header static text
            app.buttons["Blocklist"],
            app.buttons["Select…"],
        ]
        var opened = false
        for picker in pickerCandidates where picker.exists && picker.isHittable {
            picker.tap()
            opened = true
            break
        }
        XCTAssertTrue(opened, "Couldn't open the blocklist picker.")
        tap(app.buttons["Focus"])

        tap(app.buttons["Start"])

        // Two valid outcomes:
        //   • Real device with FamilyControls auth — Start succeeds, the
        //     BlockNowSheet dismisses, and Home shows the BLOCK ACTIVE
        //     card with a hittable Cancel affordance.
        //   • Simulator (or device without auth granted) — the sheet stays
        //     up and surfaces a "not been authorized" error in red.
        // Both paths prove the flow up to the engine handoff; the post-
        // handoff shield + DA registration side is documented in the PRD
        // as manual on-device verification.
        //
        // We can't use `.exists` for the BLOCK ACTIVE static text because
        // the home view is in the hierarchy *behind* the sheet too — use
        // sheet dismissal as the signal instead.
        let sheetTitle = app.staticTexts["Block Now"]
        let authError = app.staticTexts.containing(NSPredicate(
            format: "label CONTAINS[c] %@", "Family Controls"
        )).firstMatch
        let deadline = Date().addingTimeInterval(5)
        var sheetDismissed = false
        var sawAuthError = false
        while Date() < deadline {
            if !sheetTitle.exists { sheetDismissed = true; break }
            if authError.exists { sawAuthError = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(
            sheetDismissed || sawAuthError,
            "Start must either dismiss the sheet (success) or surface an auth error (simulator)."
        )

        // Only the success path can exercise the cancel affordance.
        if sheetDismissed {
            let cancelBtn = app.buttons["Cancel Focus"]
            XCTAssertTrue(
                cancelBtn.waitForExistence(timeout: 3),
                "Active block card should expose a Cancel button."
            )
            cancelBtn.tap()
            XCTAssertTrue(
                app.staticTexts["TODAY"].waitForExistence(timeout: 3),
                "After cancelling, Home should return to its idle state."
            )
        }
    }
}
