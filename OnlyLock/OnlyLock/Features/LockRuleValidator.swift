import FamilyControls
import Foundation

enum LockRuleValidationError: LocalizedError {
    case startMustBeInFuture
    case invalidDuration
    case invalidRepeatWeekdays
    case noTargetSelected
    case invalidManualDomain(String)
    case endTimeOverflow

    private var isEnglish: Bool {
        AppLanguageRuntime.currentLanguage == .english
    }

    var errorDescription: String? {
        switch self {
        case .startMustBeInFuture:
            return isEnglish ? "Start time must be later than now." : "开始时间必须晚于当前时间。"
        case .invalidDuration:
            return isEnglish ? "Lock duration must be an integer greater than 0 minutes." : "锁定时长必须是大于 0 的整数分钟。"
        case .invalidRepeatWeekdays:
            return isEnglish ? "Please select at least one repeat day." : "请至少选择一个重复日期。"
        case .noTargetSelected:
            return isEnglish ? "Please select at least one app or enter one website domain." : "请至少选择一个应用或输入一个网站域名。"
        case .invalidManualDomain(let domain):
            return isEnglish ? "Invalid website domain format: \(domain)" : "网站域名格式无效：\(domain)"
        case .endTimeOverflow:
            return isEnglish ? "Invalid lock end time. Adjust start time or duration." : "锁定结束时间无效，请调整开始时间或时长。"
        }
    }
}

struct LockRuleValidator {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func buildRule(
        name: String?,
        startAt: Date,
        durationMinutes: Int,
        isWeeklyRepeat: Bool,
        repeatWeekdays: Set<Int>,
        selection: FamilyActivitySelection,
        manualWebDomains: Set<String>,
        existing: LockRule? = nil,
        now: Date = Date()
    ) throws -> LockRule {
        let normalizedStartAt = normalizeToMinuteBoundary(startAt)

        try validate(
            startAt: normalizedStartAt,
            durationMinutes: durationMinutes,
            isWeeklyRepeat: isWeeklyRepeat,
            repeatWeekdays: repeatWeekdays,
            selection: selection,
            manualWebDomains: manualWebDomains,
            now: now
        )

        return LockRule.make(
            name: name,
            startAt: normalizedStartAt,
            durationMinutes: durationMinutes,
            isWeeklyRepeat: isWeeklyRepeat,
            repeatWeekdays: repeatWeekdays,
            applicationTokens: selection.applicationTokens,
            categoryTokens: selection.categoryTokens,
            webDomainTokens: selection.webDomainTokens,
            manualWebDomains: manualWebDomains,
            existingId: existing?.id,
            existingCreatedAt: existing?.createdAt,
            now: now
        )
    }

    func validate(
        startAt: Date,
        durationMinutes: Int,
        isWeeklyRepeat: Bool,
        repeatWeekdays: Set<Int>,
        selection: FamilyActivitySelection,
        manualWebDomains: Set<String>,
        now: Date = Date()
    ) throws {
        if !isWeeklyRepeat, startAt <= now {
            throw LockRuleValidationError.startMustBeInFuture
        }

        guard durationMinutes > 0 else {
            throw LockRuleValidationError.invalidDuration
        }

        if isWeeklyRepeat {
            let validWeekdays = repeatWeekdays.filter { (1...7).contains($0) }
            guard !validWeekdays.isEmpty else {
                throw LockRuleValidationError.invalidRepeatWeekdays
            }
        }

        guard
            !selection.applicationTokens.isEmpty ||
            !selection.categoryTokens.isEmpty ||
            !selection.webDomainTokens.isEmpty ||
            !manualWebDomains.isEmpty
        else {
            throw LockRuleValidationError.noTargetSelected
        }

        for domain in manualWebDomains {
            guard isValidManualDomain(domain) else {
                throw LockRuleValidationError.invalidManualDomain(domain)
            }
        }

        guard calendar.date(byAdding: .minute, value: durationMinutes, to: startAt) != nil else {
            throw LockRuleValidationError.endTimeOverflow
        }
    }

    private func normalizeToMinuteBoundary(_ date: Date) -> Date {
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    private func isValidManualDomain(_ domain: String) -> Bool {
        let normalized = domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty, normalized.count <= 253 else {
            return false
        }

        let pattern = #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }
}
