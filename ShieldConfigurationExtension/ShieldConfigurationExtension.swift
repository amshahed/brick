import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: UIColor.systemBackground,
            title: ShieldConfiguration.Label(
                text: "Blocked by Brick",
                color: UIColor.label
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitleText(for: application),
                color: UIColor.secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Take a break",
                color: UIColor.white
            ),
            primaryButtonBackgroundColor: UIColor.systemBlue,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: UIColor.secondaryLabel
            )
        )
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        ShieldConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        ShieldConfiguration()
    }

    private func subtitleText(for application: Application) -> String {
        if let name = application.localizedDisplayName {
            return "\(name) is paused. Take a short break to unlock it for a few minutes."
        }
        return "This app is paused. Take a short break to unlock it for a few minutes."
    }
}
