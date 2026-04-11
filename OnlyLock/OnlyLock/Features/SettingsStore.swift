import Combine
import Foundation
import UserNotifications
import UIKit

@MainActor
final class SettingsStore: ObservableObject {
    enum MembershipTier: String {
        case none
        case monthly
        case lifetime

        var title: String {
            let isEnglish = AppLanguageRuntime.currentLanguage == .english
            switch self {
            case .none:
                return isEnglish ? "No Membership" : "未开通会员"
            case .monthly:
                return isEnglish ? "Monthly" : "月度会员"
            case .lifetime:
                return isEnglish ? "Lifetime" : "终身会员"
            }
        }

        var subtitle: String {
            let isEnglish = AppLanguageRuntime.currentLanguage == .english
            switch self {
            case .none:
                return isEnglish ? "Free plan" : "当前为基础版"
            case .monthly:
                return isEnglish ? "Unlock premium monthly" : "按月解锁高级功能"
            case .lifetime:
                return isEnglish ? "Unlock all premium forever" : "永久解锁全部高级功能"
            }
        }

        var symbolName: String {
            switch self {
            case .none:
                return "person"
            case .monthly:
                return "calendar.badge.clock"
            case .lifetime:
                return "infinity"
            }
        }
    }

    enum AppearancePreference: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var localizationKey: String {
            switch self {
            case .system:
                return "系统"
            case .light:
                return "浅色"
            case .dark:
                return "深色"
            }
        }

        var title: String {
            AppLanguageRuntime.localized(for: localizationKey)
        }
    }

    @Published private(set) var profileName: String
    @Published private(set) var profileAvatarData: Data?
    @Published private(set) var isNotificationsEnabled: Bool
    @Published private(set) var appearancePreference: AppearancePreference
    @Published private(set) var membershipTier: MembershipTier
    @Published private(set) var systemNotificationsAuthorized = false
    @Published private(set) var isRequestingNotificationPermission = false

    private let defaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter

    init(
        defaults: UserDefaults? = nil,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        let sharedDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)
        self.defaults = defaults ?? sharedDefaults ?? .standard
        self.notificationCenter = notificationCenter

        profileName = (self.defaults.string(forKey: OnlyLockShared.settingsProfileNameKey) ?? "")
        profileAvatarData = self.defaults.data(forKey: OnlyLockShared.settingsProfileAvatarDataKey)
        membershipTier = SettingsStore.resolvedMembershipTier(from: self.defaults)

        if self.defaults.object(forKey: OnlyLockShared.settingsLockNotificationsEnabledKey) == nil {
            let migratedValue: Bool
            if self.defaults.object(forKey: OnlyLockShared.settingsNotificationsEnabledKey) != nil {
                migratedValue = self.defaults.bool(forKey: OnlyLockShared.settingsNotificationsEnabledKey)
            } else {
                migratedValue = true
            }
            isNotificationsEnabled = migratedValue
            self.defaults.set(migratedValue, forKey: OnlyLockShared.settingsLockNotificationsEnabledKey)
        } else {
            isNotificationsEnabled = self.defaults.bool(forKey: OnlyLockShared.settingsLockNotificationsEnabledKey)
        }

        if let storedAppearance = self.defaults.string(forKey: OnlyLockShared.settingsAppearancePreferenceKey),
           let preference = AppearancePreference(rawValue: storedAppearance) {
            appearancePreference = preference
        } else {
            appearancePreference = .system
            self.defaults.set(AppearancePreference.system.rawValue, forKey: OnlyLockShared.settingsAppearancePreferenceKey)
        }

    }

    var displayName: String {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            ? (AppLanguageRuntime.currentLanguage == .english ? "OnlyLock User" : "OnlyLock 用户")
            : trimmed
    }

    func updateProfileName(_ value: String) {
        profileName = value
        defaults.set(value, forKey: OnlyLockShared.settingsProfileNameKey)
    }

    func updateProfileAvatarData(_ data: Data?) {
        profileAvatarData = data
        if let data {
            defaults.set(data, forKey: OnlyLockShared.settingsProfileAvatarDataKey)
        } else {
            defaults.removeObject(forKey: OnlyLockShared.settingsProfileAvatarDataKey)
        }
    }

    func refreshNotificationAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        let isAuthorized = settings.authorizationStatus == .authorized ||
            settings.authorizationStatus == .provisional ||
            settings.authorizationStatus == .ephemeral

        systemNotificationsAuthorized = isAuthorized
        if !isAuthorized, isNotificationsEnabled {
            setNotificationsEnabled(false)
        }
    }

    func handleNotificationToggleChange(to enabled: Bool) async {
        guard !isRequestingNotificationPermission else { return }

        if !enabled {
            setNotificationsEnabled(false)
            return
        }

        await refreshNotificationAuthorizationStatus()
        if systemNotificationsAuthorized {
            setNotificationsEnabled(true)
            return
        }

        isRequestingNotificationPermission = true
        defer { isRequestingNotificationPermission = false }

        let granted: Bool
        do {
            granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            granted = false
        }

        if granted {
            setNotificationsEnabled(true)
        } else {
            setNotificationsEnabled(false)
        }

        await refreshNotificationAuthorizationStatus()
    }

    func updateAppearancePreference(_ preference: AppearancePreference) {
        appearancePreference = preference
        defaults.set(preference.rawValue, forKey: OnlyLockShared.settingsAppearancePreferenceKey)
    }

    func refreshMembershipStatus() {
        membershipTier = SettingsStore.resolvedMembershipTier(from: defaults)
    }

    private func setNotificationsEnabled(_ enabled: Bool) {
        isNotificationsEnabled = enabled
        defaults.set(enabled, forKey: OnlyLockShared.settingsLockNotificationsEnabledKey)
    }

    private static func resolvedMembershipTier(from defaults: UserDefaults) -> MembershipTier {
        let storedTier = MembershipTier(rawValue: defaults.string(forKey: OnlyLockShared.membershipTierKey) ?? "") ?? .none
        guard storedTier != .none else { return .none }
        return OnlyLockShared.hasActiveMembership(defaults: defaults) ? storedTier : .none
    }
}
