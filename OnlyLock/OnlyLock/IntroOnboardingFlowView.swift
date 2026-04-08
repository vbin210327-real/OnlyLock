import Combine
import FamilyControls
import StoreKit
import SwiftUI
import UserNotifications
import UIKit

private enum IntroGoalChoice: String, CaseIterable {
    case focus
    case time
    case sleep
    case calm

    private var localizationKey: String {
        switch self {
        case .focus: return "深度专注"
        case .time: return "高效学习"
        case .sleep: return "早点睡觉"
        case .calm: return "减少分心"
        }
    }

    var title: String {
        AppLanguageRuntime.localized(for: localizationKey)
    }
}

private enum IntroDistractionChoice: String, CaseIterable {
    case shortVideo
    case social
    case notifications
    case oneMoreLook

    private var localizationKey: String {
        switch self {
        case .shortVideo: return "短视频"
        case .social: return "社交媒体"
        case .notifications: return "不良网站"
        case .oneMoreLook: return "电子游戏"
        }
    }

    var title: String {
        AppLanguageRuntime.localized(for: localizationKey)
    }
}

private enum IntroPaywallPlan: CaseIterable {
    case lifetime
    case monthly
}

struct IntroOnboardingFlowView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var currentStep = 0
    @State private var appears = false
    @State private var isRequestingAuthorization = false
    @State private var isRequestingNotificationAuthorization = false
    @State private var permissionArrowOffsetY: CGFloat = 78
    @State private var isPermissionPrivacyPresented = false
    @State private var isAppPickerEmptySheetPresented = false
    @State private var isAppPickerMultipleSheetPresented = false
    @State private var onboardingStartAt = IntroOnboardingFlowView.defaultOnboardingStartAt()
    @State private var onboardingEndAt = IntroOnboardingFlowView.defaultOnboardingEndAt(from: IntroOnboardingFlowView.defaultOnboardingStartAt())
    @State private var isCreatingOnboardingLock = false
    @State private var onboardingAppPickerSelection = FamilyActivitySelection(includeEntireCategory: true)
    @State private var isOnboardingAppPickerPresented = false
    @State private var isOnboardingStartPickerPresented = false
    @State private var isOnboardingEndPickerPresented = false
    @State private var selectedPaywallPlan: IntroPaywallPlan = .lifetime
    @State private var hasRestoredPersistedProgress = false
    @State private var isOnboardingStartTimeExpiredSheetPresented = false
    @GestureState private var permissionPrivacySheetDragOffset: CGFloat = 0
    @State private var authorizationErrorMessage: String?
    @StateObject private var authorizationService = AuthorizationService()
    @StateObject private var paywallStore = IntroOnboardingPaywallStore()

    @AppStorage(OnlyLockShared.onboardingPrimaryGoalKey) private var selectedGoalRawValue = ""
    @AppStorage(OnlyLockShared.onboardingPrimaryDistractionKey) private var selectedDistractionRawValue = ""

    let onBackToWelcome: () -> Void
    let onSkipIntro: () -> Void
    let onComplete: () -> Void
    private let onboardingRuleValidator = LockRuleValidator()
    private let onboardingScheduler = LockScheduler()
    private let onboardingDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
    
    private func l(_ key: String) -> String {
        AppLanguageRuntime.localized(for: key)
    }

    private var isDark: Bool { colorScheme == .dark }

    private var backgroundColor: Color {
        return isDark ? Color(red: 0.08, green: 0.08, blue: 0.09) : Color(red: 0.965, green: 0.965, blue: 0.965)
    }

    private var primaryText: Color {
        isDark ? .white : .black
    }

    private var secondaryText: Color {
        isDark ? Color.white.opacity(0.70) : Color.black.opacity(0.55)
    }

    private var accentFill: Color {
        isDark ? .white : .black
    }

    private var accentForeground: Color {
        isDark ? .black : .white
    }

    private var permissionFrameBlue: Color {
        Color(red: 10 / 255, green: 132 / 255, blue: 1.0)
    }

    private var permissionFrameStroke: Color {
        permissionFrameBlue.opacity(0.70)
    }

    private var permissionArrowColor: Color {
        Color(red: 0 / 255, green: 122 / 255, blue: 1.0)
    }

    private var canContinue: Bool {
        switch currentStep {
        case 0:
            return selectedGoal != nil
        case 1:
            return selectedDistraction != nil
        default:
            return true
        }
    }

    private var selectedGoal: IntroGoalChoice? {
        IntroGoalChoice(rawValue: selectedGoalRawValue)
    }

    private var selectedDistraction: IntroDistractionChoice? {
        IntroDistractionChoice(rawValue: selectedDistractionRawValue)
    }

    private var currentDisplayStep: Int? {
        switch currentStep {
        case 0: return 1
        case 1: return 2
        case 2: return nil
        case 3: return 3
        case 4: return 4
        case 5: return 5
        case 6: return 6
        case 7: return 7
        case 8: return 8
        default: return nil
        }
    }

    private var currentProgressIndex: Int? {
        currentDisplayStep.map { $0 - 1 }
    }

    private var currentTitle: String? {
        switch currentStep {
        case 0:
            return "你的主要目标是什么？"
        case 1:
            return "什么最容易打断你？"
        case 3:
            return "先开启屏幕时间权限"
        case 6:
            return selectedOnboardingAppCount > 1 ? "先给这些应用设一个锁定时间" : "先给这个应用设一个锁定时间"
        case 7:
            return nil
        case 8:
            return "最后，确认你的目标"
        default:
            return nil
        }
    }

    private var currentSubtitle: String? {
        switch currentStep {
        case 3:
            return "为了锁住分心 App 和网站，OnlyLock 需要你的授权"
        default:
            return nil
        }
    }

    private var progressCount: Int {
        8
    }

    private var selectedOnboardingAppCount: Int {
        onboardingAppPickerSelection.applicationTokens.count
    }

    private var onboardingMaximumEndAt: Date {
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: onboardingStartAt) ?? onboardingStartAt
        return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: nextDay) ?? nextDay
    }

    private var onboardingDurationMinutes: Int {
        max(1, Int(onboardingEndAt.timeIntervalSince(onboardingStartAt) / 60))
    }

    private var onboardingDurationFullText: String {
        "\(onboardingDurationMinutes)\(l("分钟"))"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                centerContent
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
            .overlay(alignment: .top) {
                VStack(spacing: 10) {
                    topBar

                    if let currentTitle {
                        Text(AppLanguageRuntime.localized(for: currentTitle))
                            .font(.system(size: currentStep == 6 ? 32 : (currentStep == 8 ? 30 : ((currentStep == 0 || currentStep == 1) ? 32 : 34)), weight: .bold))
                            .foregroundStyle(primaryText)
                            .multilineTextAlignment(currentStep == 6 ? .leading : .center)
                            .lineLimit(
                                currentStep == 8 ? 1 :
                                    (currentStep == 6 ? 2 :
                                        (((currentStep == 1 || currentStep == 3) && AppLanguageRuntime.currentLanguage == .english) ? 2 : 1))
                            )
                            .minimumScaleFactor(
                                ((currentStep == 1 || currentStep == 3) && AppLanguageRuntime.currentLanguage == .english) ? 0.78 :
                                    ((currentStep == 0 || currentStep == 1) ? 0.68 : (currentStep == 8 ? 0.72 : (currentStep == 6 ? 0.92 : 0.82)))
                            )
                            .allowsTightening(currentStep == 8)
                            .frame(maxWidth: .infinity, alignment: currentStep == 6 ? .leading : .center)
                            .padding(.horizontal, currentStep == 6 ? 28 : ((currentStep == 0 || currentStep == 1) ? 20 : 24))
                            .opacity(appears ? 1 : 0)
                            .offset(y: appears ? 0 : 12)
                            .animation(.easeOut(duration: 0.42).delay(0.08), value: appears)
                    }

                    if let currentSubtitle {
                        let isEnglish = AppLanguageRuntime.currentLanguage == .english
                        Text(AppLanguageRuntime.localized(for: currentSubtitle))
                            .font(.system(size: isEnglish ? 17 : 20, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .padding(.horizontal, isEnglish ? 24 : 36)
                            .opacity(appears ? 1 : 0)
                            .offset(y: appears ? 0 : 12)
                            .animation(.easeOut(duration: 0.42).delay(0.12), value: appears)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 24)
            }
            .overlay(alignment: .bottom) {
                if currentStep < 2 {
                    bottomBar
                        .padding(.horizontal, 36)
                        .padding(.bottom, 8)
                } else if currentStep == 2 {
                    EmptyView()
                } else if currentStep == 3 {
                    permissionBottomBar
                        .padding(.horizontal, 36)
                        .padding(.bottom, 8)
                } else if currentStep == 4 {
                    actionBottomBar(buttonTitle: isRequestingNotificationAuthorization ? l("请求中...") : l("继续")) {
                        Task {
                            await requestNotificationAuthorizationAndAdvance()
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 8)
                } else if currentStep == 5 {
                    actionBottomBar(buttonTitle: l("选择应用")) {
                        isOnboardingAppPickerPresented = true
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 8)
                } else if currentStep == 6 {
                    actionBottomBar(buttonTitle: l("继续")) {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            currentStep = 7
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 8)
                } else if currentStep == 7 {
                    EmptyView()
                } else {
                    actionBottomBar(buttonTitle: isCreatingOnboardingLock ? l("创建中...") : l("锁定目标")) {
                        Task {
                            await createOnboardingLockAndContinue()
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 8)
                }
            }
            .overlay {
                if isPermissionPrivacyPresented {
                    permissionPrivacyOverlay
                } else if isAppPickerMultipleSheetPresented {
                    appPickerMultipleOverlay
                } else if isAppPickerEmptySheetPresented {
                    appPickerEmptyOverlay
                } else if isOnboardingStartTimeExpiredSheetPresented {
                    onboardingStartTimeExpiredOverlay
                }
            }
            .alert(l("无法完成操作"), isPresented: Binding(
                get: { authorizationErrorMessage != nil },
                set: { newValue in
                    if !newValue {
                        authorizationErrorMessage = nil
                    }
                }
            )) {
                Button(l("知道了"), role: .cancel) {}
            } message: {
                Text(authorizationErrorMessage ?? "")
            }
        }
        .familyActivityPicker(
            isPresented: $isOnboardingAppPickerPresented,
            selection: $onboardingAppPickerSelection
        )
        .sheet(isPresented: $isOnboardingStartPickerPresented) {
            OnboardingStartTimePickerSheet(
                date: $onboardingStartAt,
                minimumDate: Date(),
                maximumDate: nil
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isOnboardingEndPickerPresented) {
            OnboardingStartTimePickerSheet(
                date: $onboardingEndAt,
                minimumDate: onboardingStartAt.addingTimeInterval(60),
                maximumDate: onboardingMaximumEndAt
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            restorePersistedOnboardingProgressIfNeeded()
            appears = true
            startPermissionArrowAnimationIfNeeded()
        }
        .task {
            await paywallStore.prepare()
            if paywallStore.hasUnlockedAccess, currentStep == 2 {
                currentStep = 3
            }
        }
        .onChange(of: currentStep) { _, _ in
            if paywallStore.hasUnlockedAccess, currentStep == 2 {
                withAnimation(.easeInOut(duration: 0.24)) {
                    currentStep = 3
                }
                return
            }
            persistOnboardingProgress()
            startPermissionArrowAnimationIfNeeded()
        }
        .onChange(of: paywallStore.hasUnlockedAccess) { _, isUnlocked in
            guard isUnlocked, currentStep == 2 else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                currentStep = 3
            }
        }
        .onChange(of: onboardingStartAt) { _, _ in
            clampOnboardingEndAt()
            persistOnboardingProgress()
        }
        .onChange(of: onboardingEndAt) { _, _ in
            clampOnboardingEndAt()
            persistOnboardingProgress()
        }
        .onChange(of: isOnboardingAppPickerPresented) { oldValue, newValue in
            guard oldValue, !newValue, currentStep == 5 else { return }
            handleOnboardingAppPickerDismiss()
        }
    }

    private var centerContent: some View {
        ZStack {
            if currentStep == 0 {
                choiceStepView(
                    options: IntroGoalChoice.allCases.map(\.title),
                    selectedOption: selectedGoal?.title,
                    action: { tapped in
                        if let match = IntroGoalChoice.allCases.first(where: { $0.title == tapped }) {
                            selectedGoalRawValue = match.rawValue
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if currentStep == 1 {
                choiceStepView(
                    options: IntroDistractionChoice.allCases.map(\.title),
                    selectedOption: selectedDistraction?.title,
                    action: { tapped in
                        if let match = IntroDistractionChoice.allCases.first(where: { $0.title == tapped }) {
                            selectedDistractionRawValue = match.rawValue
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if currentStep == 2 {
                paywallStepView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if currentStep == 4 {
                notificationPermissionStepView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if currentStep == 5 {
                appPickerIntroStepView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if currentStep == 6 {
                lockTimeIntroStepView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if currentStep == 7 {
                progressFeedbackStepView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if currentStep == 8 {
                finalCommitStepView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                permissionStepView
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.24), value: currentStep)
    }

    private var topBar: some View {
        HStack {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                if currentStep == 0 {
                    clearPersistedOnboardingProgress()
                    onBackToWelcome()
                } else if currentStep == 8 {
                    return
                } else if currentStep == 3, paywallStore.hasUnlockedAccess {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        currentStep = 1
                    }
                } else if currentStep == 2 {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        currentStep -= 1
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        currentStep -= 1
                    }
                }
            } label: {
                Image(systemName: currentStep == 2 ? "xmark" : "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(currentStep == 8 ? 0 : 1)
            .allowsHitTesting(currentStep != 8)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()

                if currentStep < 2 {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        currentStep += 1
                    }
                } else if currentStep == 3 {
                    return
                } else {
                    clearPersistedOnboardingProgress()
                    onSkipIntro()
                }
            } label: {
                Text(AppLanguageRuntime.localized(for: "跳过"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(currentStep >= 2 ? 0 : 1)
            .allowsHitTesting(currentStep < 2)
        }
        .frame(height: 36)
        .overlay(alignment: .center) {
            if let currentDisplayStep {
                Text("\(currentDisplayStep)/\(progressCount)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .allowsHitTesting(false)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                guard canContinue else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                if currentStep < 1 {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        currentStep += 1
                    }
                } else {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        currentStep = paywallStore.hasUnlockedAccess ? 3 : 2
                    }
                }
            } label: {
                Text(AppLanguageRuntime.localized(for: "继续"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accentForeground.opacity(canContinue ? 1 : 0.6))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canContinue ? accentFill : accentFill.opacity(0.22))
                    )
            }
            .buttonStyle(.plain)
            .opacity(appears ? 1 : 0)
            .offset(y: appears ? 0 : 18)
            .animation(.easeOut(duration: 0.45).delay(0.16), value: appears)

            HStack(spacing: 8) {
                ForEach(0..<progressCount, id: \.self) { index in
                    Circle()
                        .fill(index == currentProgressIndex ? primaryText : primaryText.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 22)
            .opacity(appears ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.22), value: appears)
        }
    }

    private var permissionStepView: some View {
        GeometryReader { proxy in
            let arrowOffsetX = -(proxy.size.width * 0.23)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(l("“OnlyLock” 想要访问屏幕时间"))
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(l("允许 ”OnlyLock“访问屏幕使用时间可能会使其能够查看你的活动数据、限制内容，以及限制应用和网站的使用。"))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 26)
                    .padding(.bottom, 24)

                    HStack(spacing: 12) {
                        Button {
                            Task {
                                await requestOnboardingAuthorization()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isRequestingAuthorization {
                                    ProgressView()
                                        .tint(accentForeground)
                                }
                                Text(l("继续"))
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(accentForeground)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(accentFill)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRequestingAuthorization)
                        .opacity(isRequestingAuthorization ? 0.72 : 1)

                        Button {
                        } label: {
                            Text(l("暂不允许"))
                                .font(.system(size: 16, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .foregroundStyle(primaryText.opacity(0.82))
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
                .background(isDark ? Color(white: 0.12) : Color.black.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(permissionFrameStroke, lineWidth: 2.5)
                }
                .padding(.horizontal, 28)
                .shadow(color: Color.black.opacity(isDark ? 0.34 : 0.06), radius: 22, x: 0, y: 14)
                .opacity(appears ? 1 : 0)
                .offset(y: appears ? 0 : 18)
                .animation(.easeOut(duration: 0.52).delay(0.16), value: appears)
                .overlay(alignment: .bottom) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(permissionArrowColor)
                        .opacity(appears ? 1 : 0)
                        .offset(x: arrowOffsetX)
                        .offset(y: permissionArrowOffsetY)
                        .animation(.easeOut(duration: 0.28).delay(0.22), value: appears)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .padding(.horizontal, 8)
    }

    private var notificationPermissionStepView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 26) {
                Text(l("要开启通知吗？"))
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(l("我们不会打扰你。通知由你自己掌控。"))
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .padding(.horizontal, 16)
            }
            .padding(.horizontal, 30)
            .offset(y: -24)
            .opacity(appears ? 1 : 0)
            .offset(y: appears ? -24 : 12)
            .animation(.easeOut(duration: 0.48).delay(0.14), value: appears)

            Spacer(minLength: 0)
        }
    }

    private var appPickerIntroStepView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(l("从最让你分心的应用开始"))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(AppLanguageRuntime.currentLanguage == .english ? 2 : 1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .padding(.horizontal, 22)
                .offset(y: -18)
                .opacity(appears ? 1 : 0)
                .offset(y: appears ? -18 : 10)
                .animation(.easeOut(duration: 0.48).delay(0.14), value: appears)

            Spacer(minLength: 0)
        }
    }

    private var progressFeedbackStepView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                VStack(spacing: 28) {
                    Text(l("你喜欢目前的进展方式吗？"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(isDark ? Color.white : Color.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 22) {
                        progressFeedbackOptionButton(title: l("是")) {
                            requestOnboardingReviewIfPossible()
                            withAnimation(.easeInOut(duration: 0.24)) {
                                currentStep = 8
                            }
                        }

                        progressFeedbackOptionButton(title: l("否")) {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                currentStep = 8
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(isDark ? Color(red: 0.16, green: 0.16, blue: 0.17) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .offset(y: -10)
            .opacity(appears ? 1 : 0)
            .offset(y: appears ? -10 : 12)
            .animation(.easeOut(duration: 0.48).delay(0.14), value: appears)

            Spacer(minLength: 0)
        }
    }

    private func progressFeedbackOptionButton(title: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(l(title))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(isDark ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 78)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isDark ? Color.white : Color.black)
                )
        }
        .buttonStyle(.plain)
    }

    private var finalCommitStepView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 18) {
                finalCommitChecklistRow(
                    title: finalCommitLockTitle,
                    detail: {
                        finalCommitAppIconsRow
                    }
                )

                finalCommitChecklistRow(
                    title: finalCommitTimeRangeTitle,
                    detail: {
                        Text("\(onboardingStartDateText)  -  \(onboardingEndDateText)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(secondaryText)
                    }
                )
            }
            .padding(.horizontal, 28)
            .offset(y: -8)
            .opacity(appears ? 1 : 0)
            .offset(y: appears ? -8 : 12)
            .animation(.easeOut(duration: 0.48).delay(0.14), value: appears)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var finalCommitAppIconsRow: some View {
        let orderedTokens = onboardingAppPickerSelection.applicationTokens.sorted { String(describing: $0) < String(describing: $1) }
        let visibleTokens = Array(orderedTokens.prefix(4))
        let overflowCount = max(0, orderedTokens.count - visibleTokens.count)

        HStack(spacing: 10) {
            ForEach(Array(visibleTokens.enumerated()), id: \.offset) { _, token in
                Label(token)
                    .labelStyle(.iconOnly)
                    .frame(width: 26, height: 26)
            }

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(secondaryText)
            }
        }
    }

    private func finalCommitChecklistRow<Detail: View>(
        title: String,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentFill)
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentForeground)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                detail()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(onboardingCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    
    private var finalCommitLockTitle: String {
        if AppLanguageRuntime.currentLanguage == .english {
            return "Lock for \(onboardingDurationFullText)"
        }
        return "锁定\(onboardingDurationFullText)"
    }
    
    private var finalCommitTimeRangeTitle: String {
        if AppLanguageRuntime.currentLanguage == .english {
            return "Start \(onboardingStartTimeText) · End \(onboardingEndTimeText)"
        }
        return "开始 \(onboardingStartTimeText) · 结束 \(onboardingEndTimeText)"
    }

    private var paywallStepView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .center, spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isDark ? Color.white : Color.black)
                                .frame(width: 72, height: 72)
                                .shadow(color: Color.black.opacity(isDark ? 0.25 : 0.15), radius: 12, x: 0, y: 4)

                            Image("AppMark")
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .foregroundColor(isDark ? .black : .white)
                                .frame(width: 70, height: 70)
                        }
                        .padding(.bottom, 8)

                        Text(AppLanguageRuntime.localized(for: "OnlyLock会员"))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(primaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(AppLanguageRuntime.localized(for: "解锁所有会员功能"))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        paywallFeatureRow(text: AppLanguageRuntime.localized(for: "无限锁定"))
                        paywallFeatureRow(text: AppLanguageRuntime.localized(for: "硬核锁定无绕行"))
                        paywallFeatureRow(text: AppLanguageRuntime.localized(for: "锁定所有App/网站"))
                        paywallFeatureRow(text: AppLanguageRuntime.localized(for: "每周定制屏幕使用时间报告"))
                        paywallFeatureRow(text: AppLanguageRuntime.localized(for: "纯净无广"))
                        paywallFeatureRow(text: AppLanguageRuntime.localized(for: "更多高级功能"))
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 48)
                }
                .padding(.top, 48)

                Spacer(minLength: 0)
            }

            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    paywallOptionCard(for: .lifetime)
                    paywallOptionCard(for: .monthly)
                }

                if let errorMessage = paywallStore.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task {
                        if paywallStore.hasLoadedProducts {
                            await purchaseSelectedPlan()
                        } else {
                            await paywallStore.reloadProducts()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if paywallStore.isPurchasing {
                            ProgressView()
                                .tint(accentForeground)
                        }
                        Text(AppLanguageRuntime.localized(for: paywallPrimaryButtonTitle))
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundStyle(accentForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accentFill)
                    )
                }
                .buttonStyle(.plain)
                .disabled(paywallStore.isPurchasing || paywallStore.isRestoring || paywallStore.isLoadingProducts)
                .opacity((paywallStore.isLoadingProducts || (!paywallStore.hasLoadedProducts && paywallStore.errorMessage != nil)) ? 0.72 : 1)

                HStack(spacing: 0) {
                    Link(AppLanguageRuntime.localized(for: "隐私政策"), destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity)

                    Button {
                        Task {
                            await restoreMembership()
                        }
                    } label: {
                        if paywallStore.isRestoring {
                            ProgressView()
                                .tint(secondaryText)
                                .frame(height: 14)
                        } else {
                            Text(AppLanguageRuntime.localized(for: "恢复购买"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(paywallStore.isPurchasing || paywallStore.isRestoring)
                    .frame(maxWidth: .infinity)

                    Link(AppLanguageRuntime.localized(for: "使用条款"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(isDark ? Color(red: 0.14, green: 0.14, blue: 0.15) : Color.white)
                    .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.08), radius: 24, x: 0, y: -6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.04), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .opacity(appears ? 1 : 0)
        .offset(y: appears ? 0 : 14)
        .animation(.easeOut(duration: 0.48).delay(0.14), value: appears)
    }

    private func paywallFeatureRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primaryText)
                .frame(width: 18, height: 18)

            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func paywallOptionCard(for plan: IntroPaywallPlan) -> some View {
        let isSelected = selectedPaywallPlan == plan
        let title: String
        let subtitle: String?
        let price: String
        let isEnglish = AppLanguageRuntime.currentLanguage == .english

        switch plan {
        case .lifetime:
            title = isEnglish ? "Lifetime" : AppLanguageRuntime.localized(for: "终身会员")
            subtitle = AppLanguageRuntime.localized(for: "一次购买，永久解锁")
            price = paywallStore.lifetimeDisplayPrice
        case .monthly:
            title = isEnglish ? "Monthly" : AppLanguageRuntime.localized(for: "月度会员")
            subtitle = AppLanguageRuntime.localized(for: "3天免费试用")
            price = paywallStore.monthlyDisplayPrice
        }

        return Button {
            guard selectedPaywallPlan != plan else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            selectedPaywallPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Top row: title + checkmark
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)

                    Spacer(minLength: 4)

                    Group {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(accentForeground, accentFill)
                                .font(.system(size: 20))
                        } else {
                            Circle()
                                .stroke(primaryText.opacity(0.18), lineWidth: 1.5)
                                .frame(width: 20, height: 20)
                        }
                    }
                }

                // Subtitle with fixed height so both cards align
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.88)
                        .frame(height: isEnglish ? 30 : 16, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 3)
                }

                // Price
                Text(price)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.05) : Color.white)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? accentFill : primaryText.opacity(isDark ? 0.12 : 0.08), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var paywallPrimaryButtonTitle: String {
        if paywallStore.isLoadingProducts {
            return "加载中..."
        }
        if !paywallStore.hasLoadedProducts {
            return "重新加载购买选项"
        }

        switch selectedPaywallPlan {
        case .lifetime:
            return "买断"
        case .monthly:
            return "开始3天免费试用"
        }
    }

    private var lockTimeIntroStepView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(l("开始时间"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryText)

                Button {
                    isOnboardingStartPickerPresented = true
                } label: {
                    HStack {
                        Text("\(onboardingStartDateText)  /  \(onboardingStartTimeText)")
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
                    .background(onboardingCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(l("结束时间"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryText)

                Button {
                    isOnboardingEndPickerPresented = true
                } label: {
                    HStack {
                        Text("\(onboardingEndDateText)  /  \(onboardingEndTimeText)")
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
                    .background(onboardingCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(onboardingDividerColor)
                .frame(height: 1)

            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(secondaryText)

                    Text(l("锁定时长："))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(primaryText)
                }

                Spacer()

                Text(onboardingDurationText)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryText)
            }
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 28)
        .opacity(appears ? 1 : 0)
        .offset(y: appears ? 0 : 10)
        .animation(.easeOut(duration: 0.48).delay(0.14), value: appears)
    }

    private var onboardingCardBackground: Color {
        isDark ? Color.white.opacity(0.06) : Color.white
    }

    private var onboardingDividerColor: Color {
        primaryText.opacity(isDark ? 0.10 : 0.08)
    }

    private var onboardingStartDateText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: onboardingStartAt)
    }

    private var onboardingStartTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: onboardingStartAt)
    }

    private var onboardingEndDateText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: onboardingEndAt)
    }

    private var onboardingEndTimeText: String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageRuntime.currentLanguage.locale
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: onboardingEndAt)
    }

    private var onboardingDurationText: String {
        let minutes = onboardingDurationMinutes
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours > 0, remainder > 0 {
            return "\(hours)\(l("小时"))\(remainder)\(l("分"))"
        }
        if hours > 0 {
            return "\(hours)\(l("小时"))"
        }
        return "\(minutes)\(l("分"))"
    }

    private var permissionBottomBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(l("你的数据由 Apple 权限体系保护"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(secondaryText)

                Button {
                    withAnimation(.easeOut(duration: 0.22)) {
                        isPermissionPrivacyPresented = true
                    }
                } label: {
                    Text(l("了解更多"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(primaryText)
                }
                .buttonStyle(.plain)
            }
            .opacity(appears ? 1 : 0)
            .animation(.easeOut(duration: 0.45).delay(0.28), value: appears)

            HStack(spacing: 8) {
                ForEach(0..<progressCount, id: \.self) { index in
                    Circle()
                        .fill(index == currentProgressIndex ? primaryText : primaryText.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 24)
            .opacity(appears ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.30), value: appears)
        }
    }

    private func actionBottomBar(buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                action()
            } label: {
                Text(AppLanguageRuntime.localized(for: buttonTitle))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accentForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        Capsule(style: .continuous)
                            .fill(accentFill)
                    )
            }
            .buttonStyle(.plain)
            .disabled(currentStep == 4 && isRequestingNotificationAuthorization)
            .opacity(appears ? 1 : 0)
            .offset(y: appears ? 0 : 18)
            .animation(.easeOut(duration: 0.45).delay(0.16), value: appears)

            HStack(spacing: 8) {
                ForEach(0..<progressCount, id: \.self) { index in
                    Circle()
                        .fill(index == currentProgressIndex ? primaryText : primaryText.opacity(0.18))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.top, 22)
            .opacity(appears ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.22), value: appears)
        }
    }

    private var permissionPrivacyOverlay: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.52 : 0.34)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissPermissionPrivacyOverlay()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.28) : Color.black.opacity(0.18))
                        .frame(width: 54, height: 6)
                        .padding(.top, 12)

                    ZStack {
                        Circle()
                            .fill(isDark ? Color.white : Color.black)
                            .frame(width: 64, height: 64)

                        Image(systemName: "lock.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isDark ? Color.black : Color.white)
                    }
                    .padding(.top, 18)

                    Text(l("你的数据由 Apple 保护，OnlyLock 无法看到这些内容："))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(isDark ? Color.white : Color.black)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .padding(.top, 20)
                        .padding(.horizontal, 18)

                    VStack(spacing: 18) {
                        Text(l("你的浏览记录，例如具体访问过哪些网站、打开过哪些 App"))
                        Text(l("你的完整屏幕使用明细和个人活动数据"))
                    }
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isDark ? Color.white.opacity(0.68) : Color.black.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 22)
                    .padding(.horizontal, 28)

                    Button {
                        dismissPermissionPrivacyOverlay(duration: 0.18)
                        Task {
                            await requestOnboardingAuthorization()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isRequestingAuthorization {
                                ProgressView()
                                    .tint(Color.black)
                            }
                            Text(l("继续授权"))
                                .font(.system(size: 18, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .foregroundStyle(isDark ? Color.black : Color.white)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isDark ? Color.white : Color.black)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 22)
                    .disabled(isRequestingAuthorization)
                    .opacity(isRequestingAuthorization ? 0.82 : 1)
                }
                .frame(maxWidth: 420)
                .background(isDark ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 16)
                .offset(y: max(0, permissionPrivacySheetDragOffset))
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .updating($permissionPrivacySheetDragOffset) { value, state, _ in
                            if value.translation.height > 0 {
                                state = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if value.translation.height > 90 {
                                dismissPermissionPrivacyOverlay()
                            }
                        }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var appPickerEmptyOverlay: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.52 : 0.26)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAppPickerEmptyOverlay()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.14))
                        .frame(width: 54, height: 6)
                        .padding(.top, 12)

                    Text(l("还没有选择应用"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(isDark ? Color.white : Color.black)
                        .multilineTextAlignment(.center)
                        .padding(.top, 26)
                        .padding(.horizontal, 24)

                    Text(l("请先选择一个最让你分心的应用，才能继续。"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isDark ? Color.white.opacity(0.68) : Color.black.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                        .padding(.horizontal, 30)

                    Button {
                        dismissAppPickerEmptyOverlay(duration: 0.18)
                        isOnboardingAppPickerPresented = true
                    } label: {
                        Text(l("选择应用"))
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .foregroundStyle(isDark ? Color.black : Color.white)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isDark ? Color.white : Color.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 420)
                .background(isDark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.14), radius: 28, x: 0, y: 16)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onEnded { value in
                            if value.translation.height > 90 {
                                dismissAppPickerEmptyOverlay()
                            }
                        }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var appPickerMultipleOverlay: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.52 : 0.26)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissAppPickerMultipleOverlay()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(isDark ? Color.white.opacity(0.24) : Color.black.opacity(0.14))
                        .frame(width: 54, height: 6)
                        .padding(.top, 12)

                    Text(l("已选择多个应用"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(isDark ? Color.white : Color.black)
                        .multilineTextAlignment(.center)
                        .padding(.top, 26)
                        .padding(.horizontal, 24)

                    Text(AppLanguageRuntime.currentLanguage == .english
                        ? "You selected \(selectedOnboardingAppCount) apps. Keep one for now."
                        : "你刚才选了 \(selectedOnboardingAppCount) 个应用。现在先选一个试试。")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isDark ? Color.white.opacity(0.68) : Color.black.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                        .padding(.horizontal, 30)

                    HStack(spacing: 14) {
                        Button {
                            dismissAppPickerMultipleOverlay(duration: 0.18)
                            withAnimation(.easeInOut(duration: 0.24)) {
                                currentStep = 6
                            }
                        } label: {
                            Text(AppLanguageRuntime.currentLanguage == .english
                                ? "Keep \(selectedOnboardingAppCount)"
                                : "保留 \(selectedOnboardingAppCount) 个")
                                .font(.system(size: 18, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .foregroundStyle(isDark ? Color.white : Color.black)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            dismissAppPickerMultipleOverlay(duration: 0.18)
                            isOnboardingAppPickerPresented = true
                        } label: {
                            Text(l("只选一个"))
                                .font(.system(size: 18, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .foregroundStyle(isDark ? Color.black : Color.white)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(isDark ? Color.white : Color.black)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 420)
                .background(isDark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.14), radius: 28, x: 0, y: 16)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onEnded { value in
                            if value.translation.height > 90 {
                                dismissAppPickerMultipleOverlay()
                            }
                        }
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var onboardingStartTimeExpiredOverlay: some View {
        ZStack {
            Color.black.opacity(isDark ? 0.52 : 0.26)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    Text(l("请重新选择开始时间"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(isDark ? Color.white : Color.black)
                        .multilineTextAlignment(.center)
                        .padding(.top, 28)
                        .padding(.horizontal, 24)

                    Text(l("你的开始时间晚于当前时间"))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isDark ? Color.white.opacity(0.68) : Color.black.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 18)
                        .padding(.horizontal, 30)

                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isOnboardingStartTimeExpiredSheetPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                            isOnboardingStartPickerPresented = true
                        }
                    } label: {
                        Text(l("重新选择开始时间"))
                            .font(.system(size: 18, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .foregroundStyle(isDark ? Color.black : Color.white)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isDark ? Color.white : Color.black)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 420)
                .background(isDark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.14), radius: 28, x: 0, y: 16)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func dismissPermissionPrivacyOverlay(duration: Double = 0.22) {
        withAnimation(.easeOut(duration: duration)) {
            isPermissionPrivacyPresented = false
        }
    }

    private func dismissAppPickerEmptyOverlay(duration: Double = 0.22) {
        withAnimation(.easeOut(duration: duration)) {
            isAppPickerEmptySheetPresented = false
        }
    }

    private func dismissAppPickerMultipleOverlay(duration: Double = 0.22) {
        withAnimation(.easeOut(duration: duration)) {
            isAppPickerMultipleSheetPresented = false
        }
    }

    @MainActor
    private func requestOnboardingAuthorization() async {
        if authorizationService.isApproved {
            withAnimation(.easeInOut(duration: 0.24)) {
                currentStep = 4
            }
            return
        }

        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }

        do {
            try await authorizationService.requestAuthorization()
        } catch {
            if shouldSilentlyIgnoreAuthorizationFailure(error) {
                return
            }
            authorizationErrorMessage = l("没有完成屏幕时间授权，你稍后仍可在设置或创建锁定任务时开启。")
            return
        }

        if authorizationService.isApproved {
            withAnimation(.easeInOut(duration: 0.24)) {
                currentStep = 4
            }
        } else if !shouldSilentlyIgnoreAuthorizationFailure(nil) {
            authorizationErrorMessage = l("没有完成屏幕时间授权，你稍后仍可在设置或创建锁定任务时开启。")
        }
    }

    private func shouldSilentlyIgnoreAuthorizationFailure(_ error: Error?) -> Bool {
        if #available(iOS 16.4, *) {
            if let familyControlsError = error as? FamilyControlsError,
               familyControlsError == .authorizationCanceled {
                return true
            }
        }

        return authorizationService.status == .denied
    }

    private func handleOnboardingAppPickerDismiss() {
        persistOnboardingProgress()
        if selectedOnboardingAppCount == 0 {
            withAnimation(.easeOut(duration: 0.22)) {
                isAppPickerEmptySheetPresented = true
            }
        } else if selectedOnboardingAppCount > 1 {
            withAnimation(.easeOut(duration: 0.22)) {
                isAppPickerMultipleSheetPresented = true
            }
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                currentStep = 6
            }
        }
    }

    private func clampOnboardingEndAt() {
        let minimum = onboardingStartAt.addingTimeInterval(60)
        let candidate = min(max(onboardingEndAt, minimum), onboardingMaximumEndAt)
        if onboardingEndAt != candidate {
            onboardingEndAt = candidate
        }
    }

    @MainActor
    private func createOnboardingLockAndContinue() async {
        guard !isCreatingOnboardingLock else { return }
        guard onboardingStartAt > Date() else {
            withAnimation(.easeOut(duration: 0.22)) {
                isOnboardingStartTimeExpiredSheetPresented = true
            }
            return
        }

        isCreatingOnboardingLock = true
        defer { isCreatingOnboardingLock = false }

        do {
            let rule = try onboardingRuleValidator.buildRule(
                name: nil,
                startAt: onboardingStartAt,
                durationMinutes: max(1, onboardingDurationMinutes),
                isWeeklyRepeat: false,
                repeatWeekdays: [],
                selection: onboardingAppPickerSelection,
                manualWebDomains: [],
                existing: nil
            )
            try await onboardingScheduler.saveAndSchedule(rule: rule)
            let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
            defaults.set("current", forKey: OnlyLockShared.pendingInitialTabKey)
            defaults.synchronize()
            clearPersistedOnboardingProgress()
            onComplete()
        } catch {
            authorizationErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func purchaseSelectedPlan() async {
        let succeeded: Bool
        switch selectedPaywallPlan {
        case .lifetime:
            succeeded = await paywallStore.purchaseLifetime()
        case .monthly:
            succeeded = await paywallStore.purchaseMonthly()
        }

        if succeeded {
            withAnimation(.easeInOut(duration: 0.24)) {
                currentStep = 3
            }
        } else if let errorMessage = paywallStore.errorMessage {
            authorizationErrorMessage = errorMessage
        }
    }

    @MainActor
    private func restoreMembership() async {
        let restored = await paywallStore.restorePurchases()
        if restored {
            withAnimation(.easeInOut(duration: 0.24)) {
                currentStep = 3
            }
        } else if let errorMessage = paywallStore.errorMessage {
            authorizationErrorMessage = errorMessage
        }
    }

    @MainActor
    private func requestNotificationAuthorizationAndAdvance() async {
        guard !isRequestingNotificationAuthorization else { return }

        isRequestingNotificationAuthorization = true
        defer { isRequestingNotificationAuthorization = false }

        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])

        withAnimation(.easeInOut(duration: 0.24)) {
            currentStep = 5
        }
    }

    private func requestOnboardingReviewIfPossible() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        SKStoreReviewController.requestReview(in: scene)
    }

    private func persistOnboardingProgress() {
        guard (0...8).contains(currentStep) else { return }
        onboardingDefaults.set(currentStep, forKey: OnlyLockShared.onboardingCurrentStepKey)
        onboardingDefaults.set(onboardingStartAt.timeIntervalSince1970, forKey: OnlyLockShared.onboardingStartTimestampKey)
        onboardingDefaults.set(onboardingEndAt.timeIntervalSince1970, forKey: OnlyLockShared.onboardingEndTimestampKey)

        if let data = try? JSONEncoder().encode(onboardingAppPickerSelection) {
            onboardingDefaults.set(data, forKey: OnlyLockShared.onboardingSelectionDataKey)
        }
    }

    private func restorePersistedOnboardingProgressIfNeeded() {
        guard !hasRestoredPersistedProgress else { return }
        hasRestoredPersistedProgress = true

        let storedStep = onboardingDefaults.integer(forKey: OnlyLockShared.onboardingCurrentStepKey)
        if (0...8).contains(storedStep) {
            currentStep = storedStep
        }

        let storedStartTimestamp = onboardingDefaults.double(forKey: OnlyLockShared.onboardingStartTimestampKey)
        if storedStartTimestamp > 0 {
            onboardingStartAt = Date(timeIntervalSince1970: storedStartTimestamp)
        }

        let storedEndTimestamp = onboardingDefaults.double(forKey: OnlyLockShared.onboardingEndTimestampKey)
        if storedEndTimestamp > 0 {
            onboardingEndAt = Date(timeIntervalSince1970: storedEndTimestamp)
        }

        if let data = onboardingDefaults.data(forKey: OnlyLockShared.onboardingSelectionDataKey),
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            onboardingAppPickerSelection = selection
        }

        clampOnboardingEndAt()
    }

    private func clearPersistedOnboardingProgress() {
        onboardingDefaults.removeObject(forKey: OnlyLockShared.onboardingCurrentStepKey)
        onboardingDefaults.removeObject(forKey: OnlyLockShared.onboardingStartTimestampKey)
        onboardingDefaults.removeObject(forKey: OnlyLockShared.onboardingEndTimestampKey)
        onboardingDefaults.removeObject(forKey: OnlyLockShared.onboardingSelectionDataKey)
    }

    private func startPermissionArrowAnimationIfNeeded() {
        if currentStep == 3 {
            permissionArrowOffsetY = 82
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                permissionArrowOffsetY = 64
            }
        } else {
            permissionArrowOffsetY = 78
        }
    }

    private static func defaultOnboardingStartAt(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let advanced = calendar.date(byAdding: .minute, value: 5, to: now) ?? now
        let minute = calendar.component(.minute, from: advanced)
        let roundedMinute = (minute / 5) * 5

        return calendar.date(
            bySettingHour: calendar.component(.hour, from: advanced),
            minute: roundedMinute,
            second: 0,
            of: advanced
        ) ?? advanced
    }

    private static func defaultOnboardingEndAt(from startAt: Date) -> Date {
        startAt.addingTimeInterval(30 * 60)
    }

    private func choiceStepView(
        options: [String],
        selectedOption: String?,
        action: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selectedOption

                    Button {
                        action(option)
                    } label: {
                        Text(AppLanguageRuntime.localized(for: option))
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isSelected ? accentForeground : primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 70)
                            .background(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(isSelected ? accentFill : Color.white.opacity(isDark ? 0.06 : 0.78))
                            )
                            .overlay {
                                if !isSelected {
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .stroke(primaryText.opacity(isDark ? 0.10 : 0.08), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 36)
            .opacity(appears ? 1 : 0)
            .offset(y: appears ? 0 : 18)
            .animation(.easeOut(duration: 0.48).delay(0.18), value: appears)
        }
    }
}

private struct OnboardingStartTimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Binding var date: Date
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
    private var weekSymbols: [String] {
        if AppLanguageRuntime.currentLanguage == .english {
            return ["M", "T", "W", "T", "F", "S", "S"]
        }
        return ["一", "二", "三", "四", "五", "六", "日"]
    }

    private func l(_ key: String) -> String {
        AppLanguageRuntime.localized(for: key)
    }

    init(date: Binding<Date>, minimumDate: Date, maximumDate: Date?) {
        _date = date
        self.minimumDate = minimumDate
        self.maximumDate = maximumDate
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date.wrappedValue)
        ) ?? date.wrappedValue
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
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: displayedMonth)
    }

    private var hourString: String {
        String(format: "%02d", calendar.component(.hour, from: date))
    }

    private var minuteString: String {
        String(format: "%02d", calendar.component(.minute, from: date))
    }

    private var periodText: String {
        calendar.component(.hour, from: date) < 12 ? l("上午") : l("下午")
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
        calendar.isDate(date, inSameDayAs: minimumSelectableDate)
    }

    private var isSelectingMaximumDay: Bool {
        guard let maximumSelectableDate else { return false }
        return calendar.isDate(date, inSameDayAs: maximumSelectableDate)
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
            let selectedHour = calendar.component(.hour, from: date)
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
                if let candidate = dayDate(day, in: previousMonth) {
                    cells.append(DayCell(date: candidate, day: day, isCurrentMonth: false))
                }
            }
        }

        for day in monthDays {
            if let candidate = dayDate(day, in: monthStart) {
                cells.append(DayCell(date: candidate, day: day, isCurrentMonth: true))
            }
        }

        let trailingCount = (7 - (cells.count % 7)) % 7
        if trailingCount > 0,
           let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart) {
            for day in 1...trailingCount {
                if let candidate = dayDate(day, in: nextMonth) {
                    cells.append(DayCell(date: candidate, day: day, isCurrentMonth: false))
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
        .onChange(of: date) { _, newValue in
            let start = monthStart(for: newValue)
            if !calendar.isDate(start, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = start
            }
        }
        .onChange(of: activeTimeField) { _, field in
            if field != nil {
                overlayBaseOffsetY = 0
                isOverlayDismissing = false
            }
        }
        .onDisappear {
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

            Button(l("完成")) {
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
            Text(l("选择日期和时间"))
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
        let selected = calendar.isDate(cell.date, inSameDayAs: date)
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
                Text(l("时间"))
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
        let currentHour = calendar.component(.hour, from: date)
        let currentMinute = calendar.component(.minute, from: date)
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

                Button(l("完成")) {
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
            var selectedMinute = calendar.component(.minute, from: date)

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
            updateTime(hour: calendar.component(.hour, from: date), minute: selectedMinute)
        }
    }

    private func updateTime(hour: Int, minute: Int) {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return }
        let clampedToMinimum = max(candidate, minimumSelectableDate)
        if let maximumSelectableDate {
            date = min(clampedToMinimum, maximumSelectableDate)
        } else {
            date = clampedToMinimum
        }
    }

    private func shiftMonth(by offset: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = monthStart(for: shifted)
    }

    private func selectDay(_ day: Date) {
        guard !isDayOutOfRange(day) else { return }

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

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
        date = finalDate
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

    private func isDayOutOfRange(_ candidate: Date) -> Bool {
        let dayStart = calendar.startOfDay(for: candidate)
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
                return AppLanguageRuntime.localized(for: "选择小时")
            case .minute:
                return AppLanguageRuntime.localized(for: "选择分钟")
            }
        }
    }
}

@MainActor
final class IntroOnboardingPaywallStore: ObservableObject {
    private let monthlyProductID = "com.onlylock.membership.monthly"
    private let lifetimeProductID = "com.onlylock.membership.lifetime"
    private let defaults: UserDefaults

    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var hasUnlockedAccess: Bool
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published var errorMessage: String?

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        self.hasUnlockedAccess = self.defaults.bool(forKey: OnlyLockShared.membershipUnlockedKey)
    }

    var hasLoadedProducts: Bool {
        monthlyProduct != nil && lifetimeProduct != nil
    }

    var monthlyDisplayPrice: String {
        monthlyProduct?.displayPrice ?? "¥8"
    }

    var lifetimeDisplayPrice: String {
        lifetimeProduct?.displayPrice ?? "¥18"
    }

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

    func prepare() async {
        await refreshEntitlements()
        await loadProducts(force: false)
    }

    func reloadProducts() async {
        await loadProducts(force: true)
    }

    func purchaseMonthly() async -> Bool {
        await purchase(product: monthlyProduct)
    }

    func purchaseLifetime() async -> Bool {
        await purchase(product: lifetimeProduct)
    }

    func restorePurchases() async -> Bool {
        guard !isRestoring else { return false }

        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        if isDebugSimulatorPurchaseEnabled {
            await refreshEntitlements()
            if hasUnlockedAccess {
                return true
            }
            errorMessage = AppLanguageRuntime.localized(for: "模拟器中没有可恢复的购买记录。")
            return false
        }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if hasUnlockedAccess {
                return true
            }
            errorMessage = AppLanguageRuntime.localized(for: "没有找到可恢复的购买记录。")
            return false
        } catch {
            errorMessage = AppLanguageRuntime.localized(for: "恢复购买失败，请稍后再试。")
            return false
        }
    }

    private func loadProducts(force: Bool) async {
        guard !isLoadingProducts else { return }
        guard force || !hasLoadedProducts else { return }

        isLoadingProducts = true
        errorMessage = nil
        defer { isLoadingProducts = false }

        for attempt in 0..<3 {
            do {
                let products = try await Product.products(for: [monthlyProductID, lifetimeProductID])
                monthlyProduct = products.first(where: { $0.id == monthlyProductID })
                lifetimeProduct = products.first(where: { $0.id == lifetimeProductID })

                if hasLoadedProducts {
                    errorMessage = nil
                    return
                }
            } catch {
                if attempt == 2 {
                    errorMessage = AppLanguageRuntime.localized(for: "暂时无法加载购买选项，请稍后重试。")
                    return
                }
            }

            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(700))
            }
        }

        errorMessage = AppLanguageRuntime.localized(for: "暂时无法加载购买选项，请稍后重试。")
    }

    private func purchase(product: Product?) async -> Bool {
        guard !isPurchasing else { return false }
        guard let product else {
            errorMessage = AppLanguageRuntime.localized(for: "购买选项还在加载中，请稍后再试。")
            return false
        }

        if isDebugSimulatorPurchaseEnabled {
            applyPurchasedTier(for: product.id)
            return true
        }

        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = AppLanguageRuntime.localized(for: "购买验证失败，请稍后再试。")
                    return false
                }
                applyPurchasedTier(for: transaction.productID)
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .pending:
                errorMessage = AppLanguageRuntime.localized(for: "购买正在等待确认。")
                return false
            case .userCancelled:
                return false
            @unknown default:
                errorMessage = AppLanguageRuntime.localized(for: "购买未完成，请稍后再试。")
                return false
            }
        } catch {
            errorMessage = AppLanguageRuntime.localized(for: "购买失败，请稍后再试。")
            return false
        }
    }

    private func refreshEntitlements() async {
        var unlockedProductIDs = Set<String>()
        var monthlyExpirationTimestamp: TimeInterval = 0

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard transaction.revocationDate == nil else { continue }

            if transaction.productID == monthlyProductID || transaction.productID == lifetimeProductID {
                unlockedProductIDs.insert(transaction.productID)
                if transaction.productID == monthlyProductID,
                   let expirationDate = transaction.expirationDate {
                    monthlyExpirationTimestamp = max(monthlyExpirationTimestamp, expirationDate.timeIntervalSince1970)
                }
            }
        }

        if isDebugSimulatorPurchaseEnabled, unlockedProductIDs.isEmpty {
            let storedTier = SettingsStore.MembershipTier(
                rawValue: defaults.string(forKey: OnlyLockShared.membershipTierKey) ?? ""
            ) ?? .none
            let unlocked = OnlyLockShared.hasActiveMembership(defaults: defaults)
            hasUnlockedAccess = unlocked
            defaults.set(unlocked, forKey: OnlyLockShared.membershipUnlockedKey)
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

        let tier: SettingsStore.MembershipTier
        if unlockedProductIDs.contains(lifetimeProductID) {
            tier = .lifetime
        } else if unlockedProductIDs.contains(monthlyProductID) {
            tier = .monthly
        } else {
            tier = .none
        }

        let unlocked = tier != .none
        hasUnlockedAccess = unlocked
        defaults.set(unlocked, forKey: OnlyLockShared.membershipUnlockedKey)
        defaults.set(tier.rawValue, forKey: OnlyLockShared.membershipTierKey)
        defaults.set(tier == .monthly ? monthlyExpirationTimestamp : 0, forKey: OnlyLockShared.membershipExpirationTimestampKey)
        defaults.synchronize()
    }

    private func applyPurchasedTier(for productID: String) {
        let tier: SettingsStore.MembershipTier
        if productID == lifetimeProductID {
            tier = .lifetime
        } else if productID == monthlyProductID {
            tier = .monthly
        } else {
            tier = .none
        }

        hasUnlockedAccess = tier != .none
        defaults.set(tier != .none, forKey: OnlyLockShared.membershipUnlockedKey)
        defaults.set(tier.rawValue, forKey: OnlyLockShared.membershipTierKey)
        if tier == .monthly {
            defaults.set(Date().addingTimeInterval(30 * 24 * 60 * 60).timeIntervalSince1970, forKey: OnlyLockShared.membershipExpirationTimestampKey)
        } else {
            defaults.set(0, forKey: OnlyLockShared.membershipExpirationTimestampKey)
        }
        defaults.synchronize()
    }
}

#Preview {
    IntroOnboardingFlowView(onBackToWelcome: {}, onSkipIntro: {}, onComplete: {})
}
