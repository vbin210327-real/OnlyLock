import Foundation

enum ScreenTimeInsightsTargetKind: String, Codable, Equatable {
    case app
    case website
}

struct ScreenTimeInsightsTarget: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let minutes: Int
    let kind: ScreenTimeInsightsTargetKind
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
    let generatedAt: Date
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
}
