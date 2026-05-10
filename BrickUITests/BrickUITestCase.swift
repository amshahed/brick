import XCTest

/// Shared base class for Brick UI tests. Centralises launch-flag handling
/// and a few small helpers so individual tests stay focused on the flow
/// they're verifying.
class BrickUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        // Attach a screenshot of the running app to every test result so
        // failures are diagnosable without re-running locally.
        if let app, app.state == .runningForeground || app.state == .runningBackground {
            let screenshot = app.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "final-state-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)

            // Also dump the visible accessibility tree, abbreviated.
            let dump = app.debugDescription
            let textAttachment = XCTAttachment(string: dump)
            textAttachment.name = "ax-tree-\(name)"
            textAttachment.lifetime = .keepAlways
            add(textAttachment)
        }
        try super.tearDownWithError()
    }

    /// Launch the app with a clean SwiftData store + UserDefaults, on the
    /// main app screen (onboarding skipped, default passcode "1234" set so
    /// `RootView` doesn't divert to PasscodeSetup). Tests that need the
    /// onboarding flow should call `launchAtOnboarding` instead. Pass
    /// `extraArgs` to override the default passcode or layer additional
    /// flags.
    func launchInResetMainApp(extraArgs: [String] = []) {
        var args = [
            "--ui-test-reset-store",
            "--ui-test-skip-onboarding",
        ]
        if !extraArgs.contains("--ui-test-passcode") {
            args += ["--ui-test-passcode", "1234"]
        }
        args += extraArgs
        app.launchArguments = args
        app.launch()
        dismissSystemAlertsIfNeeded()
    }

    /// Launch the app at a fresh onboarding flow (state wiped, no skip).
    func launchAtOnboarding() {
        app.terminate()
        app.launchArguments = ["--ui-test-reset-store"]
        app.launch()
        dismissSystemAlertsIfNeeded()
    }

    /// Dismiss every authorization affordance that fires between launch
    /// and the first frame:
    ///
    ///   1. The springboard "‘Brick’ Would Like to Access Screen Time"
    ///      alert with Continue / Don't Allow.
    ///   2. The FamilyControls follow-up sheet that's presented inside the
    ///      app process — "Allow Access to Screen Time" with an inline
    ///      "Don't Allow" link.
    ///   3. Notifications and similar dialogs.
    ///
    /// We always pick the negative answer; the simulator can't grant Screen
    /// Time anyway, and the app has skip paths for everything we touch.
    private func dismissSystemAlertsIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<10 {
            var handled = false
            for source in [springboard.buttons, app.buttons] {
                for label in ["Don't Allow", "Don’t Allow"] {
                    let btn = source[label]
                    if btn.exists && btn.isHittable {
                        btn.tap()
                        handled = true
                        Thread.sleep(forTimeInterval: 0.4)
                        break
                    }
                }
                if handled { break }
            }
            if !handled {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    /// Tap an element only after waiting for it to exist. Fails the test
    /// with a descriptive message if it doesn't appear in time.
    func tap(_ element: XCUIElement, timeout: TimeInterval = 4, file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "Expected element to exist before tap: \(element)",
            file: file, line: line
        )
        element.tap()
    }

    /// Switch to a tab by its visible label. iOS 26's tab bar nests buttons
    /// under intermediate `Other` elements which makes `tabBars.buttons[…]`
    /// brittle — fall back to a generic button query if needed. Retries the
    /// tap once if the tab doesn't appear to have been selected after the
    /// first tap, since a system alert dismissal in the same frame can eat
    /// the synthesized event.
    func switchToTab(_ label: String, file: StaticString = #file, line: UInt = #line) {
        let resolve = { () -> XCUIElement in
            let direct = self.app.tabBars.buttons[label]
            if direct.waitForExistence(timeout: 2) { return direct }
            return self.app.buttons[label]
        }
        let target = resolve()
        XCTAssertTrue(
            target.waitForExistence(timeout: 4),
            "Couldn't locate tab '\(label)'",
            file: file, line: line
        )
        target.tap()
        // Retry once if the tab still isn't selected — interrupts can eat
        // the first tap. iOS marks the selected tab button as `isSelected`.
        if !target.isSelected {
            Thread.sleep(forTimeInterval: 0.5)
            let again = resolve()
            if again.exists && !again.isSelected {
                again.tap()
            }
        }
    }
}
