import Foundation

#if canImport(ManagedSettingsUI)
import ManagedSettingsUI
import ManagedSettings

// Custom Shield Configuration Provider for macOS Screen Time Shielding
@available(macOS 13.0, *)
public class FocusGuardShieldConfigurationProvider: ShieldConfigurationDataSource {
    public override init() {}

    public override func configuration(shielding application: Application) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundColor: nil,
            icon: nil,
            title: ShieldConfiguration.Label(text: "FOCUSGUARD", color: .label),
            subtitle: ShieldConfiguration.Label(text: "Time's up. You used today's attention budget.", color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close App", color: .white),
            secondaryButtonLabel: nil
        )
    }

    public override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return ShieldConfiguration(
            backgroundColor: nil,
            icon: nil,
            title: ShieldConfiguration.Label(text: "FOCUSGUARD", color: .label),
            subtitle: ShieldConfiguration.Label(text: "Website restricted by active attention policy.", color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Dismiss", color: .white),
            secondaryButtonLabel: nil
        )
    }
}
#endif
