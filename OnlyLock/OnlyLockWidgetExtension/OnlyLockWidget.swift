import SwiftUI
import WidgetKit

private enum OnlyLockWidgetShared {
    static let appGroupIdentifier = "group.com.onlylock.shared"
    static let streakKey = "onlylock.widget.currentStreak"
    static let appLanguageCodeKey = "onlylock.settings.appLanguageCode"
#if DEBUG
    static let debugStreakOverrideEnabledKey = "onlylock.debug.widget.streakOverride.enabled"
    static let debugStreakOverrideDaysKey = "onlylock.debug.widget.streakOverride.days"
#endif
}

private func widgetIsEnglish() -> Bool {
    let defaults = UserDefaults(suiteName: OnlyLockWidgetShared.appGroupIdentifier) ?? .standard
    return (defaults.string(forKey: OnlyLockWidgetShared.appLanguageCodeKey) ?? "zh-Hans") == "en"
}

private struct StreakEntry: TimelineEntry {
    let date: Date
    let streak: Int
}

private struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), streak: 7)
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: Date(), streak: currentStreak()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let now = Date()
        let entry = StreakEntry(date: now, streak: currentStreak())
        let refresh = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    private func currentStreak() -> Int {
        let defaults = UserDefaults(suiteName: OnlyLockWidgetShared.appGroupIdentifier) ?? .standard
#if DEBUG
        if defaults.bool(forKey: OnlyLockWidgetShared.debugStreakOverrideEnabledKey) {
            return max(0, defaults.integer(forKey: OnlyLockWidgetShared.debugStreakOverrideDaysKey))
        }
#endif
        return max(0, defaults.integer(forKey: OnlyLockWidgetShared.streakKey))
    }
}

private struct OnlyLockStreakWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: StreakEntry

    var body: some View {
        let foreground = colorScheme == .dark ? Color.white : Color.black

        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                if entry.streak <= 0 {
                    Text(widgetIsEnglish() ? "No check-in yet" : "还未打卡")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .position(x: width * 0.5, y: height * 0.5)
                } else {
                    Text(widgetIsEnglish() ? "Stay Focused" : "保持专注")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .allowsTightening(true)
                        .position(x: width * 0.5, y: height * 0.44)

                    Text(widgetIsEnglish() ? "\(entry.streak)-day streak" : "连续打卡\(entry.streak)天")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .allowsTightening(true)
                        .position(x: width * 0.5, y: max(0, height - 14))
                }
            }
            .frame(width: width, height: height)
        }
        .unredacted()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(WidgetContainerBackgroundCompat())
    }
}

private struct WidgetContainerBackgroundCompat: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                colorScheme == .dark ? Color.black : Color.white
            }
        } else {
            content
        }
    }
}

struct OnlyLockStreakWidget: Widget {
    let kind: String = "OnlyLockStreakWidgetV4"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            OnlyLockStreakWidgetView(entry: entry)
        }
        .configurationDisplayName(widgetIsEnglish() ? "Stay Focused" : "保持专注")
        .description(widgetIsEnglish() ? "Show your focus streak." : "展示你的连续专注记录。")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct OnlyLockWidgetBundle: WidgetBundle {
    var body: some Widget {
        OnlyLockStreakWidget()
    }
}
