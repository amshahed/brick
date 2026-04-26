import Foundation
import SwiftData

struct AppSettingsStore {
    let context: ModelContext

    private static let singletonKey = "default"

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
        let settings = try loadOrCreate()
        settings.hasCompletedOnboarding = true
        try context.save()
    }
}
