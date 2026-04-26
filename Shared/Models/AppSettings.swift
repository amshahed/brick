import Foundation
import SwiftData

@Model
final class AppSettings {
    @Attribute(.unique) var singletonKey: String
    var passcodeHash: String?
    var passcodeSalt: String?
    var passcodeModeRaw: String
    var focusOnboardingCompleted: Bool
    var completedBlocksCount: Int
    var hasCompletedOnboarding: Bool = false
    var createdAt: Date

    init(
        singletonKey: String = "default",
        passcodeHash: String? = nil,
        passcodeSalt: String? = nil,
        passcodeMode: PasscodeMode = .userChosen,
        focusOnboardingCompleted: Bool = false,
        completedBlocksCount: Int = 0,
        hasCompletedOnboarding: Bool = false,
        createdAt: Date = .now
    ) {
        self.singletonKey = singletonKey
        self.passcodeHash = passcodeHash
        self.passcodeSalt = passcodeSalt
        self.passcodeModeRaw = passcodeMode.rawValue
        self.focusOnboardingCompleted = focusOnboardingCompleted
        self.completedBlocksCount = completedBlocksCount
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
    }

    var passcodeMode: PasscodeMode {
        get { PasscodeMode(rawValue: passcodeModeRaw) ?? .userChosen }
        set { passcodeModeRaw = newValue.rawValue }
    }

    var hasPasscode: Bool {
        passcodeHash != nil && passcodeSalt != nil
    }
}

enum PasscodeMode: String, CaseIterable {
    case userChosen = "user"
    case appGenerated = "generated"
}
