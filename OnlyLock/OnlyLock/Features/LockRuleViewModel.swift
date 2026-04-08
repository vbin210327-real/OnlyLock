import Combine
import FamilyControls
import Foundation
import ManagedSettings

@MainActor
final class LockRuleViewModel: ObservableObject {
    @Published var appPickerSelection = FamilyActivitySelection(includeEntireCategory: true)
    @Published var startAt: Date
    @Published var durationText: String
    @Published var isWeeklyRepeat = false
    @Published var repeatWeekdays: Set<Int> = []
    @Published var taskName = ""
    @Published var manualWebDomains: Set<String> = []
    @Published var isAppPickerPresented = false

    @Published private(set) var rules: [LockRule] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var infoMessage: String?
    @Published private(set) var applicationTokens: Set<ApplicationToken> = []
    @Published private(set) var categoryTokens: Set<ActivityCategoryToken> = []
    @Published private(set) var webDomainTokens: Set<WebDomainToken> = []
    private var applicationTokenDisplayOrder: [ApplicationToken] = []

    private let validator: LockRuleValidator
    private let scheduler: LockScheduler

    init(now: Date = Date()) {
        validator = LockRuleValidator()
        scheduler = LockScheduler()
        startAt = LockRuleViewModel.defaultStartAt(from: now)
        durationText = "30"

        loadRules()
    }

    init(
        validator: LockRuleValidator,
        scheduler: LockScheduler,
        now: Date = Date()
    ) {
        self.validator = validator
        self.scheduler = scheduler
        startAt = LockRuleViewModel.defaultStartAt(from: now)
        durationText = "30"

        loadRules()
    }

    var selectedAppCount: Int {
        applicationTokens.count
    }

    var selectedCategoryCount: Int {
        categoryTokens.count
    }

    var selectedWebCount: Int {
        manualWebDomains.count + webDomainTokens.count
    }

    var sortedManualWebDomains: [String] {
        manualWebDomains.sorted()
    }

    var orderedWebDomainTokens: [WebDomainToken] {
        webDomainTokens.sorted { lhs, rhs in
            String(describing: lhs) < String(describing: rhs)
        }
    }

    var orderedApplicationTokens: [ApplicationToken] {
        let ordered = applicationTokenDisplayOrder.filter { applicationTokens.contains($0) }
        let missing = sortedTokens(applicationTokens.subtracting(Set(ordered)))
        return ordered + missing
    }

    var hasSelection: Bool {
        selectedAppCount > 0 || selectedWebCount > 0 || !categoryTokens.isEmpty
    }

    var totalTargetCount: Int {
        selectedAppCount + selectedCategoryCount + selectedWebCount
    }

    var durationMinutesValue: Int? {
        Int(durationText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var canSave: Bool {
        hasSelection &&
            (durationMinutesValue ?? 0) > 0 &&
            (!isWeeklyRepeat || !repeatWeekdays.isEmpty)
    }

    func applyDuration(minutes: Int) {
        durationText = String(minutes)
    }

    func presentAppPicker() {
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.applicationTokens = applicationTokens
        selection.categoryTokens = categoryTokens
        selection.webDomainTokens = webDomainTokens
        appPickerSelection = selection
        isAppPickerPresented = true
    }

    func commitAppPickerSelection() {
        let nextTokens = appPickerSelection.applicationTokens
        let previousTokens = applicationTokens
        applicationTokens = nextTokens
        categoryTokens = appPickerSelection.categoryTokens
        webDomainTokens = appPickerSelection.webDomainTokens
        updateApplicationDisplayOrder(previous: previousTokens, current: nextTokens)
    }

    @discardableResult
    func requestSave(isAuthorized: Bool) async -> Bool {
        errorMessage = nil
        infoMessage = nil

        guard isAuthorized else {
            errorMessage = AppLanguageRuntime.currentLanguage == .english
                ? "Please complete Screen Time authorization first."
                : "请先完成 Screen Time 授权。"
            return false
        }

        guard let durationMinutes = Int(durationText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = LockRuleValidationError.invalidDuration.localizedDescription
            return false
        }

        do {
            var selection = FamilyActivitySelection(includeEntireCategory: true)
            selection.applicationTokens = applicationTokens
            selection.categoryTokens = categoryTokens
            selection.webDomainTokens = webDomainTokens

            let trimmedTaskName = normalizedTaskName(taskName)

            let rule = try validator.buildRule(
                name: trimmedTaskName,
                startAt: startAt,
                durationMinutes: durationMinutes,
                isWeeklyRepeat: isWeeklyRepeat,
                repeatWeekdays: repeatWeekdays,
                selection: selection,
                manualWebDomains: manualWebDomains,
                existing: nil
            )
            try await scheduler.saveAndSchedule(rule: rule)
            loadRules()
            infoMessage = AppLanguageRuntime.currentLanguage == .english
                ? "Lock task created."
                : "锁定任务已创建。"
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func presentExternalError(_ message: String) {
        infoMessage = nil
        errorMessage = message
    }

    func presentExternalInfo(_ message: String) {
        errorMessage = nil
        infoMessage = message
    }

    func clearExternalMessages() {
        infoMessage = nil
        errorMessage = nil
    }

    func resetCreateForm() {
        resetCreateFormState(clearMessages: true)
    }

    func deleteRule(id: UUID) {
        scheduler.deleteRule(id: id)
        loadRules()
    }

    func addManualWebDomain(_ rawValue: String) {
        let normalized = normalizeDomain(rawValue)
        guard !normalized.isEmpty else {
            return
        }

        manualWebDomains.insert(normalized)
    }

    func removeManualWebDomain(_ domain: String) {
        manualWebDomains.remove(domain)
    }

    func removeApplicationToken(_ token: ApplicationToken) {
        guard applicationTokens.contains(token) else { return }

        applicationTokens.remove(token)
        applicationTokenDisplayOrder.removeAll { $0 == token }

        var selection = appPickerSelection
        selection.applicationTokens = applicationTokens
        selection.categoryTokens = categoryTokens
        selection.webDomainTokens = webDomainTokens
        appPickerSelection = selection

        errorMessage = nil
        infoMessage = nil
    }

    func removeWebDomainToken(_ token: WebDomainToken) {
        guard webDomainTokens.contains(token) else { return }

        webDomainTokens.remove(token)

        var selection = appPickerSelection
        selection.applicationTokens = applicationTokens
        selection.categoryTokens = categoryTokens
        selection.webDomainTokens = webDomainTokens
        appPickerSelection = selection

        errorMessage = nil
        infoMessage = nil
    }

    private func loadRules() {
        do {
            rules = try scheduler.currentRules()
            // Keep "新建锁定" as a clean draft workspace even when an active rule exists.
            resetCreateFormState(clearMessages: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetCreateFormState(clearMessages: Bool) {
        if clearMessages {
            errorMessage = nil
            infoMessage = nil
        }

        startAt = Self.defaultStartAt(from: Date())
        durationText = "30"
        isWeeklyRepeat = false
        repeatWeekdays = []
        taskName = ""
        appPickerSelection = FamilyActivitySelection(includeEntireCategory: true)
        applicationTokens = []
        categoryTokens = []
        webDomainTokens = []
        applicationTokenDisplayOrder = []
        manualWebDomains = []
    }

    private func normalizedTaskName(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func defaultStartAt(from now: Date) -> Date {
        let calendar = Calendar.current
        let raw = calendar.date(byAdding: .minute, value: 5, to: now) ?? now
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: raw)
        components.second = 0
        return calendar.date(from: components) ?? raw
    }

    private func normalizeDomain(_ rawInput: String) -> String {
        var value = rawInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

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

    private func updateApplicationDisplayOrder(
        previous: Set<ApplicationToken>,
        current: Set<ApplicationToken>
    ) {
        let kept = applicationTokenDisplayOrder.filter { current.contains($0) }
        let added = sortedTokens(current.subtracting(previous))

        applicationTokenDisplayOrder = added + kept

        let missing = current.subtracting(Set(applicationTokenDisplayOrder))
        if !missing.isEmpty {
            applicationTokenDisplayOrder.append(contentsOf: sortedTokens(missing))
        }
    }

    private func sortedTokens(_ tokens: Set<ApplicationToken>) -> [ApplicationToken] {
        tokens.sorted { lhs, rhs in
            String(describing: lhs) < String(describing: rhs)
        }
    }

}
