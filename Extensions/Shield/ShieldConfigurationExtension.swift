import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen you see when you open a blocked app in the bedroom.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        bedroomShield(for: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        bedroomShield(for: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        bedroomShield(for: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        bedroomShield(for: webDomain.domain)
    }

    private func bedroomShield(for name: String?) -> ShieldConfiguration {
        let night = UIColor(red: 0.04, green: 0.05, blue: 0.13, alpha: 1)
        let accent = UIColor(red: 0.42, green: 0.45, blue: 0.95, alpha: 1)
        let icon = UIImage(systemName: "moon.zzz.fill")?
            .withTintColor(UIColor(red: 0.80, green: 0.82, blue: 1.0, alpha: 1), renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: night,
            icon: icon,
            title: ShieldConfiguration.Label(text: "Not in the bedroom", color: .white),
            subtitle: ShieldConfiguration.Label(
                text: "\(name ?? "This app") unlocks when you leave the room.",
                color: UIColor(white: 1, alpha: 0.7)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: accent,
            secondaryButtonLabel: nil
        )
    }
}
