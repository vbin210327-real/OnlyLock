import DeviceActivity
import Foundation
import UserNotifications

enum LockSchedulerError: LocalizedError {
    case invalidEndTime
    case membershipRequired

    var errorDescription: String? {
        let isEnglish = AppLanguageRuntime.currentLanguage == .english
        switch self {
        case .invalidEndTime:
            return isEnglish
                ? "Unable to calculate end time. Adjust settings and try again."
                : "无法计算结束时间，请调整参数后重试。"
        case .membershipRequired:
            return isEnglish
                ? "Membership has expired. Renew to continue using lock features."
                : "会员已过期，请先续费后再继续使用锁定功能。"
        }
    }
}

final class LockScheduler {
    private let shortTaskPaddingDurationMinutes = OnlyLockShared.shortTaskPaddingDurationMinutes
    private let shortTaskPaddingFallbacks = [60, 180, 1440]
    private let center: DeviceActivityCenter
    private let storage: LockRuleStorage
    private let notificationCenter: UNUserNotificationCenter
    private let calendar: Calendar
    private let defaults: UserDefaults

    init(
        center: DeviceActivityCenter = DeviceActivityCenter(),
        storage: LockRuleStorage = LockRuleStorage(),
        notificationCenter: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current,
        defaults: UserDefaults? = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)
    ) {
        self.center = center
        self.storage = storage
        self.notificationCenter = notificationCenter
        self.calendar = calendar
        self.defaults = defaults ?? .standard
    }

    func currentRule() throws -> LockRule? {
        try currentRules().first
    }

    func currentRules() throws -> [LockRule] {
        try storage.loadAll()
    }

    func saveAndSchedule(rule: LockRule) async throws {
        guard OnlyLockShared.hasActiveMembership(defaults: defaults) else {
            throw LockSchedulerError.membershipRequired
        }

        let previousRules = try storage.loadAll()
        var updatedRules = previousRules.filter { $0.id != rule.id }
        updatedRules.append(rule)
        let previousRule = previousRules.first(where: { $0.id == rule.id })
        let activityNames = Array(
            Set(
                monitoredActivityNames(for: rule) +
                (previousRule.map { monitoredActivityNames(for: $0) } ?? [])
            )
        )

        do {
            try storage.saveAll(updatedRules)
            try await prepareRuntimeNotifications()
            center.stopMonitoring(activityNames)

            if rule.isWeeklyRepeat || ((rule.endAt ?? .distantPast) > Date()) {
                try startMonitoringPrimaryActivities(for: rule)
            }
        } catch {
            try? storage.saveAll(previousRules)
            center.stopMonitoring(activityNames)

            if let previousRule,
               (previousRule.isWeeklyRepeat || ((previousRule.endAt ?? .distantPast) > Date())) {
                try? startMonitoringPrimaryActivities(for: previousRule)
            }

            try? await prepareRuntimeNotifications()
            throw error
        }
    }

    func deleteRule(id: UUID) {
        let previousRules = (try? storage.loadAll()) ?? []
        let updatedRules = previousRules.filter { $0.id != id }
        let deletedRule = previousRules.first(where: { $0.id == id })
        let activityNames = deletedRule.map { monitoredActivityNames(for: $0) } ?? monitoredActivityNames(for: id)

        do {
            if let deletedRule, isRuleActiveNow(deletedRule, now: Date()) {
                defaults.set(
                    Date().addingTimeInterval(30).timeIntervalSince1970,
                    forKey: OnlyLockShared.suppressEndNotificationUntilKey
                )
            }
            try storage.saveAll(updatedRules)
            center.stopMonitoring(activityNames)
            Task { try? await prepareRuntimeNotifications() }
        } catch {
            try? storage.saveAll(previousRules)
        }
    }

    func clearAllRules() {
        center.stopMonitoring([OnlyLockShared.legacyActivityName])

        if let rules = try? storage.loadAll() {
            center.stopMonitoring(monitoredActivityNames(for: rules))
        }

        Task {
            try? await removePendingOnlyLockNotificationRequests()
        }

        storage.clear()
    }

    func clearRule() {
        clearAllRules()
    }

    private func monitoredActivityNames(for rules: [LockRule]) -> [DeviceActivityName] {
        rules.flatMap { monitoredActivityNames(for: $0) }
    }

    private func monitoredActivityNames(for rule: LockRule) -> [DeviceActivityName] {
        if rule.isWeeklyRepeat {
            let weekdays = normalizedWeekdays(rule.repeatWeekdays)
            var names: [DeviceActivityName] = []
            for weekday in weekdays {
                names.append(OnlyLockShared.activityName(for: rule.id, weekday: weekday))
                names.append(OnlyLockShared.endSignalActivityName(for: rule.id, weekday: weekday))
            }
            return names
        }

        return monitoredActivityNames(for: rule.id)
    }

    private func monitoredActivityNames(for ruleID: UUID) -> [DeviceActivityName] {
        [
            OnlyLockShared.activityName(for: ruleID),
            OnlyLockShared.endSignalActivityName(for: ruleID)
        ]
    }

    private func startMonitoringPrimaryActivities(for rule: LockRule) throws {
        if rule.isWeeklyRepeat {
            for weekday in normalizedWeekdays(rule.repeatWeekdays) {
                try startMonitoringPrimaryActivity(for: rule, weekday: weekday)
            }
            return
        }

        try startMonitoringPrimaryActivity(for: rule, weekday: nil)
    }

    private func startMonitoringPrimaryActivity(for rule: LockRule, weekday: Int?) throws {
        let activityName: DeviceActivityName
        if let weekday {
            activityName = OnlyLockShared.activityName(for: rule.id, weekday: weekday)
        } else {
            activityName = OnlyLockShared.activityName(for: rule.id)
        }

        let paddings: [Int?]
        if rule.durationMinutes < shortTaskPaddingDurationMinutes {
            paddings = shortTaskPaddingFallbacks.map { Optional($0) }
        } else {
            paddings = [nil]
        }

        var lastError: Error?

        for padding in paddings {
            do {
                try center.startMonitoring(
                    activityName,
                    during: try makePrimarySchedule(for: rule, paddedTo: padding, weekday: weekday)
                )
                return
            } catch let error as DeviceActivityCenter.MonitoringError where error == .intervalTooShort {
                lastError = error
                continue
            } catch {
                throw error
            }
        }

        throw lastError ?? LockSchedulerError.invalidEndTime
    }

    private func makePrimarySchedule(
        for rule: LockRule,
        paddedTo paddingMinutes: Int? = nil,
        weekday: Int?
    ) throws -> DeviceActivitySchedule {
        guard let actualEndAt = rule.endAt else {
            throw LockSchedulerError.invalidEndTime
        }

        let endAt: Date
        let effectivePaddingMinutes = paddingMinutes ?? shortTaskPaddingDurationMinutes

        if rule.durationMinutes < effectivePaddingMinutes {
            endAt = calendar.date(byAdding: .minute, value: effectivePaddingMinutes, to: rule.startAt) ?? actualEndAt
        } else {
            endAt = actualEndAt
        }

        let startComponents: DateComponents
        let endComponents: DateComponents
        let repeats: Bool

        if let weekday {
            let startHour = calendar.component(.hour, from: rule.startAt)
            let startMinute = calendar.component(.minute, from: rule.startAt)
            let endHour = calendar.component(.hour, from: endAt)
            let endMinute = calendar.component(.minute, from: endAt)
            let dayShift = calendar.dateComponents([.day], from: rule.startAt, to: endAt).day ?? 0
            let normalizedDayShift = max(0, dayShift % 7)
            let endWeekday = ((weekday - 1 + normalizedDayShift) % 7) + 1

            var start = DateComponents()
            start.weekday = weekday
            start.hour = startHour
            start.minute = startMinute
            startComponents = start

            var end = DateComponents()
            end.weekday = endWeekday
            end.hour = endHour
            end.minute = endMinute
            endComponents = end
            repeats = true
        } else {
            let units: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
            startComponents = calendar.dateComponents(units, from: rule.startAt)
            endComponents = calendar.dateComponents(units, from: endAt)
            repeats = false
        }
        let warningTime: DateComponents?

        if rule.durationMinutes < effectivePaddingMinutes {
            warningTime = DateComponents(minute: effectivePaddingMinutes - rule.durationMinutes)
        } else {
            warningTime = nil
        }

        return DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: repeats,
            warningTime: warningTime
        )
    }

    private func normalizedWeekdays(_ weekdays: Set<Int>) -> [Int] {
        weekdays
            .filter { (1...7).contains($0) }
            .sorted()
    }

    private func isRuleActiveNow(_ rule: LockRule, now: Date) -> Bool {
        if rule.isWeeklyRepeat {
            guard let activeWindow = repeatActiveWindow(for: rule, now: now) else {
                return false
            }
            return now >= activeWindow.start && now < activeWindow.end
        }

        guard let endAt = rule.endAt else {
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

    private func prepareRuntimeNotifications() async throws {
        try await removePendingOnlyLockNotificationRequests()

        // Runtime notifications are emitted by the monitor extension only after
        // lock/unlock has actually been applied.
        let previousSettings = await notificationCenter.notificationSettings()
        let previousStatus = previousSettings.authorizationStatus
        let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])

        // First-time grant via task creation should immediately enable in-app
        // notification toggle, so lock start notifications are not suppressed.
        if granted, previousStatus == .notDetermined {
            defaults.set(true, forKey: OnlyLockShared.settingsLockNotificationsEnabledKey)
        }
    }

    private func removePendingOnlyLockNotificationRequests() async throws {
        let pendingIdentifiers = await fetchPendingNotificationIdentifiers()
        let onlyLockIdentifiers = pendingIdentifiers.filter { identifier in
            identifier.hasPrefix(OnlyLockShared.lockStartNotificationPrefix) ||
                identifier.hasPrefix(OnlyLockShared.lockEndNotificationPrefix) ||
                identifier == OnlyLockShared.legacyLockStartNotificationIdentifier ||
                identifier == OnlyLockShared.legacyLockEndNotificationIdentifier
        }

        guard !onlyLockIdentifiers.isEmpty else {
            return
        }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: onlyLockIdentifiers)
    }

    private func fetchPendingNotificationIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            notificationCenter.getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }
}
