import Combine
import UIKit
import UserNotifications

extension Notification.Name {
    static let onlyLockWeeklyReportHistoryDidChange = Notification.Name("onlylock.weeklyReport.historyDidChange")
}

private func fallbackCompletedWeeklyReportStart(from now: Date) -> Date {
    let calendar = Calendar.current
    let currentWeekStart = OnlyLockShared.startOfWeekMonday(containing: now, calendar: calendar)
    return calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
}

private func latestPublishedWeeklyReportStart(from now: Date) -> Date {
    let calendar = Calendar.current
    let currentWeekStart = OnlyLockShared.startOfWeekMonday(containing: now, calendar: calendar)
    var releaseComponents = calendar.dateComponents([.year, .month, .day], from: currentWeekStart)
    releaseComponents.hour = 9
    releaseComponents.minute = 0
    releaseComponents.second = 0
    let currentWeekRelease = calendar.date(from: releaseComponents) ?? currentWeekStart
    let daysBack = now >= currentWeekRelease ? 7 : 14
    return calendar.date(byAdding: .day, value: -daysBack, to: currentWeekStart) ?? currentWeekStart
}

private func weeklyReportStart(from userInfo: [AnyHashable: Any]) -> Date? {
    let weekStartTimestamp: TimeInterval?
    if let value = userInfo[OnlyLockShared.weeklyInsightsNotificationWeekStartKey] as? TimeInterval {
        weekStartTimestamp = value
    } else if let value = userInfo[OnlyLockShared.weeklyInsightsNotificationWeekStartKey] as? NSNumber {
        weekStartTimestamp = value.doubleValue
    } else if let value = userInfo[OnlyLockShared.weeklyInsightsNotificationWeekStartKey] as? String {
        weekStartTimestamp = TimeInterval(value)
    } else {
        weekStartTimestamp = nil
    }

    return weekStartTimestamp.map { Date(timeIntervalSince1970: $0) }
}

private func effectiveWeeklyReportNow(defaults: UserDefaults? = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)) -> Date {
    OnlyLockShared.resolvedNow(defaults: defaults, fallback: Date())
}

private func resolvedWeeklyReportStart(
    for notification: UNNotification,
    defaults: UserDefaults? = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)
) -> Date {
    let requestIdentifier = notification.request.identifier
    if requestIdentifier.hasPrefix("onlylock.notification.weeklyReport.debug.") {
        return weeklyReportStart(from: notification.request.content.userInfo)
            ?? fallbackCompletedWeeklyReportStart(from: effectiveWeeklyReportNow(defaults: defaults))
    }

    return fallbackCompletedWeeklyReportStart(from: notification.date)
}

private func persistWeeklyReportHistoryEntry(for weekStart: Date, defaults: UserDefaults) {
    let normalizedWeekStart = OnlyLockShared.startOfWeekMonday(containing: weekStart, calendar: .current)
    let timestamp = Int(normalizedWeekStart.timeIntervalSince1970)
    let existing = Set(defaults.array(forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey) as? [Int] ?? [])
    guard !existing.contains(timestamp) else { return }
    defaults.set(Array(existing.union([timestamp])).sorted(by: >), forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey)
    defaults.synchronize()
    NotificationCenter.default.post(name: .onlyLockWeeklyReportHistoryDidChange, object: nil)
}

enum AppQuickAction: String {
    case createLockTask = "com.onlylock.quickaction.createLockTask"
    case viewScreenTime = "com.onlylock.quickaction.viewScreenTime"
    case shareApp = "com.onlylock.quickaction.shareApp"

    private var localizedTitle: String {
        let isEnglish = AppLanguageRuntime.currentLanguage == .english
        switch self {
        case .createLockTask:
            return isEnglish ? "Create Lock Task" : "创建锁定任务"
        case .viewScreenTime:
            return isEnglish ? "View Screen Time" : "看屏幕时间"
        case .shareApp:
            return isEnglish ? "Share App" : "分享 App"
        }
    }

    var shortcutItem: UIApplicationShortcutItem {
        switch self {
        case .createLockTask:
            return UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: localizedTitle,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle"),
                userInfo: nil
            )
        case .viewScreenTime:
            return UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: localizedTitle,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "chart.line.uptrend.xyaxis"),
                userInfo: nil
            )
        case .shareApp:
            return UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: localizedTitle,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "square.and.arrow.up"),
                userInfo: nil
            )
        }
    }
}

final class AppQuickActionRouter: ObservableObject {
    struct WeeklyInsightsRoute {
        let weekStart: Date?
    }

    static let shared = AppQuickActionRouter()

    @Published private(set) var pendingAction: AppQuickAction?
    @Published private(set) var pendingWeeklyInsightsRoute: WeeklyInsightsRoute?

    private init() {}

    @MainActor
    func configureShortcutItems() {
        UIApplication.shared.shortcutItems = [
            AppQuickAction.createLockTask.shortcutItem,
            AppQuickAction.viewScreenTime.shortcutItem,
            AppQuickAction.shareApp.shortcutItem
        ]
    }

    func handle(shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = AppQuickAction(rawValue: shortcutItem.type) else {
            return false
        }
        DispatchQueue.main.async {
            self.pendingAction = action
        }
        return true
    }

    func handleWeeklyInsightsRoute(weekStart: Date?) {
        DispatchQueue.main.async {
            self.pendingWeeklyInsightsRoute = WeeklyInsightsRoute(weekStart: weekStart)
        }
    }

    @MainActor
    func consumePendingAction() -> AppQuickAction? {
        let action = pendingAction
        pendingAction = nil
        return action
    }

    @MainActor
    func consumePendingWeeklyInsightsRoute() -> WeeklyInsightsRoute? {
        let route = pendingWeeklyInsightsRoute
        pendingWeeklyInsightsRoute = nil
        return route
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let response = connectionOptions.notificationResponse {
            handleWeeklyReportNotificationIfNeeded(response: response)
        }
        guard let shortcutItem = connectionOptions.shortcutItem else { return }
        _ = AppQuickActionRouter.shared.handle(shortcutItem: shortcutItem)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppQuickActionRouter.shared.handle(shortcutItem: shortcutItem))
    }

    private func handleWeeklyReportNotificationIfNeeded(response: UNNotificationResponse) {
        let requestIdentifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        let matchedByType = (userInfo[OnlyLockShared.weeklyInsightsNotificationTypeKey] as? String) == OnlyLockShared.weeklyInsightsNotificationTypeValue
        let matchedByIdentifier = requestIdentifier == OnlyLockShared.weeklyInsightsNotificationIdentifier
            || requestIdentifier.hasPrefix("\(OnlyLockShared.weeklyInsightsNotificationIdentifier).")
            || requestIdentifier.hasPrefix("onlylock.notification.weeklyReport.debug.")
        guard matchedByType || matchedByIdentifier else { return }

        let weekStart = resolvedWeeklyReportStart(for: response.notification)
        AppQuickActionRouter.shared.handleWeeklyInsightsRoute(weekStart: weekStart)
    }

}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let weeklyInsightsNotificationScheduler = WeeklyInsightsNotificationScheduler()
    private let installMarkerDefaultsKey = "onlylock.install.marker"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        handleFreshInstallNotificationResetIfNeeded(application: application)
        Task { @MainActor in
            AppQuickActionRouter.shared.configureShortcutItems()
        }
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            _ = AppQuickActionRouter.shared.handle(shortcutItem: shortcutItem)
        }
        Task {
            await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Keep delegate attached in case system or scene transitions reset it.
        UNUserNotificationCenter.current().delegate = self
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            application.applicationIconBadgeNumber = 0
        }
        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        defaults.set(0, forKey: OnlyLockShared.notificationBadgeCountKey)
        defaults.synchronize()
        Task { @MainActor in
            AppQuickActionRouter.shared.configureShortcutItems()
        }
        Task {
            await syncWeeklyReportHistoryFromDeliveredNotifications()
            await reconcileWeeklyReportHistoryIfNeeded()
            await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
        }
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: connectingSceneSession.configuration.name,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(AppQuickActionRouter.shared.handle(shortcutItem: shortcutItem))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        persistWeeklyReportHistoryIfNeeded(notification: notification)
        syncAppIconBadgeForWeeklyReportIfNeeded(userInfo: userInfo)
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let requestIdentifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        let matchedByType = (userInfo[OnlyLockShared.weeklyInsightsNotificationTypeKey] as? String) == OnlyLockShared.weeklyInsightsNotificationTypeValue
        let matchedByIdentifier = requestIdentifier == OnlyLockShared.weeklyInsightsNotificationIdentifier
            || requestIdentifier.hasPrefix("\(OnlyLockShared.weeklyInsightsNotificationIdentifier).")
            || requestIdentifier.hasPrefix("onlylock.notification.weeklyReport.debug.")

        if matchedByType || matchedByIdentifier {
            let weekStart = resolvedWeeklyReportStart(for: response.notification)
            persistWeeklyReportHistoryIfNeeded(weekStart: weekStart)
            AppQuickActionRouter.shared.handleWeeklyInsightsRoute(weekStart: weekStart)
        }
        completionHandler()
    }

    private func persistWeeklyReportHistoryIfNeeded(notification: UNNotification) {
        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        let weekStart = resolvedWeeklyReportStart(for: notification, defaults: defaults)
        persistWeeklyReportHistoryEntry(for: weekStart, defaults: defaults)
    }

    private func persistWeeklyReportHistoryIfNeeded(weekStart: Date) {
        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        persistWeeklyReportHistoryEntry(for: weekStart, defaults: defaults)
    }

    private func syncWeeklyReportHistoryFromDeliveredNotifications() async {
        let deliveredNotifications = await deliveredWeeklyReportNotifications()
        guard !deliveredNotifications.isEmpty else { return }

        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        for notification in deliveredNotifications {
            let requestIdentifier = notification.request.identifier
            let userInfo = notification.request.content.userInfo
            let matchedByType = (userInfo[OnlyLockShared.weeklyInsightsNotificationTypeKey] as? String) == OnlyLockShared.weeklyInsightsNotificationTypeValue
            let matchedByIdentifier = requestIdentifier == OnlyLockShared.weeklyInsightsNotificationIdentifier
                || requestIdentifier.hasPrefix("\(OnlyLockShared.weeklyInsightsNotificationIdentifier).")
                || requestIdentifier.hasPrefix("onlylock.notification.weeklyReport.debug.")
            guard matchedByType || matchedByIdentifier else { continue }

            let weekStart = resolvedWeeklyReportStart(for: notification, defaults: defaults)
            persistWeeklyReportHistoryEntry(for: weekStart, defaults: defaults)
        }
    }

    private func reconcileWeeklyReportHistoryIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        let weekStart = latestPublishedWeeklyReportStart(from: effectiveWeeklyReportNow(defaults: defaults))
        let timestamp = Int(OnlyLockShared.startOfWeekMonday(containing: weekStart, calendar: .current).timeIntervalSince1970)
        let deleted = Set(defaults.array(forKey: OnlyLockShared.weeklyReportDeletedWeekStartsKey) as? [Int] ?? [])
        guard !deleted.contains(timestamp) else { return }

        let existingHistory = Set(defaults.array(forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey) as? [Int] ?? [])
        guard !existingHistory.contains(timestamp) else { return }

        persistWeeklyReportHistoryEntry(for: weekStart, defaults: defaults)
    }

    private func deliveredWeeklyReportNotifications() async -> [UNNotification] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
                continuation.resume(returning: notifications)
            }
        }
    }

    private func syncAppIconBadgeForWeeklyReportIfNeeded(userInfo: [AnyHashable: Any]) {
        let requestType = userInfo[OnlyLockShared.weeklyInsightsNotificationTypeKey] as? String
        guard requestType == OnlyLockShared.weeklyInsightsNotificationTypeValue else { return }

        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        let previousBadgeCount = max(0, defaults.integer(forKey: OnlyLockShared.notificationBadgeCountKey))
        let nextBadgeCount = max(1, previousBadgeCount + 1)
        defaults.set(nextBadgeCount, forKey: OnlyLockShared.notificationBadgeCountKey)
        defaults.synchronize()

        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(nextBadgeCount) { _ in }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = nextBadgeCount
            }
        }
    }

    private func handleFreshInstallNotificationResetIfNeeded(application: UIApplication) {
        let installDefaults = UserDefaults.standard
        guard !installDefaults.bool(forKey: installMarkerDefaultsKey) else { return }

        clearSystemBadge(application: application)
        clearStoredBadgeState()
        clearDeliveredAndPendingNotifications()

        installDefaults.set(true, forKey: installMarkerDefaultsKey)
        installDefaults.synchronize()
    }

    private func clearSystemBadge(application: UIApplication) {
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
        } else {
            application.applicationIconBadgeNumber = 0
        }
    }

    private func clearStoredBadgeState() {
        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        defaults.set(0, forKey: OnlyLockShared.notificationBadgeCountKey)
        defaults.synchronize()
    }

    private func clearDeliveredAndPendingNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
}
