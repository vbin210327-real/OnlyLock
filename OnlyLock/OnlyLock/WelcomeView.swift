import SwiftUI

struct WelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var languageStore: AppLanguageStore
    @State private var appears = false

    let onGetStarted: () -> Void

    private var isDark: Bool { colorScheme == .dark }
    
    // Minimalist light gray background for light mode
    private var pageBackground: Color {
        isDark ? Color(red: 0.08, green: 0.08, blue: 0.09) : Color(red: 0.965, green: 0.965, blue: 0.965)
    }

    private func localized(_ key: String) -> String {
        AppLanguageRuntime.localized(for: key)
    }

    var body: some View {
        GeometryReader { proxy in
            let bottomInset = max(proxy.safeAreaInsets.bottom, 18)
            let statusTopInset = max(proxy.safeAreaInsets.top, 8)
            let languageTopPadding = max(0, statusTopInset - 24)
            let languageButtonHeight: CGFloat = 50
            let contentTopSpacer = max(10.0, statusTopInset + languageButtonHeight - 26)

            ZStack {
                pageBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: contentTopSpacer)

                    // Horizontal Flat Cards
                    VStack(spacing: 16) {
                        // Row 1
                        HStack(spacing: 16) {
                            FlatCardView(
                                iconName: "moon.zzz.fill",
                                title: localized("夺回深夜睡眠"),
                                subtitle: localized("终结睡前报复性熬夜")
                            )
                            FlatCardView(
                                iconName: "scope",
                                title: localized("开启深度专注"),
                                subtitle: localized("夺回注意力的主导权")
                            )
                            FlatCardView(
                                iconName: "arrow.3.trianglepath",
                                title: localized("重塑用机习惯"),
                                subtitle: localized("物理级防沉迷机制")
                            )
                        }
                        .offset(x: appears ? 40 : 72)
                        .opacity(appears ? 1 : 0)
                        .animation(.easeOut(duration: 0.58).delay(0.10), value: appears)

                        // Row 2
                        HStack(spacing: 16) {
                            FlatCardView(
                                iconName: "sparkles",
                                title: localized("逃离数字焦虑"),
                                subtitle: localized("屏蔽无意义信息流")
                            )
                            FlatCardView(
                                iconName: "iphone.badge.play",
                                title: localized("节省屏幕时长"),
                                subtitle: localized("平均每日1.32小时")
                            )
                            FlatCardView(
                                iconName: "shield.lefthalf.filled",
                                title: localized("逃离数字焦虑"),
                                subtitle: localized("屏蔽无意义信息流")
                            )
                        }
                        .offset(x: appears ? -40 : -72)
                        .opacity(appears ? 1 : 0)
                        .animation(.easeOut(duration: 0.58).delay(0.20), value: appears)
                    }
                    .frame(width: proxy.size.width)
                    .mask(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black, location: 0.08),
                                .init(color: .black, location: 0.92),
                                .init(color: .clear, location: 1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.top, 12)
                    .padding(.bottom, 94)

                    // Center Icon Card
                    ZStack {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color.black)
                            .frame(width: 126, height: 126)
                            .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.14), radius: 18, x: 0, y: 10)

                        Image("AppMark")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 108, height: 108)
                    }
                    .opacity(appears ? 1 : 0)
                    .scaleEffect(appears ? 1 : 0.92)
                    .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.36), value: appears)

                    // Bottom Content
                    VStack(spacing: 12) {
                        Text(localized("夺回你的时间"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(isDark ? .white : .black)
                            .opacity(appears ? 1 : 0)
                            .offset(y: appears ? 0 : 16)
                            .animation(.easeOut(duration: 0.55).delay(0.48), value: appears)

                        Text(localized("培养新习惯，屏蔽分心内容，找回完整的专注力。"))
                            .font(.system(size: languageStore.currentLanguage == .english ? 16 : 18, weight: .medium))
                            .foregroundColor(isDark ? Color.white.opacity(0.75) : Color.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineLimit(languageStore.currentLanguage == .english ? 2 : 1)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 22)
                            .opacity(appears ? 1 : 0)
                            .offset(y: appears ? 0 : 16)
                            .animation(.easeOut(duration: 0.55).delay(0.54), value: appears)
                    }
                    .padding(.top, 28)

                    // Button
                    Button(action: {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        onGetStarted()
                    }) {
                        Text(localized("立即开始"))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(isDark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isDark ? Color.white : Color.black)
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 36)
                    .padding(.top, 30)
                    .opacity(appears ? 1 : 0)
                    .offset(y: appears ? 0 : 16)
                    .animation(.easeOut(duration: 0.5).delay(0.62), value: appears)
                    
                    Spacer()
                        .frame(height: bottomInset + 30)
                }
                .frame(width: proxy.size.width)

                VStack {
                    HStack {
                        Spacer()

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                languageStore.toggleLanguage()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(languageStore.switchFlag)
                                    .font(.system(size: 18))

                                Text(languageStore.switchLabel)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(isDark ? Color.white : Color.black)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: languageButtonHeight)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isDark ? Color(white: 0.18) : Color.white)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(isDark ? 0.28 : 0.05), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, languageTopPadding)
                    .padding(.horizontal, 12)

                    Spacer()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .onAppear {
            appears = true
        }
    }
}

struct FlatCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    var iconName: String
    var title: String
    var subtitle: String? = nil
    
    // Matched card width from the screenshot geometry
    var width: CGFloat = 172
    
    private var isDark: Bool { colorScheme == .dark }
    private var isEnglish: Bool { AppLanguageRuntime.currentLanguage == .english }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: iconName)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(isDark ? .white : .black)
            
            Spacer(minLength: 16)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: isEnglish ? 15 : 16, weight: .semibold))
                    .foregroundColor(isDark ? .white : .black)
                    .lineLimit(isEnglish ? 2 : 1)
                    .minimumScaleFactor(0.9)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: isEnglish ? 12 : 14, weight: .regular))
                        .foregroundColor(isDark ? Color(white: 0.65) : Color(white: 0.55))
                        .lineLimit(isEnglish ? 2 : 1)
                        .minimumScaleFactor(0.9)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(" ")
                        .font(.system(size: 14, weight: .regular))
                        .hidden()
                }
            }
        }
        .padding(18)
        .frame(width: width, height: isEnglish ? 128 : 116, alignment: .leading)
        .background(isDark ? Color(white: 0.14) : Color.white)
        // More rounded corners as in the simple modern style
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // The minimalist drop shadow
        .shadow(color: Color.black.opacity(isDark ? 0.35 : 0.04), radius: 14, x: 0, y: 6)
    }
}

#Preview {
    WelcomeView(onGetStarted: {})
        .environmentObject(AppLanguageStore.shared)
}
