import Foundation
import SwiftData

struct AppSettingsStore {
    let context: ModelContext

    private static let singletonKey = "default"

    /// UserDefaults backstop for `hasCompletedOnboarding`. SwiftData saves
    /// have intermittently failed in this app on real devices (likely App
    /// Group / SQLite lock contention with the DeviceActivity extension),
    /// which used to trap users in the onboarding flow. RootView ORs this
    /// with the persisted SwiftData flag so the user can reach the app even
    /// if the persistent save throws.
    static let onboardingCompletedDefaultsKey = "brick.onboarding.completed"

    @discardableResult
    func loadOrCreate() throws -> AppSettings {
        let key = Self.singletonKey
        let descriptor = FetchDescriptor<AppSettings>(
            predicate: #Predicate { $0.singletonKey == key }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let new = AppSettings()
        context.insert(new)
        try context.save()
        return new
    }

    func setPasscode(_ code: String, mode: PasscodeMode) throws {
        let settings = try loadOrCreate()
        let salt = PasscodeService.makeSalt()
        settings.passcodeSalt = salt
        settings.passcodeHash = PasscodeService.hash(code, salt: salt)
        settings.passcodeMode = mode
        try context.save()
    }

    func incrementCompletedBlocks() throws {
        let settings = try loadOrCreate()
        settings.completedBlocksCount += 1
        try context.save()
    }

    func markFocusOnboardingComplete() throws {
        let settings = try loadOrCreate()
        settings.focusOnboardingCompleted = true
        try context.save()
    }

    func markOnboardingComplete() throws {
        // Always set the UserDefaults fallback first — even if the SwiftData
        // save throws below, the user reaches the app on next launch.
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedDefaultsKey)
        let settings = try loadOrCreate()
        settings.hasCompletedOnboarding = true
        try context.save()
    }
}
