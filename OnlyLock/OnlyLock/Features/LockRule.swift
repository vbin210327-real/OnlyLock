import Foundation
import ManagedSettings

struct LockRule: Codable, Equatable {
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
    let updatedAt: Date

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

    init(
        id: UUID,
        name: String?,
        startAt: Date,
        durationMinutes: Int,
        isWeeklyRepeat: Bool,
        repeatWeekdays: Set<Int>,
        applicationTokens: Set<ApplicationToken>,
        categoryTokens: Set<ActivityCategoryToken>,
        webDomainTokens: Set<WebDomainToken>,
        manualWebDomains: Set<String>,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.startAt = startAt
        self.durationMinutes = durationMinutes
        self.isWeeklyRepeat = isWeeklyRepeat
        self.repeatWeekdays = repeatWeekdays
        self.applicationTokens = applicationTokens
        self.categoryTokens = categoryTokens
        self.webDomainTokens = webDomainTokens
        self.manualWebDomains = manualWebDomains
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var hasAnyTarget: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty || !manualWebDomains.isEmpty
    }

    var endAt: Date? {
        Calendar.current.date(byAdding: .minute, value: durationMinutes, to: startAt)
    }

    static func make(
        name: String?,
        startAt: Date,
        durationMinutes: Int,
        isWeeklyRepeat: Bool,
        repeatWeekdays: Set<Int>,
        applicationTokens: Set<ApplicationToken>,
        categoryTokens: Set<ActivityCategoryToken>,
        webDomainTokens: Set<WebDomainToken>,
        manualWebDomains: Set<String>,
        existingId: UUID? = nil,
        existingCreatedAt: Date? = nil,
        now: Date = Date()
    ) -> LockRule {
        LockRule(
            id: existingId ?? UUID(),
            name: name,
            startAt: startAt,
            durationMinutes: durationMinutes,
            isWeeklyRepeat: isWeeklyRepeat,
            repeatWeekdays: repeatWeekdays,
            applicationTokens: applicationTokens,
            categoryTokens: categoryTokens,
            webDomainTokens: webDomainTokens,
            manualWebDomains: manualWebDomains,
            createdAt: existingCreatedAt ?? now,
            updatedAt: now
        )
    }
}

enum LockRuleStorageError: LocalizedError {
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        let isEnglish = AppLanguageRuntime.currentLanguage == .english
        switch self {
        case .encodingFailed:
            return isEnglish ? "Unable to save lock rules. Please try again." : "无法保存锁定规则，请稍后重试。"
        case .decodingFailed:
            return isEnglish ? "Lock rule data is corrupted. Old data has been ignored." : "当前锁定规则损坏，已忽略旧数据。"
        }
    }
}

struct LockRuleStorage {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)) {
        defaults = userDefaults ?? .standard
    }

    func load() throws -> LockRule? {
        return try loadAll().first
    }

    func loadAll() throws -> [LockRule] {
        guard let data = defaults.data(forKey: OnlyLockShared.lockRuleStorageKey) else {
            return []
        }

        do {
            let rules = try decoder.decode([LockRule].self, from: data)
            return rules.sorted { lhs, rhs in
                if lhs.startAt == rhs.startAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.startAt < rhs.startAt
            }
        } catch {
            // Backward compatibility for previous single-rule storage format.
            if let legacyRule = try? decoder.decode(LockRule.self, from: data) {
                return [legacyRule]
            }

            defaults.removeObject(forKey: OnlyLockShared.lockRuleStorageKey)
            throw LockRuleStorageError.decodingFailed
        }
    }

    func save(_ rule: LockRule) throws {
        try saveAll([rule])
    }

    func saveAll(_ rules: [LockRule]) throws {
        let orderedRules = rules.sorted { lhs, rhs in
            if lhs.startAt == rhs.startAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.startAt < rhs.startAt
        }

        guard !orderedRules.isEmpty else {
            defaults.removeObject(forKey: OnlyLockShared.lockRuleStorageKey)
            return
        }

        do {
            let data = try encoder.encode(orderedRules)
            defaults.set(data, forKey: OnlyLockShared.lockRuleStorageKey)
        } catch {
            throw LockRuleStorageError.encodingFailed
        }
    }

    func clear() {
        defaults.removeObject(forKey: OnlyLockShared.lockRuleStorageKey)
    }
}
