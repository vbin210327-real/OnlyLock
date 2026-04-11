import Combine
import DeviceActivity
import FamilyControls
import ManagedSettings
import PhotosUI
import StoreKit
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

private func onlyLockL(_ key: String) -> String {
    AppLanguageRuntime.localized(for: key)
}

private func onlyLockWeekdayLabel(_ weekday: Int) -> String {
    if AppLanguageRuntime.currentLanguage == .english {
        switch weekday {
        case 1: return "S"
        case 2: return "M"
        case 3: return "T"
        case 4: return "W"
        case 5: return "T"
        case 6: return "F"
        case 7: return "S"
        default: return ""
        }
    }

    switch weekday {
    case 1: return "日"
    case 2: return "一"
    case 3: return "二"
    case 4: return "三"
    case 5: return "四"
    case 6: return "五"
    case 7: return "六"
    default: return ""
    }
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var languageStore: AppLanguageStore

    @StateObject private var authorizationService = AuthorizationService()
    @StateObject private var viewModel = LockRuleViewModel()
    @StateObject private var rewardViewModel = RewardViewModel()
    @StateObject private var screenTimeInsightsStore = ScreenTimeInsightsStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var membershipRenewalStore = IntroOnboardingPaywallStore()
    @ObservedObject private var quickActionRouter = AppQuickActionRouter.shared

    @State private var isSavingRule = false
    @State private var isPreAuthorizationPresented = false
    @State private var isRequestingAuthorization = false
    @State private var isAuthorizationRecoveryPresented = false
    @State private var isAwaitingSettingsReturn = false
    @State private var pendingAuthorizationAction: PendingAuthorizationAction = .none
    @State private var preAuthorizationContext: PreAuthorizationContext = .none
    @State private var preAuthorizationDismissResetTask: Task<Void, Never>?
    @State private var isTopBarCollapsed = false
    @State private var isProgressTopBarCollapsed = false
    @State private var isRewardsTopBarCollapsed = false
    @State private var isSettingsTopBarCollapsed = false
    @State private var isTopBarStateUpdatesEnabled = true
    @State private var topBarStateResumeTask: Task<Void, Never>?
    @State private var isShowingAllSelectedApps = false
    @State private var isShowingAllSelectedWebsites = false
    @State private var scheduleTimeInputMode: ScheduleTimeInputMode = .duration
    @State private var endAtDraft = Date()
    @State private var manualDomainDraft = ""
    @State private var selectedTab: RootTab = .create
    @State private var pendingDeletionRuleID: UUID?
    @State private var pendingDeletedWeeklyReportWeekStart: Date?
    @State private var uiClockNow = Date()
    @State private var pausedTaskAnchors: [UUID: Date] = [:]
    @State private var settingsAvatarPickerItem: PhotosPickerItem?
    @State private var isSettingsAuthorizationRequesting = false
    @State private var isScreenTimeRevokeConfirmationPresented = false
    @State private var isOpeningAppStoreReview = false
    @State private var settingsErrorAlertMessage: String?
    @State private var pendingShareSheetPayload: ShareSheetPayload?
    @State private var isMembershipRenewalPresented = false
    @State private var selectedMembershipRenewalPlan: MembershipRenewalPlan = .lifetime
    @State private var selectedInsightsScope: InsightsScope = .week
    @State private var insightsAnchorDate = Date()
    @State private var insightsReportReloadID = UUID()
    @State private var isInsightsReportReloading = false
    @State private var isInsightsSnapshotGateExpired = false
    @State private var warmedInsightsRangeKeys: Set<String> = []
    @State private var insightsReportReloadTask: Task<Void, Never>?
    @State private var insightsSnapshotGateTask: Task<Void, Never>?
    @State private var insightsAuthorizationNeedsSettingsFallback = false
    @State private var isWeeklyInsightsHistoryPresented = false
    @State private var activeWeeklyReport: WeeklyReportPresentation?
    @State private var queuedWeeklyReportAfterHistoryDismiss: WeeklyReportPresentation?
    @State private var activeWeeklyDigestRoute: WeeklyDigestRoute?
    @State private var historyActiveWeeklyDigestRoute: WeeklyDigestRoute?
    @State private var queuedWeeklyDigestWeekStartAfterHistoryDismiss: Date?
    @State private var weeklyReportUnreadRevision = 0
    @State private var activeStreakMedalUnlockTier: Int?
    @State private var streakMedalDismissTask: Task<Void, Never>?
    @State private var isEditingSettingsProfileName = false
    @State private var settingsProfileNameDraft = ""
    @FocusState private var isSettingsProfileNameFocused: Bool

#if DEBUG
    @State private var isFlipPreviewPanelExpanded = false
    @State private var isFlipPreviewEnabled = false
    @State private var isDebugTimeOverrideEnabled = false
    @State private var debugManualTimelineDate = Date()
    @State private var hadDebugTimeSimulationApplied = false
    @State private var isFlipPreviewPaused = false
    @State private var isDebugForceEmptyProgressState = false
    @State private var isDebugStreakOverrideEnabled = false
    @State private var debugStreakOverrideDays = 0
    @State private var flipPreviewSpeedMultiplier: Double = 10
    @State private var flipPreviewReferenceDate = Date()
    @State private var flipPreviewDisplayBaseDate = Date()
    @State private var isDebugStreakMedalPreviewEnabled = false
    @State private var debugStreakMedalPreviewBestStreak = 0
    @State private var debugMembershipTierOverride: SettingsStore.MembershipTier = .none
    @State private var isDebugMembershipExpiredOverride = false
    @State private var isDebugInsightsDemoEnabled = false
    @State private var isDebugWeeklyReportDemoEnabled = false
    @State private var debugWeeklyReportWeekStart = OnlyLockShared.startOfWeekMonday(containing: Date())
#endif

    private var repeatWeekdayLabels: [(weekday: Int, label: String)] {
        OnlyLockShared.weekdaysStartingMonday.map { weekday in
            (weekday, onlyLockWeekdayLabel(weekday))
        }
    }
#if DEBUG
    private let debugSharedDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
    private let debugShieldStore = ManagedSettingsStore(named: OnlyLockShared.managedSettingsStoreName)
    private let debugWidgetStreakOverrideEnabledKey = "onlylock.debug.widget.streakOverride.enabled"
    private let debugWidgetStreakOverrideDaysKey = "onlylock.debug.widget.streakOverride.days"
#endif
    private let runtimeShieldStore = ManagedSettingsStore(named: OnlyLockShared.managedSettingsStoreName)
    private let weeklyInsightsNotificationScheduler = WeeklyInsightsNotificationScheduler()
    private let reviewPromptAtThreeTasksDefaultsKey = "onlylock.reviewPrompt.didAskAtThreeTasks"

    private enum RootTab: Hashable {
        case create
        case current
        case rewards
        case settings
    }

    private enum MembershipRenewalPlan: CaseIterable {
        case lifetime
        case monthly
    }

    fileprivate enum ScheduleTimeInputMode: String, CaseIterable, Identifiable {
        case duration
        case startEnd

        var id: String { rawValue }

        var title: String {
            switch self {
            case .duration:
                return onlyLockL("按时长")
            case .startEnd:
                return onlyLockL("按开始/结束")
            }
        }

        var iconName: String {
            switch self {
            case .duration:
                return "timer"
            case .startEnd:
                return "calendar.badge.clock"
            }
        }
    }

    private struct AppStoreLookupResponse: Decodable {
        struct Result: Decodable {
            let trackId: Int
        }

        let results: [Result]
    }

    private enum InsightsScope: String, CaseIterable, Identifiable {
        case day
        case week
        case trend

        var id: String { rawValue }

        var reportContext: DeviceActivityReport.Context {
            switch self {
            case .day:
                return .onlyLockInsightsDay
            case .week:
                return .onlyLockInsightsWeek
            case .trend:
                return .onlyLockInsightsTrend
            }
        }

        var title: String {
            switch self {
            case .day:
                return onlyLockL("日")
            case .week:
                return onlyLockL("周")
            case .trend:
                return onlyLockL("趋势")
            }
        }
    }

    private var pageBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.12)
            : Color(red: 0.95, green: 0.95, blue: 0.95)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.15, blue: 0.18)
            : Color.white
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.12)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.58)
    }

    private var hasActiveMembership: Bool {
        OnlyLockShared.hasActiveMembership(defaults: sharedDefaults)
    }

    private var membershipAccessTitle: String {
        onlyLockL("会员已过期")
    }

    private var membershipAccessSubtitle: String {
        onlyLockL("续费后继续使用锁定、屏幕时间分析与每周报告。")
    }

    private var removeIconPrimary: Color {
        colorScheme == .dark ? .white : .black
    }

    private var removeIconSecondary: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.24)
    }

    private var websiteRowTitleFont: Font {
        .system(size: 20, weight: .medium)
    }

    private var scheduleSubsectionTitleFont: Font {
        .system(size: 13, weight: .semibold)
    }

    private var customTabActiveColor: Color {
        colorScheme == .dark
            ? Color(red: 0.20, green: 0.22, blue: 0.32)
            : Color(red: 0.05, green: 0.05, blue: 0.16)
    }

    private var customTabInactiveIconColor: Color {
        colorScheme == .dark
            ? Color(red: 0.70, green: 0.73, blue: 0.82)
            : Color(red: 0.45, green: 0.48, blue: 0.60)
    }

    private var upcomingTimelineAccent: Color {
        colorScheme == .dark
            ? Color(red: 0.66, green: 0.71, blue: 0.82)
            : Color(red: 0.40, green: 0.46, blue: 0.58)
    }

    private var upcomingTimelineBorder: Color {
        colorScheme == .dark
            ? upcomingTimelineAccent.opacity(0.52)
            : upcomingTimelineAccent.opacity(0.42)
    }

    private var settingsSwitchTint: Color {
        colorScheme == .dark
            ? Color(red: 0.38, green: 0.40, blue: 0.46)
            : .black
    }

    private var customTabBarReservedHeight: CGFloat {
        54
    }

    private var shouldShowCurrentLockTimeline: Bool {
#if DEBUG
        return !viewModel.rules.isEmpty && !isDebugForceEmptyProgressState
#else
        return !viewModel.rules.isEmpty
#endif
    }

    private var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
    }

    private var streakMedalUnlockPresentationBinding: Binding<Bool> {
        Binding(
            get: { activeStreakMedalUnlockTier != nil },
            set: { isPresented in
                if !isPresented {
                    dismissStreakMedalUnlock()
                }
            }
        )
    }

    private var settingsErrorAlertPresentedBinding: Binding<Bool> {
        Binding(
            get: { settingsErrorAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    settingsErrorAlertMessage = nil
                }
            }
        )
    }

    private var streakMedalBestStreakForDisplay: Int {
#if DEBUG
        if isDebugStreakMedalPreviewEnabled {
            return max(0, debugStreakMedalPreviewBestStreak)
        }
#endif
        return max(0, rewardViewModel.snapshot.bestStreak)
    }

    private var currentStreakForDisplay: Int {
#if DEBUG
        if isDebugStreakOverrideEnabled {
            return max(0, debugStreakOverrideDays)
        }
#endif
        return max(0, rewardViewModel.snapshot.currentStreak)
    }

    private var pendingInitialTab: RootTab? {
        switch sharedDefaults.string(forKey: OnlyLockShared.pendingInitialTabKey) {
        case "current":
            return .current
        case "create":
            return .create
        case "rewards":
            return .rewards
        case "settings":
            return .settings
        default:
            return nil
        }
    }

    var body: some View {
        bodyWithSheets
    }

    // MARK: - Body split into segments to avoid stack overflow (EXC_BAD_ACCESS code=2)
    // The original single body had ~375 lines of chained modifiers which exhausted
    // the thread stack during SwiftUI body evaluation. Splitting the modifier chain
    // across multiple computed properties keeps each stack frame manageable.

    private var bodyWithSheets: some View {
        bodyWithObservers
        .fullScreenCover(isPresented: streakMedalUnlockPresentationBinding) {
            if let unlockedTier = activeStreakMedalUnlockTier {
                streakMedalUnlockOverlay(tier: unlockedTier)
                    .ignoresSafeArea()
                    .interactiveDismissDisabled(true)
            }
        }
        .familyActivityPicker(
            isPresented: $viewModel.isAppPickerPresented,
            selection: $viewModel.appPickerSelection
        )
        .alert(onlyLockL("是否删除该条任务"), isPresented: pendingDeletionAlertBinding) {
            Button(onlyLockL("取消"), role: .cancel) {
                pendingDeletionRuleID = nil
            }
            Button(onlyLockL("确认")) {
                confirmPendingDeletion()
            }
        }
        .alert(onlyLockL("是否关闭权限"), isPresented: $isScreenTimeRevokeConfirmationPresented) {
            Button(onlyLockL("取消"), role: .cancel) {}
            Button(onlyLockL("确认"), role: .destructive) {
                Task {
                    await revokeSettingsScreenTimeAuthorization()
                }
            }
        }
        .sheet(
            isPresented: $isPreAuthorizationPresented,
            onDismiss: {
                schedulePreAuthorizationDismissReset()
            }
        ) {
            Group {
                switch preAuthorizationContext {
                case .appSelection:
                    AppSelectionPreAuthorizationSheet(
                        isRequestingAuthorization: isRequestingAuthorization,
                        onContinue: {
                            Task {
                                await continueFromPreAuthorization()
                            }
                        }
                    )
                case .general, .none:
                    GeneralPreAuthorizationSheet(
                        isRequestingAuthorization: isRequestingAuthorization,
                        onContinue: {
                            Task {
                                await continueFromPreAuthorization()
                            }
                        }
                    )
                }
            }
            .interactiveDismissDisabled(isRequestingAuthorization)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented: $isAuthorizationRecoveryPresented,
            onDismiss: {
                if !isAwaitingSettingsReturn {
                    pendingAuthorizationAction = .none
                }
            }
        ) {
            AuthorizationRecoverySheet(
                onRetry: {
                    isAuthorizationRecoveryPresented = false
                    Task {
                        await requestSystemAuthorizationAndContinue(source: .recovery)
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: $pendingShareSheetPayload) { payload in
            ActivityViewController(items: payload.items)
        }
        .fullScreenCover(isPresented: $isWeeklyInsightsHistoryPresented) {
            weeklyInsightsHistorySheet
        }
        .fullScreenCover(isPresented: $isMembershipRenewalPresented) {
            membershipRenewalPaywall
        }
        .fullScreenCover(item: $activeWeeklyDigestRoute) { route in
            weeklyDigestReportSheet(for: route.weekStart) {
                activeWeeklyDigestRoute = nil
            }
        }
        .fullScreenCover(item: $activeWeeklyReport) { presentation in
            weeklyReportSheet(presentation)
        }
#if DEBUG
        .sheet(isPresented: $isFlipPreviewPanelExpanded) {
            flipPreviewDebugPanel
        }
#endif
        .onDisappear {
            streakMedalDismissTask?.cancel()
            streakMedalDismissTask = nil
            insightsReportReloadTask?.cancel()
            insightsReportReloadTask = nil
            insightsSnapshotGateTask?.cancel()
            insightsSnapshotGateTask = nil
        }
    }

    private var bodyWithObservers: some View {
        bodyWithTimers
        .onChangeCompat(of: viewModel.appPickerSelection) {
            viewModel.commitAppPickerSelection()
        }
        .onChangeCompat(of: viewModel.selectedAppCount) { count in
            if count <= 3, isShowingAllSelectedApps {
                isShowingAllSelectedApps = false
            }
        }
        .onChangeCompat(of: viewModel.selectedWebCount) { count in
            if count <= 3, isShowingAllSelectedWebsites {
                isShowingAllSelectedWebsites = false
            }
        }
        .onChangeCompat(of: scenePhase) { newPhase in
            if newPhase == .active {
                authorizationService.refreshStatus()
                syncStartAtToCurrentMinimumIfNeeded()
                freezeTopBarStateUpdatesTemporarily()
                handleReturnFromSettingsIfNeeded()
                syncPausedTaskAnchors(now: resolvedDisplayNow)
                rewardViewModel.refresh(seedFromRules: viewModel.rules, now: resolvedDisplayNow)
                screenTimeInsightsStore.refresh()
                Task {
                    await MembershipTransactionObserver.shared.refreshNow()
                    await MainActor.run {
                        settingsStore.refreshMembershipStatus()
                        syncRuntimeShieldForAuthorizationState(now: Date())
                    }
                    await membershipRenewalStore.prepare()
                    await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
                }
            } else {
                pauseTopBarStateUpdates()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onlyLockWeeklyReportHistoryDidChange)) { _ in
            weeklyReportUnreadRevision &+= 1
            screenTimeInsightsStore.refresh()
        }
        .onChangeCompat(of: viewModel.rules) { rules in
            syncRuntimeShieldForAuthorizationState(now: Date())
            syncPausedTaskAnchors(now: resolvedDisplayNow)
            rewardViewModel.refresh(seedFromRules: rules, now: resolvedDisplayNow)
        }
        .onChangeCompat(of: authorizationService.status) {
            syncRuntimeShieldForAuthorizationState(now: Date())
            syncPausedTaskAnchors(now: resolvedDisplayNow)
            if authorizationService.isApproved {
                insightsAuthorizationNeedsSettingsFallback = false
                scheduleInsightsReportReload(force: true)
            }
            Task {
                await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
            }
        }
        .onChangeCompat(of: selectedInsightsScope) {
            scheduleInsightsReportReload()
        }
        .onChangeCompat(of: insightsAnchorDate) {
            scheduleInsightsReportReload()
        }
        .onChangeCompat(of: isWeeklyInsightsHistoryPresented) { isPresented in
            guard !isPresented else { return }

            if let pendingWeekStart = queuedWeeklyDigestWeekStartAfterHistoryDismiss {
                queuedWeeklyDigestWeekStartAfterHistoryDismiss = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    activeWeeklyDigestRoute = WeeklyDigestRoute(weekStart: pendingWeekStart)
                }
                return
            }

            guard let pending = queuedWeeklyReportAfterHistoryDismiss else { return }
            queuedWeeklyReportAfterHistoryDismiss = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                activeWeeklyReport = pending
            }
        }
        .onChangeCompat(of: selectedTab) { newTab in
            if newTab == .rewards {
                scheduleInsightsReportReload()
            }
            if newTab != .settings, isEditingSettingsProfileName {
                commitSettingsProfileNameEditing()
            }
        }
        .onChangeCompat(of: rewardViewModel.snapshot.bestStreak) { bestStreak in
            evaluateStreakMedalUnlock(bestStreak: bestStreak)
        }
        .onChangeCompat(of: settingsStore.isNotificationsEnabled) { _ in
            Task {
                await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
            }
        }
        .onChangeCompat(of: settingsStore.appearancePreference) { _ in
            syncSharedAppearanceStyleForExtensions()
        }
        .onChangeCompat(of: colorScheme) { _ in
            if settingsStore.appearancePreference == .system {
                syncSharedAppearanceStyleForExtensions()
            }
        }
        .onChangeCompat(of: settingsStore.membershipTier) { _ in
            syncRuntimeShieldForAuthorizationState(now: Date())
            if settingsStore.membershipTier == .none {
                activeWeeklyDigestRoute = nil
                historyActiveWeeklyDigestRoute = nil
                activeWeeklyReport = nil
                isWeeklyInsightsHistoryPresented = false
            }
            Task {
                await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
            }
        }
        .onChangeCompat(of: settingsStore.profileName) { newValue in
            if !isEditingSettingsProfileName {
                settingsProfileNameDraft = newValue
            }
        }
        .onChangeCompat(of: isSettingsProfileNameFocused) { focused in
            if !focused, isEditingSettingsProfileName {
                commitSettingsProfileNameEditing()
            }
        }
#if DEBUG
        .onChangeCompat(of: isFlipPreviewEnabled) { isEnabled in
            let now = Date()
            if isEnabled {
                flipPreviewReferenceDate = now
                flipPreviewDisplayBaseDate = now
                isFlipPreviewPaused = false
            } else if !isDebugTimeOverrideEnabled {
                isFlipPreviewPaused = false
            }
            refreshDebugTimeSimulation()
        }
        .onChangeCompat(of: isDebugTimeOverrideEnabled) { isEnabled in
            let now = Date()
            if isEnabled {
                flipPreviewReferenceDate = now
                flipPreviewDisplayBaseDate = currentTimelineDisplayDate(from: now)
                isFlipPreviewPaused = true
                debugManualTimelineDate = flipPreviewDisplayBaseDate
            } else if !isFlipPreviewEnabled {
                isFlipPreviewPaused = false
            }
            refreshDebugTimeSimulation()
        }
        .onChangeCompat(of: isDebugStreakMedalPreviewEnabled) { isEnabled in
            if isEnabled {
                debugStreakMedalPreviewBestStreak = rewardViewModel.snapshot.bestStreak
            } else {
                debugStreakMedalPreviewBestStreak = 0
            }
        }
        .onChangeCompat(of: isDebugStreakOverrideEnabled) { isEnabled in
            if isEnabled {
                debugStreakOverrideDays = max(0, rewardViewModel.snapshot.currentStreak)
            }
            syncDebugStreakOverrideToWidget()
        }
        .onChangeCompat(of: viewModel.rules) {
            refreshDebugTimeSimulation()
        }
        .onChangeCompat(of: debugStreakOverrideDays) {
            if isDebugStreakOverrideEnabled {
                syncDebugStreakOverrideToWidget()
            }
        }
        .onChangeCompat(of: isDebugInsightsDemoEnabled) { isEnabled in
            persistDebugInsightsDemoEnabled(isEnabled)
        }
        .onChangeCompat(of: isDebugWeeklyReportDemoEnabled) { isEnabled in
            persistDebugWeeklyReportDemoEnabled(isEnabled)
        }
#endif
    }

    private var bodyWithTimers: some View {
        bodyCore
        .onAppear {
            authorizationService.refreshStatus()
            applyPendingInitialTabIfNeeded()
            syncRuntimeShieldForAuthorizationState(now: Date())
            syncSharedAppearanceStyleForExtensions()
            consumePendingQuickActionIfNeeded()
            consumePendingWeeklyInsightsRouteIfNeeded()
            settingsProfileNameDraft = settingsStore.profileName
            if sharedDefaults.object(forKey: OnlyLockShared.settingsLastPresentedStreakMedalTierKey) == nil {
                sharedDefaults.set(0, forKey: OnlyLockShared.settingsLastPresentedStreakMedalTierKey)
            }
            uiClockNow = Date()
            syncStartAtToCurrentMinimumIfNeeded()
            syncPausedTaskAnchors(now: resolvedDisplayNow)
            rewardViewModel.refresh(seedFromRules: viewModel.rules, now: resolvedDisplayNow)
            screenTimeInsightsStore.refresh()
            scheduleInsightsReportReload(force: true)
            Task {
                await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
            }
#if DEBUG
            refreshDebugTimeSimulation()
            syncDebugStreakOverrideToWidget()
            isDebugInsightsDemoEnabled = debugSharedDefaults.bool(forKey: OnlyLockShared.debugScreenTimeInsightsOverrideEnabledKey)
            isDebugWeeklyReportDemoEnabled = debugSharedDefaults.bool(forKey: OnlyLockShared.debugWeeklyReportOverrideEnabledKey)
            debugWeeklyReportWeekStart = latestPublishedWeeklyReportStartForDebugSimulation(from: resolvedDisplayNow)
#endif
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            uiClockNow = now
            syncPausedTaskAnchors(now: resolvedDisplayNow)
            rewardViewModel.refresh(seedFromRules: viewModel.rules, now: resolvedDisplayNow)
        }
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            if selectedTab == .rewards {
                screenTimeInsightsStore.refresh()
            }
        }
        .onReceive(quickActionRouter.$pendingAction.compactMap { $0 }) { action in
            handleQuickAction(action)
            _ = quickActionRouter.consumePendingAction()
        }
        .onReceive(quickActionRouter.$pendingWeeklyInsightsRoute.compactMap { $0 }) { route in
            handleWeeklyInsightsNotificationRoute(route)
            _ = quickActionRouter.consumePendingWeeklyInsightsRoute()
        }
#if DEBUG
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            if isFlipPreviewEnabled || isDebugTimeOverrideEnabled || hadDebugTimeSimulationApplied {
                refreshDebugTimeSimulation()
            }
        }
#endif
    }

    private var bodyCore: some View {
        tabRootContent
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: customTabBarReservedHeight)
        }
        .overlay(alignment: .bottom) {
            customTabBar
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(pageBackground.ignoresSafeArea())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(preferredColorSchemeOverride)
    }

    @ViewBuilder
    private var tabRootContent: some View {
        switch selectedTab {
        case .create:
            createLockTab
        case .current:
            currentLockTab
        case .rewards:
            rewardsTab
        case .settings:
            settingsTab
        }
    }

    private func applyPendingInitialTabIfNeeded() {
        guard let pendingTab = pendingInitialTab else { return }
        selectedTab = pendingTab
        sharedDefaults.removeObject(forKey: OnlyLockShared.pendingInitialTabKey)
        sharedDefaults.synchronize()
    }

    private var createLockTab: some View {
        NavigationStack {
            createLockTabContent
        }
    }

    private var createLockTabContent: some View {
        AnyView(
            VStack(spacing: 0) {
                createTopBar

                if hasActiveMembership {
                    ScrollView {
                        ScrollViewOffsetObserver { offsetY in
                            guard isTopBarStateUpdatesEnabled else { return }
                            let shouldCollapse = offsetY > 2
                            if shouldCollapse != isTopBarCollapsed {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isTopBarCollapsed = shouldCollapse
                                }
                            }
                        }
                        .frame(height: 0)

                        VStack(alignment: .leading, spacing: 44) {
                            targetsCard
                            scheduleCard
                            taskCard
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 6)
                        .padding(.bottom, 100)
                    }
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            dismissKeyboard()
                        },
                        including: .gesture
                    )
                } else {
                    membershipExpiredGateView(
                        subtitle: "续费后继续创建锁定任务并管理应用与网站。"
                    )
                }
            }
            .background(pageBackground.ignoresSafeArea())
        )
    }

    private var currentLockTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressTopBar

                ZStack {
                    pageBackground
                        .ignoresSafeArea()

                    if hasActiveMembership {
                        if shouldShowCurrentLockTimeline {
                            TimelineView(.periodic(from: .now, by: timelineRefreshInterval)) { context in
                                currentLockList(now: currentTimelineDisplayDate(from: context.date))
                            }
                        } else {
                            currentLockEmptyState
                        }
                    } else {
                        membershipExpiredGateView(
                            subtitle: "续费后继续查看任务进度与锁定状态。"
                        )
                    }
                }
            }
            .background(pageBackground.ignoresSafeArea())
        }
    }

    private var settingsTab: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    settingsTopBar

                    ScrollView {
                        ScrollViewOffsetObserver { offsetY in
                            guard isTopBarStateUpdatesEnabled else { return }
                            let shouldCollapse = offsetY > 2
                            if shouldCollapse != isSettingsTopBarCollapsed {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isSettingsTopBarCollapsed = shouldCollapse
                                }
                            }
                        }
                        .frame(height: 0)

                        VStack(alignment: .leading, spacing: 24) {
                            AnyView(settingsProfileCard)
                            AnyView(settingsScreenTimePermissionCard)
                            AnyView(settingsSupportCard)
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 12)
                        .padding(.bottom, customTabBarReservedHeight + 24)
                    }
                }

#if DEBUG
                flipPreviewDebugOverlay
#endif
            }
            .background(pageBackground.ignoresSafeArea())
            .task {
                await settingsStore.refreshNotificationAuthorizationStatus()
                settingsStore.refreshMembershipStatus()
            }
            .alert(onlyLockL("提示"), isPresented: settingsErrorAlertPresentedBinding) {
                Button(onlyLockL("知道了"), role: .cancel) {
                    settingsErrorAlertMessage = nil
                }
            } message: {
                Text(settingsErrorAlertMessage ?? "")
            }
        }
    }

    private var settingsProfileCard: some View {
        let bestStreak = streakMedalBestStreakForDisplay
        let hasUnlockedStreakMedal = RewardEngine.highestUnlockedStreakTier(bestStreak: bestStreak) != nil
        let visualLevel = RewardEngine.streakMedalVisualLevel(bestStreak: bestStreak)
        let displayedMedalNumber = RewardEngine.displayedStreakNumber(bestStreak: bestStreak)
        return AnyView(
            VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                PhotosPicker(
                    selection: settingsAvatarPickerBinding,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    settingsAvatarView
                }
                .buttonStyle(.plain)

                if hasUnlockedStreakMedal {
                    streakMedalBadge(
                        number: displayedMedalNumber,
                        level: visualLevel,
                        size: 28,
                        context: .avatarCompact
                    )
                    .frame(width: 32, height: 32)
                    .background(pageBackground, in: Circle())
                    .overlay(Circle().stroke(dividerColor, lineWidth: 1))
                    .offset(x: 6, y: 6)
                }
            }

            Group {
                if isEditingSettingsProfileName {
                    VStack(spacing: 6) {
                        ZStack {
                            if settingsProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(onlyLockL("OnlyLock 用户"))
                                    .font(.system(size: 32, weight: .black))
                                    .foregroundStyle(settingsDisplayNameColor.opacity(0.72))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity)
                                    .allowsHitTesting(false)
                            }

                            TextField("", text: $settingsProfileNameDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 32, weight: .black))
                                .foregroundStyle(settingsDisplayNameColor)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .submitLabel(.done)
                                .focused($isSettingsProfileNameFocused)
                                .onSubmit {
                                    commitSettingsProfileNameEditing()
                                }
                        }
                    }
                } else {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Text(settingsDisplayName)
                                .font(.system(size: 32, weight: .black))
                                .foregroundStyle(settingsDisplayNameColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(secondaryText.opacity(0.72))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            beginSettingsProfileNameEditing()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        )
    }

    private var membershipTierSettingsColor: Color {
        let effectiveTier = hasActiveMembership ? settingsStore.membershipTier : .none
        switch effectiveTier {
        case .none:
            return secondaryText
        case .monthly:
            return Color(red: 0.39, green: 0.45, blue: 0.52)
        case .lifetime:
            return Color(red: 0.50, green: 0.38, blue: 0.24)
        }
    }

    private var settingsDisplayNameColor: Color {
        membershipTierSettingsColor
    }

    private func membershipExpiredGateView(subtitle: String) -> some View {
        VStack {
            Spacer(minLength: 0)
            unifiedCenteredStateCard(
                icon: appMarkIcon,
                title: membershipAccessTitle,
                buttonTitle: onlyLockL("去续费"),
                isLoading: membershipRenewalStore.isPurchasing || membershipRenewalStore.isRestoring
            ) {
                presentMembershipRenewal()
            } footer: {
                Text(onlyLockL(subtitle))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 360)
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .background(pageBackground.ignoresSafeArea())
    }

    @MainActor
    private func presentMembershipRenewal() {
        selectedMembershipRenewalPlan = .lifetime
        Task {
            await membershipRenewalStore.prepare()
        }
        isMembershipRenewalPresented = true
    }

    @MainActor
    private func handleMembershipAccessRestored() async {
        await MembershipTransactionObserver.shared.refreshNow()
        settingsStore.refreshMembershipStatus()
        rewardViewModel.refresh(seedFromRules: viewModel.rules, now: resolvedDisplayNow)
        screenTimeInsightsStore.refresh()
        if selectedTab == .rewards {
            scheduleInsightsReportReload(force: true)
        }
        syncRuntimeShieldForAuthorizationState(now: Date())
        await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
        isMembershipRenewalPresented = false
    }

    @MainActor
    private func purchaseSelectedMembershipRenewalPlan() async {
        let succeeded: Bool
        switch selectedMembershipRenewalPlan {
        case .lifetime:
            succeeded = await membershipRenewalStore.purchaseLifetime()
        case .monthly:
            succeeded = await membershipRenewalStore.purchaseMonthly()
        }

        if succeeded {
            await handleMembershipAccessRestored()
        }
    }

    @MainActor
    private func restoreMembershipRenewal() async {
        let restored = await membershipRenewalStore.restorePurchases()
        if restored {
            await handleMembershipAccessRestored()
        }
    }

    private var membershipRenewalPrimaryButtonTitle: String {
        switch selectedMembershipRenewalPlan {
        case .lifetime:
            return onlyLockL("立即解锁终身会员")
        case .monthly:
            return onlyLockL("立即续费")
        }
    }

    private func membershipRenewalOptionCard(for plan: MembershipRenewalPlan) -> some View {
        let isSelected = selectedMembershipRenewalPlan == plan
        let title = plan == .lifetime ? onlyLockL("终身会员") : onlyLockL("月度会员")
        let suffix = plan == .lifetime ? onlyLockL("买断") : onlyLockL("/月")
        let price = plan == .lifetime ? membershipRenewalStore.lifetimeDisplayPrice : membershipRenewalStore.monthlyDisplayPrice

        return Button {
            guard selectedMembershipRenewalPlan != plan else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selectedMembershipRenewalPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Text(title)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(primaryText)

                    Spacer()

                    Circle()
                        .stroke(isSelected ? primaryText : dividerColor.opacity(0.9), lineWidth: isSelected ? 6 : 2.5)
                        .frame(width: 26, height: 26)
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(price)
                        .font(.system(size: 34, weight: .black))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(suffix)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? primaryText : dividerColor, lineWidth: isSelected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var membershipRenewalPaywall: some View {
        NavigationStack {
            ZStack {
                pageBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button {
                            isMembershipRenewalPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(primaryText)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                    VStack(alignment: .leading, spacing: 18) {
                        Text(onlyLockL("可用方案"))
                            .font(.system(size: 34, weight: .black))
                            .foregroundStyle(primaryText)
                            .tracking(-0.8)
                            .padding(.top, 24)

                        VStack(spacing: 14) {
                            membershipRenewalOptionCard(for: .lifetime)
                            membershipRenewalOptionCard(for: .monthly)
                        }

                        Button {
                            Task {
                                await purchaseSelectedMembershipRenewalPlan()
                            }
                        } label: {
                            HStack(spacing: 10) {
                                if membershipRenewalStore.isPurchasing {
                                    ProgressView()
                                        .tint(colorScheme == .dark ? .black : .white)
                                }
                                Text(membershipRenewalPrimaryButtonTitle)
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundStyle(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(colorScheme == .dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(membershipRenewalStore.isPurchasing || membershipRenewalStore.isRestoring)

                        HStack {
                            Spacer()
                            Button(onlyLockL("恢复购买")) {
                                Task {
                                    await restoreMembershipRenewal()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            Spacer()
                        }

                        if let errorMessage = membershipRenewalStore.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.red)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var settingsScreenTimePermissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSectionLabel(onlyLockL("系统设置"))

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 24)

                    Text(onlyLockL("屏幕时间访问"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Spacer()

                    if isSettingsAuthorizationRequesting {
                        ProgressView()
                            .scaleEffect(0.86)
                            .tint(primaryText)
                    }

                    Toggle("", isOn: settingsScreenTimePermissionBinding)
                        .labelsHidden()
                        .tint(settingsSwitchTint)
                        .disabled(isSettingsAuthorizationRequesting)
                }
                .frame(height: 56)
                .padding(.horizontal, 14)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                HStack(spacing: 12) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 24)

                    Text(onlyLockL("App锁定通知"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Spacer()

                    if settingsStore.isRequestingNotificationPermission {
                        ProgressView()
                            .scaleEffect(0.86)
                            .tint(primaryText)
                    }

                    Toggle("", isOn: settingsNotificationToggleBinding)
                        .labelsHidden()
                        .tint(settingsSwitchTint)
                        .disabled(settingsStore.isRequestingNotificationPermission)
                }
                .frame(height: 56)
                .padding(.horizontal, 14)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .frame(width: 24)

                        Text(onlyLockL("切换外观"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(primaryText)

                        Spacer()

                        Picker(
                            onlyLockL("切换外观"),
                            selection: Binding(
                                get: { settingsStore.appearancePreference },
                                set: { applyAppearancePreferenceFromSettings($0) }
                            )
                        ) {
                            ForEach(SettingsStore.AppearancePreference.allCases) { preference in
                                Text(preference.title).tag(preference)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(primaryText)
                        .id("appearance-picker-\(languageStore.currentLanguage.rawValue)")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                }

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                HStack(spacing: 12) {
                    Image(systemName: "globe.europe.africa.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: 24)

                    Text(onlyLockL("应用语言"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            languageStore.toggleLanguage()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(languageStore.switchFlag)
                                .font(.system(size: 15))

                            Text(languageStore.currentLanguage == .zhHans ? onlyLockL("中文") : onlyLockL("英文"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(primaryText)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Capsule(style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(dividerColor, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .frame(height: 56)
                .padding(.horizontal, 14)
            }
        }
    }

    private var settingsSupportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            settingsSectionLabel(onlyLockL("支持"))

            VStack(spacing: 0) {
                Button {
                    Task {
                        await openAppStoreReviewPage()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .frame(width: 24)

                        Text(onlyLockL("去评分"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(primaryText)

                        Spacer(minLength: 0)

                        if isOpeningAppStoreReview {
                            ProgressView()
                                .scaleEffect(0.86)
                                .tint(primaryText)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(secondaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isOpeningAppStoreReview)
                .padding(.horizontal, 14)
                .frame(height: 56)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                Button {
                    openContactUsPage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .frame(width: 24)

                        Text(onlyLockL("联系我们"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(primaryText)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 56)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                Button {
                    openPrivacyPolicyPage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.doc.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .frame(width: 24)

                        Text(onlyLockL("隐私政策"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(primaryText)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 56)

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                Button {
                    openTermsOfUsePage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .frame(width: 24)

                        Text(onlyLockL("使用条款"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(primaryText)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(secondaryText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .frame(height: 56)
            }
        }
    }

    private func settingsSectionLabel(_ title: String) -> some View {
        Text(onlyLockL(title))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(secondaryText)
    }

    private func beginSettingsProfileNameEditing() {
        settingsProfileNameDraft = settingsStore.profileName
        isEditingSettingsProfileName = true
        DispatchQueue.main.async {
            isSettingsProfileNameFocused = true
        }
    }

    private func commitSettingsProfileNameEditing() {
        let trimmed = settingsProfileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsStore.updateProfileName(trimmed)
        settingsProfileNameDraft = trimmed
        isEditingSettingsProfileName = false
        isSettingsProfileNameFocused = false
    }

    private var settingsDisplayName: String {
        let trimmed = settingsStore.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? onlyLockL("OnlyLock 用户") : trimmed
    }

    private var settingsAvatarView: some View {
        Group {
            if let data = settingsStore.profileAvatarData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("AppMark")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(secondaryText)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(pageBackground)
            }
        }
        .frame(width: 108, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(dividerColor, lineWidth: 1)
        )
    }

    private var settingsAvatarPickerBinding: Binding<PhotosPickerItem?> {
        Binding(
            get: { settingsAvatarPickerItem },
            set: { newItem in
                settingsAvatarPickerItem = newItem
                guard let newItem else { return }
                Task {
                    await applySettingsAvatarSelection(newItem)
                }
            }
        )
    }

    private var settingsNotificationToggleBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.isNotificationsEnabled },
            set: { isEnabled in
                Task {
                    await settingsStore.handleNotificationToggleChange(to: isEnabled)
                }
            }
        )
    }

    private var settingsScreenTimePermissionBinding: Binding<Bool> {
        Binding(
            get: { authorizationService.isApproved },
            set: { isEnabled in
                guard !isSettingsAuthorizationRequesting else { return }

                if isEnabled {
                    Task {
                        await requestSettingsScreenTimeAuthorization()
                    }
                } else if authorizationService.isApproved {
                    isScreenTimeRevokeConfirmationPresented = true
                }
            }
        )
    }

    private var preferredColorSchemeOverride: ColorScheme? {
        switch settingsStore.appearancePreference {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func syncSharedAppearanceStyleForExtensions() {
        sharedDefaults.set(
            settingsStore.appearancePreference.rawValue,
            forKey: OnlyLockShared.settingsAppearancePreferenceKey
        )

        // Respect user appearance preference first; only follow system when set to `.system`.
        let resolvedStyle: String
        switch settingsStore.appearancePreference {
        case .dark:
            resolvedStyle = "dark"
        case .light:
            resolvedStyle = "light"
        case .system:
            resolvedStyle = colorScheme == .dark ? "dark" : "light"
        }

        sharedDefaults.set(resolvedStyle, forKey: OnlyLockShared.settingsResolvedAppearanceStyleKey)
        sharedDefaults.set(resolvedStyle == "dark", forKey: OnlyLockShared.settingsShieldUseDarkAppearanceKey)
        sharedDefaults.synchronize()
        writeShieldAppearanceSnapshot(
            preference: settingsStore.appearancePreference.rawValue,
            resolvedStyle: resolvedStyle,
            useDarkAppearance: resolvedStyle == "dark"
        )
    }

    private func writeShieldAppearanceSnapshot(preference: String, resolvedStyle: String, useDarkAppearance: Bool) {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: OnlyLockShared.appGroupIdentifier
        ) else {
            return
        }

        let payload: [String: Any] = [
            "preference": preference,
            "resolvedStyle": resolvedStyle,
            "useDarkAppearance": useDarkAppearance,
            "updatedAt": Date().timeIntervalSince1970
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }

        let fileURL = groupURL.appendingPathComponent("shield_appearance.json")
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func applyAppearancePreferenceFromSettings(_ preference: SettingsStore.AppearancePreference) {
        settingsStore.updateAppearancePreference(preference)
        syncSharedAppearanceStyleForExtensions()
    }

    private func applySettingsAvatarSelection(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        let compressed = image.jpegData(compressionQuality: 0.82) ?? data
        settingsStore.updateProfileAvatarData(compressed)
        settingsAvatarPickerItem = nil
    }

    @MainActor
    private func requestSettingsScreenTimeAuthorization(
        presentRecoverySheetOnFailure: Bool = true
    ) async {
        guard !authorizationService.isApproved else { return }
        isSettingsAuthorizationRequesting = true
        defer { isSettingsAuthorizationRequesting = false }

        do {
            try await authorizationService.requestAuthorization()
        } catch {
            if presentRecoverySheetOnFailure {
                handleAuthorizationFailure(error, source: .recovery)
            } else {
                insightsAuthorizationNeedsSettingsFallback = true
            }
            return
        }

        if !authorizationService.isApproved {
            if presentRecoverySheetOnFailure {
                isAuthorizationRecoveryPresented = true
            } else {
                insightsAuthorizationNeedsSettingsFallback = true
            }
            return
        }

        insightsAuthorizationNeedsSettingsFallback = false
    }

    @MainActor
    private func revokeSettingsScreenTimeAuthorization() async {
        guard authorizationService.isApproved else { return }
        isSettingsAuthorizationRequesting = true
        defer { isSettingsAuthorizationRequesting = false }

        do {
            try await authorizationService.revokeAuthorization()
        } catch {
            presentSettingsError("关闭屏幕时间权限失败，请稍后重试。")
            return
        }

        if authorizationService.isApproved {
            openSettingsForScreenTimePermission()
        }
    }

    private func openSettingsForScreenTimePermission() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL) else {
            presentSettingsError("无法打开系统设置，请手动前往设置撤回权限。")
            return
        }

        UIApplication.shared.open(settingsURL)
    }

    @MainActor
    private func openAppStoreReviewPage() async {
        guard !isOpeningAppStoreReview else { return }
        isOpeningAppStoreReview = true
        defer { isOpeningAppStoreReview = false }

        guard let bundleID = Bundle.main.bundleIdentifier,
              !bundleID.isEmpty else {
            presentSettingsError("暂时无法打开评分页，请稍后重试。")
            return
        }

        if let trackID = await fetchAppStoreTrackID(bundleID: bundleID),
           openAppStoreWriteReviewPage(trackID: trackID) {
            return
        }

        if openAppStoreSearchPage() {
            return
        }

        presentSettingsError("暂时无法打开评分页，请稍后重试。")
    }

    private func fetchAppStoreTrackID(bundleID: String) async -> Int? {
        guard let escapedBundleID = bundleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(escapedBundleID)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: lookupURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            return payload.results.first?.trackId
        } catch {
            return nil
        }
    }

    private func openAppStoreWriteReviewPage(trackID: Int) -> Bool {
        let writeReviewURLs = [
            URL(string: "itms-apps://itunes.apple.com/app/id\(trackID)?action=write-review"),
            URL(string: "https://apps.apple.com/app/id\(trackID)?action=write-review")
        ]

        for candidate in writeReviewURLs {
            guard let url = candidate, UIApplication.shared.canOpenURL(url) else {
                continue
            }
            UIApplication.shared.open(url)
            return true
        }

        return false
    }

    private func openPrivacyPolicyPage() {
        openSupportURL(
            "https://vbin210327-real.github.io/OnlyLock/privacy/",
            failureMessage: "暂时无法打开隐私政策，请稍后重试。"
        )
    }

    private func openContactUsPage() {
        openSupportURL(
            "https://pickle-cloth-1d6.notion.site/OnlyLock-Technical-Support-33c18e2eff0f8001a44ccc5202d77f93?source=copy_link",
            failureMessage: "暂时无法打开联系我们页面，请稍后重试。"
        )
    }

    private func openTermsOfUsePage() {
        openSupportURL(
            "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
            failureMessage: "暂时无法打开使用条款，请稍后重试。"
        )
    }

    private func openSupportURL(_ urlString: String, failureMessage: String) {
        guard let url = URL(string: urlString),
              UIApplication.shared.canOpenURL(url) else {
            presentSettingsError(failureMessage)
            return
        }

        UIApplication.shared.open(url)
    }

    private func openAppStoreSearchPage() -> Bool {
        let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "OnlyLock"
        guard let escapedQuery = displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return false
        }

        let searchURLs = [
            URL(string: "itms-apps://itunes.apple.com/search?term=\(escapedQuery)&entity=software"),
            URL(string: "https://apps.apple.com/search?term=\(escapedQuery)")
        ]

        for candidate in searchURLs {
            guard let url = candidate, UIApplication.shared.canOpenURL(url) else {
                continue
            }
            UIApplication.shared.open(url)
            return true
        }

        return false
    }

    @MainActor
    private func presentShareAppSheet() async {
        let displayName = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "OnlyLock"
        let shareText: String
        if AppLanguageRuntime.currentLanguage == .english {
            shareText = "I'm using \(displayName). Sharing it with you."
        } else {
            shareText = "我在用 \(displayName)，分享给你。"
        }
        var items: [Any] = [shareText]

        if let bundleID = Bundle.main.bundleIdentifier,
           let trackID = await fetchAppStoreTrackID(bundleID: bundleID),
           let appStoreURL = URL(string: "https://apps.apple.com/app/id\(trackID)") {
            items.append(appStoreURL)
        }
        pendingShareSheetPayload = ShareSheetPayload(items: items)
    }

    private func presentSettingsError(_ message: String) {
        settingsErrorAlertMessage = onlyLockL(message)
    }

    private var settingsStreakMedalCard: some View {
        let bestStreak = streakMedalBestStreakForDisplay
        let visualLevel = RewardEngine.streakMedalVisualLevel(bestStreak: bestStreak)
        let style = streakMedalStyle(for: visualLevel)
        let displayedNumber = RewardEngine.displayedStreakNumber(bestStreak: bestStreak)
        let subtitle: String

        if let nextTier = RewardEngine.nextStreakTier(bestStreak: bestStreak) {
            if visualLevel == .locked {
                let remaining = max(0, nextTier - bestStreak)
                if AppLanguageRuntime.currentLanguage == .english {
                    subtitle = "Unlock the \(nextTier)-day medal with \(remaining) more day(s)"
                } else {
                    subtitle = "再连续打卡\(remaining)天解锁 \(nextTier) 天勋章"
                }
            } else {
                if AppLanguageRuntime.currentLanguage == .english {
                    subtitle = "Next tier: \(nextTier)-day streak"
                } else {
                    subtitle = "下一档位：连续 \(nextTier) 天"
                }
            }
        } else {
            subtitle = AppLanguageRuntime.currentLanguage == .english
                ? "Highest streak medal unlocked"
                : "已达连续打卡勋章最高等级"
        }

        return HStack(spacing: 14) {
            streakMedalBadge(
                number: displayedNumber,
                level: visualLevel,
                size: 52
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    AppLanguageRuntime.currentLanguage == .english
                        ? "\(displayedNumber)-day streak!"
                        : "连续打卡 \(displayedNumber) 天!"
                )
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [style.cardTop, style.cardBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.ringColor.opacity(0.30), lineWidth: 1)
        )
    }

    private func streakMedalUnlockOverlay(tier: Int) -> some View {
        let visualLevel = RewardEngine.streakMedalVisualLevel(bestStreak: tier)
        let style = streakMedalStyle(for: visualLevel)

        return GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [style.cardTop, style.cardBottom, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                streakMedalSceneBackdrop(style: style)

                VStack(spacing: 0) {
                    Spacer(minLength: max(geometry.size.height * 0.13, 88))

                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(style.glowColor.opacity(0.26))
                                .frame(width: 286, height: 286)
                                .blur(radius: 52)

                            streakMedalBadge(
                                number: tier,
                                level: visualLevel,
                                size: 172
                            )
                        }

                        VStack(spacing: 0) {
                            Text(AppLanguageRuntime.currentLanguage == .english ? "New Medal Unlocked" : "解锁新勋章")
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.98))
                                .shadow(color: style.glowColor.opacity(0.18), radius: 12)

                            Spacer()
                                .frame(height: 5)

                            Text(
                                AppLanguageRuntime.currentLanguage == .english
                                    ? "\(tier)-day streak!"
                                    : "连续打卡 \(tier) 天!"
                            )
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.96))
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                                .shadow(color: style.glowColor.opacity(0.12), radius: 8)

                            Spacer()
                                .frame(height: 5)

                            Text(AppLanguageRuntime.currentLanguage == .english ? "Great job, keep going" : "太棒了，继续保持")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                        .padding(.top, 10)
                    }

                    Spacer(minLength: max(geometry.size.height * 0.17, 108))

                    Button {
                        dismissStreakMedalUnlock()
                    } label: {
                        Text(onlyLockL("解锁（2.5s）"))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(style.buttonText)
                            .frame(minWidth: 150)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 15)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [style.buttonTop, style.buttonBottom],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
                            )
                            .shadow(color: style.glowColor.opacity(0.26), radius: 16, y: 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 32))
                }
                .padding(.horizontal, 34)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func streakMedalBadge(
        number: Int,
        level: RewardEngine.StreakMedalVisualLevel,
        size: CGFloat,
        context: StreakMedalBadgeContext = .regular
    ) -> some View {
        let style = streakMedalStyle(for: level)
        let innerScale = streakMedalInnerScale(for: level)
        let suppressAura = context == .avatarCompact && streakMedalCompactSuppressesAura(level: level)
        let effectiveRingCount = suppressAura ? 0 : style.ringCount
        let shellShadowOpacity = suppressAura ? min(style.glowOpacity, 0.16) : style.glowOpacity
        let shellShadowRadius = suppressAura ? max(4, style.glowRadius * 0.35) : style.glowRadius
        let shellShadowYOffset: CGFloat = suppressAura ? 3 : 10
        let ringPaddingBase: CGFloat = 10
        let shellWidth = size * 1.18
        let shellHeight = size * 1.00
        let coreWidth = size * 0.84
        let coreHeight = size * 0.78

        return ZStack {
            if effectiveRingCount > 0 {
                ForEach(0..<effectiveRingCount, id: \.self) { ringIndex in
                    MedalHexagonShape()
                        .fill(style.beamColor.opacity(max(0.06, 0.16 - Double(ringIndex) * 0.03)))
                        .frame(
                            width: shellWidth + CGFloat(ringIndex + 1) * ringPaddingBase,
                            height: shellHeight + CGFloat(ringIndex + 1) * ringPaddingBase
                        )
                        .blur(radius: ringIndex == 0 ? 0 : 2)

                    MedalHexagonShape()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.54),
                                    style.ringColor.opacity(max(0.22, 0.54 - Double(ringIndex) * 0.12)),
                                    style.beamColor.opacity(0.26)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: ringIndex == 0 ? 2.2 : 1.5
                        )
                        .frame(
                            width: shellWidth + CGFloat(ringIndex + 1) * ringPaddingBase,
                            height: shellHeight + CGFloat(ringIndex + 1) * ringPaddingBase
                        )
                }
            }

            if !suppressAura {
                MedalHexagonShape()
                    .fill(style.glowColor.opacity(0.12))
                    .frame(width: shellWidth * 1.04, height: shellHeight * 1.04)
                    .blur(radius: 10)
            }

            MedalHexagonFrameShape(innerScale: innerScale)
                .fill(
                    LinearGradient(
                        colors: [style.shellTop, style.shellMiddle, style.shellBottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: shellWidth, height: shellHeight)
                .shadow(color: style.glowColor.opacity(shellShadowOpacity), radius: shellShadowRadius, y: shellShadowYOffset)

            streakMedalShellTexture(
                level: level,
                style: style,
                shellWidth: shellWidth,
                shellHeight: shellHeight,
                innerScale: innerScale
            )

            if suppressAura {
                MedalHexagonShape()
                    .stroke(
                        LinearGradient(
                            colors: [
                                style.ringColor.opacity(0.92),
                                style.sparkleColor.opacity(0.52),
                                style.beamColor.opacity(0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: streakMedalCompactRimWidth(for: level)
                    )
                    .frame(width: shellWidth * 0.98, height: shellHeight * 0.98)
            }

            MedalHexagonFrameShape(innerScale: innerScale)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.70),
                            style.beamColor.opacity(0.22),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: shellWidth, height: shellHeight)
                .scaleEffect(level == .platinum ? 0.985 : 0.97)
                .blendMode(.screen)

            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(streakMedalPrimarySheenOpacity(for: level)), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: shellWidth * 0.16, height: shellHeight * 1.10)
                .rotationEffect(.degrees(34))
                .offset(x: -shellWidth * 0.13, y: -shellHeight * 0.05)
                .blendMode(.screen)
                .mask(
                    MedalHexagonFrameShape(innerScale: innerScale)
                        .frame(width: shellWidth, height: shellHeight)
                )

            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, style.beamColor.opacity(streakMedalSecondarySheenOpacity(for: level)), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: shellWidth * 0.11, height: shellHeight * 0.98)
                .rotationEffect(.degrees(-36))
                .offset(x: shellWidth * 0.20, y: shellHeight * 0.05)
                .blendMode(.screen)
                .mask(
                    MedalHexagonFrameShape(innerScale: innerScale)
                        .frame(width: shellWidth, height: shellHeight)
                )

            MedalFacetLinesShape()
                .stroke(style.sparkleColor.opacity(streakMedalOuterFacetOpacity(for: level)), lineWidth: max(1, size * 0.012))
                .frame(width: shellWidth, height: shellHeight)

            MedalHexagonShape()
                .stroke(Color.white.opacity(streakMedalShellStrokeOpacity(for: level)), lineWidth: 1.6)
                .frame(width: shellWidth, height: shellHeight)

            MedalHexagonShape()
                .fill(
                    LinearGradient(
                        colors: [style.coreTop, style.coreBottom],
                        startPoint: .top,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: coreWidth, height: coreHeight)
                .shadow(color: Color.white.opacity(0.18), radius: 4, y: -2)

            streakMedalCoreTexture(
                level: level,
                style: style,
                coreWidth: coreWidth,
                coreHeight: coreHeight
            )

            MedalHexagonShape()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(streakMedalCoreGlowOpacity(for: level)), .clear, style.beamColor.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: coreWidth, height: coreHeight)
                .blendMode(.screen)

            MedalHexagonShape()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.82),
                            style.sparkleColor.opacity(0.42),
                            Color.black.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.3
                )
                .frame(width: coreWidth, height: coreHeight)

            MedalFacetLinesShape()
                .stroke(Color.white.opacity(streakMedalCoreFacetOpacity(for: level)), lineWidth: max(0.8, size * 0.009))
                .frame(width: coreWidth, height: coreHeight)

            Text("\(number)")
                .font(.system(size: size * 0.40, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(style.numberColor)
                .shadow(color: Color.white.opacity(0.18), radius: 1, y: 1)
        }
        .frame(
            width: shellWidth + CGFloat(effectiveRingCount) * ringPaddingBase,
            height: shellHeight + CGFloat(effectiveRingCount) * ringPaddingBase
        )
    }

    private enum StreakMedalBadgeContext {
        case regular
        case avatarCompact
    }

    private func streakMedalCompactSuppressesAura(level: RewardEngine.StreakMedalVisualLevel) -> Bool {
        switch level {
        case .radiantGold, .platinum, .crystal, .legendary:
            return true
        default:
            return false
        }
    }

    private func streakMedalCompactRimWidth(for level: RewardEngine.StreakMedalVisualLevel) -> CGFloat {
        switch level {
        case .radiantGold:
            return 1.3
        case .platinum:
            return 1.5
        case .crystal:
            return 1.8
        case .legendary:
            return 2.1
        default:
            return 1.2
        }
    }

    private func streakMedalInnerScale(for level: RewardEngine.StreakMedalVisualLevel) -> CGFloat {
        switch level {
        case .locked:
            return 0.78
        case .bronze:
            return 0.76
        case .silver:
            return 0.75
        case .gold:
            return 0.73
        case .radiantGold:
            return 0.70
        case .platinum:
            return 0.69
        case .crystal:
            return 0.66
        case .legendary:
            return 0.63
        }
    }

    @ViewBuilder
    private func streakMedalShellTexture(
        level: RewardEngine.StreakMedalVisualLevel,
        style: StreakMedalStyle,
        shellWidth: CGFloat,
        shellHeight: CGFloat,
        innerScale: CGFloat
    ) -> some View {
        switch level {
        case .locked, .bronze:
            EmptyView()
        case .silver:
            VStack(spacing: shellHeight * 0.18) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: shellWidth * 0.52, height: shellHeight * 0.08)
                Capsule(style: .continuous)
                    .fill(style.beamColor.opacity(0.10))
                    .frame(width: shellWidth * 0.64, height: shellHeight * 0.10)
            }
            .blur(radius: 1.5)
            .mask(MedalHexagonFrameShape(innerScale: innerScale).frame(width: shellWidth, height: shellHeight))
        case .gold:
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), .clear, style.shellBottom.opacity(0.10)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: shellWidth * 0.22, height: shellHeight * 0.88)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: shellWidth * 0.68, height: shellHeight * 0.10)
                    .offset(y: -shellHeight * 0.22)
            }
            .blendMode(.screen)
            .mask(MedalHexagonFrameShape(innerScale: innerScale).frame(width: shellWidth, height: shellHeight))
        case .radiantGold:
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.34), style.sparkleColor.opacity(0.20), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: shellWidth * 0.26, height: shellHeight * 0.94)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.26))
                    .frame(width: shellWidth * 0.78, height: shellHeight * 0.12)
                    .offset(y: -shellHeight * 0.24)
                Capsule(style: .continuous)
                    .fill(style.beamColor.opacity(0.16))
                    .frame(width: shellWidth * 0.84, height: shellHeight * 0.08)
                    .offset(y: shellHeight * 0.06)
            }
            .blendMode(.screen)
            .mask(MedalHexagonFrameShape(innerScale: innerScale).frame(width: shellWidth, height: shellHeight))
        case .platinum:
            ZStack {
                RoundedRectangle(cornerRadius: shellHeight * 0.16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), style.sparkleColor.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: shellWidth * 0.88, height: shellHeight * 0.72)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: shellWidth * 0.72, height: shellHeight * 0.12)
                    .offset(y: -shellHeight * 0.08)
            }
            .blur(radius: 1)
            .blendMode(.screen)
            .mask(MedalHexagonFrameShape(innerScale: innerScale).frame(width: shellWidth, height: shellHeight))
        case .crystal:
            ZStack {
                RoundedRectangle(cornerRadius: shellWidth * 0.05, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.30), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: shellWidth * 0.14, height: shellHeight * 1.06)
                    .rotationEffect(.degrees(34))
                    .offset(x: -shellWidth * 0.18)
                RoundedRectangle(cornerRadius: shellWidth * 0.05, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, style.sparkleColor.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: shellWidth * 0.12, height: shellHeight * 0.98)
                    .rotationEffect(.degrees(-30))
                    .offset(x: shellWidth * 0.18, y: shellHeight * 0.02)
            }
            .blendMode(.screen)
            .mask(MedalHexagonFrameShape(innerScale: innerScale).frame(width: shellWidth, height: shellHeight))
        case .legendary:
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.26), style.sparkleColor.opacity(0.18), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: shellWidth * 0.24, height: shellHeight)
                RoundedRectangle(cornerRadius: shellWidth * 0.05, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, style.beamColor.opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: shellWidth * 0.12, height: shellHeight * 1.04)
                    .rotationEffect(.degrees(-32))
                    .offset(x: shellWidth * 0.18)
            }
            .blendMode(.screen)
            .mask(MedalHexagonFrameShape(innerScale: innerScale).frame(width: shellWidth, height: shellHeight))
        }
    }

    @ViewBuilder
    private func streakMedalCoreTexture(
        level: RewardEngine.StreakMedalVisualLevel,
        style: StreakMedalStyle,
        coreWidth: CGFloat,
        coreHeight: CGFloat
    ) -> some View {
        switch level {
        case .locked, .bronze, .silver:
            EmptyView()
        case .gold:
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), .clear, Color.black.opacity(0.06)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: coreWidth * 0.18, height: coreHeight * 0.92)
                .mask(MedalHexagonShape().frame(width: coreWidth, height: coreHeight))
        case .radiantGold:
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.26), style.sparkleColor.opacity(0.18), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: coreWidth * 0.20, height: coreHeight)
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: coreWidth * 0.72, height: coreHeight * 0.08)
                    .offset(y: -coreHeight * 0.20)
            }
            .blendMode(.screen)
            .mask(MedalHexagonShape().frame(width: coreWidth, height: coreHeight))
        case .platinum:
            RoundedRectangle(cornerRadius: coreHeight * 0.12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), style.sparkleColor.opacity(0.08), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: coreWidth * 0.84, height: coreHeight * 0.66)
                .blur(radius: 0.8)
                .mask(MedalHexagonShape().frame(width: coreWidth, height: coreHeight))
        case .crystal:
            ZStack {
                RoundedRectangle(cornerRadius: coreWidth * 0.04, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.24), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: coreWidth * 0.14, height: coreHeight * 0.96)
                    .rotationEffect(.degrees(32))
                RoundedRectangle(cornerRadius: coreWidth * 0.04, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, style.sparkleColor.opacity(0.18), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: coreWidth * 0.12, height: coreHeight * 0.92)
                    .rotationEffect(.degrees(-30))
                    .offset(x: coreWidth * 0.18)
            }
            .blendMode(.screen)
            .mask(MedalHexagonShape().frame(width: coreWidth, height: coreHeight))
        case .legendary:
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), .clear, style.beamColor.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: coreWidth * 0.20, height: coreHeight)
                Capsule(style: .continuous)
                    .fill(style.sparkleColor.opacity(0.18))
                    .frame(width: coreWidth * 0.68, height: coreHeight * 0.08)
                    .offset(y: -coreHeight * 0.18)
            }
            .blendMode(.screen)
            .mask(MedalHexagonShape().frame(width: coreWidth, height: coreHeight))
        }
    }

    private func streakMedalPrimarySheenOpacity(for level: RewardEngine.StreakMedalVisualLevel) -> Double {
        switch level {
        case .locked: return 0.18
        case .bronze: return 0.22
        case .silver: return 0.18
        case .gold: return 0.22
        case .radiantGold: return 0.28
        case .platinum: return 0.14
        case .crystal: return 0.32
        case .legendary: return 0.26
        }
    }

    private func streakMedalSecondarySheenOpacity(for level: RewardEngine.StreakMedalVisualLevel) -> Double {
        switch level {
        case .locked: return 0.10
        case .bronze: return 0.14
        case .silver: return 0.16
        case .gold: return 0.16
        case .radiantGold: return 0.20
        case .platinum: return 0.10
        case .crystal: return 0.28
        case .legendary: return 0.22
        }
    }

    private func streakMedalOuterFacetOpacity(for level: RewardEngine.StreakMedalVisualLevel) -> Double {
        switch level {
        case .locked: return 0.24
        case .bronze: return 0.30
        case .silver: return 0.20
        case .gold: return 0.36
        case .radiantGold: return 0.46
        case .platinum: return 0.16
        case .crystal: return 0.58
        case .legendary: return 0.42
        }
    }

    private func streakMedalCoreFacetOpacity(for level: RewardEngine.StreakMedalVisualLevel) -> Double {
        switch level {
        case .locked: return 0.22
        case .bronze: return 0.22
        case .silver: return 0.18
        case .gold: return 0.28
        case .radiantGold: return 0.34
        case .platinum: return 0.14
        case .crystal: return 0.36
        case .legendary: return 0.30
        }
    }

    private func streakMedalShellStrokeOpacity(for level: RewardEngine.StreakMedalVisualLevel) -> Double {
        switch level {
        case .locked: return 0.52
        case .bronze: return 0.56
        case .silver: return 0.54
        case .gold: return 0.60
        case .radiantGold: return 0.70
        case .platinum: return 0.42
        case .crystal: return 0.78
        case .legendary: return 0.76
        }
    }

    private func streakMedalCoreGlowOpacity(for level: RewardEngine.StreakMedalVisualLevel) -> Double {
        switch level {
        case .locked: return 0.22
        case .bronze: return 0.26
        case .silver: return 0.24
        case .gold: return 0.30
        case .radiantGold: return 0.36
        case .platinum: return 0.18
        case .crystal: return 0.44
        case .legendary: return 0.40
        }
    }

    private func streakMedalSceneBackdrop(style: StreakMedalStyle) -> some View {
        ZStack {
            RadialGradient(
                colors: [style.glowColor.opacity(0.34), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [style.beamColor.opacity(0.18), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 250
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 140, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, style.beamColor.opacity(0.34), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 180, height: 460)
                .rotationEffect(.degrees(28))
                .offset(x: 118, y: -160)
                .blur(radius: 14)

            RoundedRectangle(cornerRadius: 120, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.white.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 130, height: 360)
                .rotationEffect(.degrees(-30))
                .offset(x: -126, y: -70)
                .blur(radius: 18)

            RoundedRectangle(cornerRadius: 90, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clear, style.sparkleColor.opacity(0.14), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 96, height: 280)
                .rotationEffect(.degrees(32))
                .offset(x: 86, y: 68)
                .blur(radius: 16)

            ForEach(Array(streakMedalSparklePoints.enumerated()), id: \.offset) { index, point in
                Circle()
                    .fill(index.isMultiple(of: 3) ? Color.white.opacity(0.95) : style.sparkleColor.opacity(0.82))
                    .frame(width: point.size, height: point.size)
                    .shadow(color: style.glowColor.opacity(0.38), radius: 6)
                    .offset(x: point.x, y: point.y)
            }
        }
    }

    private var streakMedalSparklePoints: [(x: CGFloat, y: CGFloat, size: CGFloat)] {
        [
            (122, -188, 3),
            (104, -152, 4),
            (136, -136, 2.5),
            (88, -124, 2),
            (154, -116, 2.5),
            (117, -98, 3.5),
            (146, -84, 2),
            (100, -70, 2.5),
            (164, -56, 1.8),
            (72, -40, 2),
            (150, 38, 2.5),
            (132, 64, 2),
            (-112, 118, 1.8),
            (-84, 154, 2.3)
        ]
    }

    private func evaluateStreakMedalUnlock(bestStreak: Int) {
#if DEBUG
        if isDebugStreakMedalPreviewEnabled {
            return
        }
#endif
        let unlockedTier = RewardEngine.highestUnlockedStreakTier(bestStreak: bestStreak) ?? 0
        let lastPresentedTier = sharedDefaults.integer(forKey: OnlyLockShared.settingsLastPresentedStreakMedalTierKey)

        guard unlockedTier > lastPresentedTier else { return }

        sharedDefaults.set(unlockedTier, forKey: OnlyLockShared.settingsLastPresentedStreakMedalTierKey)
        presentStreakMedalUnlock(tier: unlockedTier)
    }

    private func presentStreakMedalUnlock(tier: Int) {
        streakMedalDismissTask?.cancel()
        withAnimation {
            activeStreakMedalUnlockTier = tier
        }

        streakMedalDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissStreakMedalUnlock()
            }
        }
    }

    private func dismissStreakMedalUnlock() {
        streakMedalDismissTask?.cancel()
        streakMedalDismissTask = nil
        withAnimation {
            activeStreakMedalUnlockTier = nil
        }
    }

    @MainActor
    private func consumePendingQuickActionIfNeeded() {
        guard let action = quickActionRouter.consumePendingAction() else { return }
        handleQuickAction(action)
    }

    @MainActor
    private func consumePendingWeeklyInsightsRouteIfNeeded() {
        guard let route = quickActionRouter.consumePendingWeeklyInsightsRoute() else { return }
        handleWeeklyInsightsNotificationRoute(route)
    }

    @MainActor
    private func handleQuickAction(_ action: AppQuickAction) {
        switch action {
        case .createLockTask:
            selectedTab = .create
            guard hasActiveMembership else {
                presentMembershipRenewal()
                return
            }
            pendingAuthorizationAction = .appPicker
            preAuthorizationContext = .appSelection
            startAuthorizationFlow(for: .appPicker)
        case .viewScreenTime:
            selectedTab = .rewards
            guard hasActiveMembership else {
                presentMembershipRenewal()
                return
            }
            scheduleInsightsReportReload(force: true)
        case .shareApp:
            Task {
                await presentShareAppSheet()
            }
        }
    }

    @MainActor
    private func handleWeeklyInsightsNotificationRoute(_ route: AppQuickActionRouter.WeeklyInsightsRoute) {
        selectedTab = .rewards
        guard hasActiveMembership else {
            presentMembershipRenewal()
            return
        }
        let targetWeekStart = route.weekStart ?? OnlyLockShared.resolvedNow(defaults: sharedDefaults, fallback: Date())
        selectedInsightsScope = .week
        insightsAnchorDate = targetWeekStart
        scheduleInsightsReportReload(force: true)
        let normalizedWeekStart = startOfWeekMonday(containing: targetWeekStart)
        sharedDefaults.set(normalizedWeekStart.timeIntervalSince1970, forKey: OnlyLockShared.weeklyDigestSelectedWeekStartKey)
        let existing = sharedDefaults.array(forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey) as? [Int] ?? []
        let updated = Array(Set(existing + [Int(normalizedWeekStart.timeIntervalSince1970)])).sorted(by: >)
        sharedDefaults.set(updated, forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey)
        sharedDefaults.synchronize()
        markWeeklyReportAsRead(weekStart: normalizedWeekStart)
        activeWeeklyDigestRoute = WeeklyDigestRoute(weekStart: normalizedWeekStart)
    }

    private func streakMedalStyle(for level: RewardEngine.StreakMedalVisualLevel) -> StreakMedalStyle {
        switch level {
        case .locked:
            return StreakMedalStyle(
                cardTop: Color(red: 0.06, green: 0.10, blue: 0.20),
                cardBottom: Color(red: 0.02, green: 0.05, blue: 0.12),
                cardEdge: Color(red: 0.46, green: 0.60, blue: 0.82),
                shellTop: Color(red: 0.86, green: 0.90, blue: 0.96),
                shellMiddle: Color(red: 0.61, green: 0.68, blue: 0.78),
                shellBottom: Color(red: 0.34, green: 0.40, blue: 0.50),
                coreTop: Color(red: 0.89, green: 0.92, blue: 0.97),
                coreBottom: Color(red: 0.67, green: 0.73, blue: 0.82),
                numberColor: Color(red: 0.13, green: 0.16, blue: 0.24),
                ringColor: Color(red: 0.78, green: 0.85, blue: 0.95),
                ringCount: 0,
                glowColor: Color.white,
                glowOpacity: 0.10,
                glowRadius: 10,
                beamColor: Color(red: 0.62, green: 0.76, blue: 0.94),
                sparkleColor: Color(red: 0.88, green: 0.95, blue: 1.00),
                buttonTop: Color(red: 0.28, green: 0.43, blue: 0.75),
                buttonBottom: Color(red: 0.16, green: 0.26, blue: 0.56),
                buttonText: .white
            )
        case .bronze:
            return StreakMedalStyle(
                cardTop: Color(red: 0.12, green: 0.09, blue: 0.15),
                cardBottom: Color(red: 0.06, green: 0.05, blue: 0.10),
                cardEdge: Color(red: 0.86, green: 0.60, blue: 0.40),
                shellTop: Color(red: 0.96, green: 0.77, blue: 0.58),
                shellMiddle: Color(red: 0.77, green: 0.52, blue: 0.34),
                shellBottom: Color(red: 0.46, green: 0.25, blue: 0.15),
                coreTop: Color(red: 0.99, green: 0.90, blue: 0.78),
                coreBottom: Color(red: 0.83, green: 0.61, blue: 0.39),
                numberColor: Color(red: 0.19, green: 0.12, blue: 0.08),
                ringColor: Color(red: 0.91, green: 0.70, blue: 0.51),
                ringCount: 0,
                glowColor: Color(red: 0.95, green: 0.66, blue: 0.36),
                glowOpacity: 0.20,
                glowRadius: 9,
                beamColor: Color(red: 0.98, green: 0.77, blue: 0.53),
                sparkleColor: Color(red: 1.00, green: 0.93, blue: 0.84),
                buttonTop: Color(red: 0.83, green: 0.55, blue: 0.29),
                buttonBottom: Color(red: 0.63, green: 0.37, blue: 0.16),
                buttonText: .white
            )
        case .silver:
            return StreakMedalStyle(
                cardTop: Color(red: 0.06, green: 0.10, blue: 0.18),
                cardBottom: Color(red: 0.03, green: 0.06, blue: 0.12),
                cardEdge: Color(red: 0.72, green: 0.84, blue: 0.98),
                shellTop: Color(red: 0.97, green: 0.99, blue: 1.00),
                shellMiddle: Color(red: 0.76, green: 0.82, blue: 0.90),
                shellBottom: Color(red: 0.50, green: 0.60, blue: 0.72),
                coreTop: Color(red: 0.98, green: 0.99, blue: 1.00),
                coreBottom: Color(red: 0.78, green: 0.84, blue: 0.92),
                numberColor: Color(red: 0.14, green: 0.17, blue: 0.24),
                ringColor: Color(red: 0.85, green: 0.88, blue: 0.93),
                ringCount: 0,
                glowColor: Color(red: 0.86, green: 0.90, blue: 0.97),
                glowOpacity: 0.26,
                glowRadius: 11,
                beamColor: Color(red: 0.76, green: 0.88, blue: 1.00),
                sparkleColor: Color(red: 0.95, green: 0.98, blue: 1.00),
                buttonTop: Color(red: 0.42, green: 0.57, blue: 0.83),
                buttonBottom: Color(red: 0.22, green: 0.34, blue: 0.61),
                buttonText: .white
            )
        case .gold:
            return StreakMedalStyle(
                cardTop: Color(red: 0.11, green: 0.09, blue: 0.08),
                cardBottom: Color(red: 0.05, green: 0.04, blue: 0.03),
                cardEdge: Color(red: 0.99, green: 0.84, blue: 0.42),
                shellTop: Color(red: 1.00, green: 0.95, blue: 0.63),
                shellMiddle: Color(red: 0.96, green: 0.78, blue: 0.27),
                shellBottom: Color(red: 0.71, green: 0.49, blue: 0.08),
                coreTop: Color(red: 1.00, green: 0.98, blue: 0.82),
                coreBottom: Color(red: 0.96, green: 0.83, blue: 0.45),
                numberColor: Color(red: 0.21, green: 0.15, blue: 0.04),
                ringColor: Color(red: 0.98, green: 0.83, blue: 0.35),
                ringCount: 0,
                glowColor: Color(red: 0.99, green: 0.84, blue: 0.30),
                glowOpacity: 0.30,
                glowRadius: 12,
                beamColor: Color(red: 1.00, green: 0.88, blue: 0.38),
                sparkleColor: Color(red: 1.00, green: 0.96, blue: 0.81),
                buttonTop: Color(red: 0.95, green: 0.73, blue: 0.16),
                buttonBottom: Color(red: 0.77, green: 0.55, blue: 0.05),
                buttonText: .white
            )
        case .radiantGold:
            return StreakMedalStyle(
                cardTop: Color(red: 0.14, green: 0.11, blue: 0.04),
                cardBottom: Color(red: 0.06, green: 0.04, blue: 0.01),
                cardEdge: Color(red: 1.00, green: 0.87, blue: 0.34),
                shellTop: Color(red: 1.00, green: 0.98, blue: 0.70),
                shellMiddle: Color(red: 1.00, green: 0.82, blue: 0.26),
                shellBottom: Color(red: 0.80, green: 0.55, blue: 0.05),
                coreTop: Color(red: 1.00, green: 0.99, blue: 0.86),
                coreBottom: Color(red: 0.99, green: 0.86, blue: 0.48),
                numberColor: Color(red: 0.26, green: 0.17, blue: 0.02),
                ringColor: Color(red: 1.00, green: 0.84, blue: 0.24),
                ringCount: 1,
                glowColor: Color(red: 1.00, green: 0.84, blue: 0.28),
                glowOpacity: 0.36,
                glowRadius: 16,
                beamColor: Color(red: 1.00, green: 0.91, blue: 0.42),
                sparkleColor: Color(red: 1.00, green: 0.97, blue: 0.84),
                buttonTop: Color(red: 1.00, green: 0.80, blue: 0.16),
                buttonBottom: Color(red: 0.87, green: 0.60, blue: 0.03),
                buttonText: .white
            )
        case .platinum:
            return StreakMedalStyle(
                cardTop: Color(red: 0.03, green: 0.09, blue: 0.22),
                cardBottom: Color(red: 0.01, green: 0.04, blue: 0.13),
                cardEdge: Color(red: 0.56, green: 0.78, blue: 1.00),
                shellTop: Color(red: 0.92, green: 0.98, blue: 1.00),
                shellMiddle: Color(red: 0.62, green: 0.84, blue: 1.00),
                shellBottom: Color(red: 0.27, green: 0.46, blue: 0.82),
                coreTop: Color(red: 0.97, green: 1.00, blue: 1.00),
                coreBottom: Color(red: 0.78, green: 0.88, blue: 1.00),
                numberColor: Color(red: 0.11, green: 0.18, blue: 0.27),
                ringColor: Color(red: 0.82, green: 0.92, blue: 0.99),
                ringCount: 1,
                glowColor: Color(red: 0.70, green: 0.84, blue: 0.98),
                glowOpacity: 0.34,
                glowRadius: 18,
                beamColor: Color(red: 0.54, green: 0.80, blue: 1.00),
                sparkleColor: Color(red: 0.88, green: 0.97, blue: 1.00),
                buttonTop: Color(red: 0.34, green: 0.63, blue: 0.97),
                buttonBottom: Color(red: 0.16, green: 0.35, blue: 0.74),
                buttonText: .white
            )
        case .crystal:
            return StreakMedalStyle(
                cardTop: Color(red: 0.02, green: 0.10, blue: 0.24),
                cardBottom: Color(red: 0.00, green: 0.04, blue: 0.14),
                cardEdge: Color(red: 0.58, green: 0.84, blue: 1.00),
                shellTop: Color(red: 0.87, green: 0.98, blue: 1.00),
                shellMiddle: Color(red: 0.46, green: 0.79, blue: 1.00),
                shellBottom: Color(red: 0.12, green: 0.36, blue: 0.82),
                coreTop: Color(red: 0.95, green: 1.00, blue: 1.00),
                coreBottom: Color(red: 0.76, green: 0.89, blue: 1.00),
                numberColor: Color(red: 0.07, green: 0.17, blue: 0.29),
                ringColor: Color(red: 0.61, green: 0.88, blue: 1.00),
                ringCount: 2,
                glowColor: Color(red: 0.56, green: 0.84, blue: 1.00),
                glowOpacity: 0.38,
                glowRadius: 20,
                beamColor: Color(red: 0.44, green: 0.86, blue: 1.00),
                sparkleColor: Color(red: 0.90, green: 0.98, blue: 1.00),
                buttonTop: Color(red: 0.30, green: 0.67, blue: 1.00),
                buttonBottom: Color(red: 0.10, green: 0.36, blue: 0.82),
                buttonText: .white
            )
        case .legendary:
            return StreakMedalStyle(
                cardTop: Color(red: 0.03, green: 0.09, blue: 0.22),
                cardBottom: Color(red: 0.01, green: 0.03, blue: 0.12),
                cardEdge: Color(red: 0.76, green: 0.94, blue: 1.00),
                shellTop: Color(red: 1.00, green: 0.99, blue: 0.93),
                shellMiddle: Color(red: 0.70, green: 0.95, blue: 1.00),
                shellBottom: Color(red: 0.25, green: 0.61, blue: 0.92),
                coreTop: Color(red: 1.00, green: 0.99, blue: 0.94),
                coreBottom: Color(red: 0.98, green: 0.89, blue: 0.68),
                numberColor: Color(red: 0.10, green: 0.16, blue: 0.28),
                ringColor: Color(red: 0.90, green: 0.97, blue: 1.00),
                ringCount: 2,
                glowColor: Color(red: 0.86, green: 0.96, blue: 1.00),
                glowOpacity: 0.46,
                glowRadius: 24,
                beamColor: Color(red: 0.64, green: 0.93, blue: 1.00),
                sparkleColor: Color(red: 1.00, green: 0.98, blue: 0.88),
                buttonTop: Color(red: 0.41, green: 0.77, blue: 0.99),
                buttonBottom: Color(red: 0.17, green: 0.45, blue: 0.80),
                buttonText: .white
            )
        }
    }

    private struct StreakMedalStyle {
        let cardTop: Color
        let cardBottom: Color
        let cardEdge: Color
        let shellTop: Color
        let shellMiddle: Color
        let shellBottom: Color
        let coreTop: Color
        let coreBottom: Color
        let numberColor: Color
        let ringColor: Color
        let ringCount: Int
        let glowColor: Color
        let glowOpacity: Double
        let glowRadius: CGFloat
        let beamColor: Color
        let sparkleColor: Color
        let buttonTop: Color
        let buttonBottom: Color
        let buttonText: Color
    }

    private var rewardsTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rewardsTopBar

                if hasActiveMembership {
                    VStack(alignment: .leading, spacing: 16) {
                        insightsScopePicker
                        if authorizationService.isApproved {
                            insightsRangeHeader
                        }
                        insightsReportView
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                } else {
                    membershipExpiredGateView(
                        subtitle: "续费后继续查看屏幕时间分析与每周报告。"
                    )
                }
            }
            .background(pageBackground.ignoresSafeArea())
        }
    }

    private struct WeeklyInsightsHistoryItem: Identifiable {
        let id: String
        let weekStart: Date
        let snapshot: ScreenTimeInsightsSnapshot?
    }

    private struct WeeklyDigestRoute: Identifiable {
        let weekStart: Date

        var id: String {
            String(Int(weekStart.timeIntervalSince1970))
        }
    }

    private struct WeeklyReportPresentation: Identifiable {
        let id: String
        let current: ScreenTimeInsightsSnapshot
        let previous: ScreenTimeInsightsSnapshot?
    }

    private var weeklyInsightsHistoryItems: [WeeklyInsightsHistoryItem] {
        let deletedWeekStarts = weeklyReportDeletedWeekStartTimestamps
        var mergedByWeekStart = trendDerivedWeeklySnapshotsByWeekStart

        for (weekStart, snapshot) in groupedWeeklySnapshotsByWeekStart {
            guard hasWeeklyReportData(snapshot) else { continue }
            mergedByWeekStart[weekStart] = snapshot
        }

        let snapshotItems = mergedByWeekStart.keys.sorted(by: >).compactMap { weekStart -> WeeklyInsightsHistoryItem? in
            guard let current = mergedByWeekStart[weekStart] else { return nil }
            let previousWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart)
            let previous = previousWeekStart.flatMap { mergedByWeekStart[$0] }
            let enriched = ScreenTimeInsightsSnapshot(
                scope: current.scope,
                rangeStart: current.rangeStart,
                rangeEnd: current.rangeEnd,
                totalMinutes: current.totalMinutes,
                averageMinutes: current.averageMinutes,
                previousTotalMinutes: previous?.totalMinutes ?? current.previousTotalMinutes,
                buckets: current.buckets,
                topTargets: current.topTargets,
                topCategories: current.topCategories,
                generatedAt: current.generatedAt
            )
            guard hasWeeklyReportData(enriched) else { return nil }
            return WeeklyInsightsHistoryItem(
                id: "\(weekStart.timeIntervalSince1970)",
                weekStart: weekStart,
                snapshot: enriched
            )
        }

        let existingWeekStarts = Set(mergedByWeekStart.keys.map { Int($0.timeIntervalSince1970) })
        let indexedItems = historyIndexedWeekStarts
            .filter { !existingWeekStarts.contains(Int($0.timeIntervalSince1970)) }
            .map { weekStart in
                WeeklyInsightsHistoryItem(
                    id: "indexed.\(Int(weekStart.timeIntervalSince1970))",
                    weekStart: weekStart,
                    snapshot: historySnapshot(forWeekStart: weekStart)
                )
            }

        return (snapshotItems + indexedItems)
            .filter { !deletedWeekStarts.contains(Int(startOfWeekMonday(containing: $0.weekStart).timeIntervalSince1970)) }
            .sorted { $0.weekStart > $1.weekStart }
    }

    private var weeklyReportUnreadWeekStartTimestamps: Set<Int> {
        _ = weeklyReportUnreadRevision
        let values = sharedDefaults.array(forKey: OnlyLockShared.weeklyReportReadWeekStartsKey) as? [Int] ?? []
        return Set(values)
    }

    private var weeklyReportDeletedWeekStartTimestamps: Set<Int> {
        _ = weeklyReportUnreadRevision
        let values = sharedDefaults.array(forKey: OnlyLockShared.weeklyReportDeletedWeekStartsKey) as? [Int] ?? []
        return Set(values)
    }

    private var weeklyReportUnreadCount: Int {
        return weeklyInsightsHistoryItems.reduce(into: 0) { count, item in
            if isWeeklyReportUnread(weekStart: item.weekStart) {
                count += 1
            }
        }
    }

    private var trendDerivedWeeklySnapshotsByWeekStart: [Date: ScreenTimeInsightsSnapshot] {
        guard let trendSnapshot = latestTrendSnapshot else { return [:] }

        let calendar = Calendar.current
        let firstWeekStart = startOfWeekMonday(containing: trendSnapshot.rangeStart)
        var derived: [Date: ScreenTimeInsightsSnapshot] = [:]

        for (index, bucket) in trendSnapshot.buckets.enumerated() {
            guard bucket.totalMinutes > 0,
                  let weekStart = calendar.date(byAdding: .day, value: index * 7, to: firstWeekStart) else {
                continue
            }

            let previousTotal = index > 0 ? trendSnapshot.buckets[index - 1].totalMinutes : 0
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
            derived[weekStart] = ScreenTimeInsightsSnapshot(
                scope: "week",
                rangeStart: weekStart,
                rangeEnd: weekEnd,
                totalMinutes: bucket.totalMinutes,
                averageMinutes: bucket.totalMinutes / 7,
                previousTotalMinutes: previousTotal,
                buckets: [],
                topTargets: [],
                topCategories: [],
                generatedAt: trendSnapshot.generatedAt
            )
        }

        return derived
    }

    private var latestTrendSnapshot: ScreenTimeInsightsSnapshot? {
        screenTimeInsightsStore.snapshotsByKey.values
            .filter { $0.scope == "trend" }
            .sorted { lhs, rhs in lhs.generatedAt > rhs.generatedAt }
            .first
    }

    private var historyIndexedWeekStarts: [Date] {
        let historyIndexDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? sharedDefaults
        let normalized = (historyIndexDefaults.array(forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey) as? [Int] ?? [])
            .map { startOfWeekMonday(containing: Date(timeIntervalSince1970: TimeInterval($0))) }
            .sorted(by: >)

        var seen = Set<Int>()
        return normalized.filter { date in
            let key = Int(date.timeIntervalSince1970)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private var groupedWeeklySnapshotsByWeekStart: [Date: ScreenTimeInsightsSnapshot] {
        var grouped: [Date: ScreenTimeInsightsSnapshot] = [:]
        for snapshot in screenTimeInsightsStore.snapshotsByKey.values where snapshot.scope == "week" {
            let weekStart = startOfWeekMonday(containing: snapshot.rangeStart)
            if let existing = grouped[weekStart], existing.generatedAt >= snapshot.generatedAt {
                continue
            }
            grouped[weekStart] = snapshot
        }
        return grouped
    }

    private var historyWeekStartCandidates: [Date] {
        let normalizedFromSnapshots = screenTimeInsightsStore.snapshotsByKey.values
            .filter { $0.scope == "week" }
            .map { startOfWeekMonday(containing: $0.rangeStart) }

        let normalizedFromIndex = historyIndexedWeekStarts

        let normalizedFromFallback = weeklyInsightsHistoryCandidateWeekStarts
            .map { startOfWeekMonday(containing: $0) }

        var seen = Set<Int>()
        let ordered = (normalizedFromSnapshots + normalizedFromIndex + normalizedFromFallback)
            .sorted(by: { $0 > $1 })
            .filter { date in
                let key = Int(date.timeIntervalSince1970)
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
        return ordered
    }

    private var weeklyInsightsHistoryCandidateWeekStarts: [Date] {
        let calendar = Calendar.current
        let currentWeekStart = startOfWeekMonday(containing: Date())
        return (0..<8).compactMap { offset in
            calendar.date(byAdding: .day, value: -7 * offset, to: currentWeekStart)
        }
    }

    private func hasWeeklyReportData(_ snapshot: ScreenTimeInsightsSnapshot) -> Bool {
        if snapshot.totalMinutes > 0 { return true }
        if snapshot.previousTotalMinutes > 0 { return true }
        if snapshot.buckets.contains(where: { $0.totalMinutes > 0 }) { return true }
        return snapshot.topTargets.contains(where: { $0.minutes > 0 })
    }

    private func historySnapshot(forWeekStart weekStart: Date) -> ScreenTimeInsightsSnapshot? {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let previousWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: normalizedWeekStart) ?? normalizedWeekStart

        let current = weeklySnapshot(forWeekStart: normalizedWeekStart) ?? synthesizedWeeklySnapshot(forWeekStart: normalizedWeekStart)
        let previous = weeklySnapshot(forWeekStart: previousWeekStart) ?? synthesizedWeeklySnapshot(forWeekStart: previousWeekStart)

        guard let current else { return nil }

        let enriched = ScreenTimeInsightsSnapshot(
            scope: current.scope,
            rangeStart: current.rangeStart,
            rangeEnd: current.rangeEnd,
            totalMinutes: current.totalMinutes,
            averageMinutes: current.averageMinutes,
            previousTotalMinutes: previous?.totalMinutes ?? current.previousTotalMinutes,
            buckets: current.buckets,
            topTargets: current.topTargets,
            topCategories: current.topCategories,
            generatedAt: current.generatedAt
        )

        return hasWeeklyReportData(enriched) ? enriched : nil
    }

    private func weeklyReportReleaseDate(for weekStart: Date) -> Date {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let releaseAnchor = Calendar.current.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart
        var components = Calendar.current.dateComponents([.year, .month, .day], from: releaseAnchor)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components) ?? releaseAnchor
    }

    private func isWeeklyReportUnread(weekStart: Date) -> Bool {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let timestamp = Int(normalizedWeekStart.timeIntervalSince1970)
        return !weeklyReportUnreadWeekStartTimestamps.contains(timestamp)
    }

    private func markWeeklyReportAsRead(weekStart: Date) {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let timestamp = Int(normalizedWeekStart.timeIntervalSince1970)
        let existing = Set(sharedDefaults.array(forKey: OnlyLockShared.weeklyReportReadWeekStartsKey) as? [Int] ?? [])
        guard !existing.contains(timestamp) else { return }
        sharedDefaults.set(Array(existing.union([timestamp])).sorted(by: >), forKey: OnlyLockShared.weeklyReportReadWeekStartsKey)
        let previousBadgeCount = max(0, sharedDefaults.integer(forKey: OnlyLockShared.notificationBadgeCountKey))
        let nextBadgeCount = max(0, previousBadgeCount - 1)
        sharedDefaults.set(nextBadgeCount, forKey: OnlyLockShared.notificationBadgeCountKey)
        sharedDefaults.synchronize()
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(nextBadgeCount) { _ in }
        } else {
            UIApplication.shared.applicationIconBadgeNumber = nextBadgeCount
        }
        weeklyReportUnreadRevision &+= 1
    }

    private func deleteWeeklyReportFromHistory(weekStart: Date) {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        if isWeeklyReportUnread(weekStart: normalizedWeekStart) {
            markWeeklyReportAsRead(weekStart: normalizedWeekStart)
        }

        let timestamp = Int(normalizedWeekStart.timeIntervalSince1970)
        let existing = Set(sharedDefaults.array(forKey: OnlyLockShared.weeklyReportDeletedWeekStartsKey) as? [Int] ?? [])
        guard !existing.contains(timestamp) else { return }
        sharedDefaults.set(Array(existing.union([timestamp])).sorted(by: >), forKey: OnlyLockShared.weeklyReportDeletedWeekStartsKey)
        sharedDefaults.synchronize()
        weeklyReportUnreadRevision &+= 1
    }

    private func synthesizedWeeklySnapshot(forWeekStart weekStart: Date) -> ScreenTimeInsightsSnapshot? {
        let calendar = Calendar.current
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart

        let daySnapshots = screenTimeInsightsStore.snapshotsByKey.values
            .filter { snapshot in
                snapshot.scope == "day" &&
                snapshot.rangeStart >= normalizedWeekStart &&
                snapshot.rangeStart < weekEnd
            }

        var latestByDay: [Date: ScreenTimeInsightsSnapshot] = [:]
        for snapshot in daySnapshots {
            let dayStart = calendar.startOfDay(for: snapshot.rangeStart)
            if let existing = latestByDay[dayStart], existing.generatedAt >= snapshot.generatedAt {
                continue
            }
            latestByDay[dayStart] = snapshot
        }

        let orderedDays = latestByDay.keys.sorted()
        guard !orderedDays.isEmpty else { return nil }

        let labels = AppLanguageRuntime.currentLanguage == .english
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["一", "二", "三", "四", "五", "六", "日"]
        let buckets: [ScreenTimeInsightsBucket] = (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: normalizedWeekStart) ?? normalizedWeekStart
            let dayStart = calendar.startOfDay(for: day)
            let snapshot = latestByDay[dayStart]
            let totalMinutes = snapshot?.totalMinutes ?? 0
            return ScreenTimeInsightsBucket(
                id: "week.\(offset)",
                label: labels[offset],
                appMinutes: totalMinutes,
                webMinutes: 0
            )
        }

        var targetMinutes: [String: ScreenTimeInsightsTarget] = [:]
        var categoryMinutes: [String: ScreenTimeInsightsTarget] = [:]
        for snapshot in latestByDay.values {
            for target in snapshot.topTargets {
                let key = "\(target.kind.rawValue).\(target.name.lowercased())"
                let existing = targetMinutes[key]
                targetMinutes[key] = ScreenTimeInsightsTarget(
                    id: existing?.id ?? target.id,
                    name: target.name,
                    minutes: (existing?.minutes ?? 0) + target.minutes,
                    kind: target.kind,
                    applicationToken: existing?.applicationToken ?? target.applicationToken,
                    categoryToken: existing?.categoryToken ?? target.categoryToken
                )
            }

            for category in snapshot.topCategories {
                let key = stableInsightsCategoryKey(token: category.categoryToken, fallbackName: category.name)
                let existing = categoryMinutes[key]
                categoryMinutes[key] = ScreenTimeInsightsTarget(
                    id: existing?.id ?? category.id,
                    name: category.name,
                    minutes: (existing?.minutes ?? 0) + category.minutes,
                    kind: .category,
                    applicationToken: existing?.applicationToken ?? category.applicationToken,
                    categoryToken: existing?.categoryToken ?? category.categoryToken
                )
            }
        }

        let topTargets = targetMinutes.values
            .sorted { lhs, rhs in
                if lhs.minutes == rhs.minutes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.minutes > rhs.minutes
            }
        let topCategories = categoryMinutes.values
            .sorted { lhs, rhs in
                if lhs.minutes == rhs.minutes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.minutes > rhs.minutes
            }

        let totalMinutes = buckets.reduce(0) { $0 + $1.totalMinutes }
        let generatedAt = latestByDay.values.map(\.generatedAt).max() ?? Date.distantPast

        return ScreenTimeInsightsSnapshot(
            scope: "week",
            rangeStart: normalizedWeekStart,
            rangeEnd: weekEnd,
            totalMinutes: totalMinutes,
            averageMinutes: totalMinutes / 7,
            previousTotalMinutes: 0,
            buckets: buckets,
            topTargets: Array(topTargets.prefix(12)),
            topCategories: Array(topCategories),
            generatedAt: generatedAt
        )
    }

    private func stableInsightsCategoryKey(
        token: ActivityCategoryToken?,
        fallbackName: String
    ) -> String {
        if let canonical = canonicalInsightsCategoryKey(for: fallbackName) {
            return "category.canonical.\(canonical)"
        }
        if let token,
           let data = try? JSONEncoder().encode(token) {
            return "category.token.\(data.base64EncodedString())"
        }
        return "category.name.\(fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func canonicalInsightsCategoryKey(for rawName: String) -> String? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if name.contains("社交") ||
            name.contains("social") ||
            name.contains("network") ||
            name.contains("chat") ||
            name.contains("message") ||
            name.contains("messages") ||
            name.contains("sticker") ||
            name.contains("通讯") {
            return "social"
        }
        if name.contains("游戏") ||
            name.contains("game") ||
            name.contains("gaming") ||
            name.contains("arcade") ||
            name.contains("action") ||
            name.contains("adventure") ||
            name.contains("board") ||
            name.contains("casino") ||
            name.contains("casual") ||
            name.contains("family game") ||
            name.contains("music game") ||
            name.contains("puzzle") ||
            name.contains("racing") ||
            name.contains("role playing") ||
            name.contains("simulation") ||
            name.contains("strategy") ||
            name.contains("trivia") ||
            name.contains("word game") ||
            name.contains("益智") ||
            name.contains("动作") ||
            name.contains("冒险") ||
            name.contains("桌游") ||
            name.contains("棋牌") ||
            name.contains("卡牌") ||
            name.contains("休闲") ||
            name.contains("竞速") ||
            name.contains("角色扮演") ||
            name.contains("模拟") ||
            name.contains("策略") ||
            name.contains("问答") ||
            name.contains("文字游戏") {
            return "games"
        }
        if name.contains("娱乐") ||
            name.contains("entertainment") ||
            name.contains("video") ||
            name.contains("stream") ||
            name.contains("music") ||
            name.contains("tv") ||
            name.contains("movie") ||
            name.contains("音频") ||
            name.contains("影视") ||
            name.contains("音乐") {
            return "entertainment"
        }
        if name.contains("信息") ||
            name.contains("阅读") ||
            name.contains("read") ||
            name.contains("news") ||
            name.contains("book") ||
            name.contains("reference") ||
            name.contains("magazine") ||
            name.contains("newspaper") ||
            name.contains("books") ||
            name.contains("图书") ||
            name.contains("新闻") ||
            name.contains("报纸") ||
            name.contains("杂志") ||
            name.contains("参考") {
            return "information"
        }
        if name.contains("健康") ||
            name.contains("健身") ||
            name.contains("health") ||
            name.contains("fitness") ||
            name.contains("medical") ||
            name.contains("sports") ||
            name.contains("sport") ||
            name.contains("医疗") ||
            name.contains("体育") ||
            name.contains("运动") {
            return "health"
        }
        if name.contains("创意") ||
            name.contains("creative") ||
            name.contains("art") ||
            name.contains("drawing") ||
            name.contains("illustration") ||
            name.contains("animation") ||
            name.contains("camera") ||
            name.contains("editor") ||
            name.contains("graphics") ||
            name.contains("photo") ||
            name.contains("design") ||
            name.contains("video photo") ||
            name.contains("graphics & design") ||
            name.contains("photo & video") ||
            name.contains("摄影") ||
            name.contains("照片") ||
            name.contains("录像") ||
            name.contains("图形") ||
            name.contains("设计") ||
            name.contains("艺术") ||
            name.contains("绘画") ||
            name.contains("插画") ||
            name.contains("动画") ||
            name.contains("相机") ||
            name.contains("编辑") {
            return "creativity"
        }
        if name.contains("工具") ||
            name.contains("utility") ||
            name.contains("utilities") ||
            name.contains("developer") ||
            name.contains("productivity tools") ||
            name.contains("developer tools") ||
            name.contains("reference tools") ||
            name.contains("weather") ||
            name.contains("天气") ||
            name.contains("开发工具") {
            return "utilities"
        }
        if name.contains("效率") ||
            name.contains("财务") ||
            name.contains("productivity") ||
            name.contains("finance") ||
            name.contains("business") ||
            name.contains("商务") {
            return "productivity"
        }
        if name.contains("教育") ||
            name.contains("education") ||
            name.contains("learning") ||
            name.contains("study") ||
            name.contains("course") ||
            name.contains("classroom") ||
            name.contains("student") ||
            name.contains("kids") ||
            name.contains("学习") ||
            name.contains("课程") ||
            name.contains("课堂") ||
            name.contains("学生") ||
            name.contains("儿童") {
            return "education"
        }
        if name.contains("旅行") ||
            name.contains("travel") ||
            name.contains("local") ||
            name.contains("trip") ||
            name.contains("tour") ||
            name.contains("tourism") ||
            name.contains("hotel") ||
            name.contains("flight") ||
            name.contains("airline") ||
            name.contains("transport") ||
            name.contains("transit") ||
            name.contains("navigation") ||
            name.contains("地图") ||
            name.contains("nav") ||
            name.contains("出行") ||
            name.contains("旅游") ||
            name.contains("酒店") ||
            name.contains("航班") ||
            name.contains("航空") ||
            name.contains("交通") ||
            name.contains("本地") {
            return "travel"
        }
        if name.contains("购物") ||
            name.contains("美食") ||
            name.contains("shopping") ||
            name.contains("food") ||
            name.contains("drink") ||
            name.contains("餐") ||
            name.contains("catalog") ||
            name.contains("food & drink") ||
            name.contains("美食佳饮") ||
            name.contains("餐饮") ||
            name.contains("目录") {
            return "shoppingFood"
        }
        if name.contains("其他") || name == "other" || name.contains("misc") || name.contains("miscellaneous") {
            return "other"
        }
        if name.contains("生活") || name.contains("lifestyle") || name.contains("生活方式") {
            return "other"
        }
        return nil
    }

    private func weeklyReportPresentation(forWeekStart weekStart: Date) -> WeeklyReportPresentation? {
        let targetWeekStart = startOfWeekMonday(containing: weekStart)
#if DEBUG
        if isDebugWeeklyReportDemoEnabled,
           let presentation = savedDebugWeeklyReportPresentation(forWeekStart: targetWeekStart) {
            return presentation
        }
#endif
        let current = weeklySnapshot(forWeekStart: targetWeekStart)

        guard let current else { return nil }
        return weeklyReportPresentation(for: current)
    }

    private func weeklyReportPresentation(for current: ScreenTimeInsightsSnapshot) -> WeeklyReportPresentation {
#if DEBUG
        if isDebugWeeklyReportDemoEnabled,
           let presentation = savedDebugWeeklyReportPresentation(forWeekStart: current.rangeStart) {
            return presentation
        }
#endif
        let previousWeekStart = Calendar.current.date(
            byAdding: .day,
            value: -7,
            to: startOfWeekMonday(containing: current.rangeStart)
        )
        let previous = previousWeekStart.flatMap { weeklySnapshot(forWeekStart: $0) }

        return WeeklyReportPresentation(
            id: "\(current.rangeStart.timeIntervalSince1970)-\(current.rangeEnd.timeIntervalSince1970)",
            current: current,
            previous: previous
        )
    }

    private func fallbackWeeklySnapshot(forWeekStart weekStart: Date) -> ScreenTimeInsightsSnapshot {
        let calendar = Calendar.current
        let start = startOfWeekMonday(containing: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        let buckets: [ScreenTimeInsightsBucket] = labels.enumerated().map { index, label in
            ScreenTimeInsightsBucket(
                id: "week.\(index)",
                label: label,
                appMinutes: 0,
                webMinutes: 0
            )
        }
        return ScreenTimeInsightsSnapshot(
            scope: "week",
            rangeStart: start,
            rangeEnd: end,
            totalMinutes: 0,
            averageMinutes: 0,
            previousTotalMinutes: 0,
            buckets: buckets,
            topTargets: [],
            topCategories: [],
            generatedAt: Date()
        )
    }

    private func persistInsightsSnapshotFallback(_ snapshot: ScreenTimeInsightsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let key = OnlyLockShared.screenTimeInsightsSnapshotKey(
            scope: snapshot.scope,
            rangeStart: snapshot.rangeStart,
            rangeEnd: snapshot.rangeEnd
        )
        sharedDefaults.set(data, forKey: key)
        sharedDefaults.synchronize()
        screenTimeInsightsStore.refresh()
    }

    private var weeklyInsightsHistorySheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(onlyLockL("周报历史"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryText)
                    .padding(.horizontal, 24)

                if weeklyInsightsHistoryItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(secondaryText)

                        Text(onlyLockL("暂无通知"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(primaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                } else {
                    List {
                        ForEach(Array(weeklyInsightsHistoryItems.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 0) {
                                weeklyInsightsHistoryRowContent(item: item)

                                if index != weeklyInsightsHistoryItems.count - 1 {
                                    Rectangle()
                                        .fill(dividerColor.opacity(colorScheme == .dark ? 0.55 : 1))
                                        .frame(height: 0.5)
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    pendingDeletedWeeklyReportWeekStart = startOfWeekMonday(containing: item.weekStart)
                                } label: {
                                    Label(onlyLockL("删除"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .padding(.top, 12)
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle(onlyLockL("通知"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onlyLockL("关闭")) {
                        isWeeklyInsightsHistoryPresented = false
                    }
                }
            }
            .task { screenTimeInsightsStore.refresh() }
        }
        .alert(onlyLockL("是否删除该周报"), isPresented: pendingWeeklyReportDeletionAlertBinding) {
            Button(onlyLockL("取消"), role: .cancel) {
                pendingDeletedWeeklyReportWeekStart = nil
            }
            Button(onlyLockL("确认"), role: .destructive) {
                confirmPendingWeeklyReportDeletion()
            }
        }
        .fullScreenCover(item: $historyActiveWeeklyDigestRoute) { route in
            weeklyDigestReportSheet(for: route.weekStart) {
                historyActiveWeeklyDigestRoute = nil
            }
        }
    }

    private func weeklyInsightsHistoryRowContent(item: WeeklyInsightsHistoryItem) -> some View {
        let now = OnlyLockShared.resolvedNow(defaults: sharedDefaults, fallback: Date())
        let isUnread = isWeeklyReportUnread(weekStart: item.weekStart)
        let releaseDate = weeklyReportReleaseDate(for: item.weekStart)
        let titleRangeText = weeklyInsightsHistoryRangeText(for: item.weekStart)
        return Button {
            let normalizedWeekStart = startOfWeekMonday(containing: item.weekStart)
            sharedDefaults.set(normalizedWeekStart.timeIntervalSince1970, forKey: OnlyLockShared.weeklyDigestSelectedWeekStartKey)
            sharedDefaults.synchronize()
            markWeeklyReportAsRead(weekStart: normalizedWeekStart)
            historyActiveWeeklyDigestRoute = WeeklyDigestRoute(weekStart: normalizedWeekStart)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardBackground)
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "doc.text")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(primaryText)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isUnread {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                        }
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(titleRangeText)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Text(onlyLockL("打开周报"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(secondaryText)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(weeklyInsightsNotificationTimeText(for: releaseDate, now: now))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(secondaryText)

                    HStack(spacing: 10) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(dividerColor)
                    }
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
        }
        .buttonStyle(.plain)
    }

    private func weeklyInsightsHistoryRangeText(for weekStart: Date) -> String {
        let calendar = Calendar.current
        let start = startOfWeekMonday(containing: weekStart)
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        if AppLanguageRuntime.currentLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.dateFormat = "M月d日"
        }
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private func weeklyInsightsNotificationTimeText(for date: Date, now: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDate(date, equalTo: now, toGranularity: .minute) {
            return AppLanguageRuntime.currentLanguage == .english ? "Just now" : "刚刚"
        }

        if calendar.isDateInToday(date) {
            let hours = max(1, calendar.dateComponents([.hour], from: date, to: now).hour ?? 0)
            if AppLanguageRuntime.currentLanguage == .english {
                return hours <= 1 ? "Just now" : "\(hours)h ago"
            }
            return hours <= 1 ? "刚刚" : "\(hours)小时前"
        }

        if calendar.isDateInYesterday(date) {
            return AppLanguageRuntime.currentLanguage == .english ? "Yesterday" : "昨天"
        }

        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        if AppLanguageRuntime.currentLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate(
                calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "MMMd" : "yMMMd"
            )
        } else {
            formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "M月d日" : "yyyy年M月d日"
        }
        return formatter.string(from: date)
    }

    private func weeklyDigestReportSheet(for weekStart: Date, onClose: (() -> Void)? = nil) -> some View {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let previousWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: normalizedWeekStart) ?? normalizedWeekStart
        let range = InsightsRange(
            start: previousWeekStart,
            end: Calendar.current.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart
        )

        return ReportNavigationShell(
            title: AppLanguageRuntime.currentLanguage == .english ? "Weekly Report" : "本周报告",
            foregroundColor: primaryText,
            backgroundColor: pageBackground,
            onClose: onClose
        ) {
            DeviceActivityReport(
                .onlyLockWeeklyDigest,
                filter: insightsFilter(for: .week, range: range)
            )
            .background(pageBackground.ignoresSafeArea())
        }
    }

    private func weeklySnapshot(forWeekStart weekStart: Date) -> ScreenTimeInsightsSnapshot? {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        return screenTimeInsightsStore.snapshotsByKey.values
            .filter { snapshot in
                guard snapshot.scope == "week" else { return false }
                return startOfWeekMonday(containing: snapshot.rangeStart) == normalizedWeekStart
            }
            .sorted { lhs, rhs in lhs.generatedAt > rhs.generatedAt }
            .first
    }

    private func weeklyReportSheet(_ presentation: WeeklyReportPresentation) -> some View {
        let thisWeekHours = weeklyHours(from: presentation.current.buckets)
        let lastWeekHours = weeklyHours(from: presentation.previous?.buckets ?? [])
        let weekLabels = AppLanguageRuntime.currentLanguage == .english
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["一", "二", "三", "四", "五", "六", "日"]
        let dailyAverage = presentation.current.totalMinutes / 7
        let focusScore = weeklyFocusScore(snapshot: presentation.current)
        let scoreDelta = weeklyFocusScoreDelta(current: presentation.current, previous: presentation.previous)
        let topTarget = presentation.current.topTargets.first
        let topTargetText: String = {
            guard let top = topTarget else {
                return AppLanguageRuntime.currentLanguage == .english
                    ? "No top-used target this week yet."
                    : "本周还没有高频使用目标。"
            }
            let targetKindText = top.kind == .app ? "App" : (AppLanguageRuntime.currentLanguage == .english ? "Website" : "网站")
            let targetName = weeklyReportTargetDisplayName(for: top)
            if AppLanguageRuntime.currentLanguage == .english {
                let targetType = top.kind == .app ? "app" : "website"
                return "Top \(targetType) this week: \"\(targetName)\" for \(weeklyShortDuration(top.minutes))"
            }
            return "本周重度使用\(targetKindText)「\(targetName)」共\(weeklyShortDuration(top.minutes))"
        }()

        return ReportNavigationShell(
            title: AppLanguageRuntime.currentLanguage == .english ? "Weekly Report" : "本周报告",
            foregroundColor: primaryText,
            backgroundColor: Color.black,
            onClose: {
                activeWeeklyReport = nil
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .center, spacing: 2) {
                        Text(weeklyDurationText(presentation.current.totalMinutes))
                            .font(.system(size: 52, weight: .heavy))
                            .foregroundStyle(Color.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(AppLanguageRuntime.currentLanguage == .english ? "Total Screen Time" : "总屏幕时间")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.top, 4)

                    weeklyReportLineChart(
                        thisWeekHours: thisWeekHours,
                        lastWeekHours: lastWeekHours,
                        weekLabels: weekLabels
                    )
                    .frame(height: 236)

                    VStack(spacing: 0) {
                        weeklyInsightDivider
                        weeklyInsightRow(icon: "chart.line.uptrend.xyaxis", text: weeklyNightInsightText(from: thisWeekHours))
                        weeklyInsightDivider
                        weeklyInsightRow(
                            icon: "equal.circle",
                            text: AppLanguageRuntime.currentLanguage == .english
                                ? "Average daily usage this week: \(weeklyDurationText(dailyAverage))."
                                : "你本周平均每天使用 \(weeklyDurationText(dailyAverage))。"
                        )
                        weeklyInsightDivider
                        weeklyTopTargetInsightRow(target: topTarget, text: topTargetText)
                        weeklyInsightDivider
                    }

                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            Text(AppLanguageRuntime.currentLanguage == .english ? "Focus Score" : "专注分")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                            Text("\(focusScore)")
                                .font(.system(size: 44, weight: .black))
                                .foregroundStyle(Color.white)
                                .monospacedDigit()
                            Text("/100")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Text(
                            scoreDelta >= 0
                                ? (AppLanguageRuntime.currentLanguage == .english
                                    ? "Up \(scoreDelta) vs last week"
                                    : "较上周提升 \(scoreDelta) 分")
                                : (AppLanguageRuntime.currentLanguage == .english
                                    ? "Down \(abs(scoreDelta)) vs last week"
                                    : "较上周下降 \(abs(scoreDelta)) 分")
                        )
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(scoreDelta >= 0 ? Color(red: 0.72, green: 0.92, blue: 0.64) : Color(red: 0.95, green: 0.64, blue: 0.58))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.vertical, 8)

                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color.black.ignoresSafeArea())
        }
    }

    private struct ReportNavigationShell<Content: View>: View {
        let title: String
        let foregroundColor: Color
        let backgroundColor: Color
        let onClose: (() -> Void)?
        let content: () -> Content

        @Environment(\.dismiss) private var dismiss

        init(
            title: String,
            foregroundColor: Color,
            backgroundColor: Color,
            onClose: (() -> Void)? = nil,
            @ViewBuilder content: @escaping () -> Content
        ) {
            self.title = title
            self.foregroundColor = foregroundColor
            self.backgroundColor = backgroundColor
            self.onClose = onClose
            self.content = content
        }

        var body: some View {
            NavigationStack {
                content()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                if let onClose {
                                    onClose()
                                } else {
                                    dismiss()
                                }
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .foregroundStyle(foregroundColor)
                        }
                    }
            }
            .background(backgroundColor.ignoresSafeArea())
        }
    }

    private var weeklyInsightDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func weeklyInsightRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 22, height: 22)
            Text(onlyLockL(text))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func weeklyTopTargetInsightRow(target: ScreenTimeInsightsTarget?, text: String) -> some View {
        HStack(spacing: 12) {
            weeklyTopTargetLeadingIcon(target: target)
            weeklyTopTargetSentenceView(target: target, fallbackText: text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func weeklyTopTargetSentenceView(target: ScreenTimeInsightsTarget?, fallbackText: String) -> some View {
        if let target, target.kind == .app, let token = target.applicationToken {
            let textColor = Color.white.opacity(0.86)
            let subTextColor = Color.white.opacity(0.72)
            if AppLanguageRuntime.currentLanguage == .english {
                VStack(alignment: .leading, spacing: 2) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("Top app this week for \(weeklyShortDuration(target.minutes))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(subTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Label(token)
                        .labelStyle(.titleOnly)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("本周重度使用 App 共\(weeklyShortDuration(target.minutes))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(subTextColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(onlyLockL(fallbackText))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(2)
        }
    }

    private func weeklyReportTargetDisplayName(for target: ScreenTimeInsightsTarget) -> String {
        let trimmedStoredName = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStoredName.isEmpty && !isApplicationFallbackName(trimmedStoredName) {
            return trimmedStoredName
        }

        if let token = target.applicationToken {
            let application = Application(token: token)
            let fallback = AppLanguageRuntime.currentLanguage == .english ? "Selected App" : "已选应用"
            let rawValue = application.localizedDisplayName ?? trimmedStoredName
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || isApplicationFallbackName(trimmed) ? fallback : trimmed
        }

        return trimmedStoredName
    }

    @ViewBuilder
    private func weeklyTopTargetLeadingIcon(target: ScreenTimeInsightsTarget?) -> some View {
        if let target, target.kind == .app, let token = target.applicationToken {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let target, target.kind == .category, let token = target.categoryToken {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: target.map { $0.kind == .app ? "app.fill" : "globe" } ?? "bolt.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 22, height: 22)
        }
    }

    private func weeklyReportLineChart(thisWeekHours: [Double], lastWeekHours: [Double], weekLabels: [String]) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let leftAxisWidth: CGFloat = 52
            let rightPadding: CGFloat = 18
            let topPadding: CGFloat = 14
            let bottomPadding: CGFloat = 54
            let legendHeight: CGFloat = 26
            let chartWidth = max(1, width - leftAxisWidth - rightPadding)
            let chartHeight = max(1, height - topPadding - bottomPadding - legendHeight)
            let plotOrigin = CGPoint(x: leftAxisWidth, y: topPadding)
            let axisLabelColumnWidth: CGFloat = 26
            let axisLabelLeadingX: CGFloat = 8
            let axisLabelCenterX = axisLabelLeadingX + axisLabelColumnWidth / 2
            let gridStartX = axisLabelLeadingX + axisLabelColumnWidth + 1
            let allValues = thisWeekHours + lastWeekHours
            let maxRaw = max(2.0, allValues.max() ?? 2.0)
            let yMax = max(2.0, ceil(maxRaw / 2.0) * 2.0)

            ZStack(alignment: .topLeading) {
                // horizontal grid
                ForEach(0..<4, id: \.self) { index in
                    let ratio = Double(index) / 3.0
                    let y = plotOrigin.y + chartHeight * CGFloat(1 - ratio)
                    Path { path in
                        path.move(to: CGPoint(x: gridStartX, y: y))
                        path.addLine(to: CGPoint(x: plotOrigin.x + chartWidth, y: y))
                    }
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)

                    Text(index == 0 ? "0" : "\(Int((yMax / 3.0) * Double(index)))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: axisLabelColumnWidth, alignment: .trailing)
                        .position(x: axisLabelCenterX, y: y)
                }

                Text(onlyLockL("小时"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: axisLabelColumnWidth, alignment: .leading)
                    .position(x: gridStartX + axisLabelColumnWidth / 2, y: max(0, plotOrigin.y - 14))

                weeklyLinePath(values: thisWeekHours, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                weeklyLinePath(values: lastWeekHours, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: [4, 4]))

                ForEach(Array(thisWeekHours.enumerated()), id: \.offset) { index, value in
                    let point = weeklyPoint(index: index, value: value, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .position(point)
                }

                ForEach(Array(lastWeekHours.enumerated()), id: \.offset) { index, value in
                    let point = weeklyPoint(index: index, value: value, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 6, height: 6)
                        .position(point)
                }

                ForEach(Array(weekLabels.enumerated()), id: \.offset) { index, label in
                    let x = plotOrigin.x + CGFloat(index) * (chartWidth / 6)
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .position(x: x, y: plotOrigin.y + chartHeight + 20)
                }

                HStack(spacing: 24) {
                    weeklyLegendDot(style: .solid, title: onlyLockL("本周"))
                    weeklyLegendDot(style: .dashed, title: onlyLockL("上周"))
                }
                .frame(width: chartWidth, alignment: .center)
                .position(x: plotOrigin.x + chartWidth / 2, y: plotOrigin.y + chartHeight + 44)
            }
        }
    }

    private enum WeeklyLegendStyle {
        case solid
        case dashed
    }

    private func weeklyLegendDot(style: WeeklyLegendStyle, title: String) -> some View {
        HStack(spacing: 6) {
            if style == .solid {
                Capsule()
                    .fill(Color.white)
                    .frame(width: 22, height: 3)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.45))
                            .frame(width: 4, height: 3)
                    }
                }
                .frame(width: 28, alignment: .leading)
            }

            Text(onlyLockL(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
        }
    }

    private func weeklyLinePath(
        values: [Double],
        yMax: Double,
        origin: CGPoint,
        width: CGFloat,
        height: CGFloat
    ) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }

        for (index, value) in values.enumerated() {
            let point = weeklyPoint(index: index, value: value, yMax: yMax, origin: origin, width: width, height: height)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func weeklyPoint(
        index: Int,
        value: Double,
        yMax: Double,
        origin: CGPoint,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        let safeYMax = max(1, yMax)
        let xStep = width / 6
        let normalized = min(max(value / safeYMax, 0), 1)
        let x = origin.x + CGFloat(index) * xStep
        let y = origin.y + height * CGFloat(1 - normalized)
        return CGPoint(x: x, y: y)
    }

    private func weeklyHours(from buckets: [ScreenTimeInsightsBucket]) -> [Double] {
        if buckets.isEmpty {
            return Array(repeating: 0, count: 7)
        }
        let sorted = buckets.prefix(7).map { Double(max(0, $0.totalMinutes)) / 60.0 }
        if sorted.count < 7 {
            return sorted + Array(repeating: 0, count: 7 - sorted.count)
        }
        return sorted
    }

    private func weeklyDurationText(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let hour = safe / 60
        let minute = safe % 60
        if AppLanguageRuntime.currentLanguage == .english {
            if hour > 0 {
                return minute > 0 ? "\(hour)h \(minute)m" : "\(hour)h"
            }
            return "\(minute)m"
        }
        if hour > 0 {
            return "\(hour)小时\(minute)分钟"
        }
        return "\(minute)分钟"
    }

    private func weeklyShortDuration(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let hour = safe / 60
        let minute = safe % 60
        if AppLanguageRuntime.currentLanguage == .english {
            if hour > 0 {
                return minute > 0 ? "\(hour)h \(minute)m" : "\(hour)h"
            }
            return "\(minute)m"
        }
        if hour > 0 {
            return "\(hour)小时\(minute)分钟"
        }
        return "\(minute)分钟"
    }

    private func weeklyFocusScore(snapshot: ScreenTimeInsightsSnapshot) -> Int {
        let averageDailyHours = max(0, Double(snapshot.totalMinutes)) / 60.0 / 7.0

        func interpolatedScore(
            for hours: Double,
            hourRange: ClosedRange<Double>,
            scoreRange: ClosedRange<Int>
        ) -> Int {
            let span = hourRange.upperBound - hourRange.lowerBound
            guard span > 0 else { return scoreRange.lowerBound }
            let progress = min(max((hours - hourRange.lowerBound) / span, 0), 1)
            let highScore = Double(scoreRange.upperBound)
            let lowScore = Double(scoreRange.lowerBound)
            let value = highScore - progress * (highScore - lowScore)
            return Int(round(value))
        }

        switch averageDailyHours {
        case ..<1.5:
            return interpolatedScore(for: averageDailyHours, hourRange: 0...1.5, scoreRange: 88...100)
        case 1.5..<2.5:
            return interpolatedScore(for: averageDailyHours, hourRange: 1.5...2.5, scoreRange: 75...87)
        case 2.5..<3.5:
            return interpolatedScore(for: averageDailyHours, hourRange: 2.5...3.5, scoreRange: 60...74)
        case 3.5..<5:
            return interpolatedScore(for: averageDailyHours, hourRange: 3.5...5, scoreRange: 45...59)
        case 5..<6.5:
            return interpolatedScore(for: averageDailyHours, hourRange: 5...6.5, scoreRange: 33...44)
        case 6.5..<8:
            return interpolatedScore(for: averageDailyHours, hourRange: 6.5...8, scoreRange: 28...32)
        case 8..<10:
            return interpolatedScore(for: averageDailyHours, hourRange: 8...10, scoreRange: 25...27)
        case 10..<12:
            return interpolatedScore(for: averageDailyHours, hourRange: 10...12, scoreRange: 23...24)
        case 12..<14:
            return interpolatedScore(for: averageDailyHours, hourRange: 12...14, scoreRange: 21...22)
        case 14...16:
            return 20
        default:
            return 20
        }
    }

    private func weeklyFocusScoreDelta(current: ScreenTimeInsightsSnapshot, previous: ScreenTimeInsightsSnapshot?) -> Int {
        let currentScore = weeklyFocusScore(snapshot: current)
        guard let previous else { return 0 }
        let previousScore = weeklyFocusScore(snapshot: previous)
        return currentScore - previousScore
    }

    private func weeklyNightInsightText(from thisWeekHours: [Double]) -> String {
        guard let (index, value) = thisWeekHours.enumerated().max(by: { $0.element < $1.element }) else {
            return AppLanguageRuntime.currentLanguage == .english
                ? "Weekly trend is still forming."
                : "本周使用趋势还在形成中。"
        }
        if AppLanguageRuntime.currentLanguage == .english {
            let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let dayLabel = (0..<labels.count).contains(index) ? labels[index] : "This week"
            return "Peak screen time was on \(dayLabel), about \(String(format: "%.1f", value))h."
        }
        let labels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let dayLabel = (0..<labels.count).contains(index) ? labels[index] : "本周"
        return "屏幕时间在\(dayLabel)达到峰值，约 \(String(format: "%.1f", value)) 小时。"
    }

    @MainActor
    private func presentWeeklyReportIfPossible(forWeekStart weekStart: Date, openHistoryFallback: Bool) {
        if let presentation = weeklyReportPresentation(forWeekStart: weekStart) {
            activeWeeklyReport = presentation
            return
        }

        if let latest = latestWeeklySnapshot() {
            activeWeeklyReport = weeklyReportPresentation(for: latest)
            return
        }

        let fallbackSnapshot = fallbackWeeklySnapshot(forWeekStart: weekStart)
        persistInsightsSnapshotFallback(fallbackSnapshot)
        activeWeeklyReport = weeklyReportPresentation(for: fallbackSnapshot)
        if activeWeeklyReport != nil {
            return
        }

        if openHistoryFallback {
            isWeeklyInsightsHistoryPresented = true
        }
    }

    private func latestWeeklySnapshot() -> ScreenTimeInsightsSnapshot? {
        screenTimeInsightsStore.snapshotsByKey.values
            .filter { $0.scope == "week" }
            .sorted { lhs, rhs in
                if lhs.rangeStart == rhs.rangeStart {
                    return lhs.generatedAt > rhs.generatedAt
                }
                return lhs.rangeStart > rhs.rangeStart
            }
            .first
    }

    private struct InsightsRange {
        let start: Date
        let end: Date
    }

    private var insightsScopePicker: some View {
        HStack(spacing: 6) {
            ForEach(InsightsScope.allCases) { scope in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedInsightsScope = scope
                    }
                } label: {
                    let isSelected = selectedInsightsScope == scope
                    Text(scope.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? (colorScheme == .dark ? .black : .white) : primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? (colorScheme == .dark ? Color.white : Color.black) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(dividerColor, lineWidth: 1)
        )
    }

    private var insightsRangeHeader: some View {
        HStack(spacing: 10) {
            Button {
                shiftInsightsRange(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primaryText)
                    .frame(width: 32, height: 32)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(dividerColor, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text(insightsRangeText(range: activeInsightsRange, scope: selectedInsightsScope))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(primaryText)
                .monospacedDigit()

            Spacer(minLength: 0)

            Button {
                shiftInsightsRange(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(primaryText)
                    .frame(width: 32, height: 32)
                    .background(cardBackground, in: Circle())
                    .overlay(Circle().stroke(dividerColor, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var activeInsightsRange: InsightsRange {
        insightsRange(for: selectedInsightsScope, anchor: insightsAnchorDate)
    }

    private func shiftInsightsRange(by direction: Int) {
        let calendar = Calendar.current
        let dayOffset: Int
        switch selectedInsightsScope {
        case .day:
            dayOffset = direction
        case .week:
            dayOffset = 7 * direction
        case .trend:
            dayOffset = 42 * direction
        }

        if let next = calendar.date(byAdding: .day, value: dayOffset, to: insightsAnchorDate) {
            insightsAnchorDate = next
        }
    }

    @ViewBuilder
    private var insightsReportView: some View {
        if !authorizationService.isApproved {
            insightsAuthorizationPromptCard
        } else {
            let range = insightsRange(for: selectedInsightsScope, anchor: insightsAnchorDate)
#if DEBUG
            if let debugSnapshot = debugInsightsDemoSnapshot(for: selectedInsightsScope, range: range) {
                localInsightsReport(snapshot: debugSnapshot, scope: selectedInsightsScope)
                    .frame(maxWidth: .infinity, minHeight: 520, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                systemInsightsReportView(for: range)
            }
#else
            systemInsightsReportView(for: range)
#endif
        }
    }

    private var insightsAuthorizationPromptCard: some View {
        unifiedCenteredStateCard(
            icon: insightsAuthorizationBarIcon,
            title: onlyLockL("开启权限后可查看屏幕时间分析"),
            buttonTitle: onlyLockL("开启权限"),
            isLoading: isSettingsAuthorizationRequesting,
            action: {
                Task {
                    await requestSettingsScreenTimeAuthorization(presentRecoverySheetOnFailure: false)
                }
            }
        ) {
            if insightsAuthorizationNeedsSettingsFallback {
                Button {
                    openSettingsForScreenTimePermission()
                } label: {
                    Text(onlyLockL("仍未开启？前往系统设置"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var insightsAuthorizationBarIcon: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let barWidth = w * 0.14
            let barSpacing = w * 0.06
            let barHeights: [CGFloat] = [0.34, 0.62, 0.46, 0.84]

            VStack(spacing: h * 0.08) {
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(Array(barHeights.enumerated()), id: \.offset) { item in
                        RoundedRectangle(cornerRadius: barWidth * 0.30, style: .continuous)
                            .fill(primaryText)
                            .frame(width: barWidth, height: h * item.element)
                    }
                }
                .frame(height: h * 0.76, alignment: .bottom)

                Capsule(style: .continuous)
                    .fill(primaryText)
                    .frame(width: w * 0.74, height: max(3, h * 0.055))
            }
            .frame(width: w, height: h, alignment: .center)
        }
        .frame(width: 86, height: 82)
        .accessibilityHidden(true)
    }

    private var emptyTaskVectorIcon: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let strokeW = max(3.2, w * 0.064)
            let iconColor = primaryText
            let cutoutColor = pageBackground

            ZStack {
                RoundedRectangle(cornerRadius: w * 0.13, style: .continuous)
                    .stroke(
                        iconColor.opacity(0.22),
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: w * 0.56, height: h * 0.44)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -w * 0.31, y: h * 0.12)

                RoundedRectangle(cornerRadius: w * 0.13, style: .continuous)
                    .stroke(
                        iconColor.opacity(0.22),
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: w * 0.56, height: h * 0.44)
                    .rotationEffect(.degrees(9))
                    .offset(x: w * 0.31, y: h * 0.12)

                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .fill(pageBackground)
                    .frame(width: w * 0.72, height: h * 0.54)
                    .offset(y: h * 0.08)

                RoundedRectangle(cornerRadius: w * 0.16, style: .continuous)
                    .stroke(
                        iconColor,
                        style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: w * 0.72, height: h * 0.54)
                    .offset(y: h * 0.08)

                Group {
                    let middleCardWidth = w * 0.72
                    let middleCardHeight = h * 0.54
                    let lockBodyWidth = middleCardWidth * 0.36
                    let lockBodyHeight = middleCardHeight * 0.30
                    let lockCenterY = middleCardHeight * 0.58
                    let lockBodyTop = lockCenterY - (lockBodyHeight * 0.5)
                    let shackleInset = lockBodyWidth * 0.24
                    let shackleTop = lockBodyTop - middleCardHeight * 0.28
                    let lockStroke = strokeW * 0.72

                    ZStack {
                        RoundedRectangle(cornerRadius: lockBodyWidth * 0.18, style: .continuous)
                            .stroke(
                                iconColor.opacity(0.86),
                                style: StrokeStyle(lineWidth: lockStroke, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: lockBodyWidth, height: lockBodyHeight)
                            .position(x: middleCardWidth * 0.5, y: lockCenterY)

                        Path { p in
                            let left = (middleCardWidth - lockBodyWidth) * 0.5 + shackleInset
                            let right = (middleCardWidth + lockBodyWidth) * 0.5 - shackleInset

                            p.move(to: CGPoint(x: left, y: lockBodyTop))
                            p.addLine(to: CGPoint(x: left, y: lockBodyTop - middleCardHeight * 0.12))
                            p.addCurve(
                                to: CGPoint(x: right, y: lockBodyTop - middleCardHeight * 0.12),
                                control1: CGPoint(x: left, y: shackleTop),
                                control2: CGPoint(x: right, y: shackleTop)
                            )
                            p.addLine(to: CGPoint(x: right, y: lockBodyTop))
                        }
                        .stroke(
                            iconColor.opacity(0.86),
                            style: StrokeStyle(lineWidth: lockStroke, lineCap: .round, lineJoin: .round)
                        )

                        Circle()
                            .fill(iconColor.opacity(0.86))
                            .frame(width: lockBodyWidth * 0.18, height: lockBodyWidth * 0.18)
                            .position(x: middleCardWidth * 0.5, y: lockCenterY + lockBodyHeight * 0.06)

                        Capsule(style: .continuous)
                            .fill(iconColor.opacity(0.86))
                            .frame(width: lockBodyWidth * 0.11, height: lockBodyHeight * 0.34)
                            .position(x: middleCardWidth * 0.5, y: lockCenterY + lockBodyHeight * 0.29)
                    }
                    .frame(width: middleCardWidth, height: middleCardHeight)
                    .offset(y: h * 0.08)
                }

                Circle()
                    .fill(iconColor)
                    .frame(width: w * 0.31, height: w * 0.31)
                    .overlay(
                        Circle()
                            .stroke(cutoutColor, lineWidth: strokeW * 0.76)
                    )
                    .offset(x: w * 0.31, y: -h * 0.09)

                Capsule(style: .continuous)
                    .fill(cutoutColor)
                    .frame(width: w * 0.16, height: strokeW * 0.9)
                    .offset(x: w * 0.31, y: -h * 0.09)

                Capsule(style: .continuous)
                    .fill(cutoutColor)
                    .frame(width: strokeW * 0.9, height: w * 0.16)
                    .offset(x: w * 0.31, y: -h * 0.09)
            }
        }
        .frame(width: 86, height: 82)
        .accessibilityHidden(true)
    }

    private func unifiedCenteredStateCard<Icon: View, Footer: View>(
        icon: Icon,
        title: String,
        buttonTitle: String,
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(pageBackground)

            VStack(spacing: 14) {
                icon

                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .padding(.horizontal, 12)

                Spacer()
                    .frame(height: 10)

                Button(action: action) {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(colorScheme == .dark ? .black : .white)
                        }
                        Text(buttonTitle)
                            .font(.system(size: 20, weight: .bold))
                    }
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .frame(width: 230, height: 64)
                    .background(
                        colorScheme == .dark ? Color.white : Color.black,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .opacity(isLoading ? 0.75 : 1)

                footer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var insightsReportPlaceholder: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(pageBackground)
    }

    private func systemInsightsReportView(for range: InsightsRange) -> some View {
        let rangeKey = insightsRangeCacheKey(scope: selectedInsightsScope, range: range)
        let hasWarmRangeCache = warmedInsightsRangeKeys.contains(rangeKey)
        let isSnapshotReady = hasMatchingInsightsSnapshot(for: selectedInsightsScope, range: range)
        let shouldShowLoading = !hasWarmRangeCache && (isInsightsReportReloading || (!isSnapshotReady && !isInsightsSnapshotGateExpired))

        return ZStack {
            DeviceActivityReport(
                selectedInsightsScope.reportContext,
                filter: insightsFilter(for: selectedInsightsScope, range: range)
            )
            .id("insights.\(selectedInsightsScope.rawValue).\(range.start.timeIntervalSince1970).\(insightsReportReloadID.uuidString)")
            .frame(maxWidth: .infinity, minHeight: 520, alignment: .top)
            .opacity(shouldShowLoading ? 0 : 1)

            if shouldShowLoading {
                insightsReportPlaceholder
            }
        }
        .frame(maxWidth: .infinity, minHeight: 520, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

#if DEBUG
    private func debugInsightsDemoSnapshot(
        for scope: InsightsScope,
        range: InsightsRange
    ) -> ScreenTimeInsightsSnapshot? {
        guard isDebugInsightsDemoEnabled, scope != .trend else { return nil }
        return screenTimeInsightsStore.debugOverride(
            for: scope.rawValue,
            rangeStart: range.start,
            rangeEnd: range.end
        )
    }
#endif

    private func bestAvailableInsightsSnapshot(
        for scope: InsightsScope,
        range: InsightsRange
    ) -> ScreenTimeInsightsSnapshot? {
        if let exact = screenTimeInsightsStore.snapshot(
            for: scope.rawValue,
            rangeStart: range.start,
            rangeEnd: range.end
        ) {
            return exact
        }

        let candidates = screenTimeInsightsStore.snapshotsByKey.values
            .filter { $0.scope == scope.rawValue }

        let normalizedMatch = candidates.filter { snapshot in
            switch scope {
            case .day:
                return Calendar.current.isDate(snapshot.rangeStart, inSameDayAs: range.start)
            case .week:
                return startOfWeekMonday(containing: snapshot.rangeStart) == startOfWeekMonday(containing: range.start)
            case .trend:
                return startOfWeekMonday(containing: snapshot.rangeEnd) == startOfWeekMonday(containing: range.end)
            }
        }
        .sorted { lhs, rhs in lhs.generatedAt > rhs.generatedAt }

        if let normalized = normalizedMatch.first {
            return normalized
        }

        return candidates.sorted { lhs, rhs in lhs.generatedAt > rhs.generatedAt }.first
    }

    private func fallbackInsightsSnapshotIfExtensionRan(
        for scope: InsightsScope,
        range: InsightsRange
    ) -> ScreenTimeInsightsSnapshot? {
        guard screenTimeInsightsStore.diagnostic(for: scope.rawValue) != nil else { return nil }

        let buckets: [ScreenTimeInsightsBucket]
        switch scope {
        case .day:
            buckets = (0..<8).map { index in
                ScreenTimeInsightsBucket(
                    id: "day.\(index)",
                    label: String(format: "%02d", index * 3),
                    appMinutes: 0,
                    webMinutes: 0
                )
            }
        case .week:
            buckets = ["一", "二", "三", "四", "五", "六", "日"].enumerated().map { index, label in
                ScreenTimeInsightsBucket(
                    id: "week.\(index)",
                    label: label,
                    appMinutes: 0,
                    webMinutes: 0
                )
            }
        case .trend:
            buckets = (0..<6).map { index in
                ScreenTimeInsightsBucket(
                    id: "trend.\(index)",
                    label: "W\(index + 1)",
                    appMinutes: 0,
                    webMinutes: 0
                )
            }
        }

        return ScreenTimeInsightsSnapshot(
            scope: scope.rawValue,
            rangeStart: range.start,
            rangeEnd: range.end,
            totalMinutes: 0,
            averageMinutes: 0,
            previousTotalMinutes: 0,
            buckets: buckets,
            topTargets: [],
            topCategories: [],
            generatedAt: Date()
        )
    }

    private func hasMatchingInsightsSnapshot(
        for scope: InsightsScope,
        range: InsightsRange
    ) -> Bool {
        if screenTimeInsightsStore.snapshot(
            for: scope.rawValue,
            rangeStart: range.start,
            rangeEnd: range.end
        ) != nil {
            return true
        }

        return screenTimeInsightsStore.snapshotsByKey.values.contains { snapshot in
            guard snapshot.scope == scope.rawValue else { return false }
            switch scope {
            case .day:
                return Calendar.current.isDate(snapshot.rangeStart, inSameDayAs: range.start)
            case .week:
                return startOfWeekMonday(containing: snapshot.rangeStart) == startOfWeekMonday(containing: range.start)
            case .trend:
                return startOfWeekMonday(containing: snapshot.rangeEnd) == startOfWeekMonday(containing: range.end)
            }
        }
    }

    private func insightsRangeCacheKey(scope: InsightsScope, range: InsightsRange) -> String {
        "\(scope.rawValue).\(Int(range.start.timeIntervalSince1970)).\(Int(range.end.timeIntervalSince1970))"
    }

    private func localInsightsReport(snapshot: ScreenTimeInsightsSnapshot, scope: InsightsScope) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                localInsightsHeadlineBlock(snapshot: snapshot, scope: scope)
                localInsightsChartCard(snapshot: snapshot)

                if !snapshot.topCategories.isEmpty {
                    localInsightsTopCategoriesStrip(snapshot: snapshot, scope: scope)
                }

                if !snapshot.topTargets.isEmpty {
                    localInsightsTargetsList(snapshot: snapshot)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 104)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(pageBackground)
    }

    private func localInsightsHeadlineBlock(snapshot: ScreenTimeInsightsSnapshot, scope: InsightsScope) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(insightsDurationText(insightsHeadlineMinutes(for: snapshot, scope: scope)))
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(insightsSubtitleText(for: scope))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondaryText)

            if let comparisonState = insightsComparisonState(
                for: scope,
                currentTotalMinutes: snapshot.totalMinutes,
                previousTotalMinutes: snapshot.previousTotalMinutes
            ) {
                Text(insightsComparisonText(for: comparisonState, scope: scope))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(insightsComparisonColor(for: comparisonState))
            }

            if snapshot.totalMinutes == 0 {
                Text(onlyLockL("当前时间范围内还没有系统屏幕时间数据。"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryText)
            }
        }
    }

    private func insightsHeadlineMinutes(for snapshot: ScreenTimeInsightsSnapshot, scope: InsightsScope) -> Int {
        switch scope {
        case .day:
            return snapshot.totalMinutes
        case .week, .trend:
            return snapshot.averageMinutes
        }
    }

    private func localInsightsChartCard(snapshot: ScreenTimeInsightsSnapshot) -> some View {
        let buckets = snapshot.buckets
        let maxMinutes = max(60, buckets.map(\.totalMinutes).max() ?? 60)
        let rawTopMinutes = max(maxMinutes, snapshot.averageMinutes)
        let yTopMinutes = max(60, Int(ceil(Double(rawTopMinutes) / (rawTopMinutes <= 180 ? 30.0 : 60.0))) * (rawTopMinutes <= 180 ? 30 : 60))
        let axisWidth: CGFloat = 34

        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 10) {
                GeometryReader { proxy in
                    let chartHeight = max(1, proxy.size.height)
                    let labelVerticalInset: CGFloat = 8
                    let topLineY = labelVerticalInset
                    let bottomLineY = chartHeight - labelVerticalInset
                    let plotHeight = max(1, bottomLineY - topLineY)
                    let averageRatio = min(max(CGFloat(snapshot.averageMinutes) / CGFloat(max(yTopMinutes, 1)), 0), 1)
                    let averageLineY = topLineY + plotHeight * (1 - averageRatio)
                    let lineEndX = proxy.size.width - axisWidth - 4
                    let barTopY = topLineY + 1
                    let barBottomY = bottomLineY - 1
                    let barPlotHeight = max(1, barBottomY - barTopY)
                    let barPlotWidth = max(1, proxy.size.width - axisWidth)

                    ZStack(alignment: .bottomLeading) {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: topLineY))
                            path.addLine(to: CGPoint(x: lineEndX, y: topLineY))
                            path.move(to: CGPoint(x: 0, y: bottomLineY))
                            path.addLine(to: CGPoint(x: lineEndX, y: bottomLineY))
                        }
                        .stroke(dividerColor, lineWidth: 1)

                        if snapshot.averageMinutes > 0 {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: averageLineY))
                                path.addLine(to: CGPoint(x: lineEndX, y: averageLineY))
                            }
                            .stroke(secondaryText.opacity(0.70), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }

                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(buckets) { bucket in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(primaryText)
                                    .frame(height: max(0, barPlotHeight * CGFloat(bucket.totalMinutes) / CGFloat(max(yTopMinutes, 1))))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                        .frame(width: barPlotWidth, height: barPlotHeight, alignment: .bottomLeading)
                        .position(x: barPlotWidth / 2, y: barTopY + barPlotHeight / 2)
                    }
                    .overlay(alignment: .trailing) {
                        ZStack {
                            Text(insightsAxisTopLabel(yTopMinutes))
                                .position(x: axisWidth / 2, y: topLineY)

                            if snapshot.averageMinutes > 0 {
                                Text(insightsShortDuration(snapshot.averageMinutes))
                                    .position(x: axisWidth / 2 + 6, y: averageLineY)
                            }

                            Text("0m")
                                .position(x: axisWidth / 2, y: bottomLineY)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: axisWidth, alignment: .trailing)
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(height: 176)

                HStack(spacing: 8) {
                    ForEach(snapshot.buckets) { bucket in
                        Text(bucket.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.trailing, axisWidth)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(dividerColor, lineWidth: 1)
        )
    }

    private func localInsightsTargetsList(snapshot: ScreenTimeInsightsSnapshot) -> some View {
        let displayedTargets = Array(snapshot.topTargets.prefix(8))
        let targetRowHeight: CGFloat = 52

        return VStack(alignment: .leading, spacing: 12) {
            Text(onlyLockL("高频使用"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            VStack(spacing: 0) {
                ForEach(Array(displayedTargets.enumerated()), id: \.element.id) { index, target in
                    HStack(spacing: 10) {
                        localInsightsTargetLeadingIcon(for: target, compact: false)

                        localInsightsTargetNameView(for: target, compact: false)

                        Spacer(minLength: 0)

                        Text(insightsShortDuration(target.minutes))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: targetRowHeight, alignment: .center)

                    if index != displayedTargets.count - 1 {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(height: 1)
                    }
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    private func localInsightsTopCategoriesStrip(snapshot: ScreenTimeInsightsSnapshot, scope: InsightsScope) -> some View {
        let displayedCategories = Array(snapshot.topCategories.prefix(4))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(displayedCategories) { target in
                    HStack(spacing: 6) {
                        localInsightsTargetLeadingIcon(for: target, compact: true)
                        Text(insightsShortDuration(target.minutes))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .monospacedDigit()
                    }
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(dividerColor, lineWidth: 1)
                        )
                }
            }
            .padding(.trailing, 18)
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.84),
                    .init(color: .black.opacity(0.78), location: 0.91),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
#if DEBUG
        .onAppear {
            persistRenderedInsightsCategories(snapshot: snapshot, scope: scope)
        }
#endif
    }

#if DEBUG
    private func persistRenderedInsightsCategories(
        snapshot: ScreenTimeInsightsSnapshot,
        scope: InsightsScope
    ) {
        let rows = snapshot.topCategories.map { target in
            [
                "name": target.name,
                "canonical": canonicalInsightsCategoryKey(for: target.name) ?? "nil",
                "minutes": String(target.minutes),
                "hasCategoryToken": target.categoryToken == nil ? "false" : "true"
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        debugSharedDefaults.set(string, forKey: "onlylock.debug.renderedTopCategories.\(scope.rawValue)")
        debugSharedDefaults.synchronize()
    }
#endif

    @ViewBuilder
    private func localInsightsTargetLeadingIcon(
        for target: ScreenTimeInsightsTarget,
        compact: Bool
    ) -> some View {
        let side: CGFloat = compact ? 24 : 28
        let corner: CGFloat = compact ? 7 : 8

        if target.kind == .app, let token = target.applicationToken {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else if target.kind == .category, let token = target.categoryToken {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: side, height: side)
        } else if target.kind == .category {
            insightsCategoryIcon(for: target.name, compact: compact)
        } else {
            Image(systemName: target.kind == .website ? "globe" : "square.grid.2x2")
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(primaryText)
                .frame(width: side, height: side)
                .background(
                    primaryText.opacity(colorScheme == .dark ? 0.14 : 0.06),
                    in: RoundedRectangle(cornerRadius: corner, style: .continuous)
                )
        }
    }

    @ViewBuilder
    private func insightsCategoryIcon(for name: String, compact: Bool) -> some View {
        let side: CGFloat = compact ? 24 : 28
        let symbol = categoryEmoji(for: name)

        Text(symbol)
            .font(.system(size: compact ? 17 : 20))
            .frame(width: side, height: side)
    }

    private func categoryEmoji(for rawName: String) -> String {
        switch canonicalInsightsCategoryKey(for: rawName) {
        case "social":
            return "💬"
        case "games":
            return "🚀"
        case "entertainment":
            return "🍿"
        case "information":
            return "📖"
        case "health":
            return "🚴"
        case "creativity":
            return "🎨"
        case "utilities":
            return "🧮"
        case "productivity":
            return "📊"
        case "education":
            return "🌍"
        case "travel":
            return "🧳"
        case "shoppingFood":
            return "🛍️"
        case "other":
            return "🧩"
        case .none:
            print("[OnlyLockInsights][CategoryIconFallback][App] unmapped category name=\(rawName)")
            return "🧩"
        default:
            return "🧩"
        }
    }

    private enum InsightsComparisonState {
        case decrease(Int)
        case increase(Int)
        case flat
    }

    private func insightsComparisonState(
        for scope: InsightsScope,
        currentTotalMinutes: Int,
        previousTotalMinutes: Int
    ) -> InsightsComparisonState? {
        guard scope != .trend, previousTotalMinutes > 0 else { return nil }

        if currentTotalMinutes == previousTotalMinutes {
            return .flat
        }

        let difference = abs(currentTotalMinutes - previousTotalMinutes)
        let percentage = max(1, Int((Double(difference) / Double(previousTotalMinutes) * 100).rounded()))
        return currentTotalMinutes < previousTotalMinutes ? .decrease(percentage) : .increase(percentage)
    }

    private func insightsComparisonText(for state: InsightsComparisonState, scope: InsightsScope) -> String {
        let baseline: String
        if AppLanguageRuntime.currentLanguage == .english {
            baseline = scope == .week ? "last week" : "yesterday"
        } else {
            baseline = scope == .week ? "上周" : "昨天"
        }
        switch state {
        case let .decrease(percentage):
            if AppLanguageRuntime.currentLanguage == .english {
                return "Screen time decreased \(percentage)% vs \(baseline)"
            }
            return "相比于\(baseline)降低了\(percentage)%屏幕使用时间"
        case let .increase(percentage):
            if AppLanguageRuntime.currentLanguage == .english {
                return "Screen time increased \(percentage)% vs \(baseline)"
            }
            return "相比于\(baseline)增加了\(percentage)%屏幕使用时间"
        case .flat:
            return AppLanguageRuntime.currentLanguage == .english
                ? "Same as \(baseline)"
                : "与\(baseline)持平"
        }
    }

    private func insightsComparisonColor(for state: InsightsComparisonState) -> Color {
        switch state {
        case .decrease:
            return Color(red: 0.12, green: 0.48, blue: 0.29)
        case .increase:
            return Color(red: 0.65, green: 0.37, blue: 0.12)
        case .flat:
            return secondaryText
        }
    }

    private func insightsFilter(for scope: InsightsScope, range: InsightsRange) -> DeviceActivityFilter {
        let interval = DateInterval(start: range.start, end: range.end)
        switch scope {
        case .day:
            return DeviceActivityFilter(
                segment: .hourly(during: interval),
                users: .all,
                devices: .init([.iPhone, .iPad])
            )
        case .week, .trend:
            return DeviceActivityFilter(
                segment: .daily(during: interval),
                users: .all,
                devices: .init([.iPhone, .iPad])
            )
        }
    }

    private func insightsRange(for scope: InsightsScope, anchor: Date) -> InsightsRange {
        let calendar = Calendar.current
        switch scope {
        case .day:
            let start = calendar.startOfDay(for: anchor)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return InsightsRange(start: start, end: end)
        case .week:
            let start = startOfWeekMonday(containing: anchor)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return InsightsRange(start: start, end: end)
        case .trend:
            let currentWeekStart = startOfWeekMonday(containing: anchor)
            let start = calendar.date(byAdding: .day, value: -35, to: currentWeekStart) ?? currentWeekStart
            let end = calendar.date(byAdding: .day, value: 7, to: currentWeekStart) ?? currentWeekStart
            return InsightsRange(start: start, end: end)
        }
    }

    private func startOfWeekMonday(containing date: Date) -> Date {
        OnlyLockShared.startOfWeekMonday(containing: date, calendar: Calendar.current)
    }

    private func scheduleInsightsReportReload(force _: Bool = false) {
        insightsReportReloadTask?.cancel()
        insightsSnapshotGateTask?.cancel()

        let range = insightsRange(for: selectedInsightsScope, anchor: insightsAnchorDate)
        let rangeKey = insightsRangeCacheKey(scope: selectedInsightsScope, range: range)
        isInsightsReportReloading = true
        isInsightsSnapshotGateExpired = false
        screenTimeInsightsStore.refresh()
        if hasMatchingInsightsSnapshot(for: selectedInsightsScope, range: range) {
            warmedInsightsRangeKeys.insert(rangeKey)
        }

        insightsSnapshotGateTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isInsightsSnapshotGateExpired = true
                warmedInsightsRangeKeys.insert(rangeKey)
            }
        }

        insightsReportReloadTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                insightsReportReloadID = UUID()
                isInsightsReportReloading = false
                screenTimeInsightsStore.refresh()
                if hasMatchingInsightsSnapshot(for: selectedInsightsScope, range: range) {
                    warmedInsightsRangeKeys.insert(rangeKey)
                }
            }
        }
    }

    @ViewBuilder
    private func localInsightsTargetNameView(
        for target: ScreenTimeInsightsTarget,
        compact: Bool
    ) -> some View {
        let fontSize: CGFloat = compact ? 12 : 18
        let weight: Font.Weight = .semibold

        if target.kind == .app,
           let token = target.applicationToken,
           isApplicationFallbackName(target.name) {
            Label(token)
                .labelStyle(.titleOnly)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        } else {
            Text(target.name)
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private func isApplicationFallbackName(_ value: String) -> Bool {
        value.hasPrefix("Selected App ") || value.hasPrefix("已选 App ")
    }

    private func insightsRangeText(range: InsightsRange, scope: InsightsScope) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale

        switch scope {
        case .day:
            if AppLanguageRuntime.currentLanguage == .english {
                formatter.setLocalizedDateFormatFromTemplate("yMMMd")
            } else {
                formatter.dateFormat = "yyyy年M月d日"
            }
            return formatter.string(from: range.start)
        case .week, .trend:
            if AppLanguageRuntime.currentLanguage == .english {
                formatter.setLocalizedDateFormatFromTemplate("MMMd")
            } else {
                formatter.dateFormat = "M月d日"
            }
            let start = formatter.string(from: range.start)
            let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            let end = formatter.string(from: lastDay)
            return "\(start) - \(end)"
        }
    }

    private func insightsSubtitleText(for scope: InsightsScope) -> String {
        switch scope {
        case .day:
            return AppLanguageRuntime.currentLanguage == .english ? "Today's Screen Time" : "当日屏幕时间"
        case .week:
            return AppLanguageRuntime.currentLanguage == .english ? "Average Daily Screen Time" : "平均每日屏幕时间"
        case .trend:
            return AppLanguageRuntime.currentLanguage == .english ? "Average Weekly Screen Time" : "平均每周屏幕时间"
        }
    }

    private func insightsDurationText(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60

        if AppLanguageRuntime.currentLanguage == .english {
            if hour == 0 {
                return "\(minute)m"
            }
            if minute == 0 {
                return "\(hour)h"
            }
            return "\(hour)h \(minute)m"
        }

        if hour == 0 {
            return "\(minute)分钟"
        }
        if minute == 0 {
            return "\(hour)小时"
        }
        return "\(hour)小时\(minute)分"
    }

    private func insightsShortDuration(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60
        if AppLanguageRuntime.currentLanguage == .english {
            if hour == 0 {
                return "\(minute)m"
            }
            return "\(hour)h \(minute)m"
        }
        if hour == 0 {
            return "\(minute)分"
        }
        return "\(hour)时\(minute)分"
    }

    private func insightsAxisTopLabel(_ minutes: Int) -> String {
        let hour = max(1, Int(ceil(Double(minutes) / 60.0)))
        return "\(hour)h"
    }

    private func currentTimelineDisplayDate(from realNow: Date) -> Date {
#if DEBUG
        let usesDebugClock = isFlipPreviewEnabled || isDebugTimeOverrideEnabled
        guard usesDebugClock else {
            return realNow
        }

        let elapsed = realNow.timeIntervalSince(flipPreviewReferenceDate)
        let effectiveElapsed: TimeInterval
        if isFlipPreviewEnabled, !isFlipPreviewPaused {
            effectiveElapsed = elapsed * flipPreviewSpeedMultiplier
        } else {
            effectiveElapsed = 0
        }
        return flipPreviewDisplayBaseDate.addingTimeInterval(effectiveElapsed)
#else
        return realNow
#endif
    }

    private var resolvedDisplayNow: Date {
        currentTimelineDisplayDate(from: uiClockNow)
    }

    private var timelineRefreshInterval: TimeInterval {
#if DEBUG
        if (isFlipPreviewEnabled || isDebugTimeOverrideEnabled), !isFlipPreviewPaused {
            return 1
        }
#endif
        // Keep timeline refresh at 1s to guarantee countdown text changes
        // are emitted continuously, so numeric transition animations are visible.
        return 1
    }

#if DEBUG
    private var debugControlBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var debugControlSelectedBackground: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var debugControlSelectedForeground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private func debugToggleRow(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(onlyLockL(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primaryText)

            Spacer(minLength: 10)

            debugTogglePill(isOn: isOn, action: action)
        }
    }

    private func debugTogglePill(isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isOn ? debugControlSelectedForeground : secondaryText.opacity(0.32))
                    .frame(width: 8, height: 8)

                Text(isOn ? onlyLockL("开") : onlyLockL("关"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isOn ? debugControlSelectedForeground : secondaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                Capsule(style: .continuous)
                    .fill(isOn ? debugControlSelectedBackground : debugControlBackground)
            )
        }
        .buttonStyle(.plain)
    }

    private var flipPreviewDebugOverlay: some View {
        Button {
            isFlipPreviewPanelExpanded = true
        } label: {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(debugControlSelectedForeground)
                .frame(width: 44, height: 44)
                .background(debugControlSelectedBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 20)
        .padding(.bottom, customTabBarReservedHeight + 16)
    }

    private var flipPreviewDebugPanel: some View {
        NavigationStack {
            ScrollView {
                flipPreviewDebugPanelContent
                    .padding(16)
            }
            .onAppear {
                debugManualTimelineDate = currentTimelineDisplayDate(from: Date())
                syncDebugMembershipTierOverrideFromDefaults()
            }
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle(onlyLockL("调试面板"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(onlyLockL("关闭")) {
                        isFlipPreviewPanelExpanded = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var flipPreviewDebugPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            debugToggleRow(title: "空任务", isOn: isDebugForceEmptyProgressState) {
                isDebugForceEmptyProgressState.toggle()
            }

            debugToggleRow(title: "翻页预览", isOn: isFlipPreviewEnabled) {
                isFlipPreviewEnabled.toggle()
            }

            debugToggleRow(title: "时间穿越", isOn: isDebugTimeOverrideEnabled) {
                isDebugTimeOverrideEnabled.toggle()
            }

            if isDebugTimeOverrideEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text(onlyLockL("自由选择时间"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(secondaryText)

                    DatePicker(
                        "",
                        selection: $debugManualTimelineDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(primaryText)

                    Button(onlyLockL("应用所选时间")) {
                        setDebugTimelineDate(debugManualTimelineDate, pause: true)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(debugControlBackground, in: Capsule())
                }
            }

            debugToggleRow(title: "连续勋章速测", isOn: isDebugStreakMedalPreviewEnabled) {
                isDebugStreakMedalPreviewEnabled.toggle()
            }

            debugToggleRow(title: "打卡天数速测", isOn: isDebugStreakOverrideEnabled) {
                isDebugStreakOverrideEnabled.toggle()
            }

            if isDebugStreakOverrideEnabled {
                debugStreakOverrideControls
            }

            debugToggleRow(title: "分析页 Demo 数据", isOn: isDebugInsightsDemoEnabled) {
                isDebugInsightsDemoEnabled.toggle()
            }

            if isDebugInsightsDemoEnabled {
                debugInsightsDemoControls
            }

            debugToggleRow(title: "周报 Demo 数据", isOn: isDebugWeeklyReportDemoEnabled) {
                isDebugWeeklyReportDemoEnabled.toggle()
            }

            if isDebugWeeklyReportDemoEnabled {
                debugWeeklyReportDemoControls
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(onlyLockL("会员身份速测"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(secondaryText)

                HStack(spacing: 6) {
                    debugMembershipTierButton(label: "未开通", tier: .none)
                    debugMembershipTierButton(label: "月度", tier: .monthly)
                    debugMembershipTierButton(label: "终身", tier: .lifetime)
                }

                if debugMembershipTierOverride == .monthly {
                    debugToggleRow(title: "会员快速过期", isOn: isDebugMembershipExpiredOverride) {
                        isDebugMembershipExpiredOverride.toggle()
                        applyDebugMembershipOverride()
                    }
                }
            }

            if isDebugStreakMedalPreviewEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(onlyLockL("勋章档位"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(secondaryText)

                    HStack(spacing: 6) {
                        debugStreakMedalTierButton(label: "锁定", streak: 0)
                        debugStreakMedalTierButton(label: "3", streak: 3)
                        debugStreakMedalTierButton(label: "7", streak: 7)
                        debugStreakMedalTierButton(label: "14", streak: 14)
                    }

                    HStack(spacing: 6) {
                        debugStreakMedalTierButton(label: "30", streak: 30)
                        debugStreakMedalTierButton(label: "60", streak: 60)
                        debugStreakMedalTierButton(label: "100", streak: 100)
                        debugStreakMedalTierButton(label: "365", streak: 365)
                    }

                    Button(onlyLockL("弹卡预览")) {
                        let tier = RewardEngine.highestUnlockedStreakTier(
                            bestStreak: debugStreakMedalPreviewBestStreak
                        ) ?? 0
                        guard tier > 0 else { return }
                        presentStreakMedalUnlock(tier: tier)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(debugControlBackground, in: Capsule())
                }
            }

            HStack(spacing: 6) {
                flipPreviewSpeedButton(label: "1x", multiplier: 1)
                flipPreviewSpeedButton(label: "10x", multiplier: 10)
                flipPreviewSpeedButton(label: "60x", multiplier: 60)
            }

            HStack(spacing: 6) {
                Button(isFlipPreviewPaused ? "继续" : "暂停") {
                    guard isFlipPreviewEnabled else { return }
                    let now = Date()
                    if isFlipPreviewPaused {
                        flipPreviewReferenceDate = now
                        isFlipPreviewPaused = false
                    } else {
                        flipPreviewDisplayBaseDate = currentTimelineDisplayDate(from: now)
                        flipPreviewReferenceDate = now
                        isFlipPreviewPaused = true
                    }
                    refreshDebugTimeSimulation()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())

                Button(onlyLockL("+1分")) {
                    let now = Date()
                    setDebugTimelineDate(
                        currentTimelineDisplayDate(from: now).addingTimeInterval(60),
                        pause: true
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())

                Button(onlyLockL("+1天")) {
                    let now = Date()
                    setDebugTimelineDate(
                        currentTimelineDisplayDate(from: now).addingTimeInterval(24 * 60 * 60),
                        pause: true
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())
            }

            HStack(spacing: 6) {
                Button(onlyLockL("+7天")) {
                    let now = Date()
                    setDebugTimelineDate(
                        currentTimelineDisplayDate(from: now).addingTimeInterval(7 * 24 * 60 * 60),
                        pause: true
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())

                Button(onlyLockL("重置")) {
                    let now = Date()
                    flipPreviewReferenceDate = now
                    flipPreviewDisplayBaseDate = now
                    isFlipPreviewPaused = false
                    refreshDebugTimeSimulation()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())
            }

            Text(onlyLockL("时间跳转请用 +1分 / +1天 / +7天"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)

            Text(onlyLockL("仅 DEBUG 生效，不影响生产环境"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)
        }
    }

    private func flipPreviewSpeedButton(label: String, multiplier: Double) -> some View {
        let isSelected = flipPreviewSpeedMultiplier == multiplier

        return Button(label) {
            let now = Date()
            flipPreviewDisplayBaseDate = currentTimelineDisplayDate(from: now)
            flipPreviewReferenceDate = now
            flipPreviewSpeedMultiplier = multiplier
            isFlipPreviewPaused = false
            refreshDebugTimeSimulation()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(isSelected ? debugControlSelectedForeground : primaryText)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isSelected ? debugControlSelectedBackground : debugControlBackground, in: Capsule())
    }

    private func debugStreakMedalTierButton(label: String, streak: Int) -> some View {
        let isSelected = debugStreakMedalPreviewBestStreak == streak

        return Button(label) {
            debugStreakMedalPreviewBestStreak = streak
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isSelected ? debugControlSelectedForeground : primaryText)
        .padding(.horizontal, 8)
        .frame(minWidth: 36)
        .frame(height: 26)
        .background(isSelected ? debugControlSelectedBackground : debugControlBackground, in: Capsule())
    }

    private func debugMembershipTierButton(label: String, tier: SettingsStore.MembershipTier) -> some View {
        let isSelected = debugMembershipTierOverride == tier

        return Button(label) {
            debugMembershipTierOverride = tier
            if tier != .monthly {
                isDebugMembershipExpiredOverride = false
            }
            applyDebugMembershipOverride()
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isSelected ? debugControlSelectedForeground : primaryText)
        .padding(.horizontal, 8)
        .frame(minWidth: 52)
        .frame(height: 26)
        .background(isSelected ? debugControlSelectedBackground : debugControlBackground, in: Capsule())
    }

    @MainActor
    private func applyDebugMembershipOverride() {
        let tier = debugMembershipTierOverride
        debugSharedDefaults.set(tier != .none, forKey: OnlyLockShared.membershipUnlockedKey)
        debugSharedDefaults.set(tier.rawValue, forKey: OnlyLockShared.membershipTierKey)
        if tier == .monthly {
            let expiration = isDebugMembershipExpiredOverride
                ? Date().addingTimeInterval(-60).timeIntervalSince1970
                : Date().addingTimeInterval(30 * 24 * 60 * 60).timeIntervalSince1970
            debugSharedDefaults.set(expiration, forKey: OnlyLockShared.membershipExpirationTimestampKey)
        } else {
            debugSharedDefaults.set(0, forKey: OnlyLockShared.membershipExpirationTimestampKey)
        }
        debugSharedDefaults.synchronize()
        settingsStore.refreshMembershipStatus()
        syncRuntimeShieldForAuthorizationState(now: Date())
        Task {
            await weeklyInsightsNotificationScheduler.syncWeeklyReportNotification()
        }
    }

    private func setDebugTimelineDate(_ target: Date, pause: Bool) {
        let now = Date()
        if !isDebugTimeOverrideEnabled {
            isDebugTimeOverrideEnabled = true
        }
        flipPreviewDisplayBaseDate = target
        flipPreviewReferenceDate = now
        isFlipPreviewPaused = pause
        refreshDebugTimeSimulation()
    }

    private func refreshDebugTimeSimulation() {
        let usesDebugClock = isFlipPreviewEnabled || isDebugTimeOverrideEnabled
        if usesDebugClock {
            let debugNow = currentTimelineDisplayDate(from: Date())
            debugSharedDefaults.set(true, forKey: OnlyLockShared.debugTimeOverrideEnabledKey)
            debugSharedDefaults.set(debugNow.timeIntervalSince1970, forKey: OnlyLockShared.debugTimeOverrideTimestampKey)
            applyDebugShield(at: debugNow)
            Task {
                await weeklyInsightsNotificationScheduler.emitDebugWeeklyReportIfDue(simulatedNow: debugNow)
                await syncDebugWeeklyReportSimulation(at: debugNow)
            }
            hadDebugTimeSimulationApplied = true
        } else {
            debugSharedDefaults.set(false, forKey: OnlyLockShared.debugTimeOverrideEnabledKey)
            debugSharedDefaults.removeObject(forKey: OnlyLockShared.debugTimeOverrideTimestampKey)
            if hadDebugTimeSimulationApplied {
                applyDebugShield(at: Date())
                hadDebugTimeSimulationApplied = false
            }
        }
    }

    private func latestPublishedWeeklyReportStartForDebugSimulation(from now: Date) -> Date {
        let currentWeekStart = startOfWeekMonday(containing: now)
        var releaseComponents = Calendar.current.dateComponents([.year, .month, .day], from: currentWeekStart)
        releaseComponents.hour = 9
        releaseComponents.minute = 0
        releaseComponents.second = 0
        let currentWeekRelease = Calendar.current.date(from: releaseComponents) ?? currentWeekStart
        let daysBack = now >= currentWeekRelease ? 7 : 14
        return Calendar.current.date(byAdding: .day, value: -daysBack, to: currentWeekStart) ?? currentWeekStart
    }

    private func syncDebugWeeklyReportSimulation(at simulatedNow: Date) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let weekStart = latestPublishedWeeklyReportStartForDebugSimulation(from: simulatedNow)
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let timestamp = Int(normalizedWeekStart.timeIntervalSince1970)
        let deleted = Set(debugSharedDefaults.array(forKey: OnlyLockShared.weeklyReportDeletedWeekStartsKey) as? [Int] ?? [])
        guard !deleted.contains(timestamp) else { return }

        let existingHistory = Set(debugSharedDefaults.array(forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey) as? [Int] ?? [])
        if !existingHistory.contains(timestamp) {
            debugSharedDefaults.set(Array(existingHistory.union([timestamp])).sorted(by: >), forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey)
            debugSharedDefaults.synchronize()
            NotificationCenter.default.post(name: .onlyLockWeeklyReportHistoryDidChange, object: nil)
        }

        let readWeekStarts = Set(debugSharedDefaults.array(forKey: OnlyLockShared.weeklyReportReadWeekStartsKey) as? [Int] ?? [])
        let updatedHistory = Set(debugSharedDefaults.array(forKey: OnlyLockShared.weeklyReportHistoryWeekStartsKey) as? [Int] ?? [])
        let unreadCount = updatedHistory.subtracting(readWeekStarts).subtracting(deleted).count
        debugSharedDefaults.set(unreadCount, forKey: OnlyLockShared.notificationBadgeCountKey)
        debugSharedDefaults.synchronize()

        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(unreadCount) { _ in }
        } else {
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = unreadCount
            }
        }
    }

    @MainActor
    private func syncDebugStreakOverrideToWidget() {
        let streak: Int
        if isDebugStreakOverrideEnabled {
            streak = max(0, debugStreakOverrideDays)
        } else {
            streak = max(0, rewardViewModel.snapshot.currentStreak)
        }

        var didChange = false
        let previousStreak = debugSharedDefaults.integer(forKey: OnlyLockShared.widgetCurrentStreakKey)
        if previousStreak != streak {
            debugSharedDefaults.set(streak, forKey: OnlyLockShared.widgetCurrentStreakKey)
            didChange = true
        }

        if isDebugStreakOverrideEnabled {
            let previousOverrideEnabled = debugSharedDefaults.bool(forKey: debugWidgetStreakOverrideEnabledKey)
            if !previousOverrideEnabled {
                debugSharedDefaults.set(true, forKey: debugWidgetStreakOverrideEnabledKey)
                didChange = true
            }

            let previousOverrideDays = debugSharedDefaults.integer(forKey: debugWidgetStreakOverrideDaysKey)
            if previousOverrideDays != streak {
                debugSharedDefaults.set(streak, forKey: debugWidgetStreakOverrideDaysKey)
                didChange = true
            }
        } else {
            if debugSharedDefaults.object(forKey: debugWidgetStreakOverrideEnabledKey) != nil {
                debugSharedDefaults.removeObject(forKey: debugWidgetStreakOverrideEnabledKey)
                didChange = true
            }
            if debugSharedDefaults.object(forKey: debugWidgetStreakOverrideDaysKey) != nil {
                debugSharedDefaults.removeObject(forKey: debugWidgetStreakOverrideDaysKey)
                didChange = true
            }
        }

        let todayStartTimestamp = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        if streak > 0 {
            let previousCheckIn = debugSharedDefaults.double(forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey)
            if previousCheckIn != todayStartTimestamp {
                debugSharedDefaults.set(todayStartTimestamp, forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey)
                didChange = true
            }
        } else {
            if debugSharedDefaults.object(forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey) != nil {
                debugSharedDefaults.removeObject(forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey)
                didChange = true
            }
        }

        guard didChange else { return }

        debugSharedDefaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "OnlyLockStreakWidgetV4")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var debugStreakOverrideControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(onlyLockL("打卡天数"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(secondaryText)

            HStack(spacing: 6) {
                Button("-1") {
                    debugStreakOverrideDays = max(0, debugStreakOverrideDays - 1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(debugControlBackground, in: Capsule())

                Text(AppLanguageRuntime.currentLanguage == .english ? "\(debugStreakOverrideDays) days" : "\(debugStreakOverrideDays)天")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(primaryText)
                    .frame(minWidth: 56)

                Button("+1") {
                    debugStreakOverrideDays = min(999, debugStreakOverrideDays + 1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(debugControlBackground, in: Capsule())

                Button("+7") {
                    debugStreakOverrideDays = min(999, debugStreakOverrideDays + 7)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(debugControlBackground, in: Capsule())
            }
        }
    }

    private var debugInsightsEditableScope: InsightsScope {
        selectedInsightsScope == .trend ? .week : selectedInsightsScope
    }

    private var debugInsightsEditableRange: InsightsRange {
        insightsRange(for: debugInsightsEditableScope, anchor: insightsAnchorDate)
    }

    private struct DebugInsightsApplicationOption: Identifiable {
        let id: String
        let token: ApplicationToken
        let name: String
    }

    private func debugInsightsApplicationName(for token: ApplicationToken, fallbackIndex: Int) -> String {
        let application = Application(token: token)
        let fallbackPrefix = AppLanguageRuntime.currentLanguage == .english ? "Selected App " : "已选 App "
        let fallback = "\(fallbackPrefix)\(fallbackIndex + 1)"
        let rawValue = application.localizedDisplayName ?? application.bundleIdentifier ?? fallback
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var availableDebugInsightsApplicationOptions: [DebugInsightsApplicationOption] {
        let ordered = viewModel.orderedApplicationTokens
        let liveSelection = Array(viewModel.appPickerSelection.applicationTokens)
        let combined = ordered + liveSelection
        var seen: [ApplicationToken] = []
        var options: [DebugInsightsApplicationOption] = []

        for token in combined {
            guard !seen.contains(where: { $0 == token }) else { continue }
            seen.append(token)
            let index = options.count
            options.append(
                DebugInsightsApplicationOption(
                    id: "debug.insights.app.\(index)",
                    token: token,
                    name: debugInsightsApplicationName(for: token, fallbackIndex: index)
                )
            )
        }

        return options
    }

    private var debugInsightsDemoControls: some View {
        let scope = debugInsightsEditableScope
        let range = debugInsightsEditableRange
        let overrideSnapshot = currentDebugInsightsOverride(for: scope, range: range)
        let targets = paddedDebugInsightsTargets(overrideSnapshot.topTargets)
        let categories = paddedDebugInsightsCategories(overrideSnapshot.topCategories)

        return VStack(alignment: .leading, spacing: 8) {
            Text(onlyLockL("分析页 Demo 数据"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(secondaryText)

            HStack(spacing: 6) {
                debugInsightsScopeButton(label: onlyLockL("日"), scope: .day)
                debugInsightsScopeButton(label: onlyLockL("周"), scope: .week)

                Spacer(minLength: 0)

                Button(onlyLockL("上一页")) {
                    shiftDebugInsightsRange(by: -1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(debugControlBackground, in: Capsule())

                Button(onlyLockL("下一页")) {
                    shiftDebugInsightsRange(by: 1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(debugControlBackground, in: Capsule())
            }

            Text(insightsRangeText(range: range, scope: scope))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondaryText)

            HStack(spacing: 6) {
                Button(onlyLockL("填充好看数据")) {
                    screenTimeInsightsStore.saveDebugOverride(
                        makePrettyDebugInsightsOverride(for: scope, range: range)
                    )
                    warmedInsightsRangeKeys.insert(insightsRangeCacheKey(scope: scope, range: range))
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlSelectedBackground, in: Capsule())
                .foregroundStyle(debugControlSelectedForeground)

                Button(onlyLockL("清除当前页")) {
                    screenTimeInsightsStore.removeDebugOverride(
                        scope: scope.rawValue,
                        rangeStart: range.start,
                        rangeEnd: range.end
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())
            }

            if !availableDebugInsightsApplicationOptions.isEmpty {
                HStack(spacing: 6) {
                    Button(onlyLockL("用已选应用填充真实图标")) {
                        applyDebugInsightsAvailableAppTokens(scope: scope, range: range)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(debugControlBackground, in: Capsule())

                    Text(AppLanguageRuntime.currentLanguage == .english
                         ? "\(availableDebugInsightsApplicationOptions.count) apps available"
                         : "首页已选应用 \(availableDebugInsightsApplicationOptions.count) 个")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondaryText)
                }
            }

            HStack(spacing: 8) {
                Text(onlyLockL("上期总时长"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(primaryText)

                Spacer(minLength: 0)

                debugInsightsDeltaButton("-30") {
                    updateDebugInsightsOverride(scope: scope, range: range) { draft in
                        draft = draft.withPreviousTotalMinutes(max(0, draft.previousTotalMinutes - 30))
                    }
                }

                debugInsightsMinutesInput(
                    text: debugInsightsPreviousTotalMinutesBinding(scope: scope, range: range),
                    width: 62
                )

                debugInsightsDeltaButton("+30") {
                    updateDebugInsightsOverride(scope: scope, range: range) { draft in
                        draft = draft.withPreviousTotalMinutes(draft.previousTotalMinutes + 30)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(onlyLockL("柱图分钟"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText)

                ForEach(Array(overrideSnapshot.buckets.enumerated()), id: \.element.id) { index, bucket in
                    HStack(spacing: 8) {
                        Text(bucket.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .frame(width: 28, alignment: .leading)

                        Spacer(minLength: 0)

                        debugInsightsMinutesInput(
                            text: debugInsightsBucketMinutesBinding(scope: scope, range: range, index: index),
                            width: 58
                        )

                        debugInsightsDeltaButton("-15") {
                            updateDebugInsightsOverride(scope: scope, range: range) { draft in
                                draft = draft.withBucketMinutes(
                                    index: index,
                                    totalMinutes: max(0, draft.buckets[index].totalMinutes - 15)
                                )
                            }
                        }

                        debugInsightsDeltaButton("+15") {
                            updateDebugInsightsOverride(scope: scope, range: range) { draft in
                                draft = draft.withBucketMinutes(
                                    index: index,
                                    totalMinutes: draft.buckets[index].totalMinutes + 15
                                )
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(onlyLockL("Top App"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText)

                ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(availableDebugInsightsApplicationOptions) { option in
                                Button(option.name) {
                                    updateDebugInsightsOverride(scope: scope, range: range) { draft in
                                        let currentMinutes = paddedDebugInsightsTargets(draft.topTargets)[index].minutes
                                        let preferredMinutes = currentMinutes > 0 ? currentMinutes : (scope == .day ? 60 : 120)
                                        draft = draft
                                            .withTargetApplicationToken(index: index, token: option.token, preferredName: option.name)
                                            .withTargetMinutes(index: index, minutes: preferredMinutes)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(debugInsightsTargetSelectionLabel(scope: scope, range: range, index: index))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(debugControlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        debugInsightsMinutesInput(
                            text: debugInsightsTargetMinutesBinding(scope: scope, range: range, index: index),
                            width: 58
                        )

                        debugInsightsDeltaButton("-15") {
                            updateDebugInsightsOverride(scope: scope, range: range) { draft in
                                draft = draft.withTargetMinutes(index: index, minutes: max(0, target.minutes - 15))
                            }
                        }

                        debugInsightsDeltaButton("+15") {
                            updateDebugInsightsOverride(scope: scope, range: range) { draft in
                                draft = draft.withTargetMinutes(index: index, minutes: target.minutes + 15)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(onlyLockL("顶部类别"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText)

                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(debugInsightsCategoryOptions, id: \.self) { option in
                                Button(option) {
                                    debugInsightsCategoryNameBinding(scope: scope, range: range, index: index).wrappedValue = option
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(debugInsightsCategoryNameBinding(scope: scope, range: range, index: index).wrappedValue)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(debugControlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        debugInsightsMinutesInput(
                            text: debugInsightsCategoryMinutesBinding(scope: scope, range: range, index: index),
                            width: 58
                        )

                        debugInsightsDeltaButton("-15") {
                            let selectedCategoryName = debugInsightsCategoryNameBinding(scope: scope, range: range, index: index).wrappedValue
                            updateDebugInsightsOverride(scope: scope, range: range) { draft in
                                draft = draft
                                    .withCategoryName(index: index, name: selectedCategoryName)
                                    .withCategoryMinutes(index: index, minutes: max(0, category.minutes - 15))
                            }
                        }

                        debugInsightsDeltaButton("+15") {
                            let selectedCategoryName = debugInsightsCategoryNameBinding(scope: scope, range: range, index: index).wrappedValue
                            updateDebugInsightsOverride(scope: scope, range: range) { draft in
                                draft = draft
                                    .withCategoryName(index: index, name: selectedCategoryName)
                                    .withCategoryMinutes(index: index, minutes: category.minutes + 15)
                            }
                        }
                    }
                }
            }
        }
    }

    private func debugInsightsScopeButton(label: String, scope: InsightsScope) -> some View {
        let isSelected = debugInsightsEditableScope == scope

        return Button(label) {
            selectedInsightsScope = scope
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(isSelected ? debugControlSelectedForeground : primaryText)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(isSelected ? debugControlSelectedBackground : debugControlBackground, in: Capsule())
    }

    private func debugInsightsDeltaButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(debugControlBackground, in: Capsule())
    }

    private func debugInsightsMinutesInput(text: Binding<String>, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(primaryText)
                .frame(width: width)

            Text(AppLanguageRuntime.currentLanguage == .english ? "m" : "分")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(secondaryText)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(debugControlBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func shiftDebugInsightsRange(by direction: Int) {
        let scope = debugInsightsEditableScope
        if selectedInsightsScope != scope {
            selectedInsightsScope = scope
        }

        let dayOffset = scope == .day ? direction : 7 * direction
        if let next = Calendar.current.date(byAdding: .day, value: dayOffset, to: insightsAnchorDate) {
            insightsAnchorDate = next
        }
    }

    private func persistDebugInsightsDemoEnabled(_ isEnabled: Bool) {
        if isEnabled, selectedInsightsScope == .trend {
            selectedInsightsScope = .week
        }
        debugSharedDefaults.set(isEnabled, forKey: OnlyLockShared.debugScreenTimeInsightsOverrideEnabledKey)
        debugSharedDefaults.synchronize()
        screenTimeInsightsStore.refresh()
        if isEnabled {
            let scope = debugInsightsEditableScope
            let range = debugInsightsEditableRange
            warmedInsightsRangeKeys.insert(insightsRangeCacheKey(scope: scope, range: range))
        }
    }

    private func currentDebugInsightsOverride(
        for scope: InsightsScope,
        range: InsightsRange
    ) -> DebugInsightsSnapshotOverride {
        screenTimeInsightsStore.debugOverrideModel(
            for: scope.rawValue,
            rangeStart: range.start,
            rangeEnd: range.end
        ) ?? makeEmptyDebugInsightsOverride(for: scope, range: range)
    }

    private func updateDebugInsightsOverride(
        scope: InsightsScope,
        range: InsightsRange,
        mutate: (inout DebugInsightsSnapshotOverride) -> Void
    ) {
        var draft = currentDebugInsightsOverride(for: scope, range: range)
        mutate(&draft)
        screenTimeInsightsStore.saveDebugOverride(draft.sanitized)
        warmedInsightsRangeKeys.insert(insightsRangeCacheKey(scope: scope, range: range))
    }

    private func debugInsightsTargetNameBinding(
        scope: InsightsScope,
        range: InsightsRange,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let target = paddedDebugInsightsTargets(currentDebugInsightsOverride(for: scope, range: range).topTargets)[index]
                if let token = target.applicationToken, isApplicationFallbackName(target.name) {
                    return debugInsightsApplicationName(for: token, fallbackIndex: index)
                }
                return target.name
            },
            set: { newValue in
                updateDebugInsightsOverride(scope: scope, range: range) { draft in
                    draft = draft.withTargetName(index: index, name: newValue)
                }
            }
        )
    }

    private func debugInsightsTargetSelectionLabel(
        scope: InsightsScope,
        range: InsightsRange,
        index: Int
    ) -> String {
        let target = paddedDebugInsightsTargets(currentDebugInsightsOverride(for: scope, range: range).topTargets)[index]
        if let token = target.applicationToken {
            return debugInsightsApplicationName(for: token, fallbackIndex: index)
        }
        return AppLanguageRuntime.currentLanguage == .english ? "Choose app \(index + 1)" : "选择应用\(index + 1)"
    }

    private func debugInsightsPreviousTotalMinutesBinding(
        scope: InsightsScope,
        range: InsightsRange
    ) -> Binding<String> {
        Binding(
            get: {
                String(currentDebugInsightsOverride(for: scope, range: range).previousTotalMinutes)
            },
            set: { newValue in
                updateDebugInsightsOverride(scope: scope, range: range) { draft in
                    draft = draft.withPreviousTotalMinutes(debugMinutesValue(from: newValue))
                }
            }
        )
    }

    private func debugInsightsBucketMinutesBinding(
        scope: InsightsScope,
        range: InsightsRange,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let buckets = currentDebugInsightsOverride(for: scope, range: range).buckets
                guard buckets.indices.contains(index) else { return "0" }
                return String(buckets[index].totalMinutes)
            },
            set: { newValue in
                updateDebugInsightsOverride(scope: scope, range: range) { draft in
                    draft = draft.withBucketMinutes(index: index, totalMinutes: debugMinutesValue(from: newValue))
                }
            }
        )
    }

    private func debugInsightsTargetMinutesBinding(
        scope: InsightsScope,
        range: InsightsRange,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let targets = paddedDebugInsightsTargets(currentDebugInsightsOverride(for: scope, range: range).topTargets)
                guard targets.indices.contains(index) else { return "0" }
                return String(targets[index].minutes)
            },
            set: { newValue in
                updateDebugInsightsOverride(scope: scope, range: range) { draft in
                    draft = draft.withTargetMinutes(index: index, minutes: debugMinutesValue(from: newValue))
                }
            }
        )
    }

    private func debugInsightsCategoryMinutesBinding(
        scope: InsightsScope,
        range: InsightsRange,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let categories = paddedDebugInsightsCategories(currentDebugInsightsOverride(for: scope, range: range).topCategories)
                guard categories.indices.contains(index) else { return "0" }
                return String(categories[index].minutes)
            },
            set: { newValue in
                let selectedCategoryName = debugInsightsCategoryNameBinding(scope: scope, range: range, index: index).wrappedValue
                updateDebugInsightsOverride(scope: scope, range: range) { draft in
                    draft = draft
                        .withCategoryName(index: index, name: selectedCategoryName)
                        .withCategoryMinutes(index: index, minutes: debugMinutesValue(from: newValue))
                }
            }
        )
    }

    private func debugMinutesValue(from rawValue: String) -> Int {
        let digits = rawValue.filter(\.isNumber)
        guard let minutes = Int(digits) else { return 0 }
        return max(0, minutes)
    }

    private func makeEmptyDebugInsightsOverride(
        for scope: InsightsScope,
        range: InsightsRange
    ) -> DebugInsightsSnapshotOverride {
        DebugInsightsSnapshotOverride(
            scope: scope.rawValue,
            rangeStart: range.start,
            rangeEnd: range.end,
            previousTotalMinutes: 0,
            buckets: debugInsightsBucketLabels(for: scope).enumerated().map { index, label in
                DebugInsightsBucketOverride(
                    id: "\(scope.rawValue).bucket.\(index)",
                    label: label,
                    appMinutes: 0,
                    webMinutes: 0
                )
            },
            topTargets: [],
            topCategories: []
        )
    }

    private func makePrettyDebugInsightsOverride(
        for scope: InsightsScope,
        range: InsightsRange
    ) -> DebugInsightsSnapshotOverride {
        let preferredTargets = makePrettyDebugInsightsTargets(for: scope)
        let preferredCategories = makePrettyDebugInsightsCategories(for: scope)

        switch scope {
        case .day:
            let bucketLabels = debugInsightsBucketLabels(for: .day)
            let minutes = [6, 10, 18, 36, 84, 71, 43, 24]
            return DebugInsightsSnapshotOverride(
                scope: scope.rawValue,
                rangeStart: range.start,
                rangeEnd: range.end,
                previousTotalMinutes: 356,
                buckets: zip(bucketLabels.indices, bucketLabels).map { index, label in
                    DebugInsightsBucketOverride(
                        id: "day.bucket.\(index)",
                        label: label,
                        appMinutes: minutes[index],
                        webMinutes: 0
                    )
                },
                topTargets: preferredTargets,
                topCategories: preferredCategories
            )
        case .week:
            let bucketLabels = debugInsightsBucketLabels(for: .week)
            let minutes = [118, 142, 136, 165, 124, 88, 74]
            return DebugInsightsSnapshotOverride(
                scope: scope.rawValue,
                rangeStart: range.start,
                rangeEnd: range.end,
                previousTotalMinutes: 975,
                buckets: zip(bucketLabels.indices, bucketLabels).map { index, label in
                    DebugInsightsBucketOverride(
                        id: "week.bucket.\(index)",
                        label: label,
                        appMinutes: minutes[index],
                        webMinutes: 0
                    )
                },
                topTargets: preferredTargets,
                topCategories: preferredCategories
            )
        case .trend:
            return makeEmptyDebugInsightsOverride(for: scope, range: range)
        }
    }

    private func makePrettyDebugInsightsTargets(for scope: InsightsScope) -> [DebugInsightsTargetOverride] {
        let presetMinutes = scope == .day ? [92, 76, 53, 41] : [215, 182, 141, 109]
        let fallbackNames = scope == .day
            ? ["Instagram", "TikTok", "YouTube", "Safari"]
            : ["Instagram", "TikTok", "YouTube", "Reddit"]
        let appOptions = Array(availableDebugInsightsApplicationOptions.prefix(4))

        return presetMinutes.indices.map { index in
            if appOptions.indices.contains(index) {
                let option = appOptions[index]
                return DebugInsightsTargetOverride(
                    id: "demo.target.\(index)",
                    name: option.name,
                    minutes: presetMinutes[index],
                    kind: .app,
                    applicationToken: option.token
                )
            }

            return DebugInsightsTargetOverride(
                id: "demo.target.\(index)",
                name: fallbackNames[index],
                minutes: presetMinutes[index],
                kind: .app,
                applicationToken: nil
            )
        }
    }

    private func makePrettyDebugInsightsCategories(for scope: InsightsScope) -> [DebugInsightsTargetOverride] {
        let presetMinutes = scope == .day
            ? [148, 121, 96, 84, 71, 63, 52, 44, 37, 29, 21, 12]
            : [338, 291, 247, 214, 186, 167, 141, 126, 109, 93, 74, 52]
        let fallbackNames = AppLanguageRuntime.currentLanguage == .english
            ? ["Social", "Games", "Entertainment", "Information & Reading", "Health & Fitness", "Creativity", "Utilities", "Productivity & Finance", "Education", "Travel", "Shopping & Food", "Other"]
            : ["社交", "游戏", "娱乐", "信息与阅读", "健康与健身", "创意", "工具", "效率与财务", "教育", "旅行", "购物与美食", "其他"]

        return presetMinutes.indices.map { index in
            return DebugInsightsTargetOverride(
                id: "demo.category.\(index)",
                name: fallbackNames[index],
                minutes: presetMinutes[index],
                kind: .category,
                applicationToken: nil
            )
        }
    }

    private var debugInsightsCategoryOptions: [String] {
        if AppLanguageRuntime.currentLanguage == .english {
            return ["Social", "Games", "Entertainment", "Information & Reading", "Health & Fitness", "Creativity", "Utilities", "Productivity & Finance", "Education", "Travel", "Shopping & Food", "Other"]
        }
        return ["社交", "游戏", "娱乐", "信息与阅读", "健康与健身", "创意", "工具", "效率与财务", "教育", "旅行", "购物与美食", "其他"]
    }

    private func paddedDebugInsightsCategories(_ categories: [DebugInsightsTargetOverride]) -> [DebugInsightsTargetOverride] {
        var padded = categories
        while padded.count < 4 {
            padded.append(
                DebugInsightsTargetOverride(
                    id: "demo.category.\(padded.count)",
                    name: debugInsightsCategoryOptions[min(padded.count, max(0, debugInsightsCategoryOptions.count - 1))],
                    minutes: 0,
                    kind: .category,
                    applicationToken: nil,
                    categoryToken: nil
                )
            )
        }
        return Array(padded.prefix(4))
    }

    private func debugInsightsCategoryNameBinding(
        scope: InsightsScope,
        range: InsightsRange,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let category = paddedDebugInsightsCategories(currentDebugInsightsOverride(for: scope, range: range).topCategories)[index]
                let fallback = debugInsightsCategoryOptions[min(index, max(0, debugInsightsCategoryOptions.count - 1))]
                return category.name.isEmpty ? fallback : category.name
            },
            set: { newValue in
                updateDebugInsightsOverride(scope: scope, range: range) { draft in
                    draft = draft.withCategoryName(index: index, name: newValue)
                }
            }
        )
    }

    private func debugInsightsBucketLabels(for scope: InsightsScope) -> [String] {
        switch scope {
        case .day:
            return ["00", "03", "06", "09", "12", "15", "18", "21"]
        case .week:
            if AppLanguageRuntime.currentLanguage == .english {
                return ["M", "T", "W", "T", "F", "S", "S"]
            }
            return ["一", "二", "三", "四", "五", "六", "日"]
        case .trend:
            return []
        }
    }

    private func paddedDebugInsightsTargets(_ targets: [DebugInsightsTargetOverride]) -> [DebugInsightsTargetOverride] {
        var padded = targets
        while padded.count < 4 {
            padded.append(
                DebugInsightsTargetOverride(
                    id: "demo.target.\(padded.count)",
                    name: "",
                    minutes: 0,
                    kind: .app,
                    applicationToken: nil
                )
            )
        }
        return Array(padded.prefix(4))
    }

    private func applyDebugInsightsAvailableAppTokens(scope: InsightsScope, range: InsightsRange) {
        let options = Array(availableDebugInsightsApplicationOptions.prefix(4))
        guard !options.isEmpty else { return }
        let defaultMinutes = scope == .day ? [92, 76, 53, 41] : [215, 182, 141, 109]

        updateDebugInsightsOverride(scope: scope, range: range) { draft in
            for (index, option) in options.enumerated() {
                let currentMinutes = paddedDebugInsightsTargets(draft.topTargets)[index].minutes
                let preferredMinutes = currentMinutes > 0 ? currentMinutes : defaultMinutes[index]
                draft = draft
                    .withTargetApplicationToken(index: index, token: option.token, preferredName: option.name)
                    .withTargetMinutes(index: index, minutes: preferredMinutes)
            }
            if draft.topCategories.isEmpty {
                draft = draft.withCategoryTargets(makePrettyDebugInsightsCategories(for: scope))
            }
        }
    }

#if DEBUG
    private var debugWeeklyReportDemoControls: some View {
        let weekStart = startOfWeekMonday(containing: debugWeeklyReportWeekStart)
        let override = currentDebugWeeklyReportOverride(forWeekStart: weekStart)
        let currentBuckets = Array(override.current.buckets.prefix(7))
        let previousBuckets = Array(override.previous.buckets.prefix(7))
        let currentTargets = paddedDebugWeeklyReportTargets(override.current.topTargets)

        return VStack(alignment: .leading, spacing: 8) {
            Text(onlyLockL("周报 Demo 数据"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(secondaryText)

            HStack(spacing: 6) {
                Button(onlyLockL("上一周")) {
                    shiftDebugWeeklyReportWeek(by: -1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(debugControlBackground, in: Capsule())

                Text(debugWeeklyReportWeekText(weekStart: weekStart))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .frame(maxWidth: .infinity, alignment: .center)

                Button(onlyLockL("下一周")) {
                    shiftDebugWeeklyReportWeek(by: 1)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(debugControlBackground, in: Capsule())
            }

            HStack(spacing: 6) {
                Button(onlyLockL("填充好看数据")) {
                    screenTimeInsightsStore.saveDebugWeeklyReportOverride(
                        makePrettyDebugWeeklyReportOverride(forWeekStart: weekStart)
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlSelectedBackground, in: Capsule())
                .foregroundStyle(debugControlSelectedForeground)

                Button(onlyLockL("清除当前周")) {
                    screenTimeInsightsStore.removeDebugWeeklyReportOverride(forWeekStart: weekStart)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())

                Spacer(minLength: 0)

                Button(onlyLockL("打开预览")) {
                    let presentation = debugWeeklyReportPresentation(forWeekStart: weekStart)
                    isFlipPreviewPanelExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        activeWeeklyReport = presentation
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(debugControlBackground, in: Capsule())
            }

            HStack(spacing: 8) {
                debugWeeklyReportSummaryChip(
                    title: onlyLockL("本周总时长"),
                    value: weeklyDurationText(override.current.asSnapshot.totalMinutes)
                )
                debugWeeklyReportSummaryChip(
                    title: onlyLockL("上周总时长"),
                    value: weeklyDurationText(override.previous.asSnapshot.totalMinutes)
                )
                debugWeeklyReportSummaryChip(
                    title: onlyLockL("专注分"),
                    value: "\(weeklyFocusScore(snapshot: override.current.asSnapshot))"
                )
            }

            debugWeeklyReportBucketEditor(
                title: onlyLockL("本周折线分钟"),
                buckets: currentBuckets,
                update: { index, delta in
                    updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                        draft = draft.withCurrentBucketMinutes(index: index, totalMinutes: max(0, currentBuckets[index].totalMinutes + delta))
                    }
                },
                minutesText: { index in
                    debugWeeklyReportCurrentBucketMinutesBinding(weekStart: weekStart, index: index)
                }
            )

            debugWeeklyReportBucketEditor(
                title: onlyLockL("上周折线分钟"),
                buckets: previousBuckets,
                update: { index, delta in
                    updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                        draft = draft.withPreviousBucketMinutes(index: index, totalMinutes: max(0, previousBuckets[index].totalMinutes + delta))
                    }
                },
                minutesText: { index in
                    debugWeeklyReportPreviousBucketMinutesBinding(weekStart: weekStart, index: index)
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(onlyLockL("Top App"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryText)

                if !availableDebugInsightsApplicationOptions.isEmpty {
                    Text(
                        AppLanguageRuntime.currentLanguage == .english
                            ? "Home selector apps \(availableDebugInsightsApplicationOptions.count)"
                            : "首页已选应用 \(availableDebugInsightsApplicationOptions.count) 个"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(secondaryText)

                    Button(
                        AppLanguageRuntime.currentLanguage == .english
                            ? "Auto-fill from Home selection"
                            : "用首页已选应用自动填充"
                    ) {
                        guard let firstOption = availableDebugInsightsApplicationOptions.first else { return }
                        updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                            let currentMinutes = paddedDebugWeeklyReportTargets(draft.current.topTargets)[0].minutes
                            let preferredMinutes = currentMinutes > 0 ? currentMinutes : 120
                            draft = draft
                                .withCurrentTargetApplicationToken(index: 0, token: firstOption.token, preferredName: "")
                                .withCurrentTargetMinutes(index: 0, minutes: preferredMinutes)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(debugControlSelectedBackground, in: Capsule())
                    .foregroundStyle(debugControlSelectedForeground)
                }

                ForEach(Array(currentTargets.enumerated().prefix(1)), id: \.offset) { index, target in
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(availableDebugInsightsApplicationOptions) { option in
                                Button {
                                    updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                                        let currentMinutes = paddedDebugWeeklyReportTargets(draft.current.topTargets)[index].minutes
                                        let preferredMinutes = currentMinutes > 0 ? currentMinutes : 120
                                        draft = draft
                                            .withCurrentTargetApplicationToken(index: index, token: option.token, preferredName: "")
                                            .withCurrentTargetMinutes(index: index, minutes: preferredMinutes)
                                    }
                                } label: {
                                    Label(option.token)
                                        .labelStyle(.titleOnly)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                debugWeeklyReportTargetSelectionLabelView(weekStart: weekStart, index: index)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(debugControlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Text(weeklyShortDuration(target.minutes))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(primaryText)
                            .frame(width: 54, alignment: .trailing)

                        debugInsightsDeltaButton("-15") {
                            updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                                draft = draft.withCurrentTargetMinutes(index: index, minutes: max(0, target.minutes - 15))
                            }
                        }

                        debugInsightsDeltaButton("+15") {
                            updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                                draft = draft.withCurrentTargetMinutes(index: index, minutes: target.minutes + 15)
                            }
                        }
                    }
                }
            }
        }
    }

    private func debugWeeklyReportBucketEditor(
        title: String,
        buckets: [DebugInsightsBucketOverride],
        update: @escaping (_ index: Int, _ delta: Int) -> Void,
        minutesText: @escaping (_ index: Int) -> Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(secondaryText)

            ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                HStack(spacing: 8) {
                    Text(bucket.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .frame(width: 28, alignment: .leading)

                    Spacer(minLength: 0)

                    debugInsightsMinutesInput(
                        text: minutesText(index),
                        width: 58
                    )

                    debugInsightsDeltaButton("-15") {
                        update(index, -15)
                    }

                    debugInsightsDeltaButton("+15") {
                        update(index, 15)
                    }
                }
            }
        }
    }

    private func debugWeeklyReportCurrentBucketMinutesBinding(
        weekStart: Date,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let buckets = Array(currentDebugWeeklyReportOverride(forWeekStart: weekStart).current.buckets.prefix(7))
                guard buckets.indices.contains(index) else { return "0" }
                return String(buckets[index].totalMinutes)
            },
            set: { newValue in
                updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                    draft = draft.withCurrentBucketMinutes(index: index, totalMinutes: debugMinutesValue(from: newValue))
                }
            }
        )
    }

    private func debugWeeklyReportPreviousBucketMinutesBinding(
        weekStart: Date,
        index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                let buckets = Array(currentDebugWeeklyReportOverride(forWeekStart: weekStart).previous.buckets.prefix(7))
                guard buckets.indices.contains(index) else { return "0" }
                return String(buckets[index].totalMinutes)
            },
            set: { newValue in
                updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                    draft = draft.withPreviousBucketMinutes(index: index, totalMinutes: debugMinutesValue(from: newValue))
                }
            }
        )
    }

    private func debugWeeklyReportSummaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(secondaryText)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(debugControlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func shiftDebugWeeklyReportWeek(by direction: Int) {
        if let next = Calendar.current.date(byAdding: .day, value: direction * 7, to: debugWeeklyReportWeekStart) {
            debugWeeklyReportWeekStart = startOfWeekMonday(containing: next)
        }
    }

    private func persistDebugWeeklyReportDemoEnabled(_ isEnabled: Bool) {
        debugSharedDefaults.set(isEnabled, forKey: OnlyLockShared.debugWeeklyReportOverrideEnabledKey)
        debugSharedDefaults.synchronize()
        screenTimeInsightsStore.refresh()
    }

    private func currentDebugWeeklyReportOverride(forWeekStart weekStart: Date) -> DebugWeeklyReportOverride {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        return screenTimeInsightsStore.debugWeeklyReportOverride(forWeekStart: normalizedWeekStart)
            ?? makeEmptyDebugWeeklyReportOverride(forWeekStart: normalizedWeekStart)
    }

    private func updateDebugWeeklyReportOverride(
        forWeekStart weekStart: Date,
        mutate: (inout DebugWeeklyReportOverride) -> Void
    ) {
        var draft = currentDebugWeeklyReportOverride(forWeekStart: weekStart)
        mutate(&draft)
        screenTimeInsightsStore.saveDebugWeeklyReportOverride(draft.sanitized)
    }

    private func makeEmptyDebugWeeklyReportOverride(forWeekStart weekStart: Date) -> DebugWeeklyReportOverride {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let previousWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: normalizedWeekStart) ?? normalizedWeekStart
        return DebugWeeklyReportOverride(
            weekStart: normalizedWeekStart,
            current: makeEmptyDebugInsightsOverride(for: .week, range: InsightsRange(
                start: normalizedWeekStart,
                end: Calendar.current.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart
            )),
            previous: makeEmptyDebugInsightsOverride(for: .week, range: InsightsRange(
                start: previousWeekStart,
                end: Calendar.current.date(byAdding: .day, value: 7, to: previousWeekStart) ?? previousWeekStart
            ))
        )
    }

    private func makePrettyDebugWeeklyReportOverride(forWeekStart weekStart: Date) -> DebugWeeklyReportOverride {
        let normalizedWeekStart = startOfWeekMonday(containing: weekStart)
        let previousWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: normalizedWeekStart) ?? normalizedWeekStart
        let labels = AppLanguageRuntime.currentLanguage == .english
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["一", "二", "三", "四", "五", "六", "日"]

        let currentBuckets = [126, 141, 118, 132, 104, 95, 88]
        let previousBuckets = [147, 158, 143, 151, 129, 122, 110]
        let appOptions = Array(availableDebugInsightsApplicationOptions.prefix(1))
        let fallbackNames = AppLanguageRuntime.currentLanguage == .english
            ? ["YouTube", "TikTok", "Instagram"]
            : ["YouTube", "TikTok", "Instagram"]

        let currentTargets: [DebugInsightsTargetOverride] = (0..<1).map { index in
            if appOptions.indices.contains(index) {
                let option = appOptions[index]
                return DebugInsightsTargetOverride(
                    id: "weekly.demo.target.\(index)",
                    name: option.name,
                    minutes: [236][index],
                    kind: .app,
                    applicationToken: option.token,
                    categoryToken: nil
                )
            }
            return DebugInsightsTargetOverride(
                id: "weekly.demo.target.\(index)",
                name: fallbackNames[index],
                minutes: [236][index],
                kind: .app,
                applicationToken: nil,
                categoryToken: nil
            )
        }

        return DebugWeeklyReportOverride(
            weekStart: normalizedWeekStart,
            current: DebugInsightsSnapshotOverride(
                scope: "week",
                rangeStart: normalizedWeekStart,
                rangeEnd: Calendar.current.date(byAdding: .day, value: 7, to: normalizedWeekStart) ?? normalizedWeekStart,
                previousTotalMinutes: previousBuckets.reduce(0, +),
                buckets: zip(labels.indices, labels).map { index, label in
                    DebugInsightsBucketOverride(id: "weekly.current.bucket.\(index)", label: label, appMinutes: currentBuckets[index], webMinutes: 0)
                },
                topTargets: currentTargets,
                topCategories: []
            ),
            previous: DebugInsightsSnapshotOverride(
                scope: "week",
                rangeStart: previousWeekStart,
                rangeEnd: Calendar.current.date(byAdding: .day, value: 7, to: previousWeekStart) ?? previousWeekStart,
                previousTotalMinutes: 0,
                buckets: zip(labels.indices, labels).map { index, label in
                    DebugInsightsBucketOverride(id: "weekly.previous.bucket.\(index)", label: label, appMinutes: previousBuckets[index], webMinutes: 0)
                },
                topTargets: [],
                topCategories: []
            )
        )
    }

    private func debugWeeklyReportWeekText(weekStart: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        if AppLanguageRuntime.currentLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        } else {
            formatter.dateFormat = "M月d日"
        }
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: end))"
    }

    private func debugWeeklyReportPresentation(forWeekStart weekStart: Date) -> WeeklyReportPresentation {
        let override = currentDebugWeeklyReportOverride(forWeekStart: weekStart).sanitized
        return WeeklyReportPresentation(
            id: "debug.weekly.\(Int(override.weekStart.timeIntervalSince1970))",
            current: override.current.asSnapshot,
            previous: override.previous.asSnapshot
        )
    }

    private func savedDebugWeeklyReportPresentation(forWeekStart weekStart: Date) -> WeeklyReportPresentation? {
        guard let override = screenTimeInsightsStore.debugWeeklyReportOverride(forWeekStart: weekStart)?.sanitized else {
            return nil
        }
        return WeeklyReportPresentation(
            id: "debug.weekly.\(Int(override.weekStart.timeIntervalSince1970))",
            current: override.current.asSnapshot,
            previous: override.previous.asSnapshot
        )
    }

    private func debugWeeklyReportTargetNameBinding(weekStart: Date, index: Int) -> Binding<String> {
        Binding(
            get: {
                let target = paddedDebugWeeklyReportTargets(currentDebugWeeklyReportOverride(forWeekStart: weekStart).current.topTargets)[index]
                if let token = target.applicationToken, isApplicationFallbackName(target.name) {
                    return debugInsightsApplicationName(for: token, fallbackIndex: index)
                }
                return target.name
            },
            set: { newValue in
                updateDebugWeeklyReportOverride(forWeekStart: weekStart) { draft in
                    draft = draft.withCurrentTargetName(index: index, name: newValue)
                }
            }
        )
    }

    @ViewBuilder
    private func debugWeeklyReportTargetSelectionLabelView(weekStart: Date, index: Int) -> some View {
        let target = paddedDebugWeeklyReportTargets(currentDebugWeeklyReportOverride(forWeekStart: weekStart).current.topTargets)[index]
        if let token = target.applicationToken {
            Label(token)
                .labelStyle(.titleOnly)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            Text(AppLanguageRuntime.currentLanguage == .english ? "Choose app \(index + 1)" : "选择应用\(index + 1)")
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func paddedDebugWeeklyReportTargets(_ targets: [DebugInsightsTargetOverride]) -> [DebugInsightsTargetOverride] {
        var padded = targets
        while padded.count < 1 {
            padded.append(
                DebugInsightsTargetOverride(
                    id: "weekly.demo.target.\(padded.count)",
                    name: "",
                    minutes: 0,
                    kind: .app,
                    applicationToken: nil
                )
            )
        }
        return Array(padded.prefix(1))
    }
#endif

    private func applyDebugShield(at now: Date) {
        let activeRules = viewModel.rules.filter { rule in
            isDebugRuleActive(rule, at: now) && rule.hasAnyTarget
        }

        guard !activeRules.isEmpty else {
            debugShieldStore.clearAllSettings()
            return
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

        debugShieldStore.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        debugShieldStore.shield.applicationCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)
        debugShieldStore.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens
        debugShieldStore.shield.webDomainCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)

        var blockedDomains = Set(webDomainTokens.map { WebDomain(token: $0) })
        blockedDomains.formUnion(manualWebDomains.map { WebDomain(domain: $0) })
        debugShieldStore.webContent.blockedByFilter = blockedDomains.isEmpty ? nil : .specific(blockedDomains)
    }

    private func isDebugRuleActive(_ rule: LockRule, at now: Date) -> Bool {
        if rule.isWeeklyRepeat {
            guard let active = repeatActiveWindow(for: rule, now: now) else {
                return false
            }
            return now >= active.start && now < active.end
        }

        guard let endAt = rule.endAt else {
            return false
        }

        let normalizedNow = normalizedToMinute(now)
        let normalizedStart = normalizedToMinute(rule.startAt)
        let normalizedEnd = normalizedToMinute(endAt)
        return normalizedNow >= normalizedStart && normalizedNow < normalizedEnd
    }

    private func normalizedToMinute(_ date: Date) -> Date {
        OnlyLockShared.normalizedToMinuteBoundary(date)
    }

    private func syncDebugMembershipTierOverrideFromDefaults() {
        debugMembershipTierOverride = SettingsStore.MembershipTier(
            rawValue: debugSharedDefaults.string(forKey: OnlyLockShared.membershipTierKey) ?? ""
        ) ?? .none
        if debugMembershipTierOverride == .monthly {
            let expiration = debugSharedDefaults.double(forKey: OnlyLockShared.membershipExpirationTimestampKey)
            isDebugMembershipExpiredOverride = expiration > 0 && expiration <= Date().timeIntervalSince1970
        } else {
            isDebugMembershipExpiredOverride = false
        }
    }
#endif

    private var customTabBar: some View {
        HStack(spacing: 10) {
            customTabItem(.create)
            customTabItem(.current)
            customTabItem(.rewards)
            customTabItem(.settings)
        }
        .padding(.horizontal, 12)
        .padding(.top, 1)
        .padding(.bottom, 1)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: customTabBarReservedHeight, alignment: .top)
        .background(pageBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
        }
    }

    private func customTabItem(_ tab: RootTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(customTabActiveColor)
                }

                customTabIcon(for: tab, isSelected: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func customTabIcon(for tab: RootTab, isSelected: Bool) -> some View {
        let tint = isSelected ? Color.white : customTabInactiveIconColor

        switch tab {
        case .create:
            ZStack {
                Image(systemName: "viewfinder")
                    .font(.system(size: 24, weight: .semibold))
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .offset(y: 1)
            }
            .foregroundStyle(tint)
        case .current:
            Image(systemName: "hourglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
        case .rewards:
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(tint)
        case .settings:
            Image(systemName: "person.fill")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(tint)
        }
    }

    private var createTopBar: some View {
        collapsibleTopBar(
            title: "OnlyLock",
            isCollapsed: isTopBarCollapsed,
            showIcon: true,
            titleSize: 24,
            streakCount: currentStreakForDisplay,
            horizontalPadding: 24
        )
    }

    private var progressTopBar: some View {
        collapsibleTopBar(
            title: "进度",
            isCollapsed: isProgressTopBarCollapsed,
            showIcon: false,
            titleSize: 26,
            streakCount: nil,
            horizontalPadding: 32
        )
    }

    private var rewardsTopBar: some View {
        ZStack {
            collapsibleTopBar(
                title: "分析",
                isCollapsed: isRewardsTopBarCollapsed,
                showIcon: false,
                titleSize: 26,
                streakCount: nil,
                horizontalPadding: 32
            )

            HStack {
                Spacer()
                Button {
                    if hasActiveMembership {
                        screenTimeInsightsStore.refresh()
                        isWeeklyInsightsHistoryPresented = true
                    } else {
                        presentMembershipRenewal()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(primaryText)
                            .frame(width: 32, height: 32)

                        if weeklyReportUnreadCount > 0 {
                            Text(weeklyReportUnreadCount > 99 ? "99+" : "\(weeklyReportUnreadCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, weeklyReportUnreadCount > 9 ? 5 : 0)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Color.red, in: Capsule())
                                .offset(x: 8, y: -6)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
        }
    }

    private var settingsTopBar: some View {
        collapsibleTopBar(
            title: "个人中心",
            isCollapsed: isSettingsTopBarCollapsed,
            showIcon: false,
            titleSize: 26,
            streakCount: nil,
            horizontalPadding: 32
        )
    }

    private func collapsibleTopBar(
        title: String,
        isCollapsed: Bool,
        showIcon: Bool,
        titleSize: CGFloat,
        streakCount: Int?,
        horizontalPadding: CGFloat
    ) -> some View {
        let localizedTitle = onlyLockL(title)
        return HStack(spacing: 6) {
            if showIcon {
                appMarkIcon
                    .opacity(isCollapsed ? 0 : 1)
                    .frame(width: isCollapsed ? 0 : 48, height: 48)
                    .clipped()
            }

            Text(localizedTitle)
                .font(.system(size: titleSize, weight: .bold, design: .default))
                .tracking(-0.6)
                .foregroundStyle(primaryText)
                .opacity(isCollapsed ? 0 : 1)

            Spacer()

            if let streakCount {
                streakBadge(count: streakCount)
                    .opacity(isCollapsed ? 0 : 1)
                    .frame(width: isCollapsed ? 0 : nil)
                    .clipped()
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: 64)
        .overlay {
            Text(localizedTitle)
                .font(.system(size: titleSize, weight: .bold, design: .default))
                .tracking(-0.6)
                .foregroundStyle(primaryText)
                .opacity(isCollapsed ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.22), value: isCollapsed)
    }

    private func streakBadge(count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "flame")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(primaryText)

            Text("\(count)")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(primaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 66)
        .frame(height: 30)
        .background(cardBackground, in: Capsule())
    }

    private var appMarkIcon: some View {
        Rectangle()
            .fill(primaryText)
            .frame(width: 48, height: 48)
            .mask(
                Image("AppMark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            )
            .accessibilityHidden(true)
    }

    private var targetsCard: some View {
        AnyView(targetsCardContent)
    }

    private var targetsCardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            targetsCardHeader
            targetsCardStats
            targetsPickerButton
            targetsSelectionContent
        }
    }

    private var targetsCardHeader: some View {
        Text(onlyLockL("选择要锁定的内容"))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(secondaryText)
    }

    private var targetsCardStats: some View {
        HStack(spacing: 12) {
            statTile(icon: .appStoreVector, value: "\(viewModel.selectedAppCount)", label: "APP")
            statTile(icon: .globeVector, value: "\(viewModel.selectedWebCount)", label: onlyLockL("网站"))
            statTile(icon: .totalVector, value: "\(viewModel.totalTargetCount)", label: onlyLockL("总数"))
        }
    }

    private var targetsPickerButton: some View {
        Button {
            guard hasActiveMembership else {
                presentMembershipRenewal()
                return
            }
            startAuthorizationFlow(for: .appPicker)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                Text(onlyLockL("选择"))
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(colorScheme == .dark ? Color.white : Color.black)
        }
    }

    private var targetsSelectionContent: some View {
        TargetsSelectionContentView(
            selectedAppCount: viewModel.selectedAppCount,
            selectedWebCount: viewModel.selectedWebCount,
            selectedCategoryCount: viewModel.selectedCategoryCount,
            visibleSelectedApplicationTokens: visibleSelectedApplicationTokens,
            visibleSelectedWebsiteItems: visibleSelectedWebsiteItems,
            isShowingAllSelectedApps: isShowingAllSelectedApps,
            isShowingAllSelectedWebsites: isShowingAllSelectedWebsites,
            manualDomainDraft: $manualDomainDraft,
            colorScheme: colorScheme,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dividerColor: dividerColor,
            cardBackground: cardBackground,
            removeIconPrimary: removeIconPrimary,
            removeIconSecondary: removeIconSecondary,
            onToggleSelectedAppsExpansion: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingAllSelectedApps.toggle()
                }
            },
            onToggleSelectedWebsitesExpansion: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isShowingAllSelectedWebsites.toggle()
                }
            },
            onRemoveApplication: { token in
                viewModel.removeApplicationToken(token)
            },
            onRemoveManualWebDomain: { domain in
                viewModel.removeManualWebDomain(domain)
            },
            onRemoveWebDomainToken: { token in
                viewModel.removeWebDomainToken(token)
            },
            onSubmitManualWebsiteDraft: submitManualWebsiteDraft
        )
    }

    private var visibleSelectedApplicationTokens: [ApplicationToken] {
        let all = viewModel.orderedApplicationTokens
        if isShowingAllSelectedApps || all.count <= 3 {
            return all
        }

        return Array(all.prefix(3))
    }

    private var allSelectedWebsiteItems: [SelectedWebsiteDisplayItem] {
        viewModel.sortedManualWebDomains.map { .manual($0) } +
            viewModel.orderedWebDomainTokens.map { .token($0) }
    }

    private var visibleSelectedWebsiteItems: [SelectedWebsiteDisplayItem] {
        let all = allSelectedWebsiteItems
        if isShowingAllSelectedWebsites || all.count <= 3 {
            return all
        }

        return Array(all.prefix(3))
    }

    private var scheduleCard: some View {
        AnyView(scheduleCardContent)
    }

    private var scheduleCardContent: some View {
        ScheduleCardContentView(
            startAt: $viewModel.startAt,
            durationText: $viewModel.durationText,
            isWeeklyRepeat: $viewModel.isWeeklyRepeat,
            repeatWeekdays: $viewModel.repeatWeekdays,
            scheduleTimeInputMode: $scheduleTimeInputMode,
            endAtDraft: $endAtDraft,
            errorMessage: viewModel.errorMessage,
            infoMessage: viewModel.infoMessage,
            primaryText: primaryText,
            secondaryText: secondaryText,
            dividerColor: dividerColor,
            cardBackground: cardBackground,
            scheduleSubsectionTitleFont: scheduleSubsectionTitleFont,
            onDismissKeyboard: dismissKeyboard
        )
    }

    private var taskCard: some View {
        AnyView(taskCardContent)
    }

    private var taskCardContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 0.5)

            Text(onlyLockL("设置任务名（可选）"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(secondaryText)

            TextField(onlyLockL("给这个锁定任务起个名字"), text: $viewModel.taskName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(primaryText)
                .padding(.horizontal, 20)
                .frame(height: 64)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                saveRule()
            } label: {
                HStack(spacing: 10) {
                    if isSavingRule {
                        ProgressView()
                            .tint(colorScheme == .dark ? .black : .white)
                    }

                    Text(onlyLockL("开始锁定"))
                        .font(.system(size: 16, weight: .bold))
                        .tracking(0.2)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .background(colorScheme == .dark ? Color.white : Color.black)
            }
            .disabled(isSavingRule || !viewModel.canSave)
            .opacity((isSavingRule || !viewModel.canSave) ? 0.65 : 1)
        }
    }

    private var currentLockEmptyState: some View {
        // Keep vertical anchor aligned with unauthorized insights prompt.
        // Rewards has a scope picker row (~56pt) above the prompt; mirror that offset here.
        let unifiedTopAnchorOffset: CGFloat = 56

        return unifiedCenteredStateCard(
            icon: emptyTaskVectorIcon.offset(x: 4),
            title: onlyLockL("你还没有锁定任务"),
            buttonTitle: onlyLockL("去新建"),
            action: {
                selectedTab = .create
            }
        ) {
            EmptyView()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8 + unifiedTopAnchorOffset)
        .padding(.bottom, customTabBarReservedHeight + 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func sortedRulesForDisplay(now: Date) -> [LockRule] {
        let ordered = viewModel.rules.sorted { lhs, rhs in
            let lhsPhase = currentTaskPhase(for: lhs, now: now)
            let rhsPhase = currentTaskPhase(for: rhs, now: now)
            let lhsPriority = taskPhaseSortPriority(for: lhsPhase)
            let rhsPriority = taskPhaseSortPriority(for: rhsPhase)

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            let lhsAnchor = taskSortAnchorDate(for: lhs, phase: lhsPhase, now: now)
            let rhsAnchor = taskSortAnchorDate(for: rhs, phase: rhsPhase, now: now)
            let isAscending = sortsAscendingWithinPhase(lhsPhase)

            if lhsAnchor != rhsAnchor {
                return isAscending ? (lhsAnchor < rhsAnchor) : (lhsAnchor > rhsAnchor)
            }

            let lhsStart = effectiveStartAt(for: lhs, now: now)
            let rhsStart = effectiveStartAt(for: rhs, now: now)
            if lhsStart != rhsStart {
                return isAscending ? (lhsStart < rhsStart) : (lhsStart > rhsStart)
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
        }

#if DEBUG
        debugValidateTimelineOrder(ordered, now: now)
#endif
        return ordered
    }

    private func currentLockList(now: Date) -> some View {
        let orderedRules = sortedRulesForDisplay(now: now)

        return ScrollView {
            ScrollViewOffsetObserver { offsetY in
                guard isTopBarStateUpdatesEnabled else { return }
                let shouldCollapse = offsetY > 2
                if shouldCollapse != isProgressTopBarCollapsed {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isProgressTopBarCollapsed = shouldCollapse
                    }
                }
            }
            .frame(height: 0)

            VStack(alignment: .leading, spacing: 28) {
                streakCard(now: now)

                VStack(alignment: .leading, spacing: 12) {
                    Text(onlyLockL("时间轴"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(secondaryText)

                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: 1)
                            .padding(.leading, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 16)

                        VStack(spacing: 24) {
                            ForEach(Array(orderedRules.enumerated()), id: \.element.id) { item in
                                let entry = item.element
                                timelineTaskRow(
                                    rule: entry,
                                    now: now
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 6)
            .padding(.bottom, customTabBarReservedHeight + 24)
        }
    }

    private func timelineTaskRow(rule: LockRule, now: Date) -> some View {
        let phase = currentTaskPhase(for: rule, now: now)

        return HStack(alignment: .top, spacing: 14) {
            timelineAxisMarker(rule: rule, phase: phase, now: now)

            timelineTaskCard(rule: rule, now: now, phase: phase)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timelineAxisMarker(rule: LockRule, phase: CurrentTaskPhase, now: Date) -> some View {
        VStack(spacing: 4) {
            Text(timelineAxisDateText(for: rule, phase: phase, now: now))
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(timelineAxisDateForeground(for: phase))
                .padding(.horizontal, 4)
                .padding(.vertical, phase == .active ? 2 : 0)
                .background(timelineAxisDateBackground(for: phase))
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(timelineAxisMarkerFill(for: phase))
                .frame(width: 10, height: 10)
        }
        .frame(width: 42, alignment: .top)
    }

    private func timelineTaskCard(rule: LockRule, now: Date, phase: CurrentTaskPhase) -> some View {
        let isActive = phase == .active
        let isUpcoming = phase == .upcoming
        let isEndedFallbackTitle = (phase == .ended || phase == .paused) && normalizedTaskName(rule.name) == nil
        let titleText = isActive ? activeTimelineTitle(for: rule) : currentTaskDisplayTitle(for: rule, now: now)
        let hasVisibleTitle = !titleText.isEmpty

        return VStack(alignment: .leading, spacing: isActive ? 18 : 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(timelinePhaseLabel(for: phase))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryText)
                    Text(timelineTimeRange(for: rule, phase: phase, now: now))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(secondaryText)
                    if rule.isWeeklyRepeat {
                        Text(timelineRepeatWeekdaysText(for: rule))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 0)

                if isActive {
                    timelineProgressRing(fraction: activeTaskProgressFraction(rule: rule, now: now))
                } else if phase == .upcoming {
                    timelineDeleteTaskButton(fontSize: 16) {
                        pendingDeletionRuleID = rule.id
                    }
                }
            }

            if hasVisibleTitle {
                Text(titleText)
                    .font(.system(size: isActive ? 40 : (isEndedFallbackTitle ? 30 : 36), weight: .heavy))
                    .foregroundStyle(primaryText)
                    .lineLimit(
                        isActive
                            ? 2
                            : (isEndedFallbackTitle && AppLanguageRuntime.currentLanguage == .english ? 2 : 1)
                    )
                    .minimumScaleFactor(isEndedFallbackTitle ? 0.5 : 0.72)
                    .allowsTightening(!isActive)
            }

            if isActive {
                let hasStackedTargets = timelineHasStackedTargets(rule)

                FlipCountdownText(
                    value: activeTaskCountdownText(rule: rule, now: now),
                    color: primaryText,
                    alignment: .center
                )

                HStack(alignment: hasStackedTargets ? .bottom : .center, spacing: 12) {
                    timelineLockedTargetsView(for: rule)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    timelineDeleteTaskButton(fontSize: 16) {
                        pendingDeletionRuleID = rule.id
                    }
                    .fixedSize()
                    .offset(y: hasStackedTargets ? 0 : 1)
                }
            } else if isUpcoming {
                let hasStackedTargets = timelineHasStackedTargets(rule)

                FlipCountdownText(
                    value: upcomingTaskCountdownText(rule: rule, now: now),
                    color: primaryText,
                    alignment: .center
                )

                HStack(alignment: hasStackedTargets ? .bottom : .center, spacing: 12) {
                    timelineLockedTargetsView(for: rule)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    timelineDurationBadge(minutes: rule.durationMinutes)
                        .fixedSize()
                        .offset(y: hasStackedTargets ? 0 : 1)
                }
            } else {
                let subheadline = currentTaskDisplaySubheadline(for: rule, now: now)
                let hasStackedTargets = timelineHasStackedTargets(rule)
                let durationMinutes = phase == .paused
                    ? pausedLockedDurationMinutes(for: rule, now: now)
                    : rule.durationMinutes

                if !subheadline.isEmpty {
                    Text(subheadline)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .lineSpacing(3)
                        .lineLimit(
                            normalizedTaskName(rule.name) != nil
                            && phase == .ended
                            && AppLanguageRuntime.currentLanguage == .english
                            ? 2
                            : nil
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: hasStackedTargets ? .bottom : .center, spacing: 12) {
                    timelineLockedTargetsView(for: rule)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    timelineDurationBadge(minutes: durationMinutes)
                        .fixedSize()
                        .offset(y: hasStackedTargets ? 0 : 1)
                }
            }
        }
        .padding(isActive ? 22 : 18)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(timelineCardBorderColor(for: phase), lineWidth: isActive ? 2 : 1)
        )
    }

    private func timelineDeleteTaskButton(fontSize: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(onlyLockL("删除任务"))
                .font(.system(size: fontSize, weight: .semibold))
                .underline()
                .foregroundStyle(secondaryText)
        }
        .buttonStyle(.plain)
    }

    private var pendingDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletionRuleID != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionRuleID = nil
                }
            }
        )
    }

    private var pendingWeeklyReportDeletionAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletedWeeklyReportWeekStart != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletedWeeklyReportWeekStart = nil
                }
            }
        )
    }

    private func confirmPendingDeletion() {
        guard let ruleID = pendingDeletionRuleID else { return }

        viewModel.deleteRule(id: ruleID)
        pendingDeletionRuleID = nil

        if viewModel.rules.isEmpty {
            selectedTab = .create
        }
    }

    private func confirmPendingWeeklyReportDeletion() {
        guard let weekStart = pendingDeletedWeeklyReportWeekStart else { return }
        deleteWeeklyReportFromHistory(weekStart: weekStart)
        pendingDeletedWeeklyReportWeekStart = nil
    }

    private func activeTimelineTitle(for rule: LockRule) -> String {
        if let name = normalizedTaskName(rule.name) {
            return name
        }
        return ""
    }

    private func timelineDurationBadge(minutes: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 2) {
                Text("\(minutes)")
                Text(onlyLockL("分钟"))
            }
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(secondaryText)
    }

    private func timelineCardBorderColor(for phase: CurrentTaskPhase) -> Color {
        switch phase {
        case .active:
            return primaryText
        case .upcoming:
            return upcomingTimelineBorder
        case .paused:
            return dividerColor
        case .ended:
            return dividerColor
        }
    }

    private func timelineHasStackedTargets(_ rule: LockRule) -> Bool {
        let hasApps = !rule.applicationTokens.isEmpty
        let hasWebsites = !rule.manualWebDomains.isEmpty || !rule.webDomainTokens.isEmpty || !rule.categoryTokens.isEmpty
        return hasApps && hasWebsites
    }

    @ViewBuilder
    private func timelineLockedTargetsView(for rule: LockRule) -> some View {
        let orderedTokens = rule.applicationTokens.sorted { String(describing: $0) < String(describing: $1) }
        let visibleTokens = Array(orderedTokens.prefix(4))
        let manualDomains = rule.manualWebDomains.sorted()
        let visibleManual = Array(manualDomains.prefix(2))
        let orderedWebTokens = rule.webDomainTokens.sorted { String(describing: $0) < String(describing: $1) }
        let visibleWebTokens = Array(orderedWebTokens.prefix(2))
        let shownCount = visibleTokens.count + visibleManual.count + visibleWebTokens.count
        let totalCount = orderedTokens.count + manualDomains.count + orderedWebTokens.count
        let remainingCount = max(0, totalCount - shownCount)
        let hasApps = !visibleTokens.isEmpty
        let hasWebsites = !visibleManual.isEmpty || !visibleWebTokens.isEmpty || rule.categoryTokens.count > 0 || remainingCount > 0

        VStack(alignment: .leading, spacing: hasApps && hasWebsites ? 8 : 0) {
            if hasApps {
                HStack(spacing: 8) {
                    ForEach(visibleTokens, id: \.self) { token in
                        Label(token)
                            .labelStyle(.iconOnly)
                            .frame(width: 22, height: 22)
                    }
                }
            }

            if hasWebsites {
                HStack(spacing: 6) {
                    ForEach(visibleManual, id: \.self) { domain in
                        Text(domain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }

                    ForEach(visibleWebTokens, id: \.self) { token in
                        Label(token)
                            .labelStyle(.titleOnly)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }

                    if rule.categoryTokens.count > 0 {
                        Text(AppLanguageRuntime.currentLanguage == .english ? "\(rule.categoryTokens.count) categories" : "\(rule.categoryTokens.count)个类别")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }

                    if remainingCount > 0 {
                        Text("+\(remainingCount)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(secondaryText)
                    }
                }
                .frame(height: 22, alignment: .center)
                .lineLimit(1)
                .truncationMode(.tail)
            }
        }
    }

    private func timelineProgressRing(fraction: Double) -> some View {
        ZStack {
            Circle()
                .stroke(dividerColor, lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(primaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(fraction * 100))%")
                .font(.system(size: 10, weight: .bold))
                .italic()
                .foregroundStyle(primaryText)
                .monospacedDigit()
        }
        .frame(width: 48, height: 48)
    }

    private func timelinePhaseLabel(for phase: CurrentTaskPhase) -> String {
        switch phase {
        case .upcoming:
            return onlyLockL("预定")
        case .active:
            return onlyLockL("锁定中")
        case .paused:
            return onlyLockL("已暂停")
        case .ended:
            return onlyLockL("已完成")
        }
    }

    private func timelineAxisDateText(for rule: LockRule, phase: CurrentTaskPhase, now: Date) -> String {
        let date = taskSortAnchorDate(for: rule, phase: phase, now: now)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yy/MM/dd"
        return formatter.string(from: date)
    }

    private func timelineAxisDateForeground(for phase: CurrentTaskPhase) -> Color {
        switch phase {
        case .active:
            return colorScheme == .dark ? .black : .white
        case .upcoming:
            return upcomingTimelineAccent
        case .paused:
            return secondaryText
        case .ended:
            return secondaryText
        }
    }

    private func timelineAxisDateBackground(for phase: CurrentTaskPhase) -> some ShapeStyle {
        switch phase {
        case .active:
            return colorScheme == .dark ? Color.white : Color.black
        case .upcoming, .paused, .ended:
            return pageBackground
        }
    }

    private func timelineAxisMarkerFill(for phase: CurrentTaskPhase) -> Color {
        switch phase {
        case .active:
            return primaryText
        case .upcoming:
            return upcomingTimelineAccent
        case .paused:
            return dividerColor
        case .ended:
            return dividerColor
        }
    }

    private func timelineTimeRange(for rule: LockRule, phase: CurrentTaskPhase, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let range = timelineScheduledRange(for: rule, phase: phase, now: now)
        let start = formatter.string(from: range.start)
        let end = formatter.string(from: range.end)
        return "\(start)-\(end)"
    }

    private func timelineRepeatWeekdaysText(for rule: LockRule) -> String {
        let labels = repeatWeekdayLabels
            .filter { rule.repeatWeekdays.contains($0.weekday) }
            .map(\.label)

        guard !labels.isEmpty else {
            return AppLanguageRuntime.currentLanguage == .english ? "Repeats weekly" : "每周重复"
        }

        if AppLanguageRuntime.currentLanguage == .english {
            return "Weekly " + labels.joined(separator: ", ")
        }

        return "每周" + labels.joined(separator: "、")
    }

    private func activeTaskProgressFraction(rule: LockRule, now: Date) -> Double {
        let startAt = effectiveStartAt(for: rule, now: now)
        guard let endAt = effectiveEndAt(for: rule, now: now) else { return 0 }
        let total = endAt.timeIntervalSince(startAt)
        guard total > 0 else { return 0 }
        let elapsed = now.timeIntervalSince(startAt)
        return min(max(elapsed / total, 0), 1)
    }

    private func activeTaskCountdownText(rule: LockRule, now: Date) -> String {
        guard let endAt = effectiveEndAt(for: rule, now: now) else { return "00:00" }
        let remaining = max(0, Int(endAt.timeIntervalSince(now)))
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    private func upcomingTaskCountdownText(rule: LockRule, now: Date) -> String {
        let startAt = effectiveStartAt(for: rule, now: now)
        let remaining = max(0, Int(startAt.timeIntervalSince(now)))
        if remaining < 60 {
            return String(format: "00:%02d", remaining)
        }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    private var rewardOverviewCard: some View {
        let snapshot = rewardViewModel.snapshot

        return VStack(alignment: .leading, spacing: 12) {
            Text(onlyLockL("成长总览"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(secondaryText)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lv\(snapshot.level)")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)

                    Text(
                        AppLanguageRuntime.currentLanguage == .english
                            ? "XP \(snapshot.totalXP)"
                            : "总分 \(snapshot.totalXP)"
                    )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryText)

                    Text(
                        AppLanguageRuntime.currentLanguage == .english
                            ? "Completed \(snapshot.totalCompletions) · \(snapshot.totalMinutes)m"
                            : "累计完成 \(snapshot.totalCompletions) 次 · \(snapshot.totalMinutes) 分钟"
                    )
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer()

                rewardLevelRing(progress: snapshot.levelProgress, level: snapshot.level)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    private var rewardBadgeWallCard: some View {
        let unlocked = rewardViewModel.snapshot.unlockedBadgeIDs
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

        return VStack(alignment: .leading, spacing: 12) {
            Text(onlyLockL("徽章墙"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(secondaryText)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(RewardEngine.badgeDefinitions, id: \.id) { badge in
                    let isUnlocked = unlocked.contains(badge.id)
                    let unlockedBackground = colorScheme == .dark ? Color.white : Color.black
                    let unlockedPrimaryText = colorScheme == .dark ? Color.black : Color.white
                    let unlockedSecondaryText = colorScheme == .dark ? Color.black.opacity(0.76) : Color.white.opacity(0.8)

                    VStack(spacing: 8) {
                        Image(systemName: badge.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isUnlocked ? unlockedPrimaryText : secondaryText)

                        Text(badge.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isUnlocked ? unlockedPrimaryText : primaryText)
                            .lineLimit(1)

                        Text(badge.subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isUnlocked ? unlockedSecondaryText : secondaryText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isUnlocked ? unlockedBackground : cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(dividerColor, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    private var rewardRecentEventsCard: some View {
        let events = rewardViewModel.snapshot.recentEvents

        return VStack(alignment: .leading, spacing: 12) {
            Text(onlyLockL("最近奖励"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(secondaryText)

            VStack(spacing: 0) {
                if events.isEmpty {
                    Text(onlyLockL("还没有奖励记录，完成一次锁定后会显示在这里。"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(events.prefix(12).enumerated()), id: \.element.id) { index, event in
                        HStack(alignment: .center, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rewardRecentTimeText(event.completedAt))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(primaryText)

                                Text(
                                    AppLanguageRuntime.currentLanguage == .english
                                        ? "\(event.durationMinutes)m · \(event.isWeeklyRepeat ? "Weekly" : "One-time")"
                                        : "\(event.durationMinutes) 分钟 · \(event.isWeeklyRepeat ? "每周任务" : "一次性任务")"
                                )
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Text("+\(event.xpGained) XP")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(primaryText)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if index != events.prefix(12).count - 1 {
                            Rectangle()
                                .fill(dividerColor)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    private func rewardLevelRing(progress: Double, level: Int) -> some View {
        ZStack {
            Circle()
                .stroke(dividerColor, lineWidth: 4)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(primaryText, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("Lv\(level)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(primaryText)
        }
        .frame(width: 62, height: 62)
    }

    private func rewardRecentTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private struct WeekProgressDay: Identifiable {
        let id: Int
        let symbol: String
        let isCompleted: Bool
        let isToday: Bool
    }

    private func streakCard(now: Date) -> some View {
        let streak = currentStreakForDisplay
        let days = weekProgressDays(at: now)
        let hasStreak = streak > 0
        let streakAccentFill = colorScheme == .dark ? Color.white : Color.black
        let streakAccentText = colorScheme == .dark ? Color.black : Color.white
        let streakIdleFill = colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
        let streakTitleFontSize: CGFloat = AppLanguageRuntime.currentLanguage == .english ? 23 : 27

        return VStack(alignment: .leading, spacing: 12) {
            Text(onlyLockL("每日打卡"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(secondaryText)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 14) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(streakAccentFill)
                        .frame(width: 66, height: 66)
                        .overlay {
                            Image(systemName: "flame")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(streakAccentText)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            hasStreak
                                ? (AppLanguageRuntime.currentLanguage == .english ? "\(streak)-day streak" : "连续打卡\(streak)天")
                                : (AppLanguageRuntime.currentLanguage == .english ? "No check-in yet" : "今天还未打卡")
                        )
                            .font(.system(size: streakTitleFontSize, weight: .heavy))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.76)

                        if hasStreak {
                            Text(onlyLockL("继续保持"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(secondaryText)
                        }
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ForEach(days) { day in
                            Text(day.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(day.isToday ? primaryText : secondaryText)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    HStack(spacing: 10) {
                        ForEach(days) { day in
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(day.isCompleted ? streakAccentFill : streakIdleFill)

                                if day.isCompleted {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(streakAccentText)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    private func weekProgressDays(at now: Date) -> [WeekProgressDay] {
        let calendar = Calendar.current
        let completedDays = completedLockDays(at: now)
        let today = calendar.startOfDay(for: now)
        let startOfWeek = OnlyLockShared.startOfWeekMonday(containing: today, calendar: calendar)
        let symbols: [String]
        if AppLanguageRuntime.currentLanguage == .english {
            symbols = ["M", "T", "W", "T", "F", "S", "S"]
        } else {
            symbols = ["一", "二", "三", "四", "五", "六", "七"]
        }

        return symbols.enumerated().map { index, symbol in
            let dayDate = calendar.date(byAdding: .day, value: index, to: startOfWeek) ?? startOfWeek
            let dayStart = calendar.startOfDay(for: dayDate)

            return WeekProgressDay(
                id: index,
                symbol: symbol,
                isCompleted: completedDays.contains(dayStart),
                isToday: calendar.isDate(dayStart, inSameDayAs: today)
            )
        }
    }

    private func consecutiveLockStreak(at now: Date) -> Int {
        _ = now
        return currentStreakForDisplay
    }

    private func completedLockDays(at now: Date) -> Set<Date> {
#if DEBUG
        if isDebugStreakOverrideEnabled {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            let streakDays = max(0, debugStreakOverrideDays)

            guard streakDays > 0 else { return [] }

            return Set((0..<streakDays).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: today).map {
                    calendar.startOfDay(for: $0)
                }
            })
        }
#endif
        _ = now
        return rewardViewModel.snapshot.completedDays
    }

    private func taskTargetSummary(for rule: LockRule) -> String {
        let appCount = rule.applicationTokens.count
        let categoryCount = rule.categoryTokens.count
        let webCount = rule.webDomainTokens.count + rule.manualWebDomains.count
        let total = appCount + categoryCount + webCount

        if total == 0 {
            return AppLanguageRuntime.currentLanguage == .english ? "No target selected" : "未选择目标"
        }

        var segments: [String] = []
        if appCount > 0 {
            segments.append("App \(appCount)")
        }
        if webCount > 0 {
            if AppLanguageRuntime.currentLanguage == .english {
                segments.append("Web \(webCount)")
            } else {
                segments.append("网站 \(webCount)")
            }
        }
        if categoryCount > 0 {
            if AppLanguageRuntime.currentLanguage == .english {
                segments.append("Category \(categoryCount)")
            } else {
                segments.append("类别 \(categoryCount)")
            }
        }
        return segments.joined(separator: " · ")
    }

    private func taskPhaseSortPriority(for phase: CurrentTaskPhase) -> Int {
        switch phase {
        case .active:
            return 0
        case .upcoming:
            return 1
        case .paused:
            return 2
        case .ended:
            return 3
        }
    }

    private enum CurrentTaskPhase {
        case upcoming
        case active
        case paused
        case ended
    }

    private func scheduledTaskPhase(for rule: LockRule, now: Date) -> CurrentTaskPhase {
        if rule.isWeeklyRepeat {
            return repeatActiveWindow(for: rule, now: now) != nil ? .active : .upcoming
        }

        if now < rule.startAt {
            return .upcoming
        }
        if let endAt = rule.endAt, now < endAt {
            return .active
        }
        return .ended
    }

    private func currentTaskPhase(for rule: LockRule, now: Date) -> CurrentTaskPhase {
        let scheduledPhase = scheduledTaskPhase(for: rule, now: now)

        if scheduledPhase == .active, !authorizationService.isApproved {
            return .paused
        }
        return scheduledPhase
    }

    private func taskSortAnchorDate(for rule: LockRule, phase: CurrentTaskPhase, now: Date) -> Date {
        switch phase {
        case .active:
            return effectiveStartAt(for: rule, now: now)
        case .upcoming:
            return effectiveStartAt(for: rule, now: now)
        case .paused:
            return pausedReferenceDate(for: rule, now: now)
        case .ended:
            return effectiveEndAt(for: rule, now: now) ?? rule.startAt
        }
    }

    private func sortsAscendingWithinPhase(_ phase: CurrentTaskPhase) -> Bool {
        phase == .upcoming
    }

    private func timelineScheduledRange(
        for rule: LockRule,
        phase: CurrentTaskPhase,
        now: Date
    ) -> (start: Date, end: Date) {
        let start = effectiveStartAt(for: rule, now: now)

        switch phase {
        case .paused:
            return (start, max(start, pausedReferenceDate(for: rule, now: now)))
        case .active, .upcoming, .ended:
            let end = effectiveEndAt(for: rule, now: now) ?? start
            return (start, max(start, end))
        }
    }

#if DEBUG
    private func debugValidateTimelineOrder(_ rules: [LockRule], now: Date) {
        guard rules.count > 1 else { return }

        for index in 1..<rules.count {
            let previous = rules[index - 1]
            let current = rules[index]
            let previousPhase = currentTaskPhase(for: previous, now: now)
            let currentPhase = currentTaskPhase(for: current, now: now)
            let previousPriority = taskPhaseSortPriority(for: previousPhase)
            let currentPriority = taskPhaseSortPriority(for: currentPhase)

            if previousPriority > currentPriority {
                print("[OnlyLockTimeline][Debug] phase order regression at index \(index): \(previous.id) -> \(current.id)")
                return
            }

            guard previousPriority == currentPriority else { continue }
            let previousAnchor = taskSortAnchorDate(for: previous, phase: previousPhase, now: now)
            let currentAnchor = taskSortAnchorDate(for: current, phase: currentPhase, now: now)
            let isAscending = sortsAscendingWithinPhase(previousPhase)
            let isMonotonic = isAscending ? (previousAnchor <= currentAnchor) : (previousAnchor >= currentAnchor)

            if !isMonotonic {
                print("[OnlyLockTimeline][Debug] anchor order regression at index \(index): \(previous.id) -> \(current.id)")
                return
            }
        }
    }
#endif

    private func pausedReferenceDate(for rule: LockRule, now: Date) -> Date {
        if let anchor = pausedTaskAnchors[rule.id] {
            return anchor
        }

        let startAt = effectiveStartAt(for: rule, now: now)
        let endAt = effectiveEndAt(for: rule, now: now) ?? now
        let clamped = min(now, endAt)
        return clamped < startAt ? startAt : clamped
    }

    private func pausedLockedDurationMinutes(for rule: LockRule, now: Date) -> Int {
        let startAt = effectiveStartAt(for: rule, now: now)
        let pausedAt = pausedReferenceDate(for: rule, now: now)
        let elapsedSeconds = max(0, pausedAt.timeIntervalSince(startAt))
        let elapsedMinutes = Int(elapsedSeconds / 60)
        return min(rule.durationMinutes, max(0, elapsedMinutes))
    }

    private func syncPausedTaskAnchors(now: Date) {
        var updatedAnchors = pausedTaskAnchors
        let validRuleIDs = Set(viewModel.rules.map(\.id))

        updatedAnchors = updatedAnchors.filter { validRuleIDs.contains($0.key) }

        for rule in viewModel.rules {
            let scheduledPhase = scheduledTaskPhase(for: rule, now: now)
            if scheduledPhase == .active, !authorizationService.isApproved {
                if updatedAnchors[rule.id] == nil {
                    updatedAnchors[rule.id] = now
                }
            } else {
                updatedAnchors.removeValue(forKey: rule.id)
            }
        }

        if updatedAnchors != pausedTaskAnchors {
            pausedTaskAnchors = updatedAnchors
        }
    }

    private func effectiveStartAt(for rule: LockRule, now: Date) -> Date {
        if rule.isWeeklyRepeat {
            if let active = repeatActiveWindow(for: rule, now: now) {
                return active.start
            }
            return nextRepeatOccurrenceStart(for: rule, now: now) ?? rule.startAt
        }
        return rule.startAt
    }

    private func effectiveEndAt(for rule: LockRule, now: Date) -> Date? {
        if rule.isWeeklyRepeat {
            if let active = repeatActiveWindow(for: rule, now: now) {
                return active.end
            }
            if let nextStart = nextRepeatOccurrenceStart(for: rule, now: now) {
                return Calendar.current.date(byAdding: .minute, value: rule.durationMinutes, to: nextStart)
            }
            return nil
        }
        return rule.endAt
    }

    private func repeatActiveWindow(for rule: LockRule, now: Date) -> (start: Date, end: Date)? {
        guard rule.isWeeklyRepeat else { return nil }
        guard let latestStart = latestRepeatOccurrenceStart(for: rule, now: now),
              let end = Calendar.current.date(byAdding: .minute, value: rule.durationMinutes, to: latestStart),
              now >= latestStart, now < end else {
            return nil
        }
        return (latestStart, end)
    }

    private func syncRuntimeShieldForAuthorizationState(now: Date) {
        guard authorizationService.isApproved, hasActiveMembership else {
            runtimeShieldStore.clearAllSettings()
            return
        }

        let activeRules = viewModel.rules.filter { rule in
            scheduledTaskPhase(for: rule, now: now) == .active && rule.hasAnyTarget
        }

        guard !activeRules.isEmpty else {
            runtimeShieldStore.clearAllSettings()
            return
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

        runtimeShieldStore.shield.applications = applicationTokens.isEmpty ? nil : applicationTokens
        runtimeShieldStore.shield.applicationCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)
        runtimeShieldStore.shield.webDomains = webDomainTokens.isEmpty ? nil : webDomainTokens
        runtimeShieldStore.shield.webDomainCategories = categoryTokens.isEmpty ? nil : .specific(categoryTokens)

        var blockedDomains = Set(webDomainTokens.map { WebDomain(token: $0) })
        blockedDomains.formUnion(manualWebDomains.map { WebDomain(domain: $0) })
        runtimeShieldStore.webContent.blockedByFilter = blockedDomains.isEmpty ? nil : .specific(blockedDomains)
    }

    private func latestRepeatOccurrenceStart(for rule: LockRule, now: Date) -> Date? {
        let weekdays = rule.repeatWeekdays.filter { (1...7).contains($0) }
        guard !weekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: rule.startAt)
        let minute = calendar.component(.minute, from: rule.startAt)
        let searchAnchor = now.addingTimeInterval(1)

        var best: Date?
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

            if best == nil || candidate > best! {
                best = candidate
            }
        }
        return best
    }

    private func nextRepeatOccurrenceStart(for rule: LockRule, now: Date) -> Date? {
        let weekdays = rule.repeatWeekdays.filter { (1...7).contains($0) }
        guard !weekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: rule.startAt)
        let minute = calendar.component(.minute, from: rule.startAt)
        let searchAnchor = now.addingTimeInterval(1)

        var best: Date?
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
                direction: .forward
            ) else { continue }

            if best == nil || candidate < best! {
                best = candidate
            }
        }
        return best
    }

    private func currentTaskStatusPill(for rule: LockRule, now: Date) -> some View {
        let phase = currentTaskPhase(for: rule, now: now)
        let title: String
        switch phase {
        case .upcoming:
            title = AppLanguageRuntime.currentLanguage == .english ? "Upcoming" : "即将开始"
        case .active:
            title = AppLanguageRuntime.currentLanguage == .english ? "Locking" : "锁定中"
        case .paused:
            title = AppLanguageRuntime.currentLanguage == .english ? "Paused" : "已暂停"
        case .ended:
            title = AppLanguageRuntime.currentLanguage == .english ? "Ended" : "已结束"
        }

        return Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
    }

    private func currentTaskHeadline(for rule: LockRule, now: Date) -> String {
        let phase = currentTaskPhase(for: rule, now: now)
        switch phase {
        case .upcoming:
            return ""
        case .active:
            return formattedDuration(
                from: now,
                to: effectiveEndAt(for: rule, now: now) ?? now,
                fallback: AppLanguageRuntime.currentLanguage == .english ? "Locking..." : "正在锁定"
            )
        case .paused:
            return AppLanguageRuntime.currentLanguage == .english ? "Paused" : "已暂停"
        case .ended:
            return AppLanguageRuntime.currentLanguage == .english ? "Done! This focus session is complete" : "恭喜！本次专注已完成"
        }
    }

    private func currentTaskDisplayTitle(for rule: LockRule, now: Date) -> String {
        if let name = normalizedTaskName(rule.name) {
            return name
        }

        return currentTaskHeadline(for: rule, now: now)
    }

    private func currentTaskSubheadline(for rule: LockRule, now: Date) -> String {
        let phase = currentTaskPhase(for: rule, now: now)
        switch phase {
        case .upcoming:
            return ""
        case .active:
            let endText = taskDateTimeText(effectiveEndAt(for: rule, now: now) ?? effectiveStartAt(for: rule, now: now))
            if AppLanguageRuntime.currentLanguage == .english {
                return "Auto ends at \(endText)."
            }
            return "将于 \(endText) 自动结束。"
        case .paused:
            return ""
        case .ended:
            return ""
        }
    }

    private func currentTaskDisplaySubheadline(for rule: LockRule, now: Date) -> String {
        if normalizedTaskName(rule.name) != nil {
            let headline = currentTaskHeadline(for: rule, now: now)
            let subheadline = currentTaskSubheadline(for: rule, now: now)
            return [headline, subheadline].filter { !$0.isEmpty }.joined(separator: "\n")
        }

        return currentTaskSubheadline(for: rule, now: now)
    }

    private func taskMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(onlyLockL(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(secondaryText)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDuration(from start: Date, to end: Date, fallback: String) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        guard seconds > 0 else { return fallback }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                if AppLanguageRuntime.currentLanguage == .english {
                    return "\(hours)h \(minutes)m"
                }
                return "\(hours)小时\(minutes)分钟"
            }
            return AppLanguageRuntime.currentLanguage == .english ? "\(hours)h" : "\(hours)小时"
        }

        if minutes > 0 {
            return AppLanguageRuntime.currentLanguage == .english ? "\(minutes)m" : "\(minutes)分钟"
        }

        return AppLanguageRuntime.currentLanguage == .english ? "<1m" : "不到1分钟"
    }

    private func taskDateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        if AppLanguageRuntime.currentLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
        }
        return formatter.string(from: date)
    }

    private func normalizedTaskName(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var scheduledEndAt: Date? {
        guard let minutes = viewModel.durationMinutesValue, minutes > 0 else { return nil }
        return Calendar.current.date(byAdding: .minute, value: minutes, to: viewModel.startAt)
    }

    private var minimumSelectableStartAt: Date {
        let calendar = Calendar.current
        let now = Date()
        let truncated = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: calendar.component(.minute, from: now),
            second: 0,
            of: now
        ) ?? now

        let hasSubMinuteRemainder =
            calendar.component(.second, from: now) > 0 ||
            calendar.component(.nanosecond, from: now) > 0

        if hasSubMinuteRemainder {
            return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? truncated
        }

        return truncated
    }

    private func submitManualWebsiteDraft() {
        let previousCount = viewModel.manualWebDomains.count
        viewModel.addManualWebDomain(manualDomainDraft)
        if viewModel.manualWebDomains.count > previousCount {
            manualDomainDraft = ""
            fireAddWebsiteHaptic()
        }
    }

    private func saveRule() {
        guard hasActiveMembership else {
            presentMembershipRenewal()
            return
        }
        syncStartAtToCurrentMinimumIfNeeded()
        if scheduleTimeInputMode == .startEnd {
            let spanMinutes = Int(endAtDraft.timeIntervalSince(viewModel.startAt) / 60)
            guard spanMinutes > 0 else {
                viewModel.presentExternalError("结束时间必须晚于开始时间。")
                return
            }
            viewModel.durationText = String(spanMinutes)
        }
        startAuthorizationFlow(for: .save)
    }

    private func syncStartAtToCurrentMinimumIfNeeded() {
        guard !viewModel.isWeeklyRepeat else { return }
        let minimum = minimumSelectableStartAt
        guard viewModel.startAt < minimum else { return }
        viewModel.startAt = minimum
    }

    private func startAuthorizationFlow(for action: PendingAuthorizationAction) {
        preAuthorizationDismissResetTask?.cancel()
        preAuthorizationDismissResetTask = nil
        viewModel.clearExternalMessages()

        if authorizationService.isApproved {
            Task {
                await performAuthorizedAction(action)
            }
            return
        }

        pendingAuthorizationAction = action
        preAuthorizationContext = (action == .appPicker) ? .appSelection : .general
        isPreAuthorizationPresented = true
    }

    @MainActor
    private func continueFromPreAuthorization() async {
        guard pendingAuthorizationAction != .none else {
            isPreAuthorizationPresented = false
            preAuthorizationContext = .none
            return
        }

        isRequestingAuthorization = true
        await Task.yield()
        await requestSystemAuthorizationAndContinue(source: .preAuthorization)
    }

    @MainActor
    private func requestSystemAuthorizationAndContinue(source: AuthorizationRequestSource) async {
        guard pendingAuthorizationAction != .none else { return }

        if authorizationService.isApproved {
            if source == .preAuthorization {
                isPreAuthorizationPresented = false
            }
            await performAuthorizedAction(pendingAuthorizationAction)
            return
        }

        if !isRequestingAuthorization {
            isRequestingAuthorization = true
        }
        defer { isRequestingAuthorization = false }

        do {
            try await authorizationService.requestAuthorization()
        } catch {
            handleAuthorizationFailure(error, source: source)
            return
        }

        if authorizationService.isApproved {
            if source == .preAuthorization {
                isPreAuthorizationPresented = false
            }
            isAuthorizationRecoveryPresented = false
            await performAuthorizedAction(pendingAuthorizationAction)
        } else {
            if source == .preAuthorization {
                isPreAuthorizationPresented = false
            }
            isAuthorizationRecoveryPresented = true
        }
    }

    @MainActor
    private func performAuthorizedAction(_ action: PendingAuthorizationAction) async {
        isAwaitingSettingsReturn = false
        switch action {
        case .appPicker:
            pendingAuthorizationAction = .none
            preAuthorizationContext = .none
            viewModel.presentAppPicker()
        case .save:
            guard !isSavingRule else { return }
            isSavingRule = true
            defer { isSavingRule = false }
            pendingAuthorizationAction = .none
            preAuthorizationContext = .none
            isAuthorizationRecoveryPresented = false
            let preSaveCount = viewModel.rules.count
            let saveSucceeded = await viewModel.requestSave(isAuthorized: true)
            if saveSucceeded {
                maybeRequestInAppReviewAfterSave(preSaveCount: preSaveCount, postSaveCount: viewModel.rules.count)
                fireStartLockHaptic()
                viewModel.resetCreateForm()
                manualDomainDraft = ""
                selectedTab = .current
            }
        case .none:
            break
        }
    }

    private func handleAuthorizationFailure(_ error: Error, source: AuthorizationRequestSource) {
        if source == .preAuthorization {
            viewModel.clearExternalMessages()
            isPreAuthorizationPresented = false
            isAuthorizationRecoveryPresented = true
            return
        }

        if shouldSuppressAuthorizationError(error) {
            viewModel.clearExternalMessages()
            isAuthorizationRecoveryPresented = true
            return
        }

        viewModel.presentExternalError(error.localizedDescription)
    }

    private func shouldSuppressAuthorizationError(_ error: Error) -> Bool {
        if #available(iOS 16.4, *) {
            if let familyControlsError = error as? FamilyControlsError,
               familyControlsError == .authorizationCanceled {
                return true
            }
        }

        return authorizationService.status == .denied
    }

    private func openSettingsForAuthorization() {
        isAwaitingSettingsReturn = true
        isAuthorizationRecoveryPresented = false

        guard let settingsURL = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(settingsURL) else {
            isAwaitingSettingsReturn = false
            viewModel.presentExternalError("无法打开系统设置，请手动前往设置开启权限。")
            return
        }

        UIApplication.shared.open(settingsURL)
    }

    private func handleReturnFromSettingsIfNeeded() {
        guard pendingAuthorizationAction != .none else { return }
        guard isAwaitingSettingsReturn else { return }

        isAwaitingSettingsReturn = false

        if authorizationService.isApproved {
            Task {
                await performAuthorizedAction(pendingAuthorizationAction)
            }
        } else {
            isAuthorizationRecoveryPresented = true
        }
    }

    private func fireAddWebsiteHaptic() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    private func fireStartLockHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    private func maybeRequestInAppReviewAfterSave(preSaveCount: Int, postSaveCount: Int) {
        guard preSaveCount < 3, postSaveCount >= 3 else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: reviewPromptAtThreeTasksDefaultsKey) else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        defaults.set(true, forKey: reviewPromptAtThreeTasksDefaultsKey)
        SKStoreReviewController.requestReview(in: scene)
    }

    private func pauseTopBarStateUpdates() {
        topBarStateResumeTask?.cancel()
        topBarStateResumeTask = nil
        isTopBarStateUpdatesEnabled = false
    }

    private func freezeTopBarStateUpdatesTemporarily() {
        pauseTopBarStateUpdates()
        topBarStateResumeTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                isTopBarStateUpdatesEnabled = true
                topBarStateResumeTask = nil
            }
        }
    }

    private func schedulePreAuthorizationDismissReset() {
        preAuthorizationDismissResetTask?.cancel()
        preAuthorizationDismissResetTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !isPreAuthorizationPresented else { return }
                if !isRequestingAuthorization
                    && !authorizationService.isApproved
                    && !isAuthorizationRecoveryPresented {
                    pendingAuthorizationAction = .none
                    preAuthorizationContext = .none
                }
                preAuthorizationDismissResetTask = nil
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private enum StatusBannerTone {
        case error
        case success
    }

    private enum PendingAuthorizationAction {
        case none
        case save
        case appPicker
    }

    private enum AuthorizationRequestSource {
        case preAuthorization
        case recovery
    }

    private enum PreAuthorizationContext {
        case none
        case general
        case appSelection
    }

    private func statusBanner(text: String, tone: StatusBannerTone) -> some View {
        let tint: Color = tone == .error ? Color(uiColor: .systemRed) : Color(uiColor: .systemGreen)
        let iconName = tone == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        let backgroundOpacity = colorScheme == .dark ? 0.24 : 0.12
        let borderOpacity = colorScheme == .dark ? 0.45 : 0.22

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(primaryText)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(borderOpacity), lineWidth: 1)
        )
    }

    private enum StatTileIcon {
        case system(String)
        case appStoreVector
        case globeVector
        case totalVector
    }

    @ViewBuilder
    private func statTileSymbol(icon: StatTileIcon) -> some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(primaryText)
        case .appStoreVector:
            appStoreVectorIcon
                .frame(width: 26, height: 26)
        case .globeVector:
            globeVectorIcon
                .frame(width: 26, height: 26)
        case .totalVector:
            totalVectorIcon
                .frame(width: 26, height: 26)
        }
    }

    private var appStoreVectorIcon: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let strokeW = max(2.2, w * 0.104)

            // ── Left diagonal (broken at crossing → Right passes over) ──
            // Bottom segment
            Path { p in
                p.move(to: CGPoint(x: w * 0.15, y: h * 0.86))
                p.addLine(to: CGPoint(x: w * 0.47, y: h * 0.35))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
            // Top segment
            Path { p in
                p.move(to: CGPoint(x: w * 0.53, y: h * 0.27))
                p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.20))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

            // ── Right diagonal (full, goes over Left) ──
            Path { p in
                p.move(to: CGPoint(x: w * 0.85, y: h * 0.86))
                p.addLine(to: CGPoint(x: w * 0.43, y: h * 0.20))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

            // ── Horizontal crossbar (moved lower) ──
            Path { p in
                p.move(to: CGPoint(x: w * 0.12, y: h * 0.70))
                p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.70))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
        }
        .accessibilityHidden(true)
    }

    private var globeVectorIcon: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let strokeW = max(2.2, w * 0.104)
            let cx = w * 0.5
            let cy = h * 0.5
            let r = w * 0.42

            // Outer circle
            Path { p in
                p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            }
            .stroke(primaryText, lineWidth: strokeW)

            // Two curved meridians only (left/right), no center line.
            Path { p in
                p.move(to: CGPoint(x: cx, y: cy - r))
                p.addQuadCurve(
                    to: CGPoint(x: cx, y: cy + r),
                    control: CGPoint(x: cx - r * 0.78, y: cy)
                )
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

            Path { p in
                p.move(to: CGPoint(x: cx, y: cy - r))
                p.addQuadCurve(
                    to: CGPoint(x: cx, y: cy + r),
                    control: CGPoint(x: cx + r * 0.78, y: cy)
                )
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

            // Top latitude.
            Path { p in
                p.move(to: CGPoint(x: cx - r * 0.82, y: cy - r * 0.29))
                p.addLine(to: CGPoint(x: cx + r * 0.82, y: cy - r * 0.29))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

            // Bottom latitude.
            Path { p in
                p.move(to: CGPoint(x: cx - r * 0.82, y: cy + r * 0.29))
                p.addLine(to: CGPoint(x: cx + r * 0.82, y: cy + r * 0.29))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
        }
        .accessibilityHidden(true)
    }

    private var totalVectorIcon: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let strokeW = max(2.2, w * 0.104)
            let itemW = w * 0.33
            let cr = itemW * 0.32

            // Top Left
            Path { p in
                p.addRoundedRect(in: CGRect(x: w * 0.13, y: h * 0.13, width: itemW, height: itemW), cornerSize: CGSize(width: cr, height: cr))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))

            // Top Right
            Path { p in
                p.addRoundedRect(in: CGRect(x: w * 0.54, y: h * 0.13, width: itemW, height: itemW), cornerSize: CGSize(width: cr, height: cr))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))

            // Bottom Left
            Path { p in
                p.addRoundedRect(in: CGRect(x: w * 0.13, y: h * 0.54, width: itemW, height: itemW), cornerSize: CGSize(width: cr, height: cr))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))

            // Bottom Right
            Path { p in
                p.addRoundedRect(in: CGRect(x: w * 0.54, y: h * 0.54, width: itemW, height: itemW), cornerSize: CGSize(width: cr, height: cr))
            }
            .stroke(primaryText, style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }

    private func statTile(icon: StatTileIcon, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            statTileSymbol(icon: icon)

            Text(value)
                .font(.system(size: 40, weight: .heavy))
                .foregroundStyle(primaryText)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .background(cardBackground)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(onlyLockL(title))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(secondaryText)
            Spacer()
            Text(onlyLockL(value))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(primaryText)
        }
    }
}

private struct ScrollViewOffsetObserver: UIViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onOffsetChange = onOffsetChange
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject {
        var onOffsetChange: (CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onOffsetChange: @escaping (CGFloat) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func attachIfNeeded(from view: UIView) {
            guard let candidate = view.enclosingScrollView() else { return }
            guard scrollView !== candidate else { return }

            observation = nil
            scrollView = candidate
            observation = candidate.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
                self?.onOffsetChange(scrollView.contentOffset.y)
            }
        }

        deinit {
            observation = nil
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var view: UIView? = self
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}

private struct AppAndWebSelectionSheet: View {
    @Binding var selection: FamilyActivitySelection
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @State private var hasEnteredSearchModeHint = false

    private var hasAnySelection: Bool {
        !selection.applicationTokens.isEmpty ||
            !selection.categoryTokens.isEmpty ||
            !selection.webDomainTokens.isEmpty
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $selection)
                .navigationTitle(onlyLockL("选择 App 和部分网站"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(onlyLockL("取消")) {
                            onCancel()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        if hasAnySelection && !isPickerSearchContextActive() {
                            Button {
                                hasEnteredSearchModeHint = false
                                onConfirm()
                            } label: {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .accessibilityLabel(onlyLockL("确认选择"))
                        }
                    }
                }
        }
        .interactiveDismissDisabled(true)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            hasEnteredSearchModeHint = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            hasEnteredSearchModeHint = false
        }
    }

    private func isPickerSearchContextActive() -> Bool {
        guard let searchField = currentPickerSearchField() else {
            return hasEnteredSearchModeHint
        }

        let hasQuery = normalizedSearchQuery(from: searchField)

        return hasQuery || searchField.isFirstResponder || hasEnteredSearchModeHint
    }

    private func currentPickerSearchField() -> UISearchTextField? {
        guard let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return nil
        }

        return findSearchField(in: keyWindow)
    }

    private func normalizedSearchQuery(from searchField: UISearchTextField) -> Bool {
        !(searchField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func findSearchField(in view: UIView) -> UISearchTextField? {
        if let field = view as? UISearchTextField {
            return field
        }

        for child in view.subviews {
            if let match = findSearchField(in: child) {
                return match
            }
        }

        return nil
    }
}

private struct StartTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var startAt: Date
    @Binding var isSubPickerPresented: Bool
    let minimumDate: Date
    let maximumDate: Date?
    @State private var displayedMonth: Date
    @State private var activeTimeField: TimeField?
    @State private var timePickerValue = 0
    @State private var overlayBaseOffsetY: CGFloat = 0
    @State private var isOverlayDismissing = false

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()
    private let weekSymbols = ["一", "二", "三", "四", "五", "六", "日"]

    init(startAt: Binding<Date>, minimumDate: Date, maximumDate: Date?, isSubPickerPresented: Binding<Bool>) {
        _startAt = startAt
        _isSubPickerPresented = isSubPickerPresented
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: startAt.wrappedValue)
        ) ?? startAt.wrappedValue
        _displayedMonth = State(initialValue: monthStart)
    }

    private var pageBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.12)
            : Color(red: 0.95, green: 0.95, blue: 0.95)
    }

    private var topBarBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.15)
            : .white
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.17, blue: 0.21)
            : .white
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.black.opacity(0.55)
    }

    private var outlineVariant: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.16)
    }

    private var inverseText: Color {
        colorScheme == .dark ? .black : .white
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private var hourString: String {
        String(format: "%02d", calendar.component(.hour, from: startAt))
    }

    private var minuteString: String {
        String(format: "%02d", calendar.component(.minute, from: startAt))
    }

    private var periodText: String {
        calendar.component(.hour, from: startAt) < 12 ? "上午" : "下午"
    }

    private var minimumSelectableDate: Date {
        let truncated = calendar.date(
            bySettingHour: calendar.component(.hour, from: minimumDate),
            minute: calendar.component(.minute, from: minimumDate),
            second: 0,
            of: minimumDate
        ) ?? minimumDate

        let hasSubMinuteRemainder =
            calendar.component(.second, from: minimumDate) > 0 ||
            calendar.component(.nanosecond, from: minimumDate) > 0

        if hasSubMinuteRemainder {
            return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? truncated
        }

        return truncated
    }

    private var maximumSelectableDate: Date? {
        guard let maximumDate else { return nil }

        return calendar.date(
            bySettingHour: calendar.component(.hour, from: maximumDate),
            minute: calendar.component(.minute, from: maximumDate),
            second: 0,
            of: maximumDate
        ) ?? maximumDate
    }

    private var isSelectingMinimumDay: Bool {
        calendar.isDate(startAt, inSameDayAs: minimumSelectableDate)
    }

    private var isSelectingMaximumDay: Bool {
        guard let maximumSelectableDate else { return false }
        return calendar.isDate(startAt, inSameDayAs: maximumSelectableDate)
    }

    private var isTimePickerPresented: Bool {
        activeTimeField != nil
    }

    private var overlayCardOpacity: Double {
        let progress = max(0, min(1, Double(effectiveOverlayOffsetY / 320)))
        return max(0.82, 1 - progress)
    }

    private var overlayCardScale: CGFloat {
        1 - min(0.02, effectiveOverlayOffsetY / 3000)
    }

    private var overlayBackdropOpacity: Double {
        let progress = max(0, min(1, Double(effectiveOverlayOffsetY / 320)))
        return max(0.10, 0.28 * (1 - progress))
    }

    private var effectiveOverlayOffsetY: CGFloat {
        max(0, overlayBaseOffsetY)
    }

    private func availableValues(for field: TimeField) -> [Int] {
        switch field {
        case .hour:
            var minHour = 0
            var maxHour = 23

            if isSelectingMinimumDay {
                minHour = calendar.component(.hour, from: minimumSelectableDate)
            }
            if isSelectingMaximumDay, let maximumSelectableDate {
                maxHour = calendar.component(.hour, from: maximumSelectableDate)
            }
            guard minHour <= maxHour else { return [minHour] }
            return Array(minHour...maxHour)
        case .minute:
            let selectedHour = calendar.component(.hour, from: startAt)
            var minMinute = 0
            var maxMinute = 59

            if isSelectingMinimumDay {
                let minHour = calendar.component(.hour, from: minimumSelectableDate)
                if selectedHour == minHour {
                    minMinute = calendar.component(.minute, from: minimumSelectableDate)
                }
            }
            if isSelectingMaximumDay, let maximumSelectableDate {
                let maxHour = calendar.component(.hour, from: maximumSelectableDate)
                if selectedHour == maxHour {
                    maxMinute = calendar.component(.minute, from: maximumSelectableDate)
                }
            }
            guard minMinute <= maxMinute else { return [minMinute] }
            return Array(minMinute...maxMinute)
        }
    }

    private func clampedValue(_ value: Int, for field: TimeField) -> Int {
        let values = availableValues(for: field)
        guard let first = values.first, let last = values.last else { return value }
        return min(max(value, first), last)
    }

    private var calendarCells: [DayCell] {
        let monthStart = monthStart(for: displayedMonth)
        guard let monthDays = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells: [DayCell] = []

        if leadingCount > 0,
           let previousMonth = calendar.date(byAdding: .month, value: -1, to: monthStart),
           let previousMonthDays = calendar.range(of: .day, in: .month, for: previousMonth) {
            let start = previousMonthDays.count - leadingCount + 1
            for day in start...previousMonthDays.count {
                if let date = dayDate(day, in: previousMonth) {
                    cells.append(DayCell(date: date, day: day, isCurrentMonth: false))
                }
            }
        }

        for day in monthDays {
            if let date = dayDate(day, in: monthStart) {
                cells.append(DayCell(date: date, day: day, isCurrentMonth: true))
            }
        }

        let trailingCount = (7 - (cells.count % 7)) % 7
        if trailingCount > 0,
           let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) {
            for day in 1...trailingCount {
                if let date = dayDate(day, in: nextMonth) {
                    cells.append(DayCell(date: date, day: day, isCurrentMonth: false))
                }
            }
        }

        return cells
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 44) {
                        calendarSection
                        timeSection
                        helpSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 34)
                }
                .scrollDisabled(isTimePickerPresented)
            }
            .allowsHitTesting(!isTimePickerPresented)

            if let activeTimeField {
                timePickerOverlay(for: activeTimeField)
            }
        }
        .onChangeCompat(of: startAt) { newValue in
            let start = monthStart(for: newValue)
            if !calendar.isDate(start, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = start
            }
        }
        .onChangeCompat(of: activeTimeField) { field in
            isSubPickerPresented = field != nil
            if field != nil {
                overlayBaseOffsetY = 0
                isOverlayDismissing = false
            }
        }
        .onDisappear {
            isSubPickerPresented = false
            overlayBaseOffsetY = 0
            isOverlayDismissing = false
        }
        .animation(.easeInOut(duration: 0.18), value: activeTimeField)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(primaryText)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(onlyLockL("完成")) {
                dismiss()
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10))
            )
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(topBarBackground)
        .overlay {
            Text(onlyLockL("选择日期和时间"))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(primaryText)
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(monthTitle)
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(primaryText)

                Spacer()

                HStack(spacing: 18) {
                    monthShiftButton(icon: "chevron.left", offset: -1)
                    monthShiftButton(icon: "chevron.right", offset: 1)
                }
            }
            .padding(.bottom, 6)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 24) {
                ForEach(weekSymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }

                ForEach(calendarCells) { cell in
                    dayCell(cell)
                }
            }
        }
    }

    private func monthShiftButton(icon: String, offset: Int) -> some View {
        Button {
            shiftMonth(by: offset)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(primaryText)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ cell: DayCell) -> some View {
        let selected = calendar.isDate(cell.date, inSameDayAs: startAt)
        let disabled = isDayOutOfRange(cell.date)
        let baseColor: Color = cell.isCurrentMonth ? primaryText : secondaryText.opacity(0.55)

        return Button {
            selectDay(cell.date)
        } label: {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(primaryText)
                        .frame(width: 40, height: 40)
                }

                Text("\(cell.day)")
                    .font(.system(size: 16, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? inverseText : baseColor)
                    .opacity(disabled ? 0.40 : 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(onlyLockL("时间"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(secondaryText)

                Spacer()

                Text(periodText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryText)
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(outlineVariant)
                    .frame(height: 2)
            }

            HStack(spacing: 16) {
                timeTile(value: hourString, field: .hour)

                Text(":")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(secondaryText)
                    .offset(y: -4)

                timeTile(value: minuteString, field: .minute)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }

    private func timeTile(value: String, field: TimeField) -> some View {
        Button {
            openTimeField(field)
        } label: {
            Text(value)
                .font(.system(size: 72, weight: .heavy))
                .tracking(-1.2)
                .foregroundStyle(primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var helpSection: some View {
        Text(onlyLockL("锁定将于选定时间自动生效。\n您可以在设置中随时调整。"))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    @ViewBuilder
    private func timePickerOverlay(for field: TimeField) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(overlayBackdropOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissOverlay(animated: true)
                }

            VStack(spacing: 0) {
                dragHeaderArea(for: field)

                Picker("", selection: $timePickerValue) {
                    ForEach(availableValues(for: field), id: \.self) { value in
                        Text(String(format: "%02d", value))
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(height: 210)
            }
            .offset(y: effectiveOverlayOffsetY)
            .opacity(overlayCardOpacity)
            .scaleEffect(overlayCardScale, anchor: .top)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func openTimeField(_ field: TimeField) {
        let currentHour = calendar.component(.hour, from: startAt)
        let currentMinute = calendar.component(.minute, from: startAt)
        let rawValue = field == .hour ? currentHour : currentMinute
        timePickerValue = clampedValue(rawValue, for: field)
        activeTimeField = field
    }

    private func dismissOverlay(animated: Bool) {
        guard activeTimeField != nil else { return }
        guard !isOverlayDismissing else { return }

        if !animated {
            activeTimeField = nil
            overlayBaseOffsetY = 0
            return
        }

        isOverlayDismissing = true
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            overlayBaseOffsetY = 420
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            activeTimeField = nil
            overlayBaseOffsetY = 0
            isOverlayDismissing = false
        }
    }

    @ViewBuilder
    private func dragHeaderArea(for field: TimeField) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(field.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primaryText)

                Spacer()

                Button(onlyLockL("完成")) {
                    applyTimeValue(field)
                    dismissOverlay(animated: true)
                }
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(primaryText)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
        }
        .contentShape(Rectangle())
    }

    private func applyTimeValue(_ field: TimeField) {
        switch field {
        case .hour:
            let selectedHour = clampedValue(timePickerValue, for: .hour)
            var selectedMinute = calendar.component(.minute, from: startAt)

            if isSelectingMinimumDay {
                let minHour = calendar.component(.hour, from: minimumSelectableDate)
                if selectedHour == minHour {
                    let minMinute = calendar.component(.minute, from: minimumSelectableDate)
                    selectedMinute = max(selectedMinute, minMinute)
                }
            }

            if isSelectingMaximumDay, let maximumSelectableDate {
                let maxHour = calendar.component(.hour, from: maximumSelectableDate)
                if selectedHour == maxHour {
                    let maxMinute = calendar.component(.minute, from: maximumSelectableDate)
                    selectedMinute = min(selectedMinute, maxMinute)
                }
            }

            updateTime(hour: selectedHour, minute: selectedMinute)
        case .minute:
            let selectedMinute = clampedValue(timePickerValue, for: .minute)
            updateTime(hour: calendar.component(.hour, from: startAt), minute: selectedMinute)
        }
    }

    private func updateTime(hour: Int, minute: Int) {
        var components = calendar.dateComponents([.year, .month, .day], from: startAt)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return }
        let clampedToMinimum = max(candidate, minimumSelectableDate)
        if let maximumSelectableDate {
            startAt = min(clampedToMinimum, maximumSelectableDate)
        } else {
            startAt = clampedToMinimum
        }
    }

    private func shiftMonth(by offset: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = monthStart(for: shifted)
    }

    private func selectDay(_ day: Date) {
        guard !isDayOutOfRange(day) else { return }

        let hour = calendar.component(.hour, from: startAt)
        let minute = calendar.component(.minute, from: startAt)

        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return }
        let clampedToMinimum = max(candidate, minimumSelectableDate)
        let finalDate: Date
        if let maximumSelectableDate {
            finalDate = min(clampedToMinimum, maximumSelectableDate)
        } else {
            finalDate = clampedToMinimum
        }
        startAt = finalDate
        displayedMonth = monthStart(for: finalDate)
    }

    private func monthStart(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func dayDate(_ day: Int, in monthDate: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = day
        return calendar.date(from: components)
    }

    private func isDayOutOfRange(_ date: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        if dayStart < calendar.startOfDay(for: minimumSelectableDate) {
            return true
        }
        if let maximumSelectableDate, dayStart > calendar.startOfDay(for: maximumSelectableDate) {
            return true
        }
        return false
    }

    private struct DayCell: Identifiable {
        let date: Date
        let day: Int
        let isCurrentMonth: Bool

        var id: Date { date }
    }

    private enum TimeField: Int, Identifiable {
        case hour
        case minute

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .hour:
                return "选择小时"
            case .minute:
                return "选择分钟"
            }
        }

    }
}

private struct MedalHexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = medalHexagonPoints(in: rect)

        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct MedalHexagonFrameShape: Shape {
    let innerScale: CGFloat

    func path(in rect: CGRect) -> Path {
        let outerWidth = rect.width
        let outerHeight = rect.height
        let innerWidth = rect.width * innerScale
        let innerHeight = rect.height * innerScale
        let outerOffsetX = (outerWidth - innerWidth) * 0.5
        let outerOffsetY = (outerHeight - innerHeight) * 0.5

        let outerPoints = medalHexagonPoints(in: rect)
        let innerPoints = medalHexagonPoints(
            in: CGRect(
                x: rect.minX + outerOffsetX,
                y: rect.minY + outerOffsetY,
                width: innerWidth,
                height: innerHeight
            )
        )

        var path = Path()
        path.move(to: outerPoints[0])
        for point in outerPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()

        let reversedInnerPoints = Array(innerPoints.reversed())

        path.move(to: reversedInnerPoints[0])
        for point in reversedInnerPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()

        return path
    }
}

private struct MedalFacetLinesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = medalHexagonPoints(in: rect)
        let top = points[0]
        let topRight = points[1]
        let bottomRight = points[2]
        let bottom = points[3]
        let bottomLeft = points[4]
        let topLeft = points[5]
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let upperCenter = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.24)
        let lowerCenter = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.76)

        var path = Path()
        path.move(to: top)
        path.addLine(to: center)
        path.addLine(to: bottom)

        path.move(to: topLeft)
        path.addLine(to: center)
        path.addLine(to: bottomLeft)

        path.move(to: topRight)
        path.addLine(to: center)
        path.addLine(to: bottomRight)

        path.move(to: topLeft)
        path.addLine(to: upperCenter)
        path.addLine(to: topRight)

        path.move(to: bottomLeft)
        path.addLine(to: lowerCenter)
        path.addLine(to: bottomRight)

        return path
    }
}

private func medalHexagonPoints(in rect: CGRect) -> [CGPoint] {
    let width = rect.width
    let height = rect.height
    let sideInset = width * 0.10
    let topY = rect.minY + height * 0.055
    let upperY = rect.minY + height * 0.285
    let lowerY = rect.minY + height * 0.715
    let bottomY = rect.minY + height * 0.945

    return [
        CGPoint(x: rect.minX + width * 0.5, y: topY),
        CGPoint(x: rect.minX + width - sideInset, y: upperY),
        CGPoint(x: rect.minX + width - sideInset, y: lowerY),
        CGPoint(x: rect.minX + width * 0.5, y: bottomY),
        CGPoint(x: rect.minX + sideInset, y: lowerY),
        CGPoint(x: rect.minX + sideInset, y: upperY)
    ]
}

private struct MedalShardShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.68))
        path.closeSubpath()
        return path
    }
}

private struct GeneralPreAuthorizationSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let isRequestingAuthorization: Bool
    let onContinue: () -> Void

    private var actionBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var actionForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(onlyLockL("锁定前需要开启屏幕时间权限"))
                        .font(.system(size: 28, weight: .bold))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(onlyLockL("为什么要开启权限"))
                            .font(.system(size: 22, weight: .semibold))
                        Text(onlyLockL("为了按你的规则锁住 App 和网站，我们需要获得屏幕时间权限。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(onlyLockL("授权后你可以"))
                            .font(.system(size: 22, weight: .semibold))
                        Text(onlyLockL("让锁定任务按开始时间自动生效、到期自动结束。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(onlyLockL("隐私说明"))
                            .font(.system(size: 22, weight: .semibold))
                        Text(onlyLockL("我们仅使用授权来执行你设置的锁定任务。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text(onlyLockL("你的数据不会被上传，所有锁定设置只保存在本地里"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text(onlyLockL("你可随时在系统设置撤回 Screen Time 授权。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)

            Button {
                onContinue()
            } label: {
                HStack {
                    if isRequestingAuthorization {
                        ProgressView()
                            .tint(actionForeground)
                    }
                    Text(onlyLockL("去开启权限"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(actionForeground)
                .background(actionBackground)
            }
            .disabled(isRequestingAuthorization)
            .opacity(isRequestingAuthorization ? 0.7 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
}

private struct AppSelectionPreAuthorizationSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let isRequestingAuthorization: Bool
    let onContinue: () -> Void

    private var actionBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var actionForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(onlyLockL("选择前需要开启屏幕时间权限"))
                        .font(.system(size: 28, weight: .bold))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(onlyLockL("为什么必须先授权"))
                            .font(.system(size: 22, weight: .semibold))
                        Text(onlyLockL("iOS 仅在授权后才允许展示可选 App 和网站列表；未授权时无法打开选择器。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(onlyLockL("授权后你可以"))
                            .font(.system(size: 22, weight: .semibold))
                        Text(onlyLockL("精确挑选要锁定的 App 和部分网站，并让锁定任务按开始时间自动生效、到期自动结束。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(onlyLockL("隐私说明"))
                            .font(.system(size: 22, weight: .semibold))
                        Text(onlyLockL("我们仅使用授权来执行你设置的锁定任务。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text(onlyLockL("你的数据不会被上传，所有锁定设置只保存在本地里"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text(onlyLockL("你可随时在系统设置撤回 Screen Time 授权。"))
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 0.5)

            Button {
                onContinue()
            } label: {
                HStack {
                    if isRequestingAuthorization {
                        ProgressView()
                            .tint(actionForeground)
                    }
                    Text(onlyLockL("去开启权限"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(actionForeground)
                .background(actionBackground)
            }
            .disabled(isRequestingAuthorization)
            .opacity(isRequestingAuthorization ? 0.7 : 1)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }
}

private struct AuthorizationRecoverySheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let onRetry: () -> Void

    private var actionBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var actionForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(actionBackground)
                    .frame(width: 72, height: 72)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(actionForeground)
            }
            .frame(maxWidth: .infinity)

            Text(onlyLockL("还差一步就能\n开始锁定"))
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .padding(.top, 20)

            Spacer(minLength: 26)

            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Text(onlyLockL("再试一次授权"))
                        .font(.system(size: 22, weight: .black))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(actionForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(actionBackground)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

private enum SelectedWebsiteDisplayItem: Hashable {
    case manual(String)
    case token(WebDomainToken)
}

private struct TargetsSelectionContentView: View {
    let selectedAppCount: Int
    let selectedWebCount: Int
    let selectedCategoryCount: Int
    let visibleSelectedApplicationTokens: [ApplicationToken]
    let visibleSelectedWebsiteItems: [SelectedWebsiteDisplayItem]
    let isShowingAllSelectedApps: Bool
    let isShowingAllSelectedWebsites: Bool
    @Binding var manualDomainDraft: String
    let colorScheme: ColorScheme
    let primaryText: Color
    let secondaryText: Color
    let dividerColor: Color
    let cardBackground: Color
    let removeIconPrimary: Color
    let removeIconSecondary: Color
    let onToggleSelectedAppsExpansion: () -> Void
    let onToggleSelectedWebsitesExpansion: () -> Void
    let onRemoveApplication: (ApplicationToken) -> Void
    let onRemoveManualWebDomain: (String) -> Void
    let onRemoveWebDomainToken: (WebDomainToken) -> Void
    let onSubmitManualWebsiteDraft: () -> Void

    private func l(_ key: String) -> String {
        AppLanguageRuntime.localized(for: key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !visibleSelectedApplicationTokens.isEmpty || selectedAppCount > 0 {
                selectedAppsStrip
            }

            if selectedCategoryCount > 0 {
                selectedCategoriesRow
            }

            manualWebsiteInputSection

            if !visibleSelectedWebsiteItems.isEmpty || selectedWebCount > 0 {
                selectedWebsitesStrip
            }
        }
    }

    private var selectedCategoriesRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(secondaryText)
            Text(
                AppLanguageRuntime.currentLanguage == .english
                    ? "Selected categories: \(selectedCategoryCount)"
                    : "已选类别 \(selectedCategoryCount) 个"
            )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryText)
        }
    }

    private var manualWebsiteInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l("手动添加网站"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondaryText)

            HStack(spacing: 8) {
                TextField(l("输入任意域名 (example.com)"), text: $manualDomainDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(primaryText)
                    .submitLabel(.done)
                    .onSubmit {
                        onSubmitManualWebsiteDraft()
                    }

                Button(l("添加")) {
                    onSubmitManualWebsiteDraft()
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(primaryText)
            }
            .padding(.vertical, 14)

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1.5)
        }
    }

    private var selectedAppsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("已选 App"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryText)

                Spacer()

                Text(AppLanguageRuntime.currentLanguage == .english ? "\(selectedAppCount)" : "\(selectedAppCount) 个")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)

                if selectedAppCount > 3 {
                    Button(isShowingAllSelectedApps ? l("收起") : l("查看全部")) {
                        onToggleSelectedAppsExpansion()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryText)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(visibleSelectedApplicationTokens.enumerated()), id: \.element) { item in
                    let token = item.element
                    selectedAppRow(token, index: item.offset)

                    if item.offset != visibleSelectedApplicationTokens.count - 1 {
                        Rectangle()
                            .fill(dividerColor)
                            .frame(height: 1)
                    }
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    private func selectedAppRow(_ token: ApplicationToken, index: Int) -> some View {
        HStack(spacing: 12) {
            appIconView(for: token)

            appTitleView(for: token, fallbackIndex: index)

            Button {
                onRemoveApplication(token)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(removeIconPrimary, removeIconSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private func appIconView(for token: ApplicationToken) -> some View {
        Label(token)
            .labelStyle(.iconOnly)
            .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private func appTitleView(for token: ApplicationToken, fallbackIndex: Int) -> some View {
        let fallback = applicationFallbackName(for: token, fallbackIndex: fallbackIndex)

        if fallback.hasPrefix(applicationFallbackNamePrefix) {
            Label(token)
                .labelStyle(.titleOnly)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(fallback)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func applicationFallbackName(for token: ApplicationToken, fallbackIndex: Int) -> String {
        let application = Application(token: token)
        let fallback = "\(applicationFallbackNamePrefix)\(fallbackIndex + 1)"
        let rawValue = application.localizedDisplayName ?? application.bundleIdentifier ?? fallback
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var applicationFallbackNamePrefix: String {
        AppLanguageRuntime.currentLanguage == .english ? "Selected App " : "已选 App "
    }

    private var selectedWebsitesStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("已选网站"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryText)

                Spacer()

                Text(AppLanguageRuntime.currentLanguage == .english ? "\(selectedWebCount)" : "\(selectedWebCount) 个")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryText)

                if selectedWebCount > 3 {
                    Button(isShowingAllSelectedWebsites ? l("收起") : l("查看全部")) {
                        onToggleSelectedWebsitesExpansion()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(primaryText)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(visibleSelectedWebsiteItems.enumerated()), id: \.offset) { index, item in
                    selectedWebsiteRow(item, index: index)
                }
            }
        }
    }

    private func selectedWebsiteRow(_ item: SelectedWebsiteDisplayItem, index: Int) -> some View {
        HStack(spacing: 8) {
            websiteTitleView(for: item, fallbackIndex: index)

            Button {
                switch item {
                case .manual(let domain):
                    onRemoveManualWebDomain(domain)
                case .token(let token):
                    onRemoveWebDomainToken(token)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(removeIconPrimary, removeIconSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    @ViewBuilder
    private func websiteTitleView(for item: SelectedWebsiteDisplayItem, fallbackIndex: Int) -> some View {
        switch item {
        case .manual(let domain):
            websiteRowTitle {
                Text(domain)
            }
        case .token(let token):
            let fallback = webDomainFallbackName(for: token, fallbackIndex: fallbackIndex)
            if fallback.hasPrefix(websiteFallbackNamePrefix) {
                websiteRowTitle {
                    Label(token)
                        .labelStyle(.titleOnly)
                }
            } else {
                websiteRowTitle {
                    Text(fallback)
                }
            }
        }
    }

    private func webDomainFallbackName(for token: WebDomainToken, fallbackIndex: Int) -> String {
        let fallback = "\(websiteFallbackNamePrefix)\(fallbackIndex + 1)"
        let rawValue = WebDomain(token: token).domain ?? fallback
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private var websiteFallbackNamePrefix: String {
        AppLanguageRuntime.currentLanguage == .english ? "Website " : "网站 "
    }

    private func websiteRowTitle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 14, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduleCardContentView: View {
    @Binding var startAt: Date
    @Binding var durationText: String
    @Binding var isWeeklyRepeat: Bool
    @Binding var repeatWeekdays: Set<Int>
    @Binding var scheduleTimeInputMode: ContentView.ScheduleTimeInputMode
    @Binding var endAtDraft: Date
    let errorMessage: String?
    let infoMessage: String?
    let primaryText: Color
    let secondaryText: Color
    let dividerColor: Color
    let cardBackground: Color
    let scheduleSubsectionTitleFont: Font
    let onDismissKeyboard: () -> Void

    @State private var isStartTimePickerPresented = false
    @State private var isStartTimeSubPickerPresented = false
    @State private var isEndTimePickerPresented = false
    @State private var isEndTimeSubPickerPresented = false
    @State private var selectedQuickDurationMinutes: Int?
    @State private var durationDraft = ""
    @State private var isSanitizingDurationDraft = false
    @State private var isSyncingScheduleInputs = false
    @FocusState private var isDurationDraftFocused: Bool

    private let quickDurations = [15, 30, 45, 60, 90, 105]
    private var repeatWeekdayLabels: [(weekday: Int, label: String)] {
        OnlyLockShared.weekdaysStartingMonday.map { weekday in
            let label = onlyLockWeekdayLabel(weekday)
            return (weekday, label.isEmpty ? "\(weekday)" : label)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if let errorMessage {
                statusBanner(text: errorMessage, tone: .error)
            }

            if let infoMessage {
                statusBanner(text: infoMessage, tone: .success)
            }

            startTimeSection

            if scheduleTimeInputMode == .duration {
                durationModeSection
            } else {
                startEndModeSection
            }

            repeatSection
        }
        .sheet(
            isPresented: $isStartTimePickerPresented,
            onDismiss: {
                isStartTimeSubPickerPresented = false
            }
        ) {
            StartTimePickerSheet(
                startAt: $startAt,
                minimumDate: startTimePickerMinimumDate,
                maximumDate: nil,
                isSubPickerPresented: $isStartTimeSubPickerPresented
            )
            .presentationDetents([.large])
            .presentationDragIndicator(isStartTimeSubPickerPresented ? .hidden : .visible)
            .interactiveDismissDisabled(isStartTimeSubPickerPresented)
        }
        .sheet(
            isPresented: $isEndTimePickerPresented,
            onDismiss: {
                isEndTimeSubPickerPresented = false
            }
        ) {
            StartTimePickerSheet(
                startAt: $endAtDraft,
                minimumDate: endTimePickerMinimumDate,
                maximumDate: maximumSelectableEndAt,
                isSubPickerPresented: $isEndTimeSubPickerPresented
            )
            .presentationDetents([.large])
            .presentationDragIndicator(isEndTimeSubPickerPresented ? .hidden : .visible)
            .interactiveDismissDisabled(isEndTimeSubPickerPresented)
        }
        .onAppear {
            bootstrapState()
        }
        .onChangeCompat(of: startAt) { _ in
            guard !isSyncingScheduleInputs else { return }
            if scheduleTimeInputMode == .startEnd {
                clampEndAtDraftAndSyncDuration()
            } else {
                syncEndAtDraftFromDuration()
            }
        }
        .onChangeCompat(of: durationText) { _ in
            syncDurationDraftFromModel()
            guard !isSyncingScheduleInputs else { return }
            if scheduleTimeInputMode == .duration {
                syncEndAtDraftFromDuration()
            }
        }
        .onChangeCompat(of: scheduleTimeInputMode) { mode in
            isDurationDraftFocused = false
            selectedQuickDurationMinutes = nil
            guard !isSyncingScheduleInputs else { return }
            if mode == .startEnd {
                clampEndAtDraftAndSyncDuration()
            } else {
                if let value = durationMinutesValue, value > 720 {
                    durationText = "720"
                }
                syncEndAtDraftFromDuration()
            }
        }
        .onChangeCompat(of: endAtDraft) { _ in
            guard !isSyncingScheduleInputs else { return }
            guard scheduleTimeInputMode == .startEnd else { return }
            clampEndAtDraftAndSyncDuration()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(onlyLockL("设置锁定时间"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(secondaryText)

            Spacer(minLength: 0)

            scheduleTimeModeCompactControl
        }
    }

    private var startTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(onlyLockL("开始时间"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondaryText)

                Button {
                    onDismissKeyboard()
                    syncStartAtToCurrentMinimumIfNeeded()
                    isStartTimePickerPresented = true
                } label: {
                    HStack {
                        Text("\(startDateText)  /  \(startTimeText)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(primaryText)

                        Spacer(minLength: 12)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(secondaryText)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
        }
    }

    private var durationModeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(onlyLockL("快捷时长"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 14)], spacing: 14) {
                    ForEach(quickDurations, id: \.self) { minute in
                        quickDurationButton(minute)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Text(onlyLockL("自定义时长（最长720分钟）"))
                    .font(scheduleSubsectionTitleFont)
                    .foregroundStyle(secondaryText)

                HStack(spacing: 20) {
                    durationValueEditor

                    Slider(value: durationSliderBinding, in: 1...720, step: 1)
                        .tint(primaryText)
                }
            }

            Rectangle()
                .fill(dividerColor)
                .frame(height: 0.5)

            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(secondaryText)

                    Text(onlyLockL("结束时间："))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(primaryText)
                }

                Spacer()

                Text(scheduledEndText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryText)
            }
            .padding(.vertical, 4)
        }
    }

    private var startEndModeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(onlyLockL("结束时间"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryText)

                Button {
                    onDismissKeyboard()
                    syncStartAtToCurrentMinimumIfNeeded()
                    clampEndAtDraftAndSyncDuration()
                    isEndTimePickerPresented = true
                } label: {
                    HStack {
                        Text("\(endDateText)  /  \(endTimeText)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(primaryText)

                        Spacer(minLength: 12)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(secondaryText)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)

            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(secondaryText)

                    Text(AppLanguageRuntime.localized(for: "锁定时长："))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(primaryText)
                }

                Spacer()

                Text(startEndDurationText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryText)
            }
            .padding(.vertical, 4)
        }
    }

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { isWeeklyRepeat },
                set: { isOn in
                    isWeeklyRepeat = isOn
                    if isOn {
                        applyDefaultRepeatWeekdayIfNeeded()
                    } else {
                        repeatWeekdays = []
                    }
                }
            )) {
                Text(AppLanguageRuntime.localized(for: "每周重复"))
                    .font(scheduleSubsectionTitleFont)
                    .foregroundStyle(secondaryText)
            }
            .tint(primaryText)

            if isWeeklyRepeat {
                repeatWeekdayStrip
            }
        }
    }

    private func quickDurationButton(_ minute: Int) -> some View {
        let isSelected = durationMinutesValue == minute

        return Button {
            selectedQuickDurationMinutes = minute
            durationText = String(minute)
        } label: {
            VStack(spacing: 4) {
                Text(
                    AppLanguageRuntime.currentLanguage == .english
                        ? "\(minute)m"
                        : "\(minute)分"
                )
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? primaryText : secondaryText)
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(isSelected ? primaryText : Color.clear)
                    .frame(width: 40)
                    .frame(height: 2)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 44, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var durationMinutesValue: Int? {
        Int(durationText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var durationSliderBinding: Binding<Double> {
        Binding(
            get: { Double(min(max(durationMinutesValue ?? 30, 1), 720)) },
            set: { newValue in
                selectedQuickDurationMinutes = nil
                isDurationDraftFocused = false
                durationText = String(Int(newValue.rounded()))
            }
        )
    }

    private var durationValueEditor: some View {
        TextField("", text: $durationDraft)
            .font(.system(size: 48, weight: .heavy))
            .foregroundStyle(primaryText)
            .keyboardType(.numberPad)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.leading)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .allowsTightening(false)
            .frame(width: 84, alignment: .leading)
            .textFieldStyle(.plain)
            .submitLabel(.done)
            .focused($isDurationDraftFocused)
            .onChangeCompat(of: durationDraft) { newValue in
                sanitizeDurationDraft(newValue)
                commitDurationDraftLive()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(onlyLockL("完成")) {
                        commitDurationDraft()
                        onDismissKeyboard()
                    }
                }
            }
    }

    private var scheduleTimeModeCompactControl: some View {
        HStack(spacing: 2) {
            scheduleTimeModeArrowButton("chevron.left", direction: -1)
            Image(systemName: scheduleTimeInputMode.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryText)
                .frame(width: 28, height: 28)
            scheduleTimeModeArrowButton("chevron.right", direction: 1)
        }
    }

    private func scheduleTimeModeArrowButton(_ systemName: String, direction: Int) -> some View {
        let modes = ContentView.ScheduleTimeInputMode.allCases
        let currentIndex = modes.firstIndex(of: scheduleTimeInputMode) ?? 0
        let targetIndex = currentIndex + direction
        let isEnabled = modes.indices.contains(targetIndex)

        return Button {
            guard isEnabled else { return }
            scheduleTimeInputMode = modes[targetIndex]
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isEnabled ? secondaryText : dividerColor)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var repeatWeekdayStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(repeatWeekdayLabels.enumerated()), id: \.element.weekday) { item in
                repeatWeekdayChip(
                    weekday: item.element.weekday,
                    title: item.element.label
                )
                if item.offset < repeatWeekdayLabels.count - 1 {
                    Rectangle()
                        .fill(dividerColor)
                        .frame(width: 1, height: 40)
                }
            }
        }
        .frame(height: 40)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .stroke(dividerColor, lineWidth: 1)
        )
    }

    private func repeatWeekdayChip(weekday: Int, title: String) -> some View {
        let isSelected = repeatWeekdays.contains(weekday)

        return Button {
            if isSelected {
                if repeatWeekdays.count > 1 {
                    repeatWeekdays.remove(weekday)
                }
            } else {
                repeatWeekdays.insert(weekday)
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isSelected ? Color.white : primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(isSelected ? Color.black : cardBackground)
        }
        .buttonStyle(.plain)
    }

    private var minimumSelectableStartAt: Date {
        let calendar = Calendar.current
        let now = Date()
        let truncated = calendar.date(
            bySettingHour: calendar.component(.hour, from: now),
            minute: calendar.component(.minute, from: now),
            second: 0,
            of: now
        ) ?? now

        let hasSubMinuteRemainder =
            calendar.component(.second, from: now) > 0 ||
            calendar.component(.nanosecond, from: now) > 0

        if hasSubMinuteRemainder {
            return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? truncated
        }

        return truncated
    }

    private var startTimePickerMinimumDate: Date {
        if isWeeklyRepeat {
            return Calendar.current.startOfDay(for: Date())
        }
        return minimumSelectableStartAt
    }

    private var endTimePickerMinimumDate: Date {
        Calendar.current.date(byAdding: .minute, value: 1, to: startAt) ?? startAt
    }

    private var maximumSelectableEndAt: Date {
        let calendar = Calendar.current
        let startOfCurrentDay = calendar.startOfDay(for: startAt)
        let startOfDayAfterNext = calendar.date(byAdding: .day, value: 2, to: startOfCurrentDay) ?? startAt
        return calendar.date(byAdding: .minute, value: -1, to: startOfDayAfterNext) ?? startAt
    }

    private var maximumCrossDayDurationMinutes: Int {
        max(1, Int(maximumSelectableEndAt.timeIntervalSince(startAt) / 60))
    }

    private var scheduledEndAt: Date? {
        guard let minutes = durationMinutesValue, minutes > 0 else { return nil }
        return Calendar.current.date(byAdding: .minute, value: minutes, to: startAt)
    }

    private var scheduledEndText: String {
        guard let endAt = scheduledEndAt else { return "--:--" }
        return formattedEndTimeText(endAt)
    }

    private var startDateText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        if AppLanguageRuntime.currentLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        } else {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return formatter.string(from: startAt)
    }

    private var startTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startAt)
    }

    private var endDateText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        if AppLanguageRuntime.currentLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        } else {
            formatter.dateFormat = "yyyy年M月d日"
        }
        return formatter.string(from: endAtDraft)
    }

    private var endTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: endAtDraft)
    }

    private var startEndDurationMinutes: Int {
        let raw = Int(endAtDraft.timeIntervalSince(startAt) / 60)
        return min(max(raw, 1), maximumCrossDayDurationMinutes)
    }

    private var startEndDurationText: String {
        formattedDuration(minutes: startEndDurationMinutes)
    }

    private func formattedDuration(minutes: Int) -> String {
        let safe = max(0, minutes)
        let hour = safe / 60
        let minute = safe % 60
        if AppLanguageRuntime.currentLanguage == .english {
            if hour > 0, minute > 0 {
                return "\(hour)h \(minute)m"
            }
            if hour > 0 {
                return "\(hour)h"
            }
            return "\(minute)m"
        }
        if hour > 0, minute > 0 {
            return "\(hour)小时\(minute)分钟"
        }
        if hour > 0 {
            return "\(hour)小时"
        }
        return "\(minute)分钟"
    }

    private func formattedEndTimeText(_ endAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        formatter.dateFormat = "HH:mm"
        let timeText = formatter.string(from: endAt)

        if Calendar.current.isDate(endAt, inSameDayAs: startAt) {
            return timeText
        }

        return AppLanguageRuntime.currentLanguage == .english ? "Next day \(timeText)" : "次日 \(timeText)"
    }

    private func bootstrapState() {
        syncDurationDraftFromModel()
        if scheduleTimeInputMode == .startEnd {
            clampEndAtDraftAndSyncDuration()
        } else {
            syncEndAtDraftFromDuration()
        }
    }

    private func syncDurationDraftFromModel() {
        let normalized = String(min(max(durationMinutesValue ?? 30, 1), 720))
        if durationDraft != normalized {
            durationDraft = normalized
        }
    }

    private func sanitizeDurationDraft(_ rawValue: String) {
        guard !isSanitizingDurationDraft else { return }

        let digitsOnly = rawValue.filter(\.isNumber)
        var sanitized = String(digitsOnly.prefix(3))

        if let value = Int(sanitized) {
            if value <= 0 {
                sanitized = "1"
            } else if value > 720 {
                sanitized = "720"
            }
        }

        guard sanitized != rawValue else { return }
        isSanitizingDurationDraft = true
        durationDraft = sanitized
        isSanitizingDurationDraft = false
    }

    private func commitDurationDraft() {
        let fallback = min(max(durationMinutesValue ?? 30, 1), 720)
        let trimmed = durationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else {
            durationText = String(fallback)
            durationDraft = String(fallback)
            selectedQuickDurationMinutes = nil
            return
        }

        let clamped = min(max(value, 1), 720)
        durationText = String(clamped)
        durationDraft = String(clamped)
        selectedQuickDurationMinutes = nil
    }

    private func commitDurationDraftLive() {
        let trimmed = durationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0 else { return }

        let clamped = min(max(value, 1), 720)
        let nextValue = String(clamped)
        if durationText != nextValue {
            durationText = nextValue
        }
        if durationDraft != nextValue {
            durationDraft = nextValue
        }
        selectedQuickDurationMinutes = nil
    }

    private func syncEndAtDraftFromDuration() {
        guard !isSyncingScheduleInputs else { return }
        isSyncingScheduleInputs = true
        defer { isSyncingScheduleInputs = false }

        let minutes = min(max(durationMinutesValue ?? 30, 1), maximumCrossDayDurationMinutes)
        let candidate = Calendar.current.date(byAdding: .minute, value: minutes, to: startAt) ?? startAt
        if endAtDraft != candidate {
            endAtDraft = candidate
        }
    }

    private func clampEndAtDraftAndSyncDuration() {
        guard !isSyncingScheduleInputs else { return }
        isSyncingScheduleInputs = true
        defer { isSyncingScheduleInputs = false }

        let minEndAt = endTimePickerMinimumDate
        let maxEndAt = maximumSelectableEndAt
        var clampedEndAt = endAtDraft

        if clampedEndAt < minEndAt {
            clampedEndAt = minEndAt
        }
        if clampedEndAt > maxEndAt {
            clampedEndAt = maxEndAt
        }
        if clampedEndAt != endAtDraft {
            endAtDraft = clampedEndAt
        }

        let minutes = min(max(Int(clampedEndAt.timeIntervalSince(startAt) / 60), 1), maximumCrossDayDurationMinutes)
        let nextDuration = String(minutes)
        if durationText != nextDuration {
            durationText = nextDuration
        }
        selectedQuickDurationMinutes = nil
    }

    private func syncStartAtToCurrentMinimumIfNeeded() {
        guard !isWeeklyRepeat else { return }
        let minimum = minimumSelectableStartAt
        guard startAt < minimum else { return }
        startAt = minimum
    }

    private func applyDefaultRepeatWeekdayIfNeeded() {
        guard repeatWeekdays.isEmpty else { return }
        let weekday = Calendar.current.component(.weekday, from: startAt)
        repeatWeekdays = [weekday]
    }

    private enum StatusBannerTone {
        case error
        case success
    }

    private func statusBanner(text: String, tone: StatusBannerTone) -> some View {
        let tint: Color = tone == .error ? Color(uiColor: .systemRed) : Color(uiColor: .systemGreen)

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(primaryText)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct FlipCountdownText: View {
    let value: String
    let color: Color
    let alignment: Alignment
    @State private var displayedValue: String

    init(value: String, color: Color, alignment: Alignment) {
        self.value = value
        self.color = color
        self.alignment = alignment
        _displayedValue = State(initialValue: value)
    }

    var body: some View {
        Text(displayedValue)
            .font(.system(size: 64, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.18)
            .allowsTightening(true)
            .onChangeCompat(of: value) { newValue in
                withAnimation(.easeInOut(duration: 0.20)) {
                    displayedValue = newValue
                }
            }
            .ifAvailableIOS17 { view in
                view.contentTransition(.numericText(countsDown: true))
            }
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

private extension View {
    @ViewBuilder
    func ifAvailableIOS17<Transformed: View>(
        @ViewBuilder _ transform: (Self) -> Transformed
    ) -> some View {
        if #available(iOS 17.0, *) {
            transform(self)
        } else {
            self
        }
    }

    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }

    @ViewBuilder
    func onChangeCompat<Value: Equatable>(
        of value: Value,
        perform action: @escaping () -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, _ in
                action()
            }
        } else {
            self.onChange(of: value) { _ in
                action()
            }
        }
    }
}

private struct ShareSheetPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension DeviceActivityReport.Context {
    static let onlyLockInsightsDay = Self("onlylock.insights.day")
    static let onlyLockInsightsWeek = Self("onlylock.insights.week")
    static let onlyLockInsightsTrend = Self("onlylock.insights.trend")
    static let onlyLockWeeklyDigest = Self("onlylock.insights.weeklyDigest")
}

#Preview {
    ContentView()
}
