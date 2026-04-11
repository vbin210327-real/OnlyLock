import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private let attemptTracker = ShieldAttemptTracker()
    private let appGroupIdentifier = "group.com.onlylock.shared"
    private let appearancePreferenceKey = "onlylock.settings.appearancePreference"
    private let resolvedAppearanceStyleKey = "onlylock.settings.appearanceResolvedStyle"

    private enum ShieldAppearanceStyle {
        case light
        case dark
    }

    private struct ShieldRenderDiagnostic: Encodable {
        let timestamp: TimeInterval
        let currentTraitStyle: String
        let screenTraitStyle: String
        let preference: String?
        let resolvedStyle: String?
        let useDarkAppearance: Bool?
        let selectedAppearance: String
        let selectedAsset: String
        let title: String
        let subtitle: String?
    }

    private var isEnglish: Bool {
        (sharedString(forKey: "onlylock.settings.appLanguageCode") ?? "zh-Hans") == "en"
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
        let appearanceStyle = resolvedShieldAppearanceStyle()
        let backgroundBlurStyle: UIBlurEffect.Style = appearanceStyle == .dark ? .systemMaterialDark : .systemMaterialLight
        let titleTextColor: UIColor = appearanceStyle == .dark ? .white : .black
        let subtitleTextColor: UIColor = appearanceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.62)
            : UIColor.black.withAlphaComponent(0.58)
        let primaryButtonTextColor: UIColor = appearanceStyle == .dark ? .black : .white
        let primaryButtonBackgroundColor: UIColor = appearanceStyle == .dark ? .white : .black
        let shieldBackgroundColor: UIColor = appearanceStyle == .dark
            ? UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
            : UIColor(red: 0.985, green: 0.985, blue: 0.99, alpha: 1.0)

        writeRenderDiagnostic(
            appearanceStyle: appearanceStyle,
            selectedAsset: appearanceStyle == .dark ? "AppMarkWhite/AppMarkGlyphWhite" : "AppMark/AppMarkGlyph",
            title: title,
            subtitle: subtitle
        )

        return ShieldConfiguration(
            backgroundBlurStyle: backgroundBlurStyle,
            backgroundColor: shieldBackgroundColor,
            icon: icon,
            title: ShieldConfiguration.Label(
                text: title,
                color: titleTextColor
            ),
            subtitle: subtitle.flatMap {
                ShieldConfiguration.Label(
                    text: $0,
                    color: subtitleTextColor
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
        let useWhiteAsset = resolvedShieldAppearanceStyle() == .dark
        let preferredAssetNames = useWhiteAsset
            ? ["AppMarkWhite"]
            : ["AppMark"]
        let forcedTint: UIColor = useWhiteAsset ? .white : .black

        for assetName in preferredAssetNames {
            if let image = UIImage(named: assetName, in: bundle, compatibleWith: nil) {
                return image.withRenderingMode(.alwaysOriginal)
            }
        }

        return fallbackOnlyLockIcon(tintColor: forcedTint)
    }

    private func resolvedShieldAppearanceStyle() -> ShieldAppearanceStyle {
        let normalizedPreference = sharedString(forKey: appearancePreferenceKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalizedPreference == "dark" {
            return .dark
        }

        if normalizedPreference == "light" {
            return .light
        }

        let resolvedStyle = sharedString(forKey: resolvedAppearanceStyleKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if resolvedStyle == "dark" {
            return .dark
        }

        if resolvedStyle == "light" {
            return .light
        }

        if let useDarkAppearance = sharedBool(forKey: "onlylock.settings.shieldUseDarkAppearance") {
            return useDarkAppearance ? .dark : .light
        }

        return .light
    }

    private func sharedString(forKey key: String) -> String? {
        CFPreferencesAppSynchronize(appGroupIdentifier as CFString)
        return CFPreferencesCopyAppValue(key as CFString, appGroupIdentifier as CFString) as? String
    }

    private func sharedBool(forKey key: String) -> Bool? {
        CFPreferencesAppSynchronize(appGroupIdentifier as CFString)
        guard let value = CFPreferencesCopyAppValue(key as CFString, appGroupIdentifier as CFString) else {
            return nil
        }

        if let boolValue = value as? Bool {
            return boolValue
        }

        if let numberValue = value as? NSNumber {
            return numberValue.boolValue
        }

        if let stringValue = value as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1":
                return true
            case "false", "0":
                return false
            default:
                return nil
            }
        }

        return nil
    }

    private func writeRenderDiagnostic(
        appearanceStyle: ShieldAppearanceStyle,
        selectedAsset: String,
        title: String,
        subtitle: String?
    ) {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return
        }

        let payload = ShieldRenderDiagnostic(
            timestamp: Date().timeIntervalSince1970,
            currentTraitStyle: {
                switch UITraitCollection.current.userInterfaceStyle {
                case .dark: return "dark"
                case .light: return "light"
                default: return "unspecified"
                }
            }(),
            screenTraitStyle: {
                switch UIScreen.main.traitCollection.userInterfaceStyle {
                case .dark: return "dark"
                case .light: return "light"
                default: return "unspecified"
                }
            }(),
            preference: sharedString(forKey: appearancePreferenceKey),
            resolvedStyle: sharedString(forKey: resolvedAppearanceStyleKey),
            useDarkAppearance: sharedBool(forKey: "onlylock.settings.shieldUseDarkAppearance"),
            selectedAppearance: appearanceStyle == .dark ? "dark" : "light",
            selectedAsset: selectedAsset,
            title: title,
            subtitle: subtitle
        )

        guard let data = try? JSONEncoder().encode(payload) else {
            return
        }

        let fileURL = groupURL.appendingPathComponent("shield_render_diagnostic.json")
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func fallbackOnlyLockIcon(tintColor: UIColor) -> UIImage {
        let size = CGSize(width: 92, height: 92)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: size)
            let viewfinderConfig = UIImage.SymbolConfiguration(pointSize: 52, weight: .semibold)
            let lockConfig = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
            let viewfinder = UIImage(systemName: "viewfinder", withConfiguration: viewfinderConfig)?
                .withTintColor(tintColor, renderingMode: .alwaysOriginal)
            let lock = UIImage(systemName: "lock.fill", withConfiguration: lockConfig)?
                .withTintColor(tintColor, renderingMode: .alwaysOriginal)

            let viewfinderRect = CGRect(x: rect.midX - 26, y: rect.midY - 26, width: 52, height: 52)
            viewfinder?.draw(in: viewfinderRect)

            let lockRect = CGRect(x: rect.midX - 10, y: rect.midY - 9, width: 20, height: 20)
            lock?.draw(in: lockRect)
        }
    }
}
