import CryptoKit
import Foundation
import ManagedSettings

private enum ShieldTrackingShared {
    static let appGroupIdentifier = "group.com.onlylock.shared"
    static let lockRuleStorageKey = "onlylock.lockRule"
    static let attemptCounterStorageKey = "onlylock.shield.attemptCounters"
    static let debugTimeOverrideEnabledKey = "onlylock.debug.timeOverride.enabled"
    static let debugTimeOverrideTimestampKey = "onlylock.debug.timeOverride.timestamp"
    static let appLanguageCodeKey = "onlylock.settings.appLanguageCode"
}

private struct ShieldLockRule: Decodable {
    let id: UUID
    let name: String?
    let startAt: Date
    let durationMinutes: Int
    let isWeeklyRepeat: Bool
    let repeatWeekdays: Set<Int>
    let applicationTokens: Set<ApplicationToken>
    let categoryTokens: Set<ActivityCategoryToken>
    let webDomainTokens: Set<WebDomainToken>
    let manualWebDomains: Set<String>
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case startAt
        case durationMinutes
        case isWeeklyRepeat
        case repeatWeekdays
        case applicationTokens
        case categoryTokens
        case webDomainTokens
        case manualWebDomains
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        startAt = try container.decode(Date.self, forKey: .startAt)
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        isWeeklyRepeat = try container.decodeIfPresent(Bool.self, forKey: .isWeeklyRepeat) ?? false
        repeatWeekdays = try container.decodeIfPresent(Set<Int>.self, forKey: .repeatWeekdays) ?? []
        applicationTokens = try container.decode(Set<ApplicationToken>.self, forKey: .applicationTokens)
        categoryTokens = try container.decodeIfPresent(Set<ActivityCategoryToken>.self, forKey: .categoryTokens) ?? []
        webDomainTokens = try container.decode(Set<WebDomainToken>.self, forKey: .webDomainTokens)
        manualWebDomains = try container.decodeIfPresent(Set<String>.self, forKey: .manualWebDomains) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var endAt: Date? {
        Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startAt)
    }

    func isActive(at now: Date) -> Bool {
        if isWeeklyRepeat {
            guard let window = repeatActiveWindow(at: now) else { return false }
            return now >= window.start && now < window.end
        }

        guard let endAt else { return false }
        return startAt <= now && now < endAt
    }

    private func repeatActiveWindow(at now: Date) -> (start: Date, end: Date)? {
        let weekdays = repeatWeekdays.filter { (1...7).contains($0) }
        guard !weekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: startAt)
        let minute = calendar.component(.minute, from: startAt)
        let searchAnchor = now.addingTimeInterval(1)

        var latestStart: Date?
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

            if latestStart == nil || candidate > latestStart! {
                latestStart = candidate
            }
        }

        guard let start = latestStart,
              let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) else {
            return nil
        }

        return (start, end)
    }
}

private struct ShieldAttemptCounterRecord: Codable {
    var todayCount: Int
    var totalCount: Int
    var todayAnchorDate: Date
    var lastIncrementAt: Date?
}

private struct ShieldAttemptCounterSnapshot {
    let todayCount: Int
    let totalCount: Int
}

private final class ShieldAttemptCounterStore {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: ShieldTrackingShared.appGroupIdentifier)) {
        defaults = userDefaults ?? .standard
    }

    func incrementAndRead(
        ruleID: UUID,
        targetID: String,
        now: Date,
        wallClockNow: Date = Date()
    ) -> ShieldAttemptCounterSnapshot {
        let key = composedKey(ruleID: ruleID, targetID: targetID)

        lock.lock()
        defer { lock.unlock() }

        var records = loadRecords()
        var record = records[key] ?? ShieldAttemptCounterRecord(
            todayCount: 0,
            totalCount: 0,
            todayAnchorDate: Calendar.current.startOfDay(for: now),
            lastIncrementAt: nil
        )

        if !Calendar.current.isDate(record.todayAnchorDate, inSameDayAs: now) {
            record.todayCount = 0
            record.todayAnchorDate = Calendar.current.startOfDay(for: now)
            record.lastIncrementAt = nil
        }

        if shouldIncrement(record: record, wallClockNow: wallClockNow) {
            record.todayCount += 1
            record.totalCount += 1
            record.lastIncrementAt = wallClockNow
            records[key] = record
            persistRecords(records)
        }

        return ShieldAttemptCounterSnapshot(todayCount: record.todayCount, totalCount: record.totalCount)
    }

    private func shouldIncrement(record: ShieldAttemptCounterRecord, wallClockNow: Date) -> Bool {
        guard let last = record.lastIncrementAt else { return true }
        return wallClockNow.timeIntervalSince(last) >= 0.35
    }

    private func composedKey(ruleID: UUID, targetID: String) -> String {
        "\(ruleID.uuidString.lowercased())::\(targetID)"
    }

    private func loadRecords() -> [String: ShieldAttemptCounterRecord] {
        guard let data = defaults.data(forKey: ShieldTrackingShared.attemptCounterStorageKey),
              let decoded = try? decoder.decode([String: ShieldAttemptCounterRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistRecords(_ records: [String: ShieldAttemptCounterRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: ShieldTrackingShared.attemptCounterStorageKey)
    }
}

private struct ShieldRuleAssignment {
    let ruleID: UUID
    let targetID: String
}

final class ShieldAttemptTracker {
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let counterStore = ShieldAttemptCounterStore()

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: ShieldTrackingShared.appGroupIdentifier)) {
        defaults = userDefaults ?? .standard
    }

    private var isEnglish: Bool {
        (defaults.string(forKey: ShieldTrackingShared.appLanguageCodeKey) ?? "zh-Hans") == "en"
    }

    func subtitleForApplication(
        _ application: Application,
        displayName: String,
        category: ActivityCategory? = nil,
        now: Date = ShieldTrackingShared.resolvedNow()
    ) -> String? {
        guard let assignment = assignmentForApplication(application, category: category, now: now) else {
            return nil
        }

        let snapshot = counterStore.incrementAndRead(ruleID: assignment.ruleID, targetID: assignment.targetID, now: now)
        if isEnglish {
            return "\nYou tried to open \"\(displayName)\"\n\nToday \(snapshot.todayCount) | Total \(snapshot.totalCount)"
        }
        return "\n你尝试打开「\(displayName)」\n\n今日 \(snapshot.todayCount) 次 | 累计 \(snapshot.totalCount) 次"
    }

    func subtitleForWebDomain(
        _ webDomain: WebDomain,
        displayName: String,
        category: ActivityCategory? = nil,
        now: Date = ShieldTrackingShared.resolvedNow()
    ) -> String? {
        guard let assignment = assignmentForWebDomain(webDomain, category: category, now: now) else {
            return nil
        }

        let snapshot = counterStore.incrementAndRead(ruleID: assignment.ruleID, targetID: assignment.targetID, now: now)
        if isEnglish {
            return "\nYou tried to open \"\(displayName)\"\n\nToday \(snapshot.todayCount) | Total \(snapshot.totalCount)"
        }
        return "\n你尝试打开「\(displayName)」\n\n今日 \(snapshot.todayCount) 次 | 累计 \(snapshot.totalCount) 次"
    }

    private func assignmentForApplication(_ application: Application, category: ActivityCategory?, now: Date) -> ShieldRuleAssignment? {
        let rules = loadRules()
        guard !rules.isEmpty else { return nil }

        let matchedRules = rules.filter { rule in
            guard rule.isActive(at: now) else { return false }

            if let token = application.token, rule.applicationTokens.contains(token) {
                return true
            }

            if let categoryToken = category?.token, rule.categoryTokens.contains(categoryToken) {
                return true
            }

            return false
        }

        let candidateRules = matchedRules.isEmpty
            ? fallbackApplicationRules(from: rules, now: now)
            : matchedRules

        guard let latestRule = candidateRules.max(by: { lhs, rhs in
            if lhs.startAt == rhs.startAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.startAt < rhs.startAt
        }) else {
            return nil
        }

        let targetID = targetIDForApplication(application)
        return ShieldRuleAssignment(ruleID: latestRule.id, targetID: targetID)
    }

    private func fallbackApplicationRules(from rules: [ShieldLockRule], now: Date) -> [ShieldLockRule] {
        rules.filter { rule in
            guard rule.isActive(at: now) else { return false }
            return !rule.applicationTokens.isEmpty || !rule.categoryTokens.isEmpty
        }
    }

    private func assignmentForWebDomain(_ webDomain: WebDomain, category: ActivityCategory?, now: Date) -> ShieldRuleAssignment? {
        let rules = loadRules()
        guard !rules.isEmpty else { return nil }
        let normalizedDomain = normalizeDomain(webDomain.domain)

        let matchedRules = rules.filter { rule in
            guard rule.isActive(at: now) else { return false }

            if let token = webDomain.token, rule.webDomainTokens.contains(token) {
                return true
            }

            if matchesManualDomain(in: rule, normalizedDomain: normalizedDomain) {
                return true
            }

            if let categoryToken = category?.token, rule.categoryTokens.contains(categoryToken) {
                return true
            }

            return false
        }

        let candidateRules = matchedRules.isEmpty
            ? fallbackWebRules(from: rules, category: category, now: now)
            : matchedRules

        guard let latestRule = candidateRules.max(by: { lhs, rhs in
            if lhs.startAt == rhs.startAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.startAt < rhs.startAt
        }) else {
            return nil
        }

        let targetID = targetIDForWebDomain(webDomain, normalizedDomain: normalizedDomain)
        return ShieldRuleAssignment(ruleID: latestRule.id, targetID: targetID)
    }

    private func matchesManualDomain(in rule: ShieldLockRule, normalizedDomain: String) -> Bool {
        guard !normalizedDomain.isEmpty else { return false }

        return rule.manualWebDomains.contains { storedDomain in
            let normalizedStored = normalizeDomain(storedDomain)
            guard !normalizedStored.isEmpty else { return false }

            return normalizedDomain == normalizedStored ||
                normalizedDomain.hasSuffix(".\(normalizedStored)") ||
                normalizedStored.hasSuffix(".\(normalizedDomain)")
        }
    }

    private func fallbackWebRules(from rules: [ShieldLockRule], category: ActivityCategory?, now: Date) -> [ShieldLockRule] {
        rules.filter { rule in
            guard rule.isActive(at: now) else { return false }

            if let categoryToken = category?.token, rule.categoryTokens.contains(categoryToken) {
                return true
            }

            return !rule.webDomainTokens.isEmpty || !rule.manualWebDomains.isEmpty
        }
    }

    private func loadRules() -> [ShieldLockRule] {
        guard let data = defaults.data(forKey: ShieldTrackingShared.lockRuleStorageKey) else {
            return []
        }

        if let decodedArray = try? decoder.decode([ShieldLockRule].self, from: data) {
            return decodedArray
        }

        if let decodedLegacy = try? decoder.decode(ShieldLockRule.self, from: data) {
            return [decodedLegacy]
        }

        return []
    }

    private func targetIDForApplication(_ application: Application) -> String {
        if let bundleID = application.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleID.isEmpty {
            return "app.bundle.\(bundleID.lowercased())"
        }

        if let token = application.token,
           let data = try? JSONEncoder().encode(token) {
            return "app.token.\(hashData(data))"
        }

        let fallback = application.localizedDisplayName?.lowercased() ?? "unknown"
        return "app.name.\(fallback)"
    }

    private func targetIDForWebDomain(_ webDomain: WebDomain, normalizedDomain: String) -> String {
        if !normalizedDomain.isEmpty {
            return "web.domain.\(normalizedDomain)"
        }

        if let token = webDomain.token,
           let data = try? JSONEncoder().encode(token) {
            return "web.token.\(hashData(data))"
        }

        return "web.unknown"
    }

    private func normalizeDomain(_ raw: String?) -> String {
        guard let raw else { return "" }
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if value.hasPrefix("http://") || value.hasPrefix("https://"),
           let host = URLComponents(string: value)?.host {
            value = host
        }

        if let slashIndex = value.firstIndex(of: "/") {
            value = String(value[..<slashIndex])
        }

        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }

        return value
    }

    private func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension ShieldTrackingShared {
    static func resolvedNow(
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupIdentifier),
        fallback: Date = Date()
    ) -> Date {
#if DEBUG
        let defaults = defaults ?? .standard
        guard defaults.bool(forKey: debugTimeOverrideEnabledKey) else {
            return fallback
        }
        let timestamp = defaults.double(forKey: debugTimeOverrideTimestampKey)
        guard timestamp > 0 else {
            return fallback
        }
        return Date(timeIntervalSince1970: timestamp)
#else
        return fallback
#endif
    }
}
