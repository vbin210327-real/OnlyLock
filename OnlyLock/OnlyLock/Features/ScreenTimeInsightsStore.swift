import Combine
import Foundation
import ManagedSettings

struct ScreenTimeInsightsBucket: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let appMinutes: Int
    let webMinutes: Int

    var totalMinutes: Int {
        max(0, appMinutes + webMinutes)
    }
}

enum ScreenTimeInsightsTargetKind: String, Codable, Equatable {
    case app
    case website
    case category
}

struct ScreenTimeInsightsTarget: Codable, Equatable, Identifiable {
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

struct ScreenTimeInsightsSnapshot: Codable, Equatable {
    let scope: String
    let rangeStart: Date
    let rangeEnd: Date
    let totalMinutes: Int
    let averageMinutes: Int
    let previousTotalMinutes: Int
    let buckets: [ScreenTimeInsightsBucket]
    let topTargets: [ScreenTimeInsightsTarget]
    let topCategories: [ScreenTimeInsightsTarget]
    let generatedAt: Date

    init(
        scope: String,
        rangeStart: Date,
        rangeEnd: Date,
        totalMinutes: Int,
        averageMinutes: Int,
        previousTotalMinutes: Int,
        buckets: [ScreenTimeInsightsBucket],
        topTargets: [ScreenTimeInsightsTarget],
        topCategories: [ScreenTimeInsightsTarget] = [],
        generatedAt: Date
    ) {
        self.scope = scope
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.totalMinutes = totalMinutes
        self.averageMinutes = averageMinutes
        self.previousTotalMinutes = previousTotalMinutes
        self.buckets = buckets
        self.topTargets = topTargets
        self.topCategories = topCategories
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case rangeStart
        case rangeEnd
        case totalMinutes
        case averageMinutes
        case previousTotalMinutes
        case buckets
        case topTargets
        case topCategories
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(String.self, forKey: .scope)
        rangeStart = try container.decode(Date.self, forKey: .rangeStart)
        rangeEnd = try container.decode(Date.self, forKey: .rangeEnd)
        totalMinutes = try container.decode(Int.self, forKey: .totalMinutes)
        averageMinutes = try container.decode(Int.self, forKey: .averageMinutes)
        previousTotalMinutes = try container.decode(Int.self, forKey: .previousTotalMinutes)
        buckets = try container.decode([ScreenTimeInsightsBucket].self, forKey: .buckets)
        topTargets = try container.decode([ScreenTimeInsightsTarget].self, forKey: .topTargets)
        topCategories = try container.decodeIfPresent([ScreenTimeInsightsTarget].self, forKey: .topCategories) ?? []
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    }
}

struct ScreenTimeInsightsDiagnostic: Codable, Equatable {
    let scope: String
    let wroteAt: Date
    let segmentCount: Int
    let appCount: Int
    let websiteCount: Int
    let totalMinutes: Int
    let topTargetCount: Int
    let note: String
}

#if DEBUG
struct DebugInsightsBucketOverride: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let appMinutes: Int
    let webMinutes: Int

    var totalMinutes: Int {
        max(0, appMinutes + webMinutes)
    }
}

struct DebugInsightsTargetOverride: Codable, Equatable, Identifiable {
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

struct DebugInsightsSnapshotOverride: Codable, Equatable {
    let scope: String
    let rangeStart: Date
    let rangeEnd: Date
    let previousTotalMinutes: Int
    let buckets: [DebugInsightsBucketOverride]
    let topTargets: [DebugInsightsTargetOverride]
    let topCategories: [DebugInsightsTargetOverride]

    init(
        scope: String,
        rangeStart: Date,
        rangeEnd: Date,
        previousTotalMinutes: Int,
        buckets: [DebugInsightsBucketOverride],
        topTargets: [DebugInsightsTargetOverride],
        topCategories: [DebugInsightsTargetOverride] = []
    ) {
        self.scope = scope
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.previousTotalMinutes = previousTotalMinutes
        self.buckets = buckets
        self.topTargets = topTargets
        self.topCategories = topCategories
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case rangeStart
        case rangeEnd
        case previousTotalMinutes
        case buckets
        case topTargets
        case topCategories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(String.self, forKey: .scope)
        rangeStart = try container.decode(Date.self, forKey: .rangeStart)
        rangeEnd = try container.decode(Date.self, forKey: .rangeEnd)
        previousTotalMinutes = try container.decode(Int.self, forKey: .previousTotalMinutes)
        buckets = try container.decode([DebugInsightsBucketOverride].self, forKey: .buckets)
        topTargets = try container.decode([DebugInsightsTargetOverride].self, forKey: .topTargets)
        topCategories = try container.decodeIfPresent([DebugInsightsTargetOverride].self, forKey: .topCategories) ?? []
    }

    var asSnapshot: ScreenTimeInsightsSnapshot {
        let totalMinutes = buckets.reduce(0) { partialResult, bucket in
            partialResult + bucket.totalMinutes
        }

        let averageMinutes: Int
        switch scope {
        case "week":
            averageMinutes = totalMinutes / 7
        case "day":
            averageMinutes = buckets.isEmpty ? 0 : totalMinutes / buckets.count
        default:
            averageMinutes = 0
        }

        return ScreenTimeInsightsSnapshot(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            totalMinutes: totalMinutes,
            averageMinutes: averageMinutes,
            previousTotalMinutes: max(0, previousTotalMinutes),
            buckets: buckets.map { bucket in
                ScreenTimeInsightsBucket(
                    id: bucket.id,
                    label: bucket.label,
                    appMinutes: max(0, bucket.appMinutes),
                    webMinutes: max(0, bucket.webMinutes)
                )
            },
            topTargets: topTargets.map { target in
                ScreenTimeInsightsTarget(
                    id: target.id,
                    name: target.name,
                    minutes: max(0, target.minutes),
                    kind: target.kind,
                    applicationToken: target.applicationToken,
                    categoryToken: target.categoryToken
                )
            },
            topCategories: topCategories.map { target in
                ScreenTimeInsightsTarget(
                    id: target.id,
                    name: target.name,
                    minutes: max(0, target.minutes),
                    kind: target.kind,
                    applicationToken: target.applicationToken,
                    categoryToken: target.categoryToken
                )
            },
            generatedAt: Date()
        )
    }
}

struct DebugWeeklyReportOverride: Codable, Equatable {
    let weekStart: Date
    let current: DebugInsightsSnapshotOverride
    let previous: DebugInsightsSnapshotOverride

    var sanitized: DebugWeeklyReportOverride {
        DebugWeeklyReportOverride(
            weekStart: OnlyLockShared.startOfWeekMonday(containing: weekStart),
            current: current.sanitized,
            previous: previous.sanitized
        )
    }
}

extension DebugWeeklyReportOverride {
    func withCurrentBucketMinutes(index: Int, totalMinutes: Int) -> DebugWeeklyReportOverride {
        DebugWeeklyReportOverride(
            weekStart: weekStart,
            current: current.withBucketMinutes(index: index, totalMinutes: totalMinutes),
            previous: previous
        )
    }

    func withPreviousBucketMinutes(index: Int, totalMinutes: Int) -> DebugWeeklyReportOverride {
        DebugWeeklyReportOverride(
            weekStart: weekStart,
            current: current,
            previous: previous.withBucketMinutes(index: index, totalMinutes: totalMinutes)
        )
    }

    func withCurrentTargetName(index: Int, name: String) -> DebugWeeklyReportOverride {
        DebugWeeklyReportOverride(
            weekStart: weekStart,
            current: current.withTargetName(index: index, name: name),
            previous: previous
        )
    }

    func withCurrentTargetMinutes(index: Int, minutes: Int) -> DebugWeeklyReportOverride {
        DebugWeeklyReportOverride(
            weekStart: weekStart,
            current: current.withTargetMinutes(index: index, minutes: minutes),
            previous: previous
        )
    }

    func withCurrentTargetApplicationToken(
        index: Int,
        token: ApplicationToken?,
        preferredName: String
    ) -> DebugWeeklyReportOverride {
        DebugWeeklyReportOverride(
            weekStart: weekStart,
            current: current.withTargetApplicationToken(index: index, token: token, preferredName: preferredName),
            previous: previous
        )
    }
}

extension DebugInsightsSnapshotOverride {
    var sanitized: DebugInsightsSnapshotOverride {
        DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: max(0, previousTotalMinutes),
            buckets: buckets.map { bucket in
                DebugInsightsBucketOverride(
                    id: bucket.id,
                    label: bucket.label,
                    appMinutes: max(0, bucket.appMinutes),
                    webMinutes: max(0, bucket.webMinutes)
                )
            },
            topTargets: topTargets
                .map { target in
                    DebugInsightsTargetOverride(
                        id: target.id,
                        name: target.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        minutes: max(0, target.minutes),
                        kind: target.kind,
                        applicationToken: target.applicationToken,
                        categoryToken: target.categoryToken
                    )
                }
                .filter { !$0.name.isEmpty || $0.minutes > 0 },
            topCategories: topCategories
                .map { target in
                    DebugInsightsTargetOverride(
                        id: target.id,
                        name: target.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        minutes: max(0, target.minutes),
                        kind: target.kind,
                        applicationToken: target.applicationToken,
                        categoryToken: target.categoryToken
                    )
                }
                .filter { !$0.name.isEmpty || $0.minutes > 0 }
        )
    }

    func withPreviousTotalMinutes(_ minutes: Int) -> DebugInsightsSnapshotOverride {
        DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: max(0, minutes),
            buckets: buckets,
            topTargets: topTargets,
            topCategories: topCategories
        )
    }

    func withBucketMinutes(index: Int, totalMinutes: Int) -> DebugInsightsSnapshotOverride {
        guard buckets.indices.contains(index) else { return self }
        var updatedBuckets = buckets
        let bucket = updatedBuckets[index]
        updatedBuckets[index] = DebugInsightsBucketOverride(
            id: bucket.id,
            label: bucket.label,
            appMinutes: max(0, totalMinutes),
            webMinutes: 0
        )
        return DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: previousTotalMinutes,
            buckets: updatedBuckets,
            topTargets: topTargets,
            topCategories: topCategories
        )
    }

    func withTargetName(index: Int, name: String) -> DebugInsightsSnapshotOverride {
        var updatedTargets = topTargets
        while updatedTargets.count <= index {
            updatedTargets.append(
                DebugInsightsTargetOverride(
                    id: "demo.target.\(updatedTargets.count)",
                    name: "",
                    minutes: 0,
                    kind: .app,
                    applicationToken: nil,
                    categoryToken: nil
                )
            )
        }
        let target = updatedTargets[index]
        updatedTargets[index] = DebugInsightsTargetOverride(
            id: target.id,
            name: name,
            minutes: target.minutes,
            kind: target.kind,
            applicationToken: target.applicationToken,
            categoryToken: target.categoryToken
        )
        return DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: previousTotalMinutes,
            buckets: buckets,
            topTargets: updatedTargets,
            topCategories: topCategories
        )
    }

    func withTargetMinutes(index: Int, minutes: Int) -> DebugInsightsSnapshotOverride {
        var updatedTargets = topTargets
        while updatedTargets.count <= index {
            updatedTargets.append(
                DebugInsightsTargetOverride(
                    id: "demo.target.\(updatedTargets.count)",
                    name: "",
                    minutes: 0,
                    kind: .app,
                    applicationToken: nil,
                    categoryToken: nil
                )
            )
        }
        let target = updatedTargets[index]
        updatedTargets[index] = DebugInsightsTargetOverride(
            id: target.id,
            name: target.name,
            minutes: max(0, minutes),
            kind: target.kind,
            applicationToken: target.applicationToken,
            categoryToken: target.categoryToken
        )
        return DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: previousTotalMinutes,
            buckets: buckets,
            topTargets: updatedTargets,
            topCategories: topCategories
        )
    }

    func withTargetApplicationToken(
        index: Int,
        token: ApplicationToken?,
        preferredName: String
    ) -> DebugInsightsSnapshotOverride {
        var updatedTargets = topTargets
        while updatedTargets.count <= index {
            updatedTargets.append(
                DebugInsightsTargetOverride(
                    id: "demo.target.\(updatedTargets.count)",
                    name: "",
                    minutes: 0,
                    kind: .app,
                    applicationToken: nil,
                    categoryToken: nil
                )
            )
        }
        updatedTargets[index] = DebugInsightsTargetOverride(
            id: "demo.target.\(index)",
            name: preferredName,
            minutes: updatedTargets[index].minutes,
            kind: .app,
            applicationToken: token,
            categoryToken: nil
        )
        return DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: previousTotalMinutes,
            buckets: buckets,
            topTargets: updatedTargets,
            topCategories: topCategories
        )
    }

    func withCategoryTargets(_ targets: [DebugInsightsTargetOverride]) -> DebugInsightsSnapshotOverride {
        DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: previousTotalMinutes,
            buckets: buckets,
            topTargets: topTargets,
            topCategories: targets
        )
    }

    func withCategoryName(index: Int, name: String) -> DebugInsightsSnapshotOverride {
        var updatedCategories = topCategories
        while updatedCategories.count <= index {
            updatedCategories.append(
                DebugInsightsTargetOverride(
                    id: "demo.category.\(updatedCategories.count)",
                    name: "",
                    minutes: 0,
                    kind: .category,
                    applicationToken: nil,
                    categoryToken: nil
                )
            )
        }
        let target = updatedCategories[index]
        updatedCategories[index] = DebugInsightsTargetOverride(
            id: target.id,
            name: name,
            minutes: target.minutes,
            kind: .category,
            applicationToken: nil,
            categoryToken: nil
        )
        return DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: previousTotalMinutes,
            buckets: buckets,
            topTargets: topTargets,
            topCategories: updatedCategories
        )
    }

    func withCategoryMinutes(index: Int, minutes: Int) -> DebugInsightsSnapshotOverride {
        var updatedCategories = topCategories
        while updatedCategories.count <= index {
            updatedCategories.append(
                DebugInsightsTargetOverride(
                    id: "demo.category.\(updatedCategories.count)",
                    name: "",
                    minutes: 0,
                    kind: .category,
                    applicationToken: nil,
                    categoryToken: nil
                )
            )
        }
        let target = updatedCategories[index]
        updatedCategories[index] = DebugInsightsTargetOverride(
            id: target.id,
            name: target.name,
            minutes: max(0, minutes),
            kind: .category,
            applicationToken: nil,
            categoryToken: nil
        )
        return DebugInsightsSnapshotOverride(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            previousTotalMinutes: previousTotalMinutes,
            buckets: buckets,
            topTargets: topTargets,
            topCategories: updatedCategories
        )
    }
}
#endif

@MainActor
final class ScreenTimeInsightsStore: ObservableObject {
    @Published private(set) var snapshotsByKey: [String: ScreenTimeInsightsSnapshot] = [:]
    @Published private(set) var diagnosticsByScope: [String: ScreenTimeInsightsDiagnostic] = [:]
#if DEBUG
    @Published private(set) var debugOverridesByKey: [String: DebugInsightsSnapshotOverride] = [:]
    @Published private(set) var debugWeeklyReportOverridesByKey: [String: DebugWeeklyReportOverride] = [:]
#endif

    private let fallbackDefaults: UserDefaults
    private let decoder = JSONDecoder()
#if DEBUG
    private let encoder = JSONEncoder()
#endif

    init(defaults: UserDefaults? = nil) {
        let sharedDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)
        self.fallbackDefaults = defaults ?? sharedDefaults ?? .standard
        refresh()
    }

    func refresh() {
        let currentDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? fallbackDefaults
        snapshotsByKey = [:]
        diagnosticsByScope = [:]
#if DEBUG
        debugOverridesByKey = [:]
        debugWeeklyReportOverridesByKey = [:]
#endif

        for (key, value) in currentDefaults.dictionaryRepresentation() {
            guard key.hasPrefix(OnlyLockShared.screenTimeInsightsSnapshotKeyPrefix),
                  let data = value as? Data,
                  let snapshot = try? decoder.decode(ScreenTimeInsightsSnapshot.self, from: data) else {
                continue
            }
            snapshotsByKey[key] = normalized(snapshot: snapshot)
        }

        if let directoryURL = snapshotDirectoryURL() {
            let fileURLs = (try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )) ?? []

            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                guard let data = try? Data(contentsOf: fileURL),
                      let snapshot = try? decoder.decode(ScreenTimeInsightsSnapshot.self, from: data) else {
                    continue
                }

                let key = OnlyLockShared.screenTimeInsightsSnapshotKey(
                    scope: snapshot.scope,
                    rangeStart: snapshot.rangeStart,
                    rangeEnd: snapshot.rangeEnd
                )
                let normalizedSnapshot = normalized(snapshot: snapshot)

                if let existing = snapshotsByKey[key], existing.generatedAt >= normalizedSnapshot.generatedAt {
                    continue
                }
                snapshotsByKey[key] = normalizedSnapshot
            }
        }

        for scope in ["day", "week", "trend"] {
            let diagnosticKey = OnlyLockShared.screenTimeInsightsDiagnosticKey(scope: scope)
            if let diagnosticData = currentDefaults.data(forKey: diagnosticKey),
               let diagnostic = try? decoder.decode(ScreenTimeInsightsDiagnostic.self, from: diagnosticData) {
                diagnosticsByScope[scope] = diagnostic
                print("[OnlyLockInsights][App] scope=\(scope) wroteAt=\(diagnostic.wroteAt) segments=\(diagnostic.segmentCount) apps=\(diagnostic.appCount) websites=\(diagnostic.websiteCount) total=\(diagnostic.totalMinutes) topTargets=\(diagnostic.topTargetCount) note=\(diagnostic.note)")
            }
        }

#if DEBUG
        for (key, value) in currentDefaults.dictionaryRepresentation() {
            guard key.hasPrefix(OnlyLockShared.debugScreenTimeInsightsOverrideKeyPrefix),
                  let data = value as? Data,
                  let override = try? decoder.decode(DebugInsightsSnapshotOverride.self, from: data) else {
                continue
            }
            debugOverridesByKey[key] = override
        }

        for (key, value) in currentDefaults.dictionaryRepresentation() {
            guard key.hasPrefix("onlylock.debug.weeklyReport.override."),
                  let data = value as? Data,
                  let override = try? decoder.decode(DebugWeeklyReportOverride.self, from: data) else {
                continue
            }
            debugWeeklyReportOverridesByKey[key] = override
        }
#endif
    }

    func snapshot(for scope: String, rangeStart: Date, rangeEnd: Date) -> ScreenTimeInsightsSnapshot? {
        snapshotsByKey[OnlyLockShared.screenTimeInsightsSnapshotKey(scope: scope, rangeStart: rangeStart, rangeEnd: rangeEnd)]
    }

    func diagnostic(for scope: String) -> ScreenTimeInsightsDiagnostic? {
        diagnosticsByScope[scope]
    }

#if DEBUG
    func debugOverride(
        for scope: String,
        rangeStart: Date,
        rangeEnd: Date
    ) -> ScreenTimeInsightsSnapshot? {
        let key = OnlyLockShared.debugScreenTimeInsightsOverrideKey(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        return debugOverridesByKey[key]?.asSnapshot
    }

    func debugOverrideModel(
        for scope: String,
        rangeStart: Date,
        rangeEnd: Date
    ) -> DebugInsightsSnapshotOverride? {
        let key = OnlyLockShared.debugScreenTimeInsightsOverrideKey(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        return debugOverridesByKey[key]
    }

    func saveDebugOverride(_ overrideSnapshot: DebugInsightsSnapshotOverride) {
        let currentDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? fallbackDefaults
        let key = OnlyLockShared.debugScreenTimeInsightsOverrideKey(
            scope: overrideSnapshot.scope,
            rangeStart: overrideSnapshot.rangeStart,
            rangeEnd: overrideSnapshot.rangeEnd
        )
        guard let data = try? encoder.encode(overrideSnapshot) else { return }
        currentDefaults.set(data, forKey: key)
        currentDefaults.synchronize()
        refresh()
    }

    func removeDebugOverride(scope: String, rangeStart: Date, rangeEnd: Date) {
        let currentDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? fallbackDefaults
        let key = OnlyLockShared.debugScreenTimeInsightsOverrideKey(
            scope: scope,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd
        )
        currentDefaults.removeObject(forKey: key)
        currentDefaults.synchronize()
        refresh()
    }

    func debugWeeklyReportOverride(forWeekStart weekStart: Date) -> DebugWeeklyReportOverride? {
        let key = OnlyLockShared.debugWeeklyReportOverrideKey(weekStart: weekStart)
        return debugWeeklyReportOverridesByKey[key]
    }

    func saveDebugWeeklyReportOverride(_ overrideSnapshot: DebugWeeklyReportOverride) {
        let currentDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? fallbackDefaults
        let normalized = overrideSnapshot.sanitized
        let key = OnlyLockShared.debugWeeklyReportOverrideKey(weekStart: normalized.weekStart)
        guard let data = try? encoder.encode(normalized) else { return }
        currentDefaults.set(data, forKey: key)
        currentDefaults.synchronize()
        refresh()
    }

    func removeDebugWeeklyReportOverride(forWeekStart weekStart: Date) {
        let currentDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? fallbackDefaults
        let key = OnlyLockShared.debugWeeklyReportOverrideKey(weekStart: weekStart)
        currentDefaults.removeObject(forKey: key)
        currentDefaults.synchronize()
        refresh()
    }
#endif

    private func snapshotDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: OnlyLockShared.appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent("ScreenTimeInsightsSnapshots", isDirectory: true)
    }

    private func normalized(snapshot: ScreenTimeInsightsSnapshot) -> ScreenTimeInsightsSnapshot {
        var mergedCategories: [String: ScreenTimeInsightsTarget] = [:]

        for category in snapshot.topCategories {
            let key = stableCategoryKey(token: category.categoryToken, fallbackName: category.name)
            let existing = mergedCategories[key]
            mergedCategories[key] = ScreenTimeInsightsTarget(
                id: existing?.id ?? category.id,
                name: existing?.name ?? category.name,
                minutes: (existing?.minutes ?? 0) + category.minutes,
                kind: .category,
                applicationToken: nil,
                categoryToken: existing?.categoryToken ?? category.categoryToken
            )
        }

        let topCategories = mergedCategories.values.sorted { lhs, rhs in
            if lhs.minutes == rhs.minutes {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.minutes > rhs.minutes
        }

        return ScreenTimeInsightsSnapshot(
            scope: snapshot.scope,
            rangeStart: snapshot.rangeStart,
            rangeEnd: snapshot.rangeEnd,
            totalMinutes: snapshot.totalMinutes,
            averageMinutes: snapshot.averageMinutes,
            previousTotalMinutes: snapshot.previousTotalMinutes,
            buckets: snapshot.buckets,
            topTargets: snapshot.topTargets,
            topCategories: topCategories,
            generatedAt: snapshot.generatedAt
        )
    }

    private func stableCategoryKey(
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

    private func canonicalCategoryKey(for rawName: String) -> String? {
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
}
