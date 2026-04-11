import DeviceActivity
import ExtensionKit
import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI

private enum ReportLanguage {
    static let appLanguageCodeKey = "onlylock.settings.appLanguageCode"

    static var isEnglish: Bool {
        let defaults = UserDefaults(suiteName: ScreenTimeInsightsShared.appGroupIdentifier) ?? .standard
        return (defaults.string(forKey: appLanguageCodeKey) ?? "zh-Hans") == "en"
    }

    static func text(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }
}

@main
struct OnlyLockReportExtension: DeviceActivityReportExtension {
    init() {
        InsightsDebugLogger.log("extension.init")
    }

    @MainActor
    var body: some DeviceActivityReportScene {
        let _ = {
            InsightsDebugLogger.log("extension.body")
        }()
        OnlyLockInsightsReport(scope: .day, context: .onlyLockInsightsDay) { configuration in
            OnlyLockInsightsReportView(configuration: configuration)
        }
        OnlyLockInsightsReport(scope: .week, context: .onlyLockInsightsWeek) { configuration in
            OnlyLockInsightsReportView(configuration: configuration)
        }
        OnlyLockInsightsReport(scope: .trend, context: .onlyLockInsightsTrend) { configuration in
            OnlyLockInsightsReportView(configuration: configuration)
        }
        OnlyLockWeeklyDigestReport(context: .onlyLockWeeklyDigest) { configuration in
            OnlyLockWeeklyDigestReportView(configuration: configuration)
        }
    }
}

private enum InsightsScope: String {
    case day
    case week
    case trend
}

private enum InsightsDebugLogger {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ message: String) {
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        print("[OnlyLockInsights][ReportExtension] \(message)")
        append(line: line, to: ScreenTimeInsightsShared.debugLogFileURL())
        append(line: line, to: ScreenTimeInsightsShared.extensionLocalDebugLogFileURL())
    }

    private static func append(line: String, to fileURL: URL?) {
        guard let fileURL, let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }
}

private enum UnknownCategoryLogger {
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ rawName: String) {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let line = "[\(timestampFormatter.string(from: Date()))] \(normalized)\n"
        append(line: line, to: ScreenTimeInsightsShared.unknownCategoryLogFileURL())
    }

    private static func append(line: String, to fileURL: URL?) {
        guard let fileURL, let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            }
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }
}

private struct InsightsBucketConfiguration: Identifiable {
    let id: String
    let label: String
    let appMinutes: Int
    let websiteMinutes: Int

    var totalMinutes: Int {
        max(0, appMinutes + websiteMinutes)
    }
}

private struct InsightsTargetConfiguration: Identifiable {
    let id: String
    let name: String
    let minutes: Int
    let kind: ScreenTimeInsightsTargetKind
    let applicationToken: ApplicationToken?
    let categoryToken: ActivityCategoryToken?

    init(
        id: String,
        name: String,
        minutes: Int,
        kind: ScreenTimeInsightsTargetKind,
        applicationToken: ApplicationToken? = nil,
        categoryToken: ActivityCategoryToken? = nil
    ) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.kind = kind
        self.applicationToken = applicationToken
        self.categoryToken = categoryToken
    }
}

private struct InsightsReportConfiguration {
    let scope: InsightsScope
    let rangeStart: Date?
    let rangeEnd: Date?
    let totalMinutes: Int
    let averageMinutes: Int
    let previousTotalMinutes: Int
    let buckets: [InsightsBucketConfiguration]
    let previousBuckets: [InsightsBucketConfiguration]
    let topTargets: [InsightsTargetConfiguration]
    let topCategories: [InsightsTargetConfiguration]
    let hasData: Bool
}

private struct OnlyLockInsightsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let content: (InsightsReportConfiguration) -> OnlyLockInsightsReportView

    private let scope: InsightsScope

    init(
        scope: InsightsScope,
        context: DeviceActivityReport.Context,
        content: @escaping (InsightsReportConfiguration) -> OnlyLockInsightsReportView
    ) {
        self.scope = scope
        self.context = context
        self.content = content
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> InsightsReportConfiguration {
        InsightsDebugLogger.log("makeConfiguration.start scope=\(scope.rawValue)")
        let configuration = await InsightsConfigurationBuilder.build(scope: scope, data: data)
        InsightsConfigurationBuilder.persistSnapshot(configuration, for: scope)

        InsightsDebugLogger.log("makeConfiguration.finish scope=\(scope.rawValue) total=\(configuration.totalMinutes) buckets=\(configuration.buckets.count) targets=\(configuration.topTargets.count) categories=\(configuration.topCategories.count)")
        print("[OnlyLockInsights][ReportExtension] scope=\(scope.rawValue) total=\(configuration.totalMinutes) targets=\(configuration.topTargets.count) categories=\(configuration.topCategories.count)")
        return configuration
    }
}

private struct OnlyLockWeeklyDigestReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let content: (InsightsReportConfiguration) -> OnlyLockWeeklyDigestReportView

    init(
        context: DeviceActivityReport.Context,
        content: @escaping (InsightsReportConfiguration) -> OnlyLockWeeklyDigestReportView
    ) {
        self.context = context
        self.content = content
    }

    func makeConfiguration(
        representing data: DeviceActivityResults<DeviceActivityData>
    ) async -> InsightsReportConfiguration {
        InsightsDebugLogger.log("makeConfiguration.start scope=weeklyDigest")
        let configuration = await InsightsConfigurationBuilder.buildWeeklyDigest(data: data)
        InsightsConfigurationBuilder.persistSnapshot(configuration, for: .week)
        InsightsDebugLogger.log("makeConfiguration.finish scope=weeklyDigest total=\(configuration.totalMinutes) buckets=\(configuration.buckets.count) targets=\(configuration.topTargets.count) categories=\(configuration.topCategories.count)")
        return configuration
    }
}

private enum InsightsConfigurationBuilder {
    private struct AggregatedInsights {
        var targets: [String: (name: String, kind: ScreenTimeInsightsTargetKind, minutes: Int, applicationToken: ApplicationToken?)]
        var categories: [String: (name: String, minutes: Int, categoryToken: ActivityCategoryToken?)]
    }

    private struct RawSegment {
        let startDate: Date
        let appMinutes: Int
        let websiteMinutes: Int
        let segmentTotalMinutes: Int

        var totalMinutes: Int {
            max(0, segmentTotalMinutes)
        }
    }

    static func build(
        scope: InsightsScope,
        data: DeviceActivityResults<DeviceActivityData>
    ) async -> InsightsReportConfiguration {
        let segments = await data
            .flatMap { $0.activitySegments }
            .reduce(into: [DeviceActivityData.ActivitySegment]()) { result, segment in
                result.append(segment)
            }
        var aggregatedInsights = AggregatedInsights(targets: [:], categories: [:])
        var rawSegments: [RawSegment] = []

        for segment in segments {
            let segmentTotalMinutes = minutesValue(from: segment.totalActivityDuration)

            for await category in segment.categories {
                let categoryName = normalizedDisplayName(category.category.localizedDisplayName) ?? ReportLanguage.text("其他", "Other")
                let categoryToken = category.category.token
                let categoryKey = stableCategoryKey(token: categoryToken, fallbackName: categoryName)

                for await applicationActivity in category.applications {
                    let minutes = minutesValue(from: applicationActivity.totalActivityDuration)
                    guard minutes > 0 else { continue }

                    let bundleIdentifier = normalizedDisplayName(applicationActivity.application.bundleIdentifier)
                    let appName = normalizedDisplayName(
                        applicationActivity.application.localizedDisplayName ??
                        applicationActivity.application.bundleIdentifier
                    ) ?? ReportLanguage.text("应用", "App")

                    let key = "app.\((bundleIdentifier ?? appName).lowercased())"
                    let existing = aggregatedInsights.targets[key] ?? (name: appName, kind: .app, minutes: 0, applicationToken: applicationActivity.application.token)
                    aggregatedInsights.targets[key] = (
                        name: existing.name,
                        kind: existing.kind,
                        minutes: existing.minutes + minutes,
                        applicationToken: existing.applicationToken ?? applicationActivity.application.token
                    )

                    let existingCategory = aggregatedInsights.categories[categoryKey] ?? (
                        name: categoryName,
                        minutes: 0,
                        categoryToken: categoryToken
                    )
                    aggregatedInsights.categories[categoryKey] = (
                        name: existingCategory.name,
                        minutes: existingCategory.minutes + minutes,
                        categoryToken: existingCategory.categoryToken ?? categoryToken
                    )
                }

                for await webDomainActivity in category.webDomains {
                    let minutes = minutesValue(from: webDomainActivity.totalActivityDuration)
                    guard minutes > 0 else { continue }

                    let domain = normalizedDisplayName(webDomainActivity.webDomain.domain) ?? ReportLanguage.text("网站", "Website")
                    let key = "web.\(domain.lowercased())"
                    let existing = aggregatedInsights.targets[key] ?? (name: domain, kind: .website, minutes: 0, applicationToken: nil)
                    aggregatedInsights.targets[key] = (
                        name: existing.name,
                        kind: existing.kind,
                        minutes: existing.minutes + minutes,
                        applicationToken: existing.applicationToken
                    )

                    let existingCategory = aggregatedInsights.categories[categoryKey] ?? (
                        name: categoryName,
                        minutes: 0,
                        categoryToken: categoryToken
                    )
                    aggregatedInsights.categories[categoryKey] = (
                        name: existingCategory.name,
                        minutes: existingCategory.minutes + minutes,
                        categoryToken: existingCategory.categoryToken ?? categoryToken
                    )
                }
            }

            rawSegments.append(
                RawSegment(
                    startDate: segment.dateInterval.start,
                    appMinutes: segmentTotalMinutes,
                    websiteMinutes: 0,
                    segmentTotalMinutes: segmentTotalMinutes
                )
            )
        }

        let buckets = makeBuckets(from: rawSegments, scope: scope)
        let totalMinutes = buckets.reduce(0) { $0 + $1.totalMinutes }
        let resolvedRange = resolvedRange(for: scope, from: rawSegments)
            ?? fallbackRange(for: scope, referenceDate: Date())
        let previousSnapshot = previousSnapshot(for: scope, currentRange: resolvedRange)
        let previousTotalMinutes = max(0, previousSnapshot?.totalMinutes ?? 0)
        let averageDivisor = max(1, buckets.count)

        let averageMinutes = averageDivisor > 0 ? totalMinutes / averageDivisor : totalMinutes
        let topTargets = aggregatedInsights.targets
            .map { key, item in
                InsightsTargetConfiguration(
                    id: key,
                    name: item.name,
                    minutes: item.minutes,
                    kind: item.kind,
                    applicationToken: item.applicationToken
                )
            }
            .sorted { lhs, rhs in
                if lhs.minutes == rhs.minutes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.minutes > rhs.minutes
            }
        let topCategories = aggregatedInsights.categories
            .map { key, item in
                InsightsTargetConfiguration(
                    id: key,
                    name: item.name,
                    minutes: item.minutes,
                    kind: .category,
                    categoryToken: item.categoryToken
                )
            }
            .sorted { lhs, rhs in
                if lhs.minutes == rhs.minutes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.minutes > rhs.minutes
            }
        persistTopCategoriesDebug(
            scope: scope.rawValue,
            topCategories: topCategories
        )
        InsightsDebugLogger.log(
            "topCategories scope=\(scope.rawValue) " +
            topCategories.map { "\($0.name)|token=\($0.categoryToken != nil)|minutes=\($0.minutes)" }.joined(separator: ", ")
        )

        return InsightsReportConfiguration(
            scope: scope,
            rangeStart: resolvedRange.start,
            rangeEnd: resolvedRange.end,
            totalMinutes: totalMinutes,
            averageMinutes: averageMinutes,
            previousTotalMinutes: previousTotalMinutes,
            buckets: buckets,
            previousBuckets: previousSnapshot?.buckets.map {
                InsightsBucketConfiguration(
                    id: $0.id,
                    label: $0.label,
                    appMinutes: $0.appMinutes,
                    websiteMinutes: $0.webMinutes
                )
            } ?? [],
            topTargets: Array(topTargets.prefix(12)),
            topCategories: topCategories,
            hasData: totalMinutes > 0
        )
    }

    static func buildWeeklyDigest(
        data: DeviceActivityResults<DeviceActivityData>
    ) async -> InsightsReportConfiguration {
        let segments = await data
            .flatMap { $0.activitySegments }
            .reduce(into: [DeviceActivityData.ActivitySegment]()) { result, segment in
                result.append(segment)
            }

        let calendar = Calendar(identifier: .gregorian)
        let defaults = UserDefaults(suiteName: ScreenTimeInsightsShared.appGroupIdentifier)
        let selectedWeekStartTimestamp = defaults?.double(forKey: ScreenTimeInsightsShared.weeklyDigestSelectedWeekStartKey) ?? 0
        let selectedWeekStart: Date
        if selectedWeekStartTimestamp > 0 {
            selectedWeekStart = startOfWeekMonday(
                for: Date(timeIntervalSince1970: selectedWeekStartTimestamp),
                calendar: calendar
            )
        } else if let latestSegmentDate = segments.map({ $0.dateInterval.start }).max() {
            selectedWeekStart = startOfWeekMonday(for: latestSegmentDate, calendar: calendar)
        } else {
            selectedWeekStart = startOfWeekMonday(for: Date(), calendar: calendar)
        }

        let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: selectedWeekStart) ?? selectedWeekStart
        let selectedWeekEnd = calendar.date(byAdding: .day, value: 7, to: selectedWeekStart) ?? selectedWeekStart

        let currentWeekSegments = segments.filter { segment in
            segment.dateInterval.start >= selectedWeekStart && segment.dateInterval.start < selectedWeekEnd
        }
        let previousWeekSegments = segments.filter { segment in
            segment.dateInterval.start >= previousWeekStart && segment.dateInterval.start < selectedWeekStart
        }

        let aggregatedInsights = await aggregateInsights(from: currentWeekSegments)
        var currentRawSegments: [RawSegment] = []
        currentRawSegments.reserveCapacity(currentWeekSegments.count)
        for segment in currentWeekSegments {
            let totalMinutes = minutesValue(from: segment.totalActivityDuration)
            currentRawSegments.append(
                RawSegment(
                    startDate: segment.dateInterval.start,
                    appMinutes: totalMinutes,
                    websiteMinutes: 0,
                    segmentTotalMinutes: totalMinutes
                )
            )
        }

        var previousRawSegments: [RawSegment] = []
        previousRawSegments.reserveCapacity(previousWeekSegments.count)
        for segment in previousWeekSegments {
            let totalMinutes = minutesValue(from: segment.totalActivityDuration)
            previousRawSegments.append(
                RawSegment(
                    startDate: segment.dateInterval.start,
                    appMinutes: totalMinutes,
                    websiteMinutes: 0,
                    segmentTotalMinutes: totalMinutes
                )
            )
        }

        let currentBuckets = makeWeekBuckets(from: currentRawSegments)
        let previousBuckets = makeWeekBuckets(from: previousRawSegments)
        let totalMinutes = currentBuckets.reduce(0) { $0 + $1.totalMinutes }
        let previousTotalMinutes = previousBuckets.reduce(0) { $0 + $1.totalMinutes }
        let averageMinutes = totalMinutes / max(1, currentBuckets.count)

        let topTargets = aggregatedInsights.targets
            .map { key, item in
                InsightsTargetConfiguration(
                    id: key,
                    name: item.name,
                    minutes: item.minutes,
                    kind: item.kind,
                    applicationToken: item.applicationToken
                )
            }
            .sorted { lhs, rhs in
                if lhs.minutes == rhs.minutes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.minutes > rhs.minutes
            }
        let topCategories = aggregatedInsights.categories
            .map { key, item in
                InsightsTargetConfiguration(
                    id: key,
                    name: item.name,
                    minutes: item.minutes,
                    kind: .category,
                    categoryToken: item.categoryToken
                )
            }
            .sorted { lhs, rhs in
                if lhs.minutes == rhs.minutes {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.minutes > rhs.minutes
            }
        persistTopCategoriesDebug(
            scope: "weeklyDigest",
            topCategories: topCategories
        )
        InsightsDebugLogger.log(
            "topCategories scope=weeklyDigest " +
            topCategories.map { "\($0.name)|token=\($0.categoryToken != nil)|minutes=\($0.minutes)" }.joined(separator: ", ")
        )

        return InsightsReportConfiguration(
            scope: .week,
            rangeStart: selectedWeekStart,
            rangeEnd: selectedWeekEnd,
            totalMinutes: totalMinutes,
            averageMinutes: averageMinutes,
            previousTotalMinutes: previousTotalMinutes,
            buckets: currentBuckets,
            previousBuckets: previousBuckets,
            topTargets: Array(topTargets.prefix(12)),
            topCategories: topCategories,
            hasData: totalMinutes > 0 || previousTotalMinutes > 0
        )
    }

    private static func aggregateInsights(
        from segments: [DeviceActivityData.ActivitySegment]
    ) async -> AggregatedInsights {
        var targetMinutes: [String: (name: String, kind: ScreenTimeInsightsTargetKind, minutes: Int, applicationToken: ApplicationToken?)] = [:]
        var categoryMinutes: [String: (name: String, minutes: Int, categoryToken: ActivityCategoryToken?)] = [:]

        for segment in segments {
            for await category in segment.categories {
                let categoryName = normalizedDisplayName(category.category.localizedDisplayName) ?? ReportLanguage.text("其他", "Other")
                let categoryToken = category.category.token
                let categoryKey = stableCategoryKey(token: categoryToken, fallbackName: categoryName)

                for await applicationActivity in category.applications {
                    let minutes = minutesValue(from: applicationActivity.totalActivityDuration)
                    guard minutes > 0 else { continue }

                    let bundleIdentifier = normalizedDisplayName(applicationActivity.application.bundleIdentifier)
                    let appName = normalizedDisplayName(
                        applicationActivity.application.localizedDisplayName ??
                        applicationActivity.application.bundleIdentifier
                    ) ?? ReportLanguage.text("应用", "App")
                    let key = "app.\((bundleIdentifier ?? appName).lowercased())"
                    let existing = targetMinutes[key] ?? (name: appName, kind: .app, minutes: 0, applicationToken: applicationActivity.application.token)
                    targetMinutes[key] = (
                        name: existing.name,
                        kind: existing.kind,
                        minutes: existing.minutes + minutes,
                        applicationToken: existing.applicationToken ?? applicationActivity.application.token
                    )

                    let existingCategory = categoryMinutes[categoryKey] ?? (
                        name: categoryName,
                        minutes: 0,
                        categoryToken: categoryToken
                    )
                    categoryMinutes[categoryKey] = (
                        name: existingCategory.name,
                        minutes: existingCategory.minutes + minutes,
                        categoryToken: existingCategory.categoryToken ?? categoryToken
                    )
                }

                for await webDomainActivity in category.webDomains {
                    let minutes = minutesValue(from: webDomainActivity.totalActivityDuration)
                    guard minutes > 0 else { continue }

                    let domain = normalizedDisplayName(webDomainActivity.webDomain.domain) ?? ReportLanguage.text("网站", "Website")
                    let key = "web.\(domain.lowercased())"
                    let existing = targetMinutes[key] ?? (name: domain, kind: .website, minutes: 0, applicationToken: nil)
                    targetMinutes[key] = (
                        name: existing.name,
                        kind: existing.kind,
                        minutes: existing.minutes + minutes,
                        applicationToken: existing.applicationToken
                    )

                    let existingCategory = categoryMinutes[categoryKey] ?? (
                        name: categoryName,
                        minutes: 0,
                        categoryToken: categoryToken
                    )
                    categoryMinutes[categoryKey] = (
                        name: existingCategory.name,
                        minutes: existingCategory.minutes + minutes,
                        categoryToken: existingCategory.categoryToken ?? categoryToken
                    )
                }
            }
        }

        return AggregatedInsights(targets: targetMinutes, categories: categoryMinutes)
    }

    private static func makeBuckets(
        from rawSegments: [RawSegment],
        scope: InsightsScope
    ) -> [InsightsBucketConfiguration] {
        switch scope {
        case .day:
            return makeDayBuckets(from: rawSegments)
        case .week:
            return makeWeekBuckets(from: rawSegments)
        case .trend:
            return makeTrendBuckets(from: rawSegments)
        }
    }

    private static func makeDayBuckets(from segments: [RawSegment]) -> [InsightsBucketConfiguration] {
        let labels = (0..<8).map { String(format: "%02d", $0 * 3) }
        let calendar = Calendar(identifier: .gregorian)

        return (0..<8).map { index in
            let matching = segments.filter {
                calendar.component(.hour, from: $0.startDate) / 3 == index
            }

            return InsightsBucketConfiguration(
                id: "day.\(index)",
                label: labels[index],
                appMinutes: matching.reduce(0) { $0 + $1.appMinutes },
                websiteMinutes: matching.reduce(0) { $0 + $1.websiteMinutes }
            )
        }
    }

    private static func makeWeekBuckets(from segments: [RawSegment]) -> [InsightsBucketConfiguration] {
        let calendar = Calendar(identifier: .gregorian)
        let labels = ReportLanguage.isEnglish
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["一", "二", "三", "四", "五", "六", "日"]

        return (0..<7).map { index in
            let matching = segments.filter {
                weekdayIndexFromMonday(for: $0.startDate, calendar: calendar) == index
            }

            return InsightsBucketConfiguration(
                id: "week.\(index)",
                label: labels[index],
                appMinutes: matching.reduce(0) { $0 + $1.appMinutes },
                websiteMinutes: matching.reduce(0) { $0 + $1.websiteMinutes }
            )
        }
    }

    private static func makeTrendBuckets(from segments: [RawSegment]) -> [InsightsBucketConfiguration] {
        let calendar = Calendar(identifier: .gregorian)
        let sortedWeekStarts = Array(
            Set(
                segments.map {
                    startOfWeekMonday(for: $0.startDate, calendar: calendar)
                }
            )
        ).sorted()

        let trailingWeekStarts: [Date]
        if sortedWeekStarts.isEmpty {
            let currentWeek = startOfWeekMonday(for: Date(), calendar: calendar)
            trailingWeekStarts = (0..<6).compactMap { offset in
                calendar.date(byAdding: .day, value: (offset - 5) * 7, to: currentWeek)
            }
        } else if sortedWeekStarts.count >= 6 {
            trailingWeekStarts = Array(sortedWeekStarts.suffix(6))
        } else {
            let lastWeek = sortedWeekStarts.last!
            let missingCount = 6 - sortedWeekStarts.count
            let prepended = (1...missingCount).compactMap { offset in
                calendar.date(byAdding: .day, value: -7 * offset, to: lastWeek)
            }.reversed()
            trailingWeekStarts = Array(prepended) + sortedWeekStarts
        }

        return trailingWeekStarts.enumerated().map { index, weekStart in
            let matching = segments.filter {
                startOfWeekMonday(for: $0.startDate, calendar: calendar) == weekStart
            }

            return InsightsBucketConfiguration(
                id: "trend.\(index)",
                label: "W\(index + 1)",
                appMinutes: matching.reduce(0) { $0 + $1.appMinutes },
                websiteMinutes: matching.reduce(0) { $0 + $1.websiteMinutes }
            )
        }
    }

    private static func weekdayIndexFromMonday(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }

    private static func startOfWeekMonday(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let mondayOffset = weekdayIndexFromMonday(for: startOfDay, calendar: calendar)
        return calendar.date(byAdding: .day, value: -mondayOffset, to: startOfDay) ?? startOfDay
    }

    private static func minutesValue(from duration: TimeInterval) -> Int {
        max(0, Int((duration / 60).rounded()))
    }

    private static func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func stableCategoryKey(
        token: ActivityCategoryToken?,
        fallbackName: String
    ) -> String {
        if let canonical = canonicalCategoryKey(for: fallbackName) {
            return "category.canonical.\(canonical)"
        }
        if let token,
           let data = try? JSONEncoder().encode(token) {
            return "category.token.\(data.base64EncodedString())"
        }
        return "category.name.\(fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private static func canonicalCategoryKey(for rawName: String) -> String? {
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

    private static func persistTopCategoriesDebug(
        scope: String,
        topCategories: [InsightsTargetConfiguration]
    ) {
        guard let defaults = UserDefaults(suiteName: ScreenTimeInsightsShared.appGroupIdentifier) else {
            return
        }
        let value = topCategories.map { target in
            "\(target.name)|token=\(target.categoryToken != nil)|id=\(target.id)|minutes=\(target.minutes)"
        }.joined(separator: "\n")
        defaults.set(value, forKey: "onlylock.screentime.categorydebug.\(scope)")
        defaults.synchronize()
    }

    private static func resolvedRange(for scope: InsightsScope, from segments: [RawSegment]) -> DateInterval? {
        let calendar = Calendar(identifier: .gregorian)
        guard let earliest = segments.map(\.startDate).min() else { return nil }

        switch scope {
        case .day:
            let start = calendar.startOfDay(for: earliest)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .week:
            let start = startOfWeekMonday(for: earliest, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .trend:
            let start = startOfWeekMonday(for: earliest, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 42, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    private static func fallbackRange(for scope: InsightsScope, referenceDate: Date) -> DateInterval {
        let calendar = Calendar(identifier: .gregorian)
        switch scope {
        case .day:
            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .week:
            let start = startOfWeekMonday(for: referenceDate, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .trend:
            let endWeekStart = startOfWeekMonday(for: referenceDate, calendar: calendar)
            let start = calendar.date(byAdding: .day, value: -35, to: endWeekStart) ?? endWeekStart
            let end = calendar.date(byAdding: .day, value: 42, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    private static func previousSnapshot(
        for scope: InsightsScope,
        currentRange: DateInterval?
    ) -> ScreenTimeInsightsSnapshot? {
        guard let currentRange,
              let previousRange = previousRange(for: scope, currentRange: currentRange),
              let defaults = UserDefaults(suiteName: ScreenTimeInsightsShared.appGroupIdentifier),
              let snapshot = snapshot(
                for: scope,
                range: previousRange,
                defaults: defaults
              ) else {
            return nil
        }

        return snapshot
    }

    private static func previousRange(
        for scope: InsightsScope,
        currentRange: DateInterval
    ) -> DateInterval? {
        let calendar = Calendar(identifier: .gregorian)

        switch scope {
        case .day:
            guard let start = calendar.date(byAdding: .day, value: -1, to: currentRange.start),
                  let end = calendar.date(byAdding: .day, value: -1, to: currentRange.end) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .week:
            guard let start = calendar.date(byAdding: .day, value: -7, to: currentRange.start),
                  let end = calendar.date(byAdding: .day, value: -7, to: currentRange.end) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .trend:
            return nil
        }
    }

    private static func snapshot(
        for scope: InsightsScope,
        range: DateInterval,
        defaults: UserDefaults
    ) -> ScreenTimeInsightsSnapshot? {
        let key = ScreenTimeInsightsShared.snapshotKey(
            scope: scope.rawValue,
            rangeStart: range.start,
            rangeEnd: range.end
        )
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ScreenTimeInsightsSnapshot.self, from: data)
    }

    static func persistSnapshot(_ configuration: InsightsReportConfiguration, for scope: InsightsScope) {
        guard let rangeStart = configuration.rangeStart,
              let rangeEnd = configuration.rangeEnd else {
            InsightsDebugLogger.log("persistSnapshot.skip scope=\(scope.rawValue) reason=missing_range")
            return
        }

        guard let defaults = UserDefaults(suiteName: ScreenTimeInsightsShared.appGroupIdentifier) else {
            InsightsDebugLogger.log("persistSnapshot.skip scope=\(scope.rawValue) reason=missing_group_defaults")
            return
        }

        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ScreenTimeInsightsShared.appGroupIdentifier
        ) {
            InsightsDebugLogger.log("persistSnapshot.group_container scope=\(scope.rawValue) path=\(containerURL.path)")
        } else {
            InsightsDebugLogger.log("persistSnapshot.group_container scope=\(scope.rawValue) path=nil")
        }

        InsightsDebugLogger.log("persistSnapshot.begin scope=\(scope.rawValue) start=\(rangeStart.timeIntervalSince1970) end=\(rangeEnd.timeIntervalSince1970) total=\(configuration.totalMinutes)")

        let snapshot = ScreenTimeInsightsSnapshot(
            scope: scope.rawValue,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            totalMinutes: configuration.totalMinutes,
            averageMinutes: configuration.averageMinutes,
            previousTotalMinutes: configuration.previousTotalMinutes,
            buckets: configuration.buckets.map {
                ScreenTimeInsightsBucket(
                    id: $0.id,
                    label: $0.label,
                    appMinutes: $0.appMinutes,
                    webMinutes: $0.websiteMinutes
                )
            },
            topTargets: configuration.topTargets.map {
                ScreenTimeInsightsTarget(
                    id: $0.id,
                    name: $0.name,
                    minutes: $0.minutes,
                    kind: $0.kind,
                    applicationToken: $0.applicationToken,
                    categoryToken: $0.categoryToken
                )
            },
            topCategories: configuration.topCategories.map {
                ScreenTimeInsightsTarget(
                    id: $0.id,
                    name: $0.name,
                    minutes: $0.minutes,
                    kind: $0.kind,
                    applicationToken: $0.applicationToken,
                    categoryToken: $0.categoryToken
                )
            },
            generatedAt: Date()
        )

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else {
            InsightsDebugLogger.log("persistSnapshot.skip scope=\(scope.rawValue) reason=encode_failed")
            return
        }
        let snapshotKey = ScreenTimeInsightsShared.snapshotKey(
            scope: scope.rawValue,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )

        defaults.set(
            data,
            forKey: snapshotKey
        )
        defaults.synchronize()
        let hasRoundTrip = defaults.data(forKey: snapshotKey) != nil
        InsightsDebugLogger.log("persistSnapshot.defaults_written scope=\(scope.rawValue) key=\(snapshotKey) roundtrip=\(hasRoundTrip)")

        if let fileURL = snapshotFileURL(scope: scope.rawValue, rangeStart: rangeStart, rangeEnd: rangeEnd) {
            try? data.write(to: fileURL, options: .atomic)
            InsightsDebugLogger.log("persistSnapshot.file_written scope=\(scope.rawValue) path=\(fileURL.path)")
        } else {
            InsightsDebugLogger.log("persistSnapshot.file_skipped scope=\(scope.rawValue) reason=missing_group_container")
        }

        persistDiagnostic(configuration: configuration, scope: scope, defaults: defaults)

        guard scope == .week else { return }
        let hasMeaningfulData =
            configuration.totalMinutes > 0 ||
            configuration.previousTotalMinutes > 0 ||
            configuration.buckets.contains(where: { $0.totalMinutes > 0 }) ||
            configuration.topTargets.contains(where: { $0.minutes > 0 })
        guard hasMeaningfulData else { return }

        let weekStartTimestamp = Int(rangeStart.timeIntervalSince1970)
        let existing = defaults.array(forKey: ScreenTimeInsightsShared.weeklyReportHistoryWeekStartsKey) as? [Int] ?? []
        let updated = Array(Set(existing + [weekStartTimestamp])).sorted(by: >)
        defaults.set(updated, forKey: ScreenTimeInsightsShared.weeklyReportHistoryWeekStartsKey)
        defaults.synchronize()
    }

    private static func persistDiagnostic(
        configuration: InsightsReportConfiguration,
        scope: InsightsScope,
        defaults: UserDefaults
    ) {
        let diagnostic = ScreenTimeInsightsDiagnostic(
            scope: scope.rawValue,
            wroteAt: Date(),
            segmentCount: configuration.buckets.count,
            appCount: configuration.topTargets.filter { $0.kind == .app }.count,
            websiteCount: configuration.topTargets.filter { $0.kind == .website }.count,
            totalMinutes: configuration.totalMinutes,
            topTargetCount: configuration.topTargets.count,
            note: "rangeStart=\(configuration.rangeStart?.timeIntervalSince1970 ?? 0), rangeEnd=\(configuration.rangeEnd?.timeIntervalSince1970 ?? 0), previousTotal=\(configuration.previousTotalMinutes)"
        )

        guard let data = try? JSONEncoder().encode(diagnostic) else { return }
        defaults.set(data, forKey: ScreenTimeInsightsShared.diagnosticKey(scope: scope.rawValue))
        defaults.synchronize()
    }

    private static func snapshotFileURL(scope: String, rangeStart: Date, rangeEnd: Date) -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ScreenTimeInsightsShared.appGroupIdentifier
        ) else {
            return nil
        }

        let directoryURL = containerURL.appendingPathComponent(
            ScreenTimeInsightsShared.snapshotDirectoryName,
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        return directoryURL.appendingPathComponent(
            ScreenTimeInsightsShared.snapshotFileName(
                scope: scope,
                rangeStart: rangeStart,
                rangeEnd: rangeEnd
            )
        )
    }
}

private struct OnlyLockInsightsReportView: View {
    @Environment(\.colorScheme) private var colorScheme
    let configuration: InsightsReportConfiguration

    private let cardCornerRadius: CGFloat = 16
    private let bottomOverlayClearance: CGFloat = 104

    private enum ComparisonState {
        case decrease(Int)
        case increase(Int)
        case flat
    }

    private var pageBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.12)
            : Color(red: 0.95, green: 0.95, blue: 0.95)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.15, blue: 0.18)
            : .white
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.64) : Color.black.opacity(0.55)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.black.opacity(0.10)
    }

    private var iconBackground: Color {
        primaryText.opacity(colorScheme == .dark ? 0.14 : 0.06)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headlineBlock
                chartCard

                if !configuration.topCategories.isEmpty {
                    compactTopCategoriesStrip
                }
                if !configuration.topTargets.isEmpty {
                    targetsList
                }
            }
            .padding(.top, 4)
            .padding(.bottom, bottomOverlayClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var headlineBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(durationText(headlineMinutes))
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitleText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondaryText)

            if let comparisonState {
                Text(comparisonText(for: comparisonState))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(comparisonColor(for: comparisonState))
            }

            if !configuration.hasData {
                Text(ReportLanguage.text("当前时间范围内还没有系统屏幕时间数据。", "No Screen Time data is available for the selected range."))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryText)
            }
        }
    }

    private var headlineMinutes: Int {
        switch configuration.scope {
        case .day:
            return configuration.totalMinutes
        case .week, .trend:
            return configuration.averageMinutes
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            chart
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(dividerColor, lineWidth: 1)
        )
    }

    private var targetsList: some View {
        let displayedTargets = Array(configuration.topTargets.prefix(8))
        let targetRowHeight: CGFloat = 52

        return VStack(alignment: .leading, spacing: 12) {
            Text(ReportLanguage.text("高频使用", "Most Used"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            VStack(spacing: 0) {
                ForEach(Array(displayedTargets.enumerated()), id: \.element.id) { index, target in
                    HStack(spacing: 10) {
                        targetLeadingIcon(for: target, compact: false)

                        Text(target.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Spacer(minLength: 0)

                        Text(shortDuration(target.minutes))
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
            .background(cardBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            )
        }
    }

    private var compactTopCategoriesStrip: some View {
        let displayedCategories = Array(configuration.topCategories.prefix(4))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(displayedCategories) { target in
                    HStack(spacing: 6) {
                        targetLeadingIcon(for: target, compact: true)
                        Text(shortDuration(target.minutes))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(primaryText)
                            .monospacedDigit()
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 10)
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
    }

    private var chart: some View {
        let buckets = configuration.buckets
        let maxMinutes = max(60, buckets.map(\.totalMinutes).max() ?? 60)
        let rawTopMinutes = max(maxMinutes, configuration.averageMinutes)
        let yTopMinutes = normalizedChartTopMinutes(rawTopMinutes)
        let axisWidth: CGFloat = 34
        let averageLabelOffsetX: CGFloat = 6

        return VStack(spacing: 10) {
            GeometryReader { proxy in
                let chartHeight = max(1, proxy.size.height)
                let labelVerticalInset: CGFloat = 8
                let topLineY = labelVerticalInset
                let bottomLineY = chartHeight - labelVerticalInset
                let plotHeight = max(1, bottomLineY - topLineY)
                let averageRatio = min(max(CGFloat(configuration.averageMinutes) / CGFloat(max(yTopMinutes, 1)), 0), 1)
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

                    if configuration.averageMinutes > 0 {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: averageLineY))
                            path.addLine(to: CGPoint(x: lineEndX, y: averageLineY))
                        }
                        .stroke(
                            secondaryText.opacity(0.70),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
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
                        Text(axisTopLabel(yTopMinutes))
                            .position(x: axisWidth / 2, y: topLineY)

                        if configuration.averageMinutes > 0 {
                            Text(axisAverageLabel(configuration.averageMinutes))
                                .position(x: axisWidth / 2 + averageLabelOffsetX, y: averageLineY)
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
                ForEach(buckets) { bucket in
                    Text(bucket.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, axisWidth)
        }
    }

    @ViewBuilder
    private func targetLeadingIcon(for target: InsightsTargetConfiguration, compact: Bool) -> some View {
        let side: CGFloat = compact ? 24 : 28
        let corner: CGFloat = compact ? 7 : 8

        if target.kind == .app, let token = target.applicationToken {
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else if target.kind == .category {
            categoryIcon(for: target.name, compact: compact)
        } else {
            Image(systemName: target.kind == .website ? "globe" : "square.grid.2x2")
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(primaryText)
                .frame(width: side, height: side)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    @ViewBuilder
    private func categoryIcon(for name: String, compact: Bool) -> some View {
        let side: CGFloat = compact ? 24 : 28
        let symbol = categoryEmoji(for: name)

        Text(symbol)
            .font(.system(size: compact ? 17 : 20))
            .frame(width: side, height: side)
    }

    private func categoryEmoji(for rawName: String) -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if name.contains("社交") ||
            name.contains("social") ||
            name.contains("network") ||
            name.contains("chat") ||
            name.contains("message") ||
            name.contains("messages") ||
            name.contains("sticker") ||
            name.contains("通讯") {
            return "💬"
        }
        if name.contains("游戏") ||
            name.contains("game") ||
            name.contains("gaming") ||
            name.contains("arcade") ||
            name.contains("益智") ||
            name.contains("桌游") ||
            name.contains("棋牌") ||
            name.contains("卡牌") {
            return "🚀"
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
            return "🍿"
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
            return "📖"
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
            return "🚴"
        }
        if name.contains("创意") ||
            name.contains("creative") ||
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
            name.contains("设计") {
            return "🎨"
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
            return "🧮"
        }
        if name.contains("效率") ||
            name.contains("财务") ||
            name.contains("productivity") ||
            name.contains("finance") ||
            name.contains("business") ||
            name.contains("商务") {
            return "📊"
        }
        if name.contains("教育") || name.contains("education") || name.contains("learning") || name.contains("学习") {
            return "🌍"
        }
        if name.contains("旅行") ||
            name.contains("travel") ||
            name.contains("navigation") ||
            name.contains("地图") ||
            name.contains("nav") ||
            name.contains("出行") {
            return "🧳"
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
            return "🛍️"
        }
        if name.contains("其他") ||
            name == "other" ||
            name.contains("misc") ||
            name.contains("miscellaneous") ||
            name.contains("生活") ||
            name.contains("lifestyle") ||
            name.contains("生活方式") {
            return "🧩"
        }
        InsightsDebugLogger.log("categoryEmoji.fallback name=\(rawName)")
        UnknownCategoryLogger.log(rawName)
        return "🧩"
    }

    private var subtitleText: String {
        switch configuration.scope {
        case .day:
            return ReportLanguage.text("当日屏幕时间", "Today's Screen Time")
        case .week:
            return ReportLanguage.text("平均每日屏幕时间", "Average Daily Screen Time")
        case .trend:
            return ReportLanguage.text("平均每周屏幕时间", "Average Weekly Screen Time")
        }
    }

    private var comparisonState: ComparisonState? {
        guard configuration.scope != .trend else { return nil }
        let previous = configuration.previousTotalMinutes
        guard previous > 0 else { return nil }

        if configuration.totalMinutes == previous {
            return .flat
        }

        let diff = abs(configuration.totalMinutes - previous)
        let percentage = max(1, Int((Double(diff) / Double(previous) * 100).rounded()))
        return configuration.totalMinutes < previous ? .decrease(percentage) : .increase(percentage)
    }

    private func comparisonText(for state: ComparisonState) -> String {
        let baseline = configuration.scope == .week
            ? ReportLanguage.text("上周", "last week")
            : ReportLanguage.text("昨天", "yesterday")
        switch state {
        case let .decrease(percentage):
            return ReportLanguage.isEnglish
                ? "Screen time decreased by \(percentage)% vs \(baseline)"
                : "相比于\(baseline)降低了\(percentage)%屏幕使用时间"
        case let .increase(percentage):
            return ReportLanguage.isEnglish
                ? "Screen time increased by \(percentage)% vs \(baseline)"
                : "相比于\(baseline)增加了\(percentage)%屏幕使用时间"
        case .flat:
            return ReportLanguage.isEnglish
                ? "Same as \(baseline)"
                : "与\(baseline)持平"
        }
    }

    private func comparisonColor(for state: ComparisonState) -> Color {
        switch state {
        case .decrease:
            return colorScheme == .dark
                ? Color(red: 0.36, green: 0.82, blue: 0.53)
                : Color(red: 0.12, green: 0.48, blue: 0.29)
        case .increase:
            return colorScheme == .dark
                ? Color(red: 0.96, green: 0.66, blue: 0.30)
                : Color(red: 0.65, green: 0.37, blue: 0.12)
        case .flat:
            return secondaryText
        }
    }

    private func durationText(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60

        if hour == 0 {
            return ReportLanguage.isEnglish ? "\(minute)m" : "\(minute)分钟"
        }
        if minute == 0 {
            return ReportLanguage.isEnglish ? "\(hour)h" : "\(hour)小时"
        }
        return ReportLanguage.isEnglish ? "\(hour)h \(minute)m" : "\(hour)小时\(minute)分"
    }

    private func shortDuration(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60
        if hour == 0 {
            return ReportLanguage.isEnglish ? "\(minute)m" : "\(minute)分"
        }
        return ReportLanguage.isEnglish ? "\(hour)h\(minute)m" : "\(hour)时\(minute)分"
    }

    private func axisAverageLabel(_ minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        let hour = safeMinutes / 60
        let minute = safeMinutes % 60

        if hour == 0 {
            return "\(minute)m"
        }
        if minute == 0 {
            return "\(hour)h"
        }
        return "\(hour)h\(minute)m"
    }

    private func axisTopLabel(_ minutes: Int) -> String {
        let hour = max(1, Int(ceil(Double(minutes) / 60.0)))
        return "\(hour)h"
    }

    private func normalizedChartTopMinutes(_ minutes: Int) -> Int {
        let safeMinutes = max(60, minutes)
        let step = safeMinutes <= 180 ? 30 : 60
        return Int(ceil(Double(safeMinutes) / Double(step))) * step
    }
}

private struct OnlyLockWeeklyDigestReportView: View {
    let configuration: InsightsReportConfiguration
    @Environment(\.colorScheme) private var colorScheme

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

    private var thisWeekHours: [Double] {
        weeklyHours(from: configuration.buckets)
    }

    private var lastWeekHours: [Double] {
        weeklyHours(from: configuration.previousBuckets)
    }

    private var focusScore: Int {
        weeklyFocusScore(totalMinutes: configuration.totalMinutes)
    }

    private var focusScoreDelta: Int {
        guard configuration.previousTotalMinutes > 0 else { return 0 }
        let previousScore = weeklyFocusScore(totalMinutes: configuration.previousTotalMinutes)
        return focusScore - previousScore
    }

    private var topTargetText: String {
        guard let top = configuration.topTargets.first else {
            return ReportLanguage.text("本周还没有高频使用目标。", "No top usage target this week.")
        }
        let targetKindText = top.kind == .app ? "App" : ReportLanguage.text("网站", "Website")
        if ReportLanguage.isEnglish {
            return "Heavy use this week: \(targetKindText) “\(top.name)” for \(weeklyDurationText(top.minutes))"
        }
        return "本周重度使用\(targetKindText)「\(top.name)」共\(weeklyDurationText(top.minutes))"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .center, spacing: 2) {
                    Text(weeklyDurationText(configuration.totalMinutes))
                        .font(.system(size: 52, weight: .heavy))
                        .foregroundStyle(primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(ReportLanguage.text("总屏幕时间", "Total Screen Time"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.top, 4)

                weeklyDigestLineChart
                    .frame(height: 236)

                VStack(spacing: 0) {
                    weeklyDigestDivider
                    weeklyDigestInsightRow(icon: "chart.line.uptrend.xyaxis", text: weeklyNightInsightText(from: thisWeekHours))
                    weeklyDigestDivider
                    weeklyDigestInsightRow(
                        icon: "equal.circle",
                        text: ReportLanguage.isEnglish
                            ? "Your average daily use this week was \(weeklyDurationText(configuration.averageMinutes))."
                            : "你本周平均每天使用 \(weeklyDurationText(configuration.averageMinutes))。"
                    )
                    weeklyDigestDivider
                    weeklyDigestTopTargetInsightRow(target: configuration.topTargets.first, text: topTargetText)
                    weeklyDigestDivider
                }

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Text(ReportLanguage.text("专注分", "Focus Score"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(primaryText.opacity(0.9))
                        Text("\(focusScore)")
                            .font(.system(size: 44, weight: .black))
                            .foregroundStyle(primaryText)
                            .monospacedDigit()
                        Text("/100")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(primaryText.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)

                    Text(
                        focusScoreDelta >= 0
                            ? ReportLanguage.isEnglish
                                ? "Up \(focusScoreDelta) vs last week"
                                : "较上周提升 \(focusScoreDelta) 分"
                            : ReportLanguage.isEnglish
                                ? "Down \(abs(focusScoreDelta)) vs last week"
                                : "较上周下降 \(abs(focusScoreDelta)) 分"
                    )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.vertical, 8)

            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var weeklyDigestDivider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func weeklyDigestInsightRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(primaryText.opacity(0.85))
                .frame(width: 22, height: 22)
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryText.opacity(0.86))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func weeklyDigestTopTargetInsightRow(target: InsightsTargetConfiguration?, text: String) -> some View {
        HStack(spacing: 12) {
            if let target {
                targetLeadingIcon(for: target, compact: true)
            } else {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primaryText.opacity(0.85))
                    .frame(width: 22, height: 22)
            }

            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryText.opacity(0.86))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func targetLeadingIcon(for target: InsightsTargetConfiguration, compact: Bool) -> some View {
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
        } else {
            Image(systemName: "globe")
                .font(.system(size: compact ? 14 : 16, weight: .semibold))
                .foregroundStyle(primaryText)
                .frame(width: side, height: side)
                .background(
                    primaryText.opacity(colorScheme == .dark ? 0.18 : 0.08),
                    in: RoundedRectangle(cornerRadius: corner, style: .continuous)
                )
        }
    }

    private var weeklyDigestLineChart: some View {
        let weekLabels = ReportLanguage.isEnglish
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["一", "二", "三", "四", "五", "六", "日"]

        return GeometryReader { proxy in
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
                ForEach(0..<4, id: \.self) { index in
                    let ratio = Double(index) / 3.0
                    let y = plotOrigin.y + chartHeight * CGFloat(1 - ratio)
                    Path { path in
                        path.move(to: CGPoint(x: gridStartX, y: y))
                        path.addLine(to: CGPoint(x: plotOrigin.x + chartWidth, y: y))
                    }
                    .stroke(dividerColor, lineWidth: 1)

                    Text(index == 0 ? "0" : "\(Int((yMax / 3.0) * Double(index)))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .frame(width: axisLabelColumnWidth, alignment: .trailing)
                        .position(x: axisLabelCenterX, y: y)
                }

                Text(ReportLanguage.text("小时", "Hrs"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryText)
                    .frame(width: axisLabelColumnWidth, alignment: .leading)
                    .position(x: gridStartX + axisLabelColumnWidth / 2, y: max(0, plotOrigin.y - 14))

                weeklyLinePath(values: thisWeekHours, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    .stroke(primaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                weeklyLinePath(values: lastWeekHours, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    .stroke(secondaryText.opacity(0.78), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: [4, 4]))

                ForEach(Array(thisWeekHours.enumerated()), id: \.offset) { index, value in
                    let point = weeklyPoint(index: index, value: value, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    Circle()
                        .fill(primaryText)
                        .frame(width: 7, height: 7)
                        .position(point)
                }

                ForEach(Array(lastWeekHours.enumerated()), id: \.offset) { index, value in
                    let point = weeklyPoint(index: index, value: value, yMax: yMax, origin: plotOrigin, width: chartWidth, height: chartHeight)
                    Circle()
                        .fill(secondaryText.opacity(0.78))
                        .frame(width: 6, height: 6)
                        .position(point)
                }

                ForEach(Array(weekLabels.enumerated()), id: \.offset) { index, label in
                    let x = plotOrigin.x + CGFloat(index) * (chartWidth / 6)
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryText)
                        .position(x: x, y: plotOrigin.y + chartHeight + 20)
                }

                HStack(spacing: 24) {
                    weeklyDigestLegendDot(style: .solid, title: ReportLanguage.text("本周", "This Week"))
                    weeklyDigestLegendDot(style: .dashed, title: ReportLanguage.text("上周", "Last Week"))
                }
                .frame(width: chartWidth, alignment: .center)
                .position(x: plotOrigin.x + chartWidth / 2, y: plotOrigin.y + chartHeight + 44)
            }
        }
    }

    private func weeklyHours(from buckets: [InsightsBucketConfiguration]) -> [Double] {
        if buckets.isEmpty {
            return Array(repeating: 0, count: 7)
        }
        let sorted = buckets.prefix(7).map { Double(max(0, $0.totalMinutes)) / 60.0 }
        if sorted.count < 7 {
            return sorted + Array(repeating: 0, count: 7 - sorted.count)
        }
        return sorted
    }

    private func weeklyLinePath(values: [Double], yMax: Double, origin: CGPoint, width: CGFloat, height: CGFloat) -> Path {
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

    private func weeklyPoint(index: Int, value: Double, yMax: Double, origin: CGPoint, width: CGFloat, height: CGFloat) -> CGPoint {
        let xStep = width / 6
        let normalized = min(max(value / max(1, yMax), 0), 1)
        return CGPoint(
            x: origin.x + CGFloat(index) * xStep,
            y: origin.y + height * CGFloat(1 - normalized)
        )
    }

    private func weeklyDigestLegendDot(style: WeeklyDigestLegendStyle, title: String) -> some View {
        HStack(spacing: 6) {
            if style == .solid {
                Capsule()
                    .fill(primaryText)
                    .frame(width: 22, height: 3)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(secondaryText.opacity(0.78))
                            .frame(width: 4, height: 3)
                    }
                }
                .frame(width: 28, alignment: .leading)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(primaryText.opacity(0.85))
        }
    }

    private func weeklyDurationText(_ minutes: Int) -> String {
        let safe = max(0, minutes)
        let hour = safe / 60
        let minute = safe % 60
        if hour > 0 {
            return ReportLanguage.isEnglish ? "\(hour)h \(minute)m" : "\(hour)小时\(minute)分钟"
        }
        return ReportLanguage.isEnglish ? "\(minute)m" : "\(minute)分钟"
    }

    private func weeklyNightInsightText(from hours: [Double]) -> String {
        guard let (index, value) = hours.enumerated().max(by: { $0.element < $1.element }) else {
            return ReportLanguage.text("本周使用趋势还在形成中。", "Your weekly pattern is still forming.")
        }
        let labels = ReportLanguage.isEnglish
            ? ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            : ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let dayLabel = (0..<labels.count).contains(index) ? labels[index] : ReportLanguage.text("本周", "this week")
        if ReportLanguage.isEnglish {
            return "Screen time peaked on \(dayLabel), around \(String(format: "%.1f", value))h."
        }
        return "屏幕时间在\(dayLabel)达到峰值，约 \(String(format: "%.1f", value)) 小时。"
    }

    private func weeklyFocusScore(totalMinutes: Int) -> Int {
        let averageDailyHours = max(0, Double(totalMinutes)) / 60.0 / 7.0

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

    private func weeklyStandardDeviation(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private enum WeeklyDigestLegendStyle {
        case solid
        case dashed
    }
}

private extension DeviceActivityReport.Context {
    static let onlyLockInsightsDay = Self("onlylock.insights.day")
    static let onlyLockInsightsWeek = Self("onlylock.insights.week")
    static let onlyLockInsightsTrend = Self("onlylock.insights.trend")
    static let onlyLockWeeklyDigest = Self("onlylock.insights.weeklyDigest")
}
