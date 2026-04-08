import Foundation
import UserNotifications

struct WeeklyInsightsNotificationScheduler {
    private let notificationCenter: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let calendar: Calendar
#if DEBUG
    private let debugLastTriggeredMinuteKey = "onlylock.debug.weeklyReport.lastTriggeredMinute"
#endif

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        defaults: UserDefaults? = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier),
        calendar: Calendar = .current
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults ?? .standard
        self.calendar = calendar
    }

    func syncWeeklyReportNotification() async {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [OnlyLockShared.weeklyInsightsNotificationIdentifier]
        )

        let currentNow = OnlyLockShared.resolvedNow(defaults: defaults, fallback: Date())
        guard OnlyLockShared.hasActiveMembership(defaults: defaults, now: currentNow) else {
            return
        }

        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let nextMondayDate = nextMondayAtNineAM(from: currentNow)
        guard OnlyLockShared.hasActiveMembership(defaults: defaults, now: nextMondayDate) else {
            return
        }
        let weekStart = completedWeekStart(forReportGeneratedAt: nextMondayDate)

        let content = UNMutableNotificationContent()
        content.title = "OnlyLock"
        content.body = weeklyNotificationBody()
        content.sound = .default
        content.badge = NSNumber(value: max(1, defaults.integer(forKey: OnlyLockShared.notificationBadgeCountKey) + 1))
        content.userInfo = [
            OnlyLockShared.weeklyInsightsNotificationTypeKey: OnlyLockShared.weeklyInsightsNotificationTypeValue,
            OnlyLockShared.weeklyInsightsNotificationWeekStartKey: weekStart.timeIntervalSince1970
        ]

        let triggerDateComponents = calendar.dateComponents(
            [.weekday, .hour, .minute],
            from: nextMondayDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: OnlyLockShared.weeklyInsightsNotificationIdentifier,
            content: content,
            trigger: trigger
        )
        try? await notificationCenter.add(request)
    }

#if DEBUG
    func emitDebugWeeklyReportIfDue(simulatedNow: Date) async {
        guard OnlyLockShared.hasActiveMembership(defaults: defaults, now: simulatedNow) else {
            return
        }

        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let weekday = calendar.component(.weekday, from: simulatedNow)
        let hour = calendar.component(.hour, from: simulatedNow)
        let minute = calendar.component(.minute, from: simulatedNow)
        guard weekday == 2, hour == 9, minute == 0 else {
            return
        }

        let minuteAnchor = calendar.dateInterval(of: .minute, for: simulatedNow)?.start ?? simulatedNow
        let minuteAnchorTimestamp = Int(minuteAnchor.timeIntervalSince1970)
        let lastTriggeredMinute = defaults.integer(forKey: debugLastTriggeredMinuteKey)
        guard lastTriggeredMinute != minuteAnchorTimestamp else {
            return
        }

        let weekStart = completedWeekStart(forReportGeneratedAt: simulatedNow)

        let content = UNMutableNotificationContent()
        content.title = "OnlyLock"
        content.body = weeklyNotificationBody()
        content.sound = .default
        content.badge = NSNumber(value: max(1, defaults.integer(forKey: OnlyLockShared.notificationBadgeCountKey) + 1))
        content.userInfo = [
            OnlyLockShared.weeklyInsightsNotificationTypeKey: OnlyLockShared.weeklyInsightsNotificationTypeValue,
            OnlyLockShared.weeklyInsightsNotificationWeekStartKey: weekStart.timeIntervalSince1970
        ]

        let identifier = "onlylock.notification.weeklyReport.debug.\(minuteAnchorTimestamp)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        do {
            try await notificationCenter.add(request)
            defaults.set(minuteAnchorTimestamp, forKey: debugLastTriggeredMinuteKey)
            defaults.synchronize()
        } catch {
            // no-op for debug helper
        }
    }
#endif

    private func nextMondayAtNineAM(from now: Date) -> Date {
        let currentWeekday = calendar.component(.weekday, from: now)
        let mondayWeekday = 2
        let daysUntilMonday = (mondayWeekday - currentWeekday + 7) % 7

        let targetDay: Date
        if daysUntilMonday == 0 {
            var todayNineComponents = calendar.dateComponents([.year, .month, .day], from: now)
            todayNineComponents.hour = 9
            todayNineComponents.minute = 0
            todayNineComponents.second = 0
            let todayNine = calendar.date(from: todayNineComponents) ?? now
            if now < todayNine {
                targetDay = todayNine
            } else {
                targetDay = calendar.date(byAdding: .day, value: 7, to: todayNine) ?? todayNine
            }
        } else {
            let nextMonday = calendar.date(byAdding: .day, value: daysUntilMonday, to: now) ?? now
            var nextMondayComponents = calendar.dateComponents([.year, .month, .day], from: nextMonday)
            nextMondayComponents.hour = 9
            nextMondayComponents.minute = 0
            nextMondayComponents.second = 0
            targetDay = calendar.date(from: nextMondayComponents) ?? nextMonday
        }

        return targetDay
    }

    private func completedWeekStart(forReportGeneratedAt date: Date) -> Date {
        let currentWeekStart = OnlyLockShared.startOfWeekMonday(containing: date, calendar: calendar)
        return calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
    }

    private func weeklyNotificationBody() -> String {
        "你的本周屏幕时间报告已生成「点击查看」"
    }
}
