import Foundation
import ManagedSettings

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

struct ScreenTimeInsightsBucket: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let appMinutes: Int
    let webMinutes: Int
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

enum ScreenTimeInsightsShared {
    static let appGroupIdentifier = "group.com.onlylock.shared"
    static let snapshotKeyPrefix = "onlylock.screentime.insights."
    static let diagnosticKeyPrefix = "onlylock.screentime.diagnostic."
    static let snapshotDirectoryName = "ScreenTimeInsightsSnapshots"
    static let debugLogFileName = "ScreenTimeInsightsDebug.log"
    static let extensionLocalDebugLogFileName = "OnlyLockReportExtension.log"
    static let unknownCategoryLogFileName = "UnknownInsightsCategories.log"
    static let weeklyDigestSelectedWeekStartKey = "onlylock.weeklyDigest.selectedWeekStart"
    static let weeklyReportHistoryWeekStartsKey = "onlylock.weeklyReport.historyWeekStarts"

    static func snapshotKey(scope: String) -> String {
        snapshotKeyPrefix + scope
    }

    static func snapshotKey(scope: String, rangeStart: Date, rangeEnd: Date) -> String {
        let start = Int(rangeStart.timeIntervalSince1970)
        let end = Int(rangeEnd.timeIntervalSince1970)
        return "\(snapshotKeyPrefix)\(scope).\(start).\(end)"
    }

    static func diagnosticKey(scope: String) -> String {
        diagnosticKeyPrefix + scope
    }

    static func snapshotFileName(scope: String, rangeStart: Date, rangeEnd: Date) -> String {
        let start = Int(rangeStart.timeIntervalSince1970)
        let end = Int(rangeEnd.timeIntervalSince1970)
        return "\(scope).\(start).\(end).json"
    }

    static func debugLogFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(debugLogFileName)
    }

    static func extensionLocalDebugLogFileURL() -> URL? {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return tempDirectory.appendingPathComponent(extensionLocalDebugLogFileName)
    }

    static func unknownCategoryLogFileURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent(unknownCategoryLogFileName)
    }
}
