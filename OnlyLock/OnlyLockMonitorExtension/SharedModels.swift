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
    static let suppressEndNotificationUntilKey = "onlylock.notification.suppressEndUntil"
    static let rewardEventKeyPrefix = "onlylock.reward.event."
    static let rewardLastImportAtKey = "onlylock.reward.lastImportAt"
    static let rewardSeededLegacyKey = "onlylock.reward.seededLegacy"
#if DEBUG
    static let debugTimeOverrideEnabledKey = "onlylock.debug.timeOverride.enabled"
    static let debugTimeOverrideTimestampKey = "onlylock.debug.timeOverride.timestamp"
#endif
    static let settingsNotificationsEnabledKey = "onlylock.settings.notificationsEnabled"
    static let settingsLockNotificationsEnabledKey = "onlylock.settings.lockNotificationsEnabled"
    static let notificationBadgeCountKey = "onlylock.notification.badgeCount"
    static let settingsProfileNameKey = "onlylock.settings.profile.name"
    static let settingsProfileAvatarDataKey = "onlylock.settings.profile.avatarData"
    static let appLanguageCodeKey = "onlylock.settings.appLanguageCode"
    static let membershipUnlockedKey = "onlylock.membership.unlocked"
    static let membershipTierKey = "onlylock.membership.tier"
    static let membershipExpirationTimestampKey = "onlylock.membership.expirationTimestamp"
    static let widgetCurrentStreakKey = "onlylock.widget.currentStreak"
    static let widgetLastCheckInDayTimestampKey = "onlylock.widget.lastCheckInDayTimestamp"

    static func isOnlyLockActivity(_ name: DeviceActivityName) -> Bool {
        isRuleStartActivity(name) || isRuleEndSignalActivity(name) || name == legacyActivityName
    }

    static func isRuleStartActivity(_ name: DeviceActivityName) -> Bool {
        name.rawValue.hasPrefix(activityNamePrefix)
    }

    static func isRuleEndSignalActivity(_ name: DeviceActivityName) -> Bool {
        name.rawValue.hasPrefix(endSignalActivityNamePrefix)
    }

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

    static func isEnglishLanguage(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier)
    ) -> Bool {
        let defaults = defaults ?? .standard
        return (defaults.string(forKey: appLanguageCodeKey) ?? "zh-Hans") == "en"
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

struct LockRule: Codable, Equatable {
    let id: UUID
    let name: String?
    let startAt: Date
    let durationMinutes: Int
    let isWeeklyRepeat: Bool
    let repeatWeekdays: Set<Int>
    let applicationTokens: Set<ApplicationToken>
    let categoryTokens: Set<ActivityCategoryToken>
    let webDomainTokens: Set<WebDomainToken>
    let manualWebDomains: Set<String>
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case startAt
        case durationMinutes
        case isWeeklyRepeat
        case repeatWeekdays
        case applicationTokens
        case categoryTokens
        case webDomainTokens
        case manualWebDomains
        case createdAt
        case updatedAt
    }

    init(
        id: UUID,
        name: String?,
        startAt: Date,
        durationMinutes: Int,
        isWeeklyRepeat: Bool,
        repeatWeekdays: Set<Int>,
        applicationTokens: Set<ApplicationToken>,
        categoryTokens: Set<ActivityCategoryToken>,
        webDomainTokens: Set<WebDomainToken>,
        manualWebDomains: Set<String>,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.startAt = startAt
        self.durationMinutes = durationMinutes
        self.isWeeklyRepeat = isWeeklyRepeat
        self.repeatWeekdays = repeatWeekdays
        self.applicationTokens = applicationTokens
        self.categoryTokens = categoryTokens
        self.webDomainTokens = webDomainTokens
        self.manualWebDomains = manualWebDomains
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        startAt = try container.decode(Date.self, forKey: .startAt)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        isWeeklyRepeat = try container.decodeIfPresent(Bool.self, forKey: .isWeeklyRepeat) ?? false
        repeatWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .repeatWeekdays) ?? []
        applicationTokens = try container.decode(Set<ApplicationToken>.self, forKey: .applicationTokens)
        categoryTokens = try container.decodeIfPresent(Set<ActivityCategoryToken>.self, forKey: .categoryTokens) ?? []
        webDomainTokens = try container.decode(Set<WebDomainToken>.self, forKey: .webDomainTokens)
        manualWebDomains = try container.decodeIfPresent(Set<String>.self, forKey: .manualWebDomains) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var hasAnyTarget: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty || !manualWebDomains.isEmpty
    }
}

struct LockRuleStorage {
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)) {
        defaults = userDefaults ?? .standard
    }

    func load() throws -> LockRule? {
        return try loadAll().first
    }

    func loadAll() throws -> [LockRule] {
        guard let data = defaults.data(forKey: OnlyLockShared.lockRuleStorageKey) else {
            return []
        }

        if let rules = try? decoder.decode([LockRule].self, from: data) {
            return rules
        }

        if let legacyRule = try? decoder.decode(LockRule.self, from: data) {
            return [legacyRule]
        }

        return []
    }
}
