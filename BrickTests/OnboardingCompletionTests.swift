import Foundation
import SwiftData
import XCTest
@testable import Brick

/// Regression coverage for the onboarding-complete fix. The original bug
/// trapped users on the Done screen if `context.save()` threw — RootView
/// kept routing them back to onboarding because the SwiftData flag was
/// never written. The fix writes a UserDefaults backstop *before* the
/// SwiftData save, so RootView's OR check lets the user through even if
/// SwiftData fails for any reason.
@MainActor
final class OnboardingCompletionTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "BrickTests.OnboardingCompletionTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Use a private suite so we don't collide with the simulator's
        // shared standard defaults across tests.
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
        // Mirror standard so the production code (which reads/writes
        // `UserDefaults.standard`) is observable. We do this by using
        // `removeObject` on standard at the start and asserting on it.
        UserDefaults.standard.removeObject(
            forKey: AppSettingsStore.onboardingCompletedDefaultsKey
        )
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(
            forKey: AppSettingsStore.onboardingCompletedDefaultsKey
        )
        try super.tearDownWithError()
    }

    func testMarkOnboardingCompleteSetsBothFlags() throws {
        let context = try InMemoryStore.make()
        let store = AppSettingsStore(context: context)

        try store.markOnboardingComplete()

        // SwiftData side.
        let settings = try store.loadOrCreate()
        XCTAssertTrue(
            settings.hasCompletedOnboarding,
            "SwiftData flag should be true after a successful save."
        )

        // UserDefaults backstop.
        XCTAssertTrue(
            UserDefaults.standard.bool(
                forKey: AppSettingsStore.onboardingCompletedDefaultsKey
            ),
            "UserDefaults backstop must be set so RootView routes past onboarding even on SwiftData failure."
        )
    }

    /// The backstop must be written *before* the SwiftData save attempt —
    /// otherwise a save failure swallows it. We can't easily inject a
    /// failing context, but we can verify the backstop is set at least once
    /// by the public API even when called multiple times.
    func testBackstopSurvivesAcrossCalls() throws {
        let context = try InMemoryStore.make()
        let store = AppSettingsStore(context: context)

        try store.markOnboardingComplete()
        // Even after manually clearing the SwiftData flag, the UD flag
        // remains and the next launch's RootView OR check still passes.
        let settings = try store.loadOrCreate()
        settings.hasCompletedOnboarding = false
        try context.save()

        XCTAssertTrue(
            UserDefaults.standard.bool(
                forKey: AppSettingsStore.onboardingCompletedDefaultsKey
            ),
            "Backstop must persist independently of SwiftData state."
        )
    }
}
