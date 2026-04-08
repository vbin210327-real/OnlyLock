import DeviceActivity
import Foundation
import ManagedSettings
import UserNotifications
import WidgetKit

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: OnlyLockShared.managedSettingsStoreName)
    private let storage = LockRuleStorage()
    private let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
    private let calendar = Calendar.current
    private let rewardEventEncoder = JSONEncoder()

    private struct ShieldSnapshot {
        let isLocked: Bool
        let activeRules: [LockRule]
    }

    private var lockStateDefaultsKey: String {
        "onlylock.monitor.lockState.isLocked"
    }

    private var startNotificationDedupPrefix: String {
        "onlylock.monitor.startNotification.lastAt."
    }

    private var isEnglish: Bool {
        OnlyLockShared.isEnglishLanguage(defaults: defaults)
    }

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        guard OnlyLockShared.isOnlyLockActivity(activity) else {
            return
        }

        let snapshot = applyShield()
        guard OnlyLockShared.hasActiveMembership(defaults: defaults, now: OnlyLockShared.resolvedNow(defaults: defaults, fallback: Date())) else {
            return
        }
        if OnlyLockShared.isRuleStartActivity(activity) {
            let now = OnlyLockShared.resolvedNow(defaults: defaults, fallback: Date())
            syncWidgetStreakForCheckIn(on: now)
            if let startedRule = startedRule(for: activity) {
                writeRewardCompletionEvent(rule: startedRule, activity: activity, completedAt: now)
            }
            postStartNotificationIfNeeded(snapshot: snapshot, activity: activity)
        }
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)

        guard OnlyLockShared.isOnlyLockActivity(activity),
              OnlyLockShared.hasActiveMembership(defaults: defaults, now: OnlyLockShared.resolvedNow(defaults: defaults, fallback: Date())),
              let warningRule = endedRule(for: activity),
              warningRule.durationMinutes < OnlyLockShared.shortTaskPaddingDurationMinutes else {
            return
        }

        _ = applyShield()
        if !shouldSuppressManualDeletionEndNotification() {
            postEndNotification(for: activity)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        guard OnlyLockShared.isOnlyLockActivity(activity) else {
            return
        }

        _ = applyShield()
        guard OnlyLockShared.hasActiveMembership(defaults: defaults, now: OnlyLockShared.resolvedNow(defaults: defaults, fallback: Date())) else {
            return
        }
        if OnlyLockShared.isRuleStartActivity(activity) {
            guard shouldPostEndNotification(for: activity) else { return }
            postEndNotification(for: activity)
        }
    }

    private func applyShield() -> ShieldSnapshot {
        let now = OnlyLockShared.resolvedNow(defaults: defaults, fallback: Date())
        guard OnlyLockShared.hasActiveMembership(defaults: defaults, now: now) else {
            clearShield()
            return ShieldSnapshot(isLocked: false, activeRules: [])
        }

        guard let rules = try? storage.loadAll() else {
            clearShield()
            return ShieldSnapshot(isLocked: false, activeRules: [])
        }

        let activeRules = rules.filter { rule in
            isRuleActive(rule, at: now) && rule.hasAnyTarget
        }

        guard !activeRules.isEmpty else {
            clearShield()
            return ShieldSnapshot(isLocked: false, activeRules: [])
        }

        var applicationTokens: Set<ApplicationToken> = []
        var categoryTokens: Set<ActivityCategoryToken> = []
        var webDomainTokens: Set<WebDomainToken> = []
        var manualWebDomains: Set<String> = []

        for rule in activeRules {
            applicationTokens.formUnion(rule.applicationTokens)
            categoryTokens.formUnion(rule.categoryTokens)
            webDomainTokens.formUnion(rule.webDomainTokens)
            manualWebDomains.formUnion(rule.manualWebDomains)
        }

        store.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        store.shield.applicationCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)
        store.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens
        store.shield.webDomainCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)

        var blockedDomains = Set(webDomainTokens.map { WebDomain(token: $0) })
        blockedDomains.formUnion(manualWebDomains.map { WebDomain(domain: $0) })
        store.webContent.blockedByFilter = blockedDomains.isEmpty ? nil : .specific(blockedDomains)

        return ShieldSnapshot(isLocked: true, activeRules: activeRules)
    }

    private func clearShield() {
        store.clearAllSettings()
    }

    private func isRuleActive(_ rule: LockRule, at now: Date) -> Bool {
        if rule.isWeeklyRepeat {
            guard let activeWindow = repeatActiveWindow(for: rule, now: now) else {
                return false
            }
            return now >= activeWindow.start && now < activeWindow.end
        }

        guard let endAt = Calendar.current.date(byAdding: .minute, value: rule.durationMinutes, to: rule.startAt) else {
            return false
        }

        let normalizedNow = OnlyLockShared.normalizedToMinuteBoundary(now, calendar: calendar)
        let normalizedStart = OnlyLockShared.normalizedToMinuteBoundary(rule.startAt, calendar: calendar)
        let normalizedEnd = OnlyLockShared.normalizedToMinuteBoundary(endAt, calendar: calendar)
        return normalizedNow >= normalizedStart && normalizedNow < normalizedEnd
    }

    private func repeatActiveWindow(for rule: LockRule, now: Date) -> (start: Date, end: Date)? {
        let weekdays = rule.repeatWeekdays.filter { (1...7).contains($0) }
        guard !weekdays.isEmpty else { return nil }

        let hour = calendar.component(.hour, from: rule.startAt)
        let minute = calendar.component(.minute, from: rule.startAt)
        let searchAnchor = now.addingTimeInterval(1)

        var latestStart: Date?
        for weekday in weekdays {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let candidate = calendar.nextDate(
                after: searchAnchor,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                direction: .backward
            ) else { continue }

            if latestStart == nil || candidate > latestStart! {
                latestStart = candidate
            }
        }

        guard let start = latestStart,
              let end = calendar.date(byAdding: .minute, value: rule.durationMinutes, to: start) else {
            return nil
        }

        return (start, end)
    }

    private func postStartNotificationIfNeeded(snapshot: ShieldSnapshot, activity: DeviceActivityName) {
        guard snapshot.isLocked else {
            defaults.set(false, forKey: lockStateDefaultsKey)
            return
        }

        guard shouldPostStartNotification(for: activity) else {
            defaults.set(true, forKey: lockStateDefaultsKey)
            return
        }

        defaults.set(true, forKey: lockStateDefaultsKey)
        let body: String
        if let startedRule = startedRule(for: activity) {
            body = makeLockStartBody(for: startedRule)
        } else {
            body = makeLockStartBody(for: snapshot.activeRules)
        }

        postNotification(
            title: "OnlyLock",
            body: body
        )
    }

    private func shouldPostStartNotification(for activity: DeviceActivityName) -> Bool {
        let key = startNotificationDedupPrefix + activity.rawValue
        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: key)

        // DeviceActivity may invoke duplicate start callbacks very close to each other.
        guard now - last >= 20 else {
            return false
        }

        defaults.set(now, forKey: key)
        return true
    }

    private func makeLockStartBody(for activeRules: [LockRule]) -> String {
        var applicationTokens: Set<ApplicationToken> = []
        var webDomainTokens: Set<WebDomainToken> = []
        var manualDomains: Set<String> = []

        for rule in activeRules {
            applicationTokens.formUnion(rule.applicationTokens)
            webDomainTokens.formUnion(rule.webDomainTokens)
            manualDomains.formUnion(rule.manualWebDomains)
        }

        let appCount = applicationTokens.count
        let webCount = webDomainTokens.count + manualDomains.count

        var segments: [String] = []
        if appCount > 0 {
            segments.append(isEnglish ? "\(appCount) apps" : "\(appCount)个App")
        }
        if webCount > 0 {
            segments.append(isEnglish ? "\(webCount) websites" : "\(webCount)个网站")
        }

        guard !segments.isEmpty else {
            return isEnglish
                ? "Locked your configured targets as planned."
                : "已按你的计划锁定你设置的目标。"
        }

        return isEnglish
            ? "Locked as planned: \(segments.joined(separator: ", "))"
            : "已按你的计划锁定\(segments.joined(separator: "、"))"
    }

    private func makeLockStartBody(for rule: LockRule) -> String {
        let targetText = makeLockTargetText(for: rule)
        return isEnglish ? "Locked as planned: \(targetText)" : "已按你的计划锁定\(targetText)"
    }

    private func postEndNotification(for activity: DeviceActivityName) {
        guard let endedRule = endedRule(for: activity) else {
            postNotification(title: "OnlyLock", body: isEnglish ? "Lock ended automatically" : "锁定已自动结束")
            return
        }

        let targetText = makeLockTargetText(for: endedRule)
        if isEnglish {
            postNotification(title: "OnlyLock", body: "\(targetText) lock ended automatically")
        } else {
            postNotification(title: "OnlyLock", body: "\(targetText)锁定已自动结束")
        }
    }

    private func shouldPostEndNotification(for activity: DeviceActivityName) -> Bool {
        if shouldSuppressManualDeletionEndNotification() {
            return false
        }

        guard let rule = endedRule(for: activity) else {
            return true
        }

        // Short tasks emit their real end notification from intervalWillEndWarning at
        // the actual end time. Suppress the later padded interval end callback.
        return rule.durationMinutes >= OnlyLockShared.shortTaskPaddingDurationMinutes
    }

    private func shouldSuppressManualDeletionEndNotification() -> Bool {
        let until = defaults.double(forKey: OnlyLockShared.suppressEndNotificationUntilKey)
        guard until > 0 else {
            return false
        }

        let now = Date().timeIntervalSince1970
        if now <= until {
            return true
        }

        defaults.removeObject(forKey: OnlyLockShared.suppressEndNotificationUntilKey)
        return false
    }

    private func endedRule(for activity: DeviceActivityName) -> LockRule? {
        rule(for: activity)
    }

    private func startedRule(for activity: DeviceActivityName) -> LockRule? {
        rule(for: activity)
    }

    private func rule(for activity: DeviceActivityName) -> LockRule? {
        guard let ruleID = ruleID(from: activity),
              let rules = try? storage.loadAll() else {
            return nil
        }

        return rules.first(where: { $0.id == ruleID })
    }

    private func ruleID(from activity: DeviceActivityName) -> UUID? {
        OnlyLockShared.ruleID(from: activity)
    }

    private func makeLockTargetText(for rule: LockRule) -> String {
        var names: [String] = []

        let applicationNames = rule.applicationTokens
            .compactMap { token in
                let app = Application(token: token)
                return normalizedDisplayName(app.localizedDisplayName ?? app.bundleIdentifier)
            }
            .sorted { (lhs: String, rhs: String) in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        let selectedWebNames = rule.webDomainTokens
            .compactMap { token in
                normalizedDisplayName(WebDomain(token: token).domain)
            }
            .sorted { (lhs: String, rhs: String) in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        let manualWebNames = rule.manualWebDomains
            .compactMap(normalizedDisplayName)
            .sorted { (lhs: String, rhs: String) in
                lhs.localizedStandardCompare(rhs) == .orderedAscending
            }

        names.append(contentsOf: applicationNames)
        names.append(contentsOf: selectedWebNames)
        names.append(contentsOf: manualWebNames)

        var deduplicated: [String] = []
        var seen: Set<String> = []

        for name in names {
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_CN"))
            if seen.insert(key).inserted {
                deduplicated.append(name)
            }
        }

        guard !deduplicated.isEmpty else {
            let appCount = rule.applicationTokens.count
            let webCount = rule.webDomainTokens.count + rule.manualWebDomains.count
            let categoryCount = rule.categoryTokens.count

            var segments: [String] = []
            if appCount > 0 {
                segments.append(isEnglish ? "\(appCount) apps" : "\(appCount)个App")
            }
            if webCount > 0 {
                segments.append(isEnglish ? "\(webCount) websites" : "\(webCount)个网站")
            }
            if categoryCount > 0 {
                segments.append(isEnglish ? "\(categoryCount) categories" : "\(categoryCount)个类别")
            }

            if !segments.isEmpty {
                return segments.joined(separator: isEnglish ? ", " : "、")
            }

            return isEnglish ? "your configured targets" : "你设置的目标"
        }

        let prefix = deduplicated.prefix(3).joined(separator: isEnglish ? ", " : "、")
        if deduplicated.count > 3 {
            return isEnglish
                ? "\(prefix) and \(deduplicated.count - 3) more"
                : "\(prefix)等\(deduplicated.count - 3)项"
        }

        return prefix
    }

    private func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeRewardCompletionEvent(rule: LockRule, activity: DeviceActivityName, completedAt: Date) {
        let normalizedCompletedAt = OnlyLockShared.normalizedToMinuteBoundary(completedAt, calendar: calendar)
        let eventID = rewardCompletionEventID(rule: rule, activity: activity, completedAt: normalizedCompletedAt)
        let event = RewardCompletionEvent(
            eventID: eventID,
            ruleID: rule.id,
            completedAt: normalizedCompletedAt,
            durationMinutes: rule.durationMinutes,
            isWeeklyRepeat: rule.isWeeklyRepeat
        )

        guard let data = try? rewardEventEncoder.encode(event) else {
            return
        }

        defaults.set(data, forKey: OnlyLockShared.rewardEventKeyPrefix + eventID)
        defaults.synchronize()
    }

    private func rewardCompletionEventID(rule: LockRule, activity: DeviceActivityName, completedAt: Date) -> String {
        let timestamp = Int(completedAt.timeIntervalSince1970)
        return "\(rule.id.uuidString.lowercased())|\(activity.rawValue)|\(timestamp)"
    }

    private func postNotification(title: String, body: String) {
        let isNotificationsEnabledObject = defaults.object(forKey: OnlyLockShared.settingsLockNotificationsEnabledKey)
        let isNotificationsEnabled = (isNotificationsEnabledObject as? Bool) ?? true
        guard isNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "onlylock.monitor.\(UUID().uuidString.lowercased())",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func syncWidgetStreakForCheckIn(on date: Date) {
        let checkInDay = calendar.startOfDay(for: date)
        let lastTimestamp = defaults.double(forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey)
        let currentStreak = max(0, defaults.integer(forKey: OnlyLockShared.widgetCurrentStreakKey))

        if lastTimestamp > 0 {
            let lastDay = Date(timeIntervalSince1970: lastTimestamp)
            if calendar.isDate(lastDay, inSameDayAs: checkInDay) {
                defaults.synchronize()
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
        }

        let newStreak: Int
        if lastTimestamp > 0,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: checkInDay),
           calendar.isDate(Date(timeIntervalSince1970: lastTimestamp), inSameDayAs: yesterday),
           currentStreak > 0 {
            newStreak = currentStreak + 1
        } else {
            newStreak = 1
        }

        defaults.set(newStreak, forKey: OnlyLockShared.widgetCurrentStreakKey)
        defaults.set(
            checkInDay.timeIntervalSince1970,
            forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey
        )
        defaults.synchronize()
        WidgetCenter.shared.reloadAllTimelines()
    }
}
