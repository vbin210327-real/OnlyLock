import StoreKit
import SwiftUI
import Combine
import ObjectiveC.runtime

@main
struct OnlyLockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var languageStore = AppLanguageStore.shared

    init() {
        AppLanguageRuntime.activate()
    }

    var body: some Scene {
        WindowGroup {
            LaunchContainerView()
                .environmentObject(languageStore)
                .environment(\.locale, languageStore.locale)
                .task {
                    await MembershipTransactionObserver.shared.startIfNeeded()
                }
        }
    }
}

@MainActor
final class MembershipTransactionObserver {
    static let shared = MembershipTransactionObserver()

    private let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
    private let productIDs: Set<String> = [
        "com.onlylock.membership.monthly",
        "com.onlylock.membership.lifetime"
    ]

    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    private init() {}

    private var isDebugSimulatorPurchaseEnabled: Bool {
#if DEBUG
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
#else
        return false
#endif
    }

    func startIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true

        await refreshMembershipUnlockedState()

        updatesTask = Task {
            for await update in Transaction.updates {
                guard !Task.isCancelled else { break }
                guard case .verified(let transaction) = update else { continue }

                if productIDs.contains(transaction.productID) {
                    await transaction.finish()
                    await refreshMembershipUnlockedState()
                }
            }
        }
    }

    func refreshNow() async {
        await refreshMembershipUnlockedState()
    }

    private func refreshMembershipUnlockedState() async {
        var unlockedProductIDs = Set<String>()
        var monthlyExpirationTimestamp: TimeInterval = 0

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.revocationDate == nil else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            unlockedProductIDs.insert(transaction.productID)
            if transaction.productID == MembershipTierResolver.monthlyProductID,
               let expirationDate = transaction.expirationDate {
                monthlyExpirationTimestamp = max(monthlyExpirationTimestamp, expirationDate.timeIntervalSince1970)
            }
        }

        if isDebugSimulatorPurchaseEnabled, unlockedProductIDs.isEmpty {
            let storedTier = SettingsStore.MembershipTier(
                rawValue: defaults.string(forKey: OnlyLockShared.membershipTierKey) ?? ""
            ) ?? .none
            let isUnlocked = storedTier != .none
            defaults.set(isUnlocked, forKey: OnlyLockShared.membershipUnlockedKey)
            defaults.set(storedTier.rawValue, forKey: OnlyLockShared.membershipTierKey)
            if storedTier == .monthly {
                let fallbackExpiration = max(
                    defaults.double(forKey: OnlyLockShared.membershipExpirationTimestampKey),
                    Date().addingTimeInterval(30 * 24 * 60 * 60).timeIntervalSince1970
                )
                defaults.set(fallbackExpiration, forKey: OnlyLockShared.membershipExpirationTimestampKey)
            } else {
                defaults.set(0, forKey: OnlyLockShared.membershipExpirationTimestampKey)
            }
            defaults.synchronize()
            return
        }

        let tier = MembershipTierResolver.resolvedTier(from: unlockedProductIDs)
        let isUnlocked = tier != .none
        defaults.set(isUnlocked, forKey: OnlyLockShared.membershipUnlockedKey)
        defaults.set(tier.rawValue, forKey: OnlyLockShared.membershipTierKey)
        defaults.set(tier == .monthly ? monthlyExpirationTimestamp : 0, forKey: OnlyLockShared.membershipExpirationTimestampKey)
        defaults.synchronize()
    }
}

private struct LaunchContainerView: View {
    @AppStorage(OnlyLockShared.hasCompletedWelcomeKey) private var hasCompletedWelcome = false
    @AppStorage(OnlyLockShared.hasCompletedIntroOnboardingKey) private var hasCompletedIntroOnboarding = false

    var body: some View {
        if hasCompletedWelcome && hasCompletedIntroOnboarding {
            ContentView()
        } else if hasCompletedWelcome {
            IntroOnboardingFlowView(
                onBackToWelcome: {
                    withAnimation(.easeOut(duration: 0.24)) {
                        hasCompletedWelcome = false
                    }
                },
                onSkipIntro: {
                    withAnimation(.easeOut(duration: 0.24)) {
                        hasCompletedIntroOnboarding = true
                    }
                },
                onComplete: {
                    withAnimation(.easeOut(duration: 0.24)) {
                        hasCompletedIntroOnboarding = true
                    }
                }
            )
        } else {
            WelcomeView {
                withAnimation(.easeOut(duration: 0.24)) {
                    hasCompletedWelcome = true
                }
            }
        }
    }
}

private enum MembershipTierResolver {
    static let monthlyProductID = "com.onlylock.membership.monthly"
    static let lifetimeProductID = "com.onlylock.membership.lifetime"

    static func resolvedTier(from productIDs: Set<String>) -> SettingsStore.MembershipTier {
        if productIDs.contains(lifetimeProductID) {
            return .lifetime
        }
        if productIDs.contains(monthlyProductID) {
            return .monthly
        }
        return .none
    }
}
enum AppLanguageOption: String, CaseIterable {
    case zhHans = "zh-Hans"
    case english = "en"

    var locale: Locale { Locale(identifier: rawValue) }
}

enum AppLanguageRuntime {
    private static let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
    private static var hasActivated = false

    static var currentLanguageCode: String {
        let raw = defaults.string(forKey: OnlyLockShared.appLanguageCodeKey) ?? AppLanguageOption.zhHans.rawValue
        return AppLanguageOption(rawValue: raw)?.rawValue ?? AppLanguageOption.zhHans.rawValue
    }

    static var currentLanguage: AppLanguageOption {
        AppLanguageOption(rawValue: currentLanguageCode) ?? .zhHans
    }

    static func setCurrentLanguage(_ language: AppLanguageOption) {
        defaults.set(language.rawValue, forKey: OnlyLockShared.appLanguageCodeKey)
    }

    static func activate() {
        guard !hasActivated else { return }
        hasActivated = true
        object_setClass(Bundle.main, OnlyLockLocalizedBundle.self)
    }

    static func localized(for key: String) -> String {
        switch currentLanguage {
        case .english:
            if let overridden = AppLanguageEnglishOverrides.translations[key] {
                return overridden
            }
            return AppLanguageEnglishMap.translations[key] ?? key
        case .zhHans:
            return key
        }
    }
}

private final class OnlyLockLocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        let custom = AppLanguageRuntime.localized(for: key)
        if custom != key {
            return custom
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    @Published private(set) var currentLanguage: AppLanguageOption

    private init() {
        currentLanguage = AppLanguageRuntime.currentLanguage
    }

    var locale: Locale { currentLanguage.locale }

    var switchFlag: String { currentLanguage == .zhHans ? "🇨🇳" : "🇺🇸" }
    var switchLabel: String { currentLanguage == .zhHans ? "中" : "EN" }

    func toggleLanguage() {
        setLanguage(currentLanguage == .zhHans ? .english : .zhHans)
    }

    func setLanguage(_ language: AppLanguageOption) {
        guard language != currentLanguage else { return }
        AppLanguageRuntime.setCurrentLanguage(language)
        currentLanguage = language
    }
}

private enum AppLanguageEnglishOverrides {
    static let translations: [String: String] = [
        "/月": "/month",
        "立即开始": "Get Started",
        "继续": "Continue",
        "跳过": "Skip",
        "从最让你分心的应用开始": "Start with the app that distracts you most",
        "你喜欢目前的进展方式吗？": "Do you like the approach so far?",
        "是": "Yes",
        "否": "No",
        "最后，确认你的目标": "Finally, confirm your goal",
        "锁定目标": "Lock Goal",
        "开始时间": "Start Time",
        "结束时间": "End Time",
        "锁定时长：": "Lock Duration:",
        "分钟": "min",
        "选择应用": "Choose Apps",
        "选择": "Choose",
        "设置任务名（可选）": "Set Task Name (Optional)",
        "开始锁定": "Start Locking",
        "个人中心": "Profile",
        "系统设置": "System Settings",
        "语言": "Language",
        "应用语言": "App Language",
        "中文": "Chinese",
        "英文": "English",
        "分析": "Insights",
        "进度": "Progress",
        "通知": "Notifications",
        "周报历史": "Weekly Reports",
        "暂无通知": "No Notifications",
        "删除": "Delete",
        "确认": "Confirm",
        "取消": "Cancel",
        "请重新选择开始时间": "Please reselect a start time",
        "你的开始时间晚于当前时间": "Your start time must be later than now",
        "重新选择开始时间": "Choose Start Time Again",
        "你的主要目标是什么？": "What is your main goal?",
        "什么最容易打断你？": "What interrupts you most?",
        "深度专注": "Deep focus",
        "高效学习": "Efficient learning",
        "早点睡觉": "Go to bed early",
        "减少分心": "Reduce distractions",
        "短视频": "Short video",
        "社交媒体": "Social media",
        "不良网站": "Bad website",
        "电子游戏": "Video games",
        "请求中...": "Requesting...",
        "创建中...": "Creating...",
        "无法完成操作": "Unable to Complete",
        "知道了": "OK",
        "还没有选择应用": "No apps selected yet",
        "请先选择一个最让你分心的应用，才能继续。": "Please choose one app that distracts you most before continuing.",
        "已选择多个应用": "Multiple apps selected",
        "你刚才选了 \\(selectedOnboardingAppCount) 个应用。现在先选一个试试。": "You selected \\(selectedOnboardingAppCount) apps just now. Pick one first.",
        "保留 \\(selectedOnboardingAppCount) 个": "Keep \\(selectedOnboardingAppCount)",
        "只选一个": "Keep One",
        "再试一次授权": "Authorize Again",
        "去开启权限": "Enable Permission",
        "隐私说明": "Privacy",
        "我们仅使用授权来执行你设置的锁定任务。": "Authorization is used only to run your lock tasks.",
        "你的数据不会被上传，所有锁定设置只保存在本地里": "Your data stays local and is never uploaded.",
        "你可随时在系统设置撤回 Screen Time 授权。": "You can revoke Screen Time permission in Settings anytime."
    ]
}

private enum AppLanguageEnglishMap {
    static let translations: [String: String] = [
        "+1分": "+1 point",
        "+1天": "+1 day",
        "+7天": "+7 days",
        ", value)) 小时。": ", value)) hours.",
        "/月": "/moon",
        "1000分钟": "1000 minutes",
        "300分钟": "300 minutes",
        "3天免费试用": "3 days free trial",
        "5000分钟": "5000 minutes",
        "App锁定通知": "App lock notification",
        "M月d日": "M day",
        "M月d日 HH:mm": "M day HH:mm",
        "OnlyLock 用户": "OnlyLock users",
        "OnlyLock会员": "Unlock Premium",
        "\\(appCount)个App": "\\(appCount)个App",
        "\\(categoryCount)个类别": "\\(categoryCount)个类别",
        "\\(debugStreakOverrideDays)天": "\\(debugStreakOverrideDays)天",
        "\\(event.durationMinutes) 分钟 · \\(event.isWeeklyRepeat ? ": "\\(event.durationMinutes) 分钟 · \\(event.isWeeklyRepeat ? ",
        "\\(hour)小时": "\\(hour)小时",
        "\\(hour)小时\\(minute)分": "\\(hour)小时\\(minute)分",
        "\\(hour)小时\\(minute)分钟": "\\(hour)小时\\(minute)分钟",
        "\\(hour)时\\(minute)分": "\\(hour)时\\(minute)分",
        "\\(hours)小时": "\\(hours)小时",
        "\\(hours)小时\\(minutes)分钟": "\\(hours)小时\\(minutes)分钟",
        "\\(hours)小时\\(remainder)分": "\\(hours)小时\\(remainder)分",
        "\\(hours)小时前": "\\(hours)小时前",
        "\\(minute)分": "\\(minute)分",
        "\\(minute)分钟": "\\(minute)分钟",
        "\\(minutes)分": "\\(minutes)分",
        "\\(minutes)分钟": "\\(minutes)分钟",
        "\\(name)\\n已被OnlyLock禁用": "\\(name)\\n已被OnlyLock禁用",
        "\\(onboardingDurationMinutes)分钟": "\\(onboardingDurationMinutes)分钟",
        "\\(prefix)等\\(deduplicated.count - 3)项": "\\(prefix)等\\(deduplicated.count - 3)项",
        "\\(rule.categoryTokens.count)个类别": "\\(rule.categoryTokens.count)个类别",
        "\\(selectedAppCount) 个": "\\(selectedAppCount) 个",
        "\\(selectedWebCount) 个": "\\(selectedWebCount) 个",
        "\\(targetText)锁定已自动结束": "\\(targetText)锁定已自动结束",
        "\\(webCount)个网站": "\\(webCount)个网站",
        "\\n你尝试打开「\\(displayName)」\\n\\n今日 \\(snapshot.todayCount) 次 | 累计 \\(snapshot.totalCount) 次": "\\n你尝试打开「\\(displayName)」\\n\\n今日 \\(snapshot.todayCount) 次 | 累计 \\(snapshot.totalCount) 次",
        "iOS 仅在授权后才允许展示可选 App 和网站列表；未授权时无法打开选择器。": "iOS only allows a list of selectable apps and websites to be displayed if authorized; the selector cannot be opened without authorization.",
        "yyyy年M月": "M month yyyy year",
        "yyyy年M月d日": "M, d, yyyy",
        "“OnlyLock” 想要访问屏幕时间": "“OnlyLock” Want to access Screen Time",
        "一": "one",
        "一次性任务": "one-time task",
        "一次购买，永久解锁": "Buy once, unlock forever",
        "三": "three",
        "上午": "morning",
        "上周": "last week",
        "下一档位：连续 \\(nextTier) 天": "下一档位：连续 \\(nextTier) 天",
        "下午": "afternoon",
        "不到1分钟": "less than 1 minute",
        "不良网站": "Bad website",
        "与\\(baseline)持平": "与\\(baseline)持平",
        "专注分": "Focus points",
        "专注大师": "Focus Master",
        "专注成习惯": "Focus becomes a habit",
        "专注起步": "Focus on starting",
        "个人中心": "Personal center",
        "为了按你的规则锁住 App 和网站，我们需要获得屏幕时间权限。": "In order to lock apps and websites according to your rules, we need to get Screen Time permission.",
        "为了锁住分心 App 和网站，OnlyLock 需要你的授权": "To limit your distracting apps, OnlyLock requires your permission",
        "为什么必须先授权": "Why do you need to authorize first?",
        "为什么要开启权限": "Why enable permissions",
        "买断": "buyout",
        "了解更多": "learn more",
        "二": "two",
        "五": "five",
        "什么最容易打断你？": "What interrupts you most easily?",
        "仅 DEBUG 生效，不影响生产环境": "Only DEBUG takes effect and does not affect the production environment.",
        "今天还未打卡": "Haven’t clocked in today yet",
        "仍未开启？前往系统设置": "Still not turned on? Go to system settings",
        "从最让你分心的应用开始": "Start with the apps that distract you the most",
        "会员已过期": "Membership has expired",
        "会员已过期，请先续费后再继续使用锁定功能。": "The membership has expired, please renew before continuing to use the lock function.",
        "会员快速过期": "Membership expires quickly",
        "会员身份速测": "Membership Quick Test",
        "你刚才选了 \\(selectedOnboardingAppCount) 个应用。现在先选一个试试。": "你刚才选了 \\(selectedOnboardingAppCount) 个应用。现在先选一个试试。",
        "你可随时在系统设置撤回 Screen Time 授权。": "You can revoke Screen Time authorization at any time in the system settings.",
        "你喜欢目前的进展方式吗？": "Do you like the approach so far?",
        "你本周平均每天使用 \\(weeklyDurationText(configuration.averageMinutes))。": "你本周平均每天使用 \\(weeklyDurationText(configuration.averageMinutes))。",
        "你本周平均每天使用 \\(weeklyDurationText(dailyAverage))。": "你本周平均每天使用 \\(weeklyDurationText(dailyAverage))。",
        "你的主要目标是什么？": "What is your main goal?",
        "你的完整屏幕使用明细和个人活动数据": "Your complete screen usage details and personal activity data",
        "你的开始时间晚于当前时间": "Your start time is later than the current time",
        "你的数据不会被上传，所有锁定设置只保存在本地里": "Your data will not be uploaded and all lock settings will only be saved locally.",
        "你的数据由 Apple 保护，OnlyLock 无法看到这些内容：": "Your data is protected by Apple and cannot be seen by OnlyLock:",
        "你的数据由 Apple 权限体系保护": "Your data is protected by Apple's permissions system",
        "你的本周屏幕时间报告已生成「点击查看」": "Your screen time report for this week has been generated \"click to view\"",
        "你的浏览记录，例如具体访问过哪些网站、打开过哪些 App": "Your browsing history, such as which websites you have visited and which apps you have opened",
        "你设置的目标": "goals you set",
        "你还没有锁定任务": "No locked tasks yet",
        "使用条款": "terms of use",
        "保持专注": "stay focused",
        "保留 \\(selectedOnboardingAppCount) 个": "保留 \\(selectedOnboardingAppCount) 个",
        "允许 ”OnlyLock“访问屏幕使用时间可能会使其能够查看你的活动数据、限制内容，以及限制应用和网站的使用。": "Allowing OnlyLock access to Screen Time may allow it to view your activity data, restrict content, and limit the use of apps and websites.",
        "先开启屏幕时间权限": "Enable screen time permission first",
        "先给这个应用设一个锁定时间": "First set a lock time for this application",
        "先给这些应用设一个锁定时间": "First set a lock time for these applications",
        "六": "six",
        "关": "Close",
        "关闭": "Close",
        "联系我们": "Contact Us",
        "关闭屏幕时间权限失败，请稍后重试。": "Failed to turn off Screen Time permissions, please try again later.",
        "再试一次授权": "Try authorization again",
        "再连续打卡\\(remaining)天解锁 \\(nextTier) 天勋章": "再连续打卡\\(remaining)天解锁 \\(nextTier) 天勋章",
        "减少分心": "Reduce distractions",
        "分享 App": "Share App",
        "分析": "analyze",
        "分钟": "minute",
        "切换外观": "Switch appearance",
        "刚刚": "just",
        "创建中...": "Creating...",
        "创建锁定任务": "Create a locked task",
        "初试锋芒": "First try",
        "删除": "delete",
        "删除任务": "Delete task",
        "加载中...": "loading...",
        "勋章档位": "Medal level",
        "即将开始": "About to start",
        "去开启权限": "to enable permissions",
        "去新建": "Create one",
        "去续费": "Renew now",
        "去评分": "Go to rating",
        "取消": "Cancel",
        "只选一个": "Choose only one",
        "可用方案": "Available plans",
        "否": "no",
        "周": "week",
        "周一": "on Monday",
        "周三": "Wednesday",
        "周二": "Tuesday",
        "周五": "Friday",
        "周六": "Saturday",
        "周四": "Thursday",
        "周报历史": "Weekly history",
        "周日": "Sunday",
        "四": "Four",
        "培养新习惯，屏蔽分心内容，找回完整的专注力。": "Build new habits, block distractions, regain focus.",
        "太棒了，继续保持": "Awesome, keep it up",
        "夺回你的时间": "Take back your time",
        "夺回注意力的主导权": "Take back your attention",
        "夺回深夜睡眠": "Sleep better at night",
        "完成": "Finish",
        "完成100次": "Completed 100 times",
        "完成10次": "Completed 10 times",
        "完成300次": "Completed 300 times",
        "完成50次": "Completed 50 times",
        "将于 \\(taskDateTimeText(effectiveEndAt(for: rule, now: now) ?? effectiveStartAt(for: rule, now: now))) 自动结束。": "将于 \\(taskDateTimeText(effectiveEndAt(for: rule, now: now) ?? effectiveStartAt(for: rule, now: now))) 自动结束。",
        "小时": "Hour",
        "屏幕时间在\\(dayLabel)达到峰值，约 \\(String(format: ": "屏幕时间在\\(dayLabel)达到峰值，约 \\(String(format: ",
        "屏幕时间访问": "screen time access",
        "屏蔽无意义信息流": "Block meaningless information flow",
        "展示你的连续专注记录。": "Show off your concentration streak.",
        "已完成": "Completed",
        "已按你的计划锁定\\(segments.joined(separator: ": "已按你的计划锁定\\(segments.joined(separator: ",
        "已按你的计划锁定\\(targetText)": "已按你的计划锁定\\(targetText)",
        "已按你的计划锁定你设置的目标。": "The goals you set are locked in according to your plan.",
        "已暂停": "Suspended",
        "已结束": "ended",
        "已达连续打卡勋章最高等级": "Reached the highest level of continuous check-in medal",
        "已选 App": "Selected App",
        "已选 App ": "Selected App",
        "已选 App \\(fallbackIndex + 1)": "已选 App \\(fallbackIndex + 1)",
        "已选择多个应用": "Multiple apps selected",
        "已选类别 \\(selectedCategoryCount) 个": "已选类别 \\(selectedCategoryCount) 个",
        "已选网站": "Selected website",
        "平均每周屏幕时间": "average weekly screen time",
        "平均每日1.32小时": "Avg 1.32h saved daily",
        "平均每日屏幕时间": "average daily screen time",
        "年度勋章": "Annual Medal",
        "应用": "application",
        "应用所选时间": "Apply selected time",
        "开": "open",
        "开启权限": "Enable permissions",
        "开启权限后可查看屏幕时间分析": "Enable access to view Insights",
        "开启深度专注": "Enter deep focus",
        "开始 \\(onboardingStartTimeText) · 结束 \\(onboardingEndTimeText)": "开始 \\(onboardingStartTimeText) · 结束 \\(onboardingEndTimeText)",
        "开始3天免费试用": "Start your 3-day free trial",
        "开始时间": "start time",
        "开始时间必须晚于当前时间。": "The start time must be later than the current time.",
        "开始锁定": "Start locking",
        "弹卡预览": "Bullet preview",
        "硬核锁定无绕行": "Hardcore locking without bypass",
        "当前为基础版": "Currently the basic version",
        "当前时间范围内还没有系统屏幕时间数据。": "There is no system screen time data for the current time range.",
        "当前锁定规则损坏，已忽略旧数据。": "The current locking rule is broken and old data has been ignored.",
        "当日屏幕时间": "Screen time of the day",
        "徽章墙": "badge wall",
        "快捷时长": "Quick duration",
        "总分 \\(snapshot.totalXP)": "总分 \\(snapshot.totalXP)",
        "总屏幕时间": "total screen time",
        "总数": "TOTAL",
        "恢复购买": "Resume purchase",
        "恢复购买失败，请稍后再试。": "Failed to restore purchase, please try again later.",
        "恭喜！本次专注已完成": "Congratulations! This focus has been completed",
        "成长总览": "Growth Overview",
        "我们不会打扰你。通知由你自己掌控。": "We won't bother you. Notifications are yours to control.",
        "我们仅使用授权来执行你设置的锁定任务。": "We only use authorization to perform the locking tasks you set.",
        "我在用 \\(displayName)，分享给你。": "我在用 \\(displayName)，分享给你。",
        "手动添加网站": "Add website manually",
        "打卡天数": "Check-in days",
        "打卡天数速测": "Quick test of check-in days",
        "打开周报": "Open weekly report",
        "执行力升级": "Execution upgrade",
        "按开始/结束": "Press start/end",
        "按时长": "By duration",
        "按月解锁高级功能": "Unlock premium features monthly",
        "授权后你可以": "After authorization you can",
        "提示": "hint",
        "支持": "support",
        "收起": "close",
        "新建锁定": "New lock",
        "无法保存锁定规则，请稍后重试。": "Unable to save locking rule, please try again later.",
        "无法完成操作": "Unable to complete operation",
        "无法打开系统设置，请手动前往设置开启权限。": "Unable to open system settings, please go to settings manually to enable permissions.",
        "无法打开系统设置，请手动前往设置撤回权限。": "Unable to open system settings, please manually go to settings to revoke permissions.",
        "无法计算结束时间，请调整参数后重试。": "Unable to calculate the end time, please adjust the parameters and try again.",
        "无限锁定": "Unlimited lock",
        "日": "day",
        "早点睡觉": "Go to bed early",
        "时间": "time",
        "时间穿越": "time travel",
        "时间跳转请用 +1分 / +1天 / +7天": "Please use +1 minute / +1 day / +7 days for time jump",
        "时间轴": "timeline",
        "昨天": "yesterday",
        "是": "yes",
        "是否关闭权限": "Whether to turn off permissions",
        "是否删除该周报": "Whether to delete this weekly report",
        "是否删除该条任务": "Whether to delete this task",
        "暂不允许": "Not allowed yet",
        "暂停": "pause",
        "暂无通知": "No notification yet",
        "暂时无法加载购买选项，请稍后重试。": "Unable to load purchase options at the moment, please try again later.",
        "暂时无法打开评分页，请稍后重试。": "The rating page cannot be opened at the moment, please try again later.",
        "暂时无法打开联系我们页面，请稍后重试。": "Unable to open contact page at the moment, please try again later.",
        "更多高级功能": "More advanced features",
        "最后，确认你的目标": "Finally, identify your goals",
        "最近奖励": "Recent rewards",
        "月度": "monthly",
        "月度会员": "monthly membership",
        "月度坚持": "Monthly persistence",
        "未开通": "Not activated",
        "未开通会员": "Not a member yet",
        "未选择目标": "No target selected",
        "本周": "this week",
        "本周使用趋势还在形成中。": "Usage trends are still forming this week.",
        "本周报告": "This week's report",
        "本周还没有高频使用目标。": "There are no high-usage targets this week.",
        "本周重度使用\\(targetKindText)「\\(top.name)」共\\(weeklyDurationText(top.minutes))": "本周重度使用\\(targetKindText)「\\(top.name)」共\\(weeklyDurationText(top.minutes))",
        "本周重度使用\\(targetKindText)「\\(top.name)」共\\(weeklyShortDuration(top.minutes))": "本周重度使用\\(targetKindText)「\\(top.name)」共\\(weeklyShortDuration(top.minutes))",
        "查看全部": "View all",
        "模拟器中没有可恢复的购买记录。": "There are no recoverable purchase records in the emulator.",
        "次日 \\(timeText)": "次日 \\(timeText)",
        "正在锁定": "Locking",
        "每周": "weekly",
        "每周定制屏幕使用时间报告": "Customized weekly screen time reports",
        "每周重复": "Repeat every week",
        "每日打卡": "Streak",
        "永久解锁全部高级功能": "Unlock all premium features permanently",
        "没有完成屏幕时间授权，你稍后仍可在设置或创建锁定任务时开启。": "If Screen Time authorization is not completed, you can still enable it later when setting up or creating a lock task.",
        "没有找到可恢复的购买记录。": "No recoverable purchase records found.",
        "浅色": "light",
        "深度专注": "Deep focus",
        "深度实践": "In-depth practice",
        "深色": "Dark",
        "添加": "Add",
        "物理级防沉迷机制": "Hard anti-distraction lock",
        "电子游戏": "Video games",
        "百日专注": "100 days of focus",
        "相比于\\(baseline)增加了\\(percentage)%屏幕使用时间": "相比于\\(baseline)增加了\\(percentage)%屏幕使用时间",
        "相比于\\(baseline)降低了\\(percentage)%屏幕使用时间": "相比于\\(baseline)降低了\\(percentage)%屏幕使用时间",
        "看屏幕时间": "screen time",
        "知道了": "knew",
        "短视频": "Short video",
        "确认": "confirm",
        "确认选择": "Confirm selection",
        "社交媒体": "Social media",
        "稳定开局": "Stable start",
        "稳定执行": "Stable execution",
        "稳态专注": "Steady focus",
        "空任务": "empty task",
        "立即开始": "Start now",
        "立即续费": "Renew now",
        "立即解锁终身会员": "Unlock lifetime membership now",
        "类别 \\(categoryCount)": "类别 \\(categoryCount)",
        "精确挑选要锁定的 App 和部分网站，并让锁定任务按开始时间自动生效、到期自动结束。": "Precisely select the apps and some websites you want to lock, and let the locking task automatically take effect according to the start time and end automatically when it expires.",
        "系统": "system",
        "系统设置": "System settings",
        "累计完成 \\(snapshot.totalCompletions) 次 · \\(snapshot.totalMinutes) 分钟": "累计完成 \\(snapshot.totalCompletions) 次 · \\(snapshot.totalMinutes) 分钟",
        "纯净无广": "No ads",
        "终结睡前报复性熬夜": "End bedtime revenge scrolling",
        "终身": "lifelong",
        "终身会员": "life member",
        "结束时间": "end time",
        "结束时间必须晚于开始时间。": "End time must be later than start time.",
        "结束时间：": "End time:",
        "给这个锁定任务起个名字": "Give this locked task a name",
        "继续": "continue",
        "继续保持": "keep it up",
        "继续授权": "Continue to authorize",
        "续费后继续使用锁定、屏幕时间分析与每周报告。": "Keep access to locking, screen time analysis, and weekly reports after renewal.",
        "续费后继续创建锁定任务并管理应用与网站。": "Renew to keep locking apps and websites.",
        "续费后继续查看任务进度与锁定状态。": "After renewal, continue to check the task progress and lock status.",
        "续费后继续查看屏幕时间分析与每周报告。": "Continue to view screen time analysis and weekly reports after renewal.",
        "网站": "WEB",
        "网站 ": "website",
        "网站 \\(fallbackIndex + 1)": "网站 \\(fallbackIndex + 1)",
        "网站 \\(webCount)": "网站 \\(webCount)",
        "网站域名格式无效：\\(domain)": "网站域名格式无效：\\(domain)",
        "翻页预览": "Page flip preview",
        "自定义时长（最长720分钟）": "Custom duration (up to 720 minutes)",
        "自由选择时间": "Free time to choose",
        "节省屏幕时长": "Reduce screen time",
        "要开启通知吗？": "Enable notifications?",
        "解锁所有会员功能": "Unlimited Access to OnlyLock",
        "解锁新勋章": "Unlock new medals",
        "解锁（2.5s）": "Unlock (2.5s)",
        "让锁定任务按开始时间自动生效、到期自动结束。": "Let the locked task automatically take effect according to the start time and end automatically when it expires.",
        "设置任务名（可选）": "Set task name (optional)",
        "设置锁定时间": "Set lock time",
        "该应用": "The application",
        "该网站": "the website",
        "请先完成 Screen Time 授权。": "Please complete Screen Time authorization first.",
        "请先选择一个最让你分心的应用，才能继续。": "Please select the most distracting app before continuing.",
        "请求中...": "Requesting...",
        "请至少选择一个应用或输入一个网站域名。": "Please select at least one app or enter a website domain name.",
        "请至少选择一个重复日期。": "Please select at least one recurring date.",
        "请重新选择开始时间": "Please select a new start time",
        "调试面板": "Debug panel",
        "购买失败，请稍后再试。": "Purchase failed, please try again later.",
        "购买未完成，请稍后再试。": "The purchase was not completed, please try again later.",
        "购买正在等待确认。": "Purchase is pending confirmation.",
        "购买选项还在加载中，请稍后再试。": "Purchase options are still loading, please try again later.",
        "购买验证失败，请稍后再试。": "Purchase verification failed, please try again later.",
        "趋势": "trend",
        "跳过": "jump over",
        "较上周下降 \\(abs(focusScoreDelta)) 分": "较上周下降 \\(abs(focusScoreDelta)) 分",
        "较上周下降 \\(abs(scoreDelta)) 分": "较上周下降 \\(abs(scoreDelta)) 分",
        "较上周提升 \\(focusScoreDelta) 分": "较上周提升 \\(focusScoreDelta) 分",
        "较上周提升 \\(scoreDelta) 分": "较上周提升 \\(scoreDelta) 分",
        "输入任意域名 (example.com)": "Enter any domain name (example.com)",
        "还差一步就能\\n开始锁定": "Only one step left to start locking\\n",
        "还未打卡": "Not clocked in yet",
        "还没有奖励记录，完成一次锁定后会显示在这里。": "There is no reward record yet, it will be displayed here after completing a lock.",
        "还没有选择应用": "No application selected yet",
        "进入状态": "enter state",
        "进入节奏": "Get into rhythm",
        "进度": "schedule",
        "连续勋章速测": "Continuous Medal Quick Test",
        "连续打卡 \\(displayedNumber) 天!": "连续打卡 \\(displayedNumber) 天!",
        "连续打卡 \\(tier) 天!": "连续打卡 \\(tier) 天!",
        "连续打卡\\(entry.streak)天": "连续打卡\\(entry.streak)天",
        "连续打卡\\(streak)天": "连续打卡\\(streak)天",
        "连胜100天": "Winning streak for 100 days",
        "连胜14天": "Winning streak for 14 days",
        "连胜30天": "Winning streak for 30 days",
        "连胜365天": "Winning streak for 365 days",
        "连胜3天": "Winning streak for 3 days",
        "连胜60天": "Winning streak for 60 days",
        "连胜7天": "Winning streak for 7 days",
        "逃离数字焦虑": "Escape digital anxiety",
        "选择": "choose",
        "选择 App 和部分网站": "Select apps and some websites",
        "选择分钟": "Select minutes",
        "选择前需要开启屏幕时间权限": "Screen Time permission needs to be enabled before selection",
        "选择小时": "Select hour",
        "选择应用": "Select app",
        "选择日期和时间": "Select date and time",
        "选择要锁定的内容": "Choose what to lock",
        "通知": "notify",
        "重塑用机习惯": "Rebuild phone habits",
        "重新加载购买选项": "Reload purchase options",
        "重新选择开始时间": "Reselect start time",
        "重置": "reset",
        "锁定": "locking",
        "锁定\\(onboardingDurationFullText)": "锁定\\(onboardingDurationFullText)",
        "锁定中": "Locked",
        "锁定任务已创建。": "Lock task has been created.",
        "锁定前需要开启屏幕时间权限": "Screen time permission needs to be turned on before locking",
        "锁定将于选定时间自动生效。\n您可以在设置中随时调整。": "The lock will automatically take effect at the selected time.\nYou can adjust it anytime in Settings.",
        "锁定已自动结束": "Lockout has ended automatically",
        "锁定所有App/网站": "Lock all apps/websites",
        "锁定时长必须是大于 0 的整数分钟。": "The lock duration must be an integer number of minutes greater than 0.",
        "锁定时长：": "Lock duration:",
        "锁定目标": "Target",
        "锁定结束时间无效，请调整开始时间或时长。": "The lock end time is invalid, please adjust the start time or duration.",
        "隐私政策": "privacy policy",
        "隐私说明": "Privacy statement",
        "预定": "Reserve",
        "高效学习": "Efficient learning",
        "高频使用": "High frequency use"
    ]
}
