import DeviceActivity
import Foundation
import ManagedSettings

enum OnlyLockShared {
    static let appGroupIdentifier = "group.com.onlylock.shared"
    static let lockRuleStorageKey = "onlylock.lockRule"
    static let cloudKitContainerIdentifier = "iCloud.com.onlylock.app"
    static let legacyActivityName = DeviceActivityName("onlylock.activity.oneOff")
    static let activityNamePrefix = "onlylock.activity.start."
    static let endSignalActivityNamePrefix = "onlylock.activity.end."
    static let repeatingWeekdaySeparator = ".w"
    static let shortTaskPaddingDurationMinutes = 60
    static let managedSettingsStoreName = ManagedSettingsStore.Name("onlylock.shield.store")
    static let legacyLockStartNotificationIdentifier = "onlylock.notification.start"
    static let legacyLockEndNotificationIdentifier = "onlylock.notification.end"

    static let lockStartNotificationPrefix = "onlylock.notification.start."
    static let lockEndNotificationPrefix = "onlylock.notification.end."
    static let weeklyInsightsNotificationIdentifier = "onlylock.notification.weeklyReport"
    static let weeklyInsightsNotificationTypeKey = "onlylock.notification.type"
    static let weeklyInsightsNotificationTypeValue = "weekly_report"
    static let weeklyInsightsNotificationWeekStartKey = "onlylock.notification.weekStartTimestamp"
    static let weeklyDigestSelectedWeekStartKey = "onlylock.weeklyDigest.selectedWeekStart"
    static let weeklyReportHistoryWeekStartsKey = "onlylock.weeklyReport.historyWeekStarts"
    static let weeklyReportReadWeekStartsKey = "onlylock.weeklyReport.readWeekStarts"
    static let weeklyReportDeletedWeekStartsKey = "onlylock.weeklyReport.deletedWeekStarts"
    static let suppressEndNotificationUntilKey = "onlylock.notification.suppressEndUntil"
    static let notificationBadgeCountKey = "onlylock.notification.badgeCount"
    static let rewardEventKeyPrefix = "onlylock.reward.event."
    static let rewardLastImportAtKey = "onlylock.reward.lastImportAt"
    static let rewardSeededLegacyKey = "onlylock.reward.seededLegacy"
#if DEBUG
    static let debugTimeOverrideEnabledKey = "onlylock.debug.timeOverride.enabled"
    static let debugTimeOverrideTimestampKey = "onlylock.debug.timeOverride.timestamp"
    static let debugWeeklyReportOverrideEnabledKey = "onlylock.debug.weeklyReport.override.enabled"
#endif
    static let settingsNotificationsEnabledKey = "onlylock.settings.notificationsEnabled"
    static let settingsLockNotificationsEnabledKey = "onlylock.settings.lockNotificationsEnabled"
    static let settingsProfileNameKey = "onlylock.settings.profile.name"
    static let settingsProfileAvatarDataKey = "onlylock.settings.profile.avatarData"
    static let settingsAppearancePreferenceKey = "onlylock.settings.appearancePreference"
    static let settingsResolvedAppearanceStyleKey = "onlylock.settings.appearanceResolvedStyle"
    static let settingsShieldUseDarkAppearanceKey = "onlylock.settings.shieldUseDarkAppearance"
    static let appLanguageCodeKey = "onlylock.settings.appLanguageCode"
    static let hasCompletedWelcomeKey = "onlylock.welcome.completed"
    static let hasCompletedIntroOnboardingKey = "onlylock.onboarding.intro.completed"
    static let pendingInitialTabKey = "onlylock.pending.initialTab"
    static let onboardingPrimaryGoalKey = "onlylock.onboarding.goal"
    static let onboardingPrimaryDistractionKey = "onlylock.onboarding.distraction"
    static let onboardingCurrentStepKey = "onlylock.onboarding.currentStep"
    static let onboardingStartTimestampKey = "onlylock.onboarding.startTimestamp"
    static let onboardingEndTimestampKey = "onlylock.onboarding.endTimestamp"
    static let onboardingSelectionDataKey = "onlylock.onboarding.selectionData"
    static let settingsLastPresentedStreakMedalTierKey = "onlylock.settings.streakMedal.lastPresentedTier"
    static let membershipUnlockedKey = "onlylock.membership.unlocked"
    static let membershipTierKey = "onlylock.membership.tier"
    static let membershipExpirationTimestampKey = "onlylock.membership.expirationTimestamp"
    static let widgetCurrentStreakKey = "onlylock.widget.currentStreak"
    static let widgetLastCheckInDayTimestampKey = "onlylock.widget.lastCheckInDayTimestamp"
    static let screenTimeInsightsSnapshotKeyPrefix = "onlylock.screentime.insights."
    static let screenTimeInsightsDiagnosticKeyPrefix = "onlylock.screentime.diagnostic."
#if DEBUG
    static let debugScreenTimeInsightsOverrideEnabledKey = "onlylock.debug.screentime.override.enabled"
    static let debugScreenTimeInsightsOverrideKeyPrefix = "onlylock.debug.screentime.override."
#endif

    static func activityName(for ruleID: UUID) -> DeviceActivityName {
        DeviceActivityName(activityNamePrefix + ruleID.uuidString.lowercased())
    }

    static func activityName(for ruleID: UUID, weekday: Int) -> DeviceActivityName {
        DeviceActivityName(activityNamePrefix + ruleID.uuidString.lowercased() + repeatingWeekdaySeparator + String(weekday))
    }

    static func endSignalActivityName(for ruleID: UUID) -> DeviceActivityName {
        DeviceActivityName(endSignalActivityNamePrefix + ruleID.uuidString.lowercased())
    }

    static func endSignalActivityName(for ruleID: UUID, weekday: Int) -> DeviceActivityName {
        DeviceActivityName(endSignalActivityNamePrefix + ruleID.uuidString.lowercased() + repeatingWeekdaySeparator + String(weekday))
    }

    static func isOnlyLockActivity(_ name: DeviceActivityName) -> Bool {
        isRuleStartActivity(name) || isRuleEndSignalActivity(name) || name == legacyActivityName
    }

    static func isRuleStartActivity(_ name: DeviceActivityName) -> Bool {
        name.rawValue.hasPrefix(activityNamePrefix)
    }

    static func isRuleEndSignalActivity(_ name: DeviceActivityName) -> Bool {
        name.rawValue.hasPrefix(endSignalActivityNamePrefix)
    }

    static func lockStartNotificationIdentifier(for ruleID: UUID) -> String {
        lockStartNotificationPrefix + ruleID.uuidString.lowercased()
    }

    static func lockEndNotificationIdentifier(for ruleID: UUID) -> String {
        lockEndNotificationPrefix + ruleID.uuidString.lowercased()
    }

    static func screenTimeInsightsSnapshotKey(scope: String) -> String {
        screenTimeInsightsSnapshotKeyPrefix + scope
    }

    static func screenTimeInsightsSnapshotKey(scope: String, rangeStart: Date, rangeEnd: Date) -> String {
        let start = Int(rangeStart.timeIntervalSince1970)
        let end = Int(rangeEnd.timeIntervalSince1970)
        return "\(screenTimeInsightsSnapshotKeyPrefix)\(scope).\(start).\(end)"
    }

    static func screenTimeInsightsDiagnosticKey(scope: String) -> String {
        screenTimeInsightsDiagnosticKeyPrefix + scope
    }

#if DEBUG
    static func debugScreenTimeInsightsOverrideKey(scope: String, rangeStart: Date, rangeEnd: Date) -> String {
        let start = Int(rangeStart.timeIntervalSince1970)
        let end = Int(rangeEnd.timeIntervalSince1970)
        return "\(debugScreenTimeInsightsOverrideKeyPrefix)\(scope).\(start).\(end)"
    }

    static func debugWeeklyReportOverrideKey(weekStart: Date) -> String {
        let normalizedStart = startOfWeekMonday(containing: weekStart)
        let timestamp = Int(normalizedStart.timeIntervalSince1970)
        return "onlylock.debug.weeklyReport.override.\(timestamp)"
    }
#endif

    static func ruleID(from activity: DeviceActivityName) -> UUID? {
        if let id = parseRuleID(activity.rawValue, prefix: activityNamePrefix) {
            return id
        }
        return parseRuleID(activity.rawValue, prefix: endSignalActivityNamePrefix)
    }

    static func resolvedNow(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier),
        fallback: Date = Date()
    ) -> Date {
#if DEBUG
        let defaults = defaults ?? .standard
        guard defaults.bool(forKey: debugTimeOverrideEnabledKey) else {
            return fallback
        }
        let timestamp = defaults.double(forKey: debugTimeOverrideTimestampKey)
        guard timestamp > 0 else {
            return fallback
        }
        return Date(timeIntervalSince1970: timestamp)
#else
        return fallback
#endif
    }

    static func normalizedToMinuteBoundary(
        _ date: Date,
        calendar: Calendar = .current
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    static func startOfWeekMonday(
        containing date: Date,
        calendar: Calendar = .current
    ) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let mondayOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: startOfDay) ?? startOfDay
    }

    static var weekdaysStartingMonday: [Int] {
        [2, 3, 4, 5, 6, 7, 1]
    }

    static func hasActiveMembership(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier),
        now: Date? = nil
    ) -> Bool {
        let defaults = defaults ?? .standard
        let tier = defaults.string(forKey: membershipTierKey) ?? "none"
        let effectiveNow = now ?? resolvedNow(defaults: defaults, fallback: Date())

        switch tier {
        case "lifetime":
            return true
        case "monthly":
            let expirationTimestamp = defaults.double(forKey: membershipExpirationTimestampKey)
            if expirationTimestamp > 0 {
                return effectiveNow.timeIntervalSince1970 < expirationTimestamp
            }
            return defaults.bool(forKey: membershipUnlockedKey)
        default:
            return false
        }
    }

    private static func parseRuleID(_ rawValue: String, prefix: String) -> UUID? {
        guard rawValue.hasPrefix(prefix) else { return nil }
        let remainder = String(rawValue.dropFirst(prefix.count))
        let idPart = remainder.components(separatedBy: repeatingWeekdaySeparator).first ?? remainder
        return UUID(uuidString: idPart)
    }
}

struct RewardCompletionEvent: Codable, Equatable, Identifiable {
    let eventID: String
    let ruleID: UUID
    let completedAt: Date
    let durationMinutes: Int
    let isWeeklyRepeat: Bool

    var id: String { eventID }
}
