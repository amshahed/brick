import XCTest

/// Covers the blocklist CRUD flow plus two regressions we landed earlier:
///   1. A blocklist that's not enforced anywhere should NOT show the
///      "currently enforcing a block" message in the editor (the
///      `lockChecked && !isUnlocked` bug).
///   2. The editor exposes an in-line "Delete blocklist" button — the only
///      visible delete affordance in the original code was the iOS swipe
///      gesture, which most users never discover.
final class BlocklistFlowUITests: BrickUITestCase {
    func testCreateBlocklistAppearsInList() {
        launchInResetMainApp()
        switchToTab("Blocklists")

        // From the empty state.
        tap(app.buttons["New blocklist"].firstMatch)

        let nameField = app.textFields.firstMatch
        tap(nameField)
        nameField.typeText("Social")
        tap(app.buttons["Save"])

        XCTAssertTrue(
            app.staticTexts["Social"].waitForExistence(timeout: 3),
            "Newly-created blocklist should appear in the list."
        )
    }

    func testInactiveBlocklistEditorHasNoEnforcementGate() {
        launchInResetMainApp()
        switchToTab("Blocklists")

        tap(app.buttons["New blocklist"].firstMatch)
        let nameField = app.textFields.firstMatch
        tap(nameField)
        nameField.typeText("Personal")
        tap(app.buttons["Save"])

        // Re-enter the editor by tapping the row.
        tap(app.staticTexts["Personal"])

        // The lockdown banner only shows when an active schedule or one-shot
        // references this blocklist. A freshly-created blocklist with no
        // schedules attached must not show it.
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(
                format: "label CONTAINS[c] %@",
                "currently enforcing a block"
            )).firstMatch.exists,
            "An inactive blocklist must not show the enforcement gate message."
        )
        XCTAssertTrue(
            app.buttons["Delete blocklist"].exists,
            "Editor should expose an in-line Delete button."
        )
    }

    func testDeleteBlocklistFromEditor() {
        launchInResetMainApp()
        switchToTab("Blocklists")

        tap(app.buttons["New blocklist"].firstMatch)
        let nameField = app.textFields.firstMatch
        tap(nameField)
        nameField.typeText("Throwaway")
        tap(app.buttons["Save"])

        tap(app.staticTexts["Throwaway"])
        tap(app.buttons["Delete blocklist"])

        // No referencing schedules → deletes immediately, dismisses editor.
        XCTAssertTrue(
            app.staticTexts["Blocklists"].waitForExistence(timeout: 3),
            "Should pop back to the Blocklists list."
        )
        XCTAssertFalse(
            app.staticTexts["Throwaway"].exists,
            "Deleted blocklist should be gone from the list."
        )
    }
}
