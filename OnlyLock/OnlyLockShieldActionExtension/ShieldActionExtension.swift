import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let attemptTracker = ShieldAttemptTracker()
    private let defaults = UserDefaults(suiteName: "group.com.onlylock.shared") ?? .standard

    private var isEnglish: Bool {
        (defaults.string(forKey: "onlylock.settings.appLanguageCode") ?? "zh-Hans") == "en"
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeApplicationConfiguration(application, category: nil)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeApplicationConfiguration(application, category: category)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        let domainName = normalizedDisplayName(webDomain.domain) ?? (isEnglish ? "This website" : "该网站")
        let subtitle = attemptTracker.subtitleForWebDomain(
            webDomain,
            displayName: domainName,
            category: nil
        )
        return makeConfiguration(
            title: composedTitle(for: domainName),
            subtitle: subtitle,
            icon: onlyLockAppIcon()
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        let domainName = normalizedDisplayName(webDomain.domain) ?? (isEnglish ? "This website" : "该网站")
        let subtitle = attemptTracker.subtitleForWebDomain(
            webDomain,
            displayName: domainName,
            category: category
        )
        return makeConfiguration(
            title: composedTitle(for: domainName),
            subtitle: subtitle,
            icon: onlyLockAppIcon()
        )
    }

    private func makeApplicationConfiguration(_ application: Application, category: ActivityCategory?) -> ShieldConfiguration {
        let appName = normalizedDisplayName(application.localizedDisplayName) ?? (isEnglish ? "This app" : "该应用")
        let subtitle = attemptTracker.subtitleForApplication(
            application,
            displayName: appName,
            category: category
        )

        return makeConfiguration(
            title: composedTitle(for: appName),
            subtitle: subtitle,
            icon: onlyLockAppIcon()
        )
    }

    private func makeConfiguration(title: String, subtitle: String?, icon: UIImage) -> ShieldConfiguration {
        let primaryButtonTextColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .black : .white
        }
        let primaryButtonBackgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        }
        let shieldBackgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)
                : UIColor(red: 0.97, green: 0.97, blue: 0.975, alpha: 1.0)
        }

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: shieldBackgroundColor,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: title,
                color: .label
            ),
            subtitle: subtitle.flatMap {
                ShieldConfiguration.Label(
                    text: $0,
                    color: .secondaryLabel
                )
            },
            primaryButtonLabel: ShieldConfiguration.Label(
                text: isEnglish ? "Close" : "关闭",
                color: primaryButtonTextColor
            ),
            primaryButtonBackgroundColor: primaryButtonBackgroundColor,
            secondaryButtonLabel: nil
        )
    }

    private func composedTitle(for name: String) -> String {
        if isEnglish {
            return "\(name)\nBlocked by OnlyLock"
        }
        return "\(name)\n已被OnlyLock禁用"
    }

    private func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func onlyLockAppIcon() -> UIImage {
        let bundle = Bundle(for: ShieldConfigurationExtension.self)

        if let image = UIImage(named: "AppMark", in: bundle, compatibleWith: nil) ??
            UIImage(named: "AppMarkGlyph", in: bundle, compatibleWith: nil) {
            return image.withRenderingMode(.alwaysOriginal)
        }

        return fallbackOnlyLockIcon()
    }

    private func fallbackOnlyLockIcon() -> UIImage {
        let size = CGSize(width: 92, height: 92)
        let renderer = UIGraphicsImageRenderer(size: size)
        let iconColor = UIColor.label

        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let viewfinderConfig = UIImage.SymbolConfiguration(pointSize: 52, weight: .semibold)
            let lockConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            let viewfinder = UIImage(systemName: "viewfinder", withConfiguration: viewfinderConfig)?
                .withTintColor(iconColor, renderingMode: .alwaysOriginal)
            let lock = UIImage(systemName: "lock.fill", withConfiguration: lockConfig)?
                .withTintColor(iconColor, renderingMode: .alwaysOriginal)

            let viewfinderRect = CGRect(x: rect.midX - 26, y: rect.midY - 26, width: 52, height: 52)
            viewfinder?.draw(in: viewfinderRect)

            let lockRect = CGRect(x: rect.midX - 10, y: rect.midY - 9, width: 20, height: 20)
            lock?.draw(in: lockRect)
        }
    }
}
