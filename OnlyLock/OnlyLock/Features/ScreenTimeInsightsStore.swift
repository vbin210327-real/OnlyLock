import Combine
import Foundation

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
}

struct ScreenTimeInsightsTarget: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let minutes: Int
    let kind: ScreenTimeInsightsTargetKind
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

@MainActor
final class ScreenTimeInsightsStore: ObservableObject {
    @Published private(set) var snapshotsByKey: [String: ScreenTimeInsightsSnapshot] = [:]
    @Published private(set) var diagnosticsByScope: [String: ScreenTimeInsightsDiagnostic] = [:]

    private let fallbackDefaults: UserDefaults
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = nil) {
        let sharedDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)
        self.fallbackDefaults = defaults ?? sharedDefaults ?? .standard
        refresh()
    }

    func refresh() {
        let currentDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? fallbackDefaults
        snapshotsByKey = [:]
        diagnosticsByScope = [:]

        for (key, value) in currentDefaults.dictionaryRepresentation() {
            guard key.hasPrefix(OnlyLockShared.screenTimeInsightsSnapshotKeyPrefix),
                  let data = value as? Data,
                  let snapshot = try? decoder.decode(ScreenTimeInsightsSnapshot.self, from: data) else {
                continue
            }
            snapshotsByKey[key] = snapshot
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

                if let existing = snapshotsByKey[key], existing.generatedAt >= snapshot.generatedAt {
                    continue
                }
                snapshotsByKey[key] = snapshot
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
    }

    func snapshot(for scope: String, rangeStart: Date, rangeEnd: Date) -> ScreenTimeInsightsSnapshot? {
        snapshotsByKey[OnlyLockShared.screenTimeInsightsSnapshotKey(scope: scope, rangeStart: rangeStart, rangeEnd: rangeEnd)]
    }

    func diagnostic(for scope: String) -> ScreenTimeInsightsDiagnostic? {
        diagnosticsByScope[scope]
    }

    private func snapshotDirectoryURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: OnlyLockShared.appGroupIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent("ScreenTimeInsightsSnapshots", isDirectory: true)
    }
}
