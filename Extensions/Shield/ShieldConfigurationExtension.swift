import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen you see when you open a blocked app in the bedroom: "Goodnight, Instagram" in the
/// picture-book colors. iOS only lets a shield set an icon, a title, a subtitle, buttons and
/// colors (always in the system font), so that's all this changes.
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
        // Same colors as the app's Assets.xcassets (this extension has no asset catalog).
        let nurseryGreen = UIColor(red: 0x2F / 255, green: 0x6B / 255, blue: 0x45 / 255, alpha: 1)
        let moonYellow = UIColor(red: 0xF2 / 255, green: 0xC8 / 255, blue: 0x49 / 255, alpha: 1)
        let paper = UIColor(red: 0xF7 / 255, green: 0xEF / 255, blue: 0xDD / 255, alpha: 1)
        let ink = UIColor(red: 0x23 / 255, green: 0x30 / 255, blue: 0x2A / 255, alpha: 1)
        // The phone asleep under its blanket, from the app icon (ShieldIcon@3x.png in this folder).
        let icon = UIImage(named: "ShieldIcon")

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: nurseryGreen,
            icon: icon,
            title: ShieldConfiguration.Label(text: name.map { "Goodnight, \($0)" } ?? "Goodnight", color: paper),
            subtitle: ShieldConfiguration.Label(
                text: "Your phone is in the bedroom, so \(name ?? "this app") is asleep. It wakes up when you leave the room.",
                color: paper.withAlphaComponent(0.88)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: ink),
            primaryButtonBackgroundColor: moonYellow,
            secondaryButtonLabel: nil
        )
    }
}
