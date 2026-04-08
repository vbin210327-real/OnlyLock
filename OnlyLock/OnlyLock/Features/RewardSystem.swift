import Combine
import CoreData
import Foundation
import WidgetKit

struct RewardRecentEvent: Identifiable, Equatable {
    let eventID: String
    let ruleID: UUID?
    let completedAt: Date
    let durationMinutes: Int
    let xpGained: Int
    let isWeeklyRepeat: Bool

    var id: String { eventID }
}

struct RewardBadgeDefinition: Equatable {
    enum Condition: Equatable {
        case bestStreak(Int)
        case totalCompletions(Int)
        case totalMinutes(Int)
    }

    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let condition: Condition
}

struct RewardProfileSnapshot: Equatable {
    let totalXP: Int
    let level: Int
    let currentStreak: Int
    let bestStreak: Int
    let totalCompletions: Int
    let totalMinutes: Int
    let levelStartXP: Int
    let nextLevelXP: Int?
    let levelProgress: Double
    let completedDays: Set<Date>
    let unlockedBadgeIDs: Set<String>
    let recentEvents: [RewardRecentEvent]

    static let empty = RewardProfileSnapshot(
        totalXP: 0,
        level: 1,
        currentStreak: 0,
        bestStreak: 0,
        totalCompletions: 0,
        totalMinutes: 0,
        levelStartXP: 0,
        nextLevelXP: RewardEngine.nextLevelXP(for: 1),
        levelProgress: 0,
        completedDays: [],
        unlockedBadgeIDs: [],
        recentEvents: []
    )
}

enum RewardEngine {
    static let levelThresholds: [Int] = [0, 100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200]
    static let streakMedalTiers: [Int] = [3, 7, 14, 30, 60, 100, 365]

    enum StreakMedalVisualLevel: Int, Equatable {
        case locked
        case bronze
        case silver
        case gold
        case radiantGold
        case platinum
        case crystal
        case legendary
    }

    static let badgeDefinitions: [RewardBadgeDefinition] = [
        RewardBadgeDefinition(id: "streak_3", title: "连胜3天", subtitle: "稳定开局", symbol: "flame.fill", condition: .bestStreak(3)),
        RewardBadgeDefinition(id: "streak_7", title: "连胜7天", subtitle: "进入节奏", symbol: "flame.fill", condition: .bestStreak(7)),
        RewardBadgeDefinition(id: "streak_14", title: "连胜14天", subtitle: "专注成习惯", symbol: "flame.fill", condition: .bestStreak(14)),
        RewardBadgeDefinition(id: "streak_30", title: "连胜30天", subtitle: "月度坚持", symbol: "flame.fill", condition: .bestStreak(30)),
        RewardBadgeDefinition(id: "streak_60", title: "连胜60天", subtitle: "稳态专注", symbol: "flame.fill", condition: .bestStreak(60)),
        RewardBadgeDefinition(id: "streak_100", title: "连胜100天", subtitle: "百日专注", symbol: "flame.fill", condition: .bestStreak(100)),
        RewardBadgeDefinition(id: "streak_365", title: "连胜365天", subtitle: "年度勋章", symbol: "flame.fill", condition: .bestStreak(365)),
        RewardBadgeDefinition(id: "sessions_10", title: "完成10次", subtitle: "初试锋芒", symbol: "checkmark.seal.fill", condition: .totalCompletions(10)),
        RewardBadgeDefinition(id: "sessions_50", title: "完成50次", subtitle: "稳定执行", symbol: "checkmark.seal.fill", condition: .totalCompletions(50)),
        RewardBadgeDefinition(id: "sessions_100", title: "完成100次", subtitle: "执行力升级", symbol: "checkmark.seal.fill", condition: .totalCompletions(100)),
        RewardBadgeDefinition(id: "sessions_300", title: "完成300次", subtitle: "深度实践", symbol: "checkmark.seal.fill", condition: .totalCompletions(300)),
        RewardBadgeDefinition(id: "minutes_300", title: "300分钟", subtitle: "专注起步", symbol: "clock.fill", condition: .totalMinutes(300)),
        RewardBadgeDefinition(id: "minutes_1000", title: "1000分钟", subtitle: "进入状态", symbol: "clock.fill", condition: .totalMinutes(1000)),
        RewardBadgeDefinition(id: "minutes_5000", title: "5000分钟", subtitle: "专注大师", symbol: "clock.fill", condition: .totalMinutes(5000))
    ]

    static func xp(for durationMinutes: Int) -> Int {
        let base = 20
        let bonus: Int
        switch durationMinutes {
        case ..<30:
            bonus = 0
        case 30..<60:
            bonus = 5
        case 60..<120:
            bonus = 10
        default:
            bonus = 15
        }
        return base + bonus
    }

    static func level(for totalXP: Int) -> Int {
        for (index, threshold) in levelThresholds.enumerated().reversed() {
            if totalXP >= threshold {
                return index + 1
            }
        }
        return 1
    }

    static func nextLevelXP(for level: Int) -> Int? {
        guard level < levelThresholds.count else { return nil }
        return levelThresholds[level]
    }

    static func levelStartXP(for level: Int) -> Int {
        let index = max(0, min(level - 1, levelThresholds.count - 1))
        return levelThresholds[index]
    }

    static func progress(totalXP: Int, level: Int) -> Double {
        guard let next = nextLevelXP(for: level) else { return 1 }
        let start = levelStartXP(for: level)
        guard next > start else { return 1 }
        let ratio = Double(totalXP - start) / Double(next - start)
        return max(0, min(1, ratio))
    }

    static func unlockedBadgeIDs(totalCompletions: Int, totalMinutes: Int, bestStreak: Int) -> Set<String> {
        var ids: Set<String> = []
        for definition in badgeDefinitions {
            let unlocked: Bool
            switch definition.condition {
            case let .bestStreak(value):
                unlocked = bestStreak >= value
            case let .totalCompletions(value):
                unlocked = totalCompletions >= value
            case let .totalMinutes(value):
                unlocked = totalMinutes >= value
            }
            if unlocked {
                ids.insert(definition.id)
            }
        }
        return ids
    }

    static func highestUnlockedStreakTier(bestStreak: Int) -> Int? {
        streakMedalTiers.last(where: { bestStreak >= $0 })
    }

    static func nextStreakTier(bestStreak: Int) -> Int? {
        streakMedalTiers.first(where: { bestStreak < $0 })
    }

    static func displayedStreakNumber(bestStreak: Int) -> Int {
        let cappedTop = streakMedalTiers.last ?? 365
        return min(max(0, bestStreak), cappedTop)
    }

    static func streakMedalVisualLevel(bestStreak: Int) -> StreakMedalVisualLevel {
        guard let tier = highestUnlockedStreakTier(bestStreak: bestStreak) else {
            return .locked
        }

        switch tier {
        case 3:
            return .bronze
        case 7:
            return .silver
        case 14:
            return .gold
        case 30:
            return .radiantGold
        case 60:
            return .platinum
        case 100:
            return .crystal
        case 365:
            return .legendary
        default:
            return .locked
        }
    }
}

final class RewardStore {
    static let shared = RewardStore()

    private enum Entity {
        static let event = "RewardEventEntity"
        static let profile = "RewardProfileEntity"
        static let badge = "RewardBadgeEntity"
    }

    private enum EventField {
        static let eventID = "eventID"
        static let ruleID = "ruleID"
        static let completedAt = "completedAt"
        static let durationMinutes = "durationMinutes"
        static let isWeeklyRepeat = "isWeeklyRepeat"
    }

    private enum ProfileField {
        static let profileID = "profileID"
        static let totalXP = "totalXP"
        static let level = "level"
        static let currentStreak = "currentStreak"
        static let bestStreak = "bestStreak"
        static let totalCompletions = "totalCompletions"
        static let totalMinutes = "totalMinutes"
        static let lastComputedAt = "lastComputedAt"
    }

    private enum BadgeField {
        static let badgeID = "badgeID"
        static let unlockedAt = "unlockedAt"
    }

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let lock = NSLock()
    private let calendar = Calendar.current
    private let container: NSPersistentCloudKitContainer

    init(userDefaults: UserDefaults? = nil) {
        let sharedDefaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier)
        defaults = userDefaults ?? sharedDefaults ?? .standard
        container = Self.makeContainer()
    }

    func importInboxEventsAndRefresh(
        seedFromLegacyStreak: Int,
        fallbackCompletedDays: Set<Date> = [],
        now: Date
    ) -> RewardProfileSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let incomingEvents = consumeInboxEvents()
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var snapshot = RewardProfileSnapshot.empty

        context.performAndWait {
            do {
                let existingEventIDs = try fetchExistingEventIDs(context: context)
                try insert(events: incomingEvents, skipping: existingEventIDs, context: context)
                try seedLegacyEventsIfNeeded(streak: seedFromLegacyStreak, now: now, context: context)
                snapshot = try recomputeSnapshot(
                    now: now,
                    fallbackCompletedDays: fallbackCompletedDays,
                    context: context
                )
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                snapshot = fallbackSnapshot(now: now, context: context)
            }
        }

        return snapshot
    }

    private static func makeContainer() -> NSPersistentCloudKitContainer {
        if let cloudContainer = try? loadContainer(enableCloudSync: true) {
            return cloudContainer
        }
        if let localContainer = try? loadContainer(enableCloudSync: false) {
            return localContainer
        }

        let inMemoryContainer = NSPersistentCloudKitContainer(name: "OnlyLock")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        inMemoryContainer.persistentStoreDescriptions = [description]

        let semaphore = DispatchSemaphore(value: 0)
        inMemoryContainer.loadPersistentStores { _, _ in
            semaphore.signal()
        }
        semaphore.wait()

        inMemoryContainer.viewContext.automaticallyMergesChangesFromParent = true
        inMemoryContainer.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return inMemoryContainer
    }

    private static func loadContainer(enableCloudSync: Bool) throws -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "OnlyLock")
        guard let description = container.persistentStoreDescriptions.first else {
            throw NSError(domain: "RewardStore", code: 1, userInfo: nil)
        }

        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if enableCloudSync {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: OnlyLockShared.cloudKitContainerIdentifier
            )
        } else {
            description.cloudKitContainerOptions = nil
        }

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let loadError {
            throw loadError
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }

    private func consumeInboxEvents() -> [RewardCompletionEvent] {
        let allKeys = defaults.dictionaryRepresentation().keys
        let targetKeys = allKeys.filter { $0.hasPrefix(OnlyLockShared.rewardEventKeyPrefix) }

        var events: [RewardCompletionEvent] = []

        for key in targetKeys.sorted() {
            defer { defaults.removeObject(forKey: key) }

            guard let data = defaults.data(forKey: key),
                  let event = try? decoder.decode(RewardCompletionEvent.self, from: data) else {
                continue
            }
            events.append(event)
        }

        defaults.set(Date().timeIntervalSince1970, forKey: OnlyLockShared.rewardLastImportAtKey)
        return events
    }

    private func fetchExistingEventIDs(context: NSManagedObjectContext) throws -> Set<String> {
        let request = NSFetchRequest<NSDictionary>(entityName: Entity.event)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [EventField.eventID]
        let results = try context.fetch(request)
        return Set(results.compactMap { $0[EventField.eventID] as? String })
    }

    private func insert(events: [RewardCompletionEvent], skipping existingEventIDs: Set<String>, context: NSManagedObjectContext) throws {
        guard !events.isEmpty else { return }

        var knownEventIDs = existingEventIDs
        for event in events {
            if knownEventIDs.contains(event.eventID) {
                continue
            }

            guard let entity = NSEntityDescription.entity(forEntityName: Entity.event, in: context) else { continue }
            let object = NSManagedObject(entity: entity, insertInto: context)
            object.setValue(event.eventID, forKey: EventField.eventID)
            object.setValue(event.ruleID.uuidString.lowercased(), forKey: EventField.ruleID)
            object.setValue(event.completedAt, forKey: EventField.completedAt)
            object.setValue(Int64(event.durationMinutes), forKey: EventField.durationMinutes)
            object.setValue(event.isWeeklyRepeat, forKey: EventField.isWeeklyRepeat)
            knownEventIDs.insert(event.eventID)
        }
    }

    private func seedLegacyEventsIfNeeded(streak: Int, now: Date, context: NSManagedObjectContext) throws {
        if defaults.bool(forKey: OnlyLockShared.rewardSeededLegacyKey) {
            return
        }

        let countRequest = NSFetchRequest<NSManagedObject>(entityName: Entity.event)
        let existingCount = try context.count(for: countRequest)

        guard existingCount == 0, streak > 0 else {
            if existingCount > 0 {
                defaults.set(true, forKey: OnlyLockShared.rewardSeededLegacyKey)
            }
            return
        }

        let today = calendar.startOfDay(for: now)
        guard let entity = NSEntityDescription.entity(forEntityName: Entity.event, in: context) else { return }

        for offset in 0..<streak {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let completedAt = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else {
                continue
            }

            let eventID = "legacy-seed-\(Int(completedAt.timeIntervalSince1970))"
            let object = NSManagedObject(entity: entity, insertInto: context)
            object.setValue(eventID, forKey: EventField.eventID)
            object.setValue("legacy", forKey: EventField.ruleID)
            object.setValue(completedAt, forKey: EventField.completedAt)
            object.setValue(Int64(30), forKey: EventField.durationMinutes)
            object.setValue(false, forKey: EventField.isWeeklyRepeat)
        }

        defaults.set(true, forKey: OnlyLockShared.rewardSeededLegacyKey)
    }

    private func recomputeSnapshot(
        now: Date,
        fallbackCompletedDays: Set<Date>,
        context: NSManagedObjectContext
    ) throws -> RewardProfileSnapshot {
        let eventsFetch = NSFetchRequest<NSManagedObject>(entityName: Entity.event)
        let events = try context.fetch(eventsFetch)

        var totalXP = 0
        var totalCompletions = 0
        var totalMinutes = 0
        var completedDays: Set<Date> = []

        for event in events {
            let duration = Int(event.value(forKey: EventField.durationMinutes) as? Int64 ?? 0)
            totalXP += RewardEngine.xp(for: duration)
            totalCompletions += 1
            totalMinutes += duration

            if let completedAt = event.value(forKey: EventField.completedAt) as? Date {
                completedDays.insert(calendar.startOfDay(for: completedAt))
            }
        }

        completedDays.formUnion(fallbackCompletedDays.map { calendar.startOfDay(for: $0) })

        let bestStreak = bestStreakCount(from: completedDays)
        let currentStreak = currentStreakCount(from: completedDays, at: now)
        let level = RewardEngine.level(for: totalXP)
        let levelStartXP = RewardEngine.levelStartXP(for: level)
        let nextLevelXP = RewardEngine.nextLevelXP(for: level)
        let progress = RewardEngine.progress(totalXP: totalXP, level: level)

        let computedBadgeIDs = RewardEngine.unlockedBadgeIDs(
            totalCompletions: totalCompletions,
            totalMinutes: totalMinutes,
            bestStreak: bestStreak
        )
        let unlockedBadgeIDs = try syncBadges(unlocked: computedBadgeIDs, context: context)

        let profile = try fetchOrCreateProfileEntity(context: context)
        profile.setValue("default", forKey: ProfileField.profileID)
        profile.setValue(Int64(totalXP), forKey: ProfileField.totalXP)
        profile.setValue(Int16(level), forKey: ProfileField.level)
        profile.setValue(Int32(currentStreak), forKey: ProfileField.currentStreak)
        profile.setValue(Int32(bestStreak), forKey: ProfileField.bestStreak)
        profile.setValue(Int64(totalCompletions), forKey: ProfileField.totalCompletions)
        profile.setValue(Int64(totalMinutes), forKey: ProfileField.totalMinutes)
        profile.setValue(now, forKey: ProfileField.lastComputedAt)

        let recentEvents = try fetchRecentEvents(context: context)

        return RewardProfileSnapshot(
            totalXP: totalXP,
            level: level,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            totalCompletions: totalCompletions,
            totalMinutes: totalMinutes,
            levelStartXP: levelStartXP,
            nextLevelXP: nextLevelXP,
            levelProgress: progress,
            completedDays: completedDays,
            unlockedBadgeIDs: unlockedBadgeIDs,
            recentEvents: recentEvents
        )
    }

    private func fetchOrCreateProfileEntity(context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.profile)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }

        guard let entity = NSEntityDescription.entity(forEntityName: Entity.profile, in: context) else {
            throw NSError(domain: "RewardStore", code: 2, userInfo: nil)
        }

        let object = NSManagedObject(entity: entity, insertInto: context)
        object.setValue("default", forKey: ProfileField.profileID)
        return object
    }

    private func syncBadges(unlocked computedBadgeIDs: Set<String>, context: NSManagedObjectContext) throws -> Set<String> {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.badge)
        let existingBadges = try context.fetch(request)

        var existingIDs: Set<String> = []
        for badge in existingBadges {
            if let badgeID = badge.value(forKey: BadgeField.badgeID) as? String {
                existingIDs.insert(badgeID)
            }
        }

        let newBadgeIDs = computedBadgeIDs.subtracting(existingIDs)
        if !newBadgeIDs.isEmpty,
           let entity = NSEntityDescription.entity(forEntityName: Entity.badge, in: context) {
            for badgeID in newBadgeIDs {
                let badge = NSManagedObject(entity: entity, insertInto: context)
                badge.setValue(badgeID, forKey: BadgeField.badgeID)
                badge.setValue(Date(), forKey: BadgeField.unlockedAt)
                existingIDs.insert(badgeID)
            }
        }

        return existingIDs
    }

    private func fetchRecentEvents(context: NSManagedObjectContext) throws -> [RewardRecentEvent] {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.event)
        request.sortDescriptors = [NSSortDescriptor(key: EventField.completedAt, ascending: false)]
        request.fetchLimit = 20

        return try context.fetch(request).compactMap { object in
            guard let eventID = object.value(forKey: EventField.eventID) as? String,
                  let completedAt = object.value(forKey: EventField.completedAt) as? Date else {
                return nil
            }

            let durationMinutes = Int(object.value(forKey: EventField.durationMinutes) as? Int64 ?? 0)
            let ruleIDString = object.value(forKey: EventField.ruleID) as? String
            let ruleID = ruleIDString.flatMap(UUID.init(uuidString:))
            let isWeeklyRepeat = object.value(forKey: EventField.isWeeklyRepeat) as? Bool ?? false

            return RewardRecentEvent(
                eventID: eventID,
                ruleID: ruleID,
                completedAt: completedAt,
                durationMinutes: durationMinutes,
                xpGained: RewardEngine.xp(for: durationMinutes),
                isWeeklyRepeat: isWeeklyRepeat
            )
        }
    }

    private func currentStreakCount(from completedDays: Set<Date>, at now: Date) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: now)

        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: previous)
        }

        return streak
    }

    private func bestStreakCount(from completedDays: Set<Date>) -> Int {
        let sortedDays = completedDays.sorted()
        guard !sortedDays.isEmpty else { return 0 }

        var best = 1
        var running = 1

        for index in 1..<sortedDays.count {
            let previous = sortedDays[index - 1]
            let current = sortedDays[index]
            if let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(expected, inSameDayAs: current) {
                running += 1
            } else {
                running = 1
            }
            best = max(best, running)
        }

        return best
    }

    private func fallbackSnapshot(now: Date, context: NSManagedObjectContext) -> RewardProfileSnapshot {
        let request = NSFetchRequest<NSManagedObject>(entityName: Entity.profile)
        request.fetchLimit = 1

        guard let profile = try? context.fetch(request).first else {
            return .empty
        }

        let totalXP = Int(profile.value(forKey: ProfileField.totalXP) as? Int64 ?? 0)
        let level = Int(profile.value(forKey: ProfileField.level) as? Int16 ?? 1)
        let currentStreak = Int(profile.value(forKey: ProfileField.currentStreak) as? Int32 ?? 0)
        let bestStreak = Int(profile.value(forKey: ProfileField.bestStreak) as? Int32 ?? 0)
        let totalCompletions = Int(profile.value(forKey: ProfileField.totalCompletions) as? Int64 ?? 0)
        let totalMinutes = Int(profile.value(forKey: ProfileField.totalMinutes) as? Int64 ?? 0)

        return RewardProfileSnapshot(
            totalXP: totalXP,
            level: level,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            totalCompletions: totalCompletions,
            totalMinutes: totalMinutes,
            levelStartXP: RewardEngine.levelStartXP(for: level),
            nextLevelXP: RewardEngine.nextLevelXP(for: level),
            levelProgress: RewardEngine.progress(totalXP: totalXP, level: level),
            completedDays: [],
            unlockedBadgeIDs: [],
            recentEvents: []
        )
    }
}

@MainActor
final class RewardViewModel: ObservableObject {
    @Published private(set) var snapshot: RewardProfileSnapshot = .empty

    private let store: RewardStore
    private var isRefreshing = false

    init(store: RewardStore? = nil) {
        self.store = store ?? RewardStore.shared
    }

    func refresh(seedFromRules rules: [LockRule], now: Date = Date()) {
        guard !isRefreshing else { return }
        isRefreshing = true

        let legacyStreak = RewardLegacySeeder.legacyStreak(from: rules, now: now)
        let fallbackCompletedDays = RewardLegacySeeder.completedDaysForScheduleFallback(from: rules, now: now)

        DispatchQueue.global(qos: .utility).async { [store] in
            let snapshot = store.importInboxEventsAndRefresh(
                seedFromLegacyStreak: legacyStreak,
                fallbackCompletedDays: fallbackCompletedDays,
                now: now
            )

            DispatchQueue.main.async {
                self.snapshot = snapshot
                self.syncWidgetStreak(streak: snapshot.currentStreak, now: now)
                self.isRefreshing = false
            }
        }
    }

    private func syncWidgetStreak(streak: Int, now: Date) {
        let defaults = UserDefaults(suiteName: OnlyLockShared.appGroupIdentifier) ?? .standard
        defaults.set(streak, forKey: OnlyLockShared.widgetCurrentStreakKey)
        if streak > 0 {
            let startOfDay = Calendar.current.startOfDay(for: now)
            defaults.set(
                startOfDay.timeIntervalSince1970,
                forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey
            )
        } else {
            defaults.removeObject(forKey: OnlyLockShared.widgetLastCheckInDayTimestampKey)
        }
        defaults.synchronize()
        WidgetCenter.shared.reloadTimelines(ofKind: "OnlyLockStreakWidgetV4")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

enum RewardLegacySeeder {
    static func legacyStreak(from rules: [LockRule], now: Date) -> Int {
        let completedDays = completedDaysForScheduleFallback(from: rules, now: now)
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: now)
        var streak = 0

        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = calendar.startOfDay(for: previous)
        }

        return streak
    }

    static func completedDaysForScheduleFallback(from rules: [LockRule], now: Date) -> Set<Date> {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var completedDays: Set<Date> = []

        for rule in rules {
            if !rule.isWeeklyRepeat {
                guard rule.startAt <= now else { continue }
                completedDays.insert(calendar.startOfDay(for: rule.startAt))
                continue
            }

            let weekdays = rule.repeatWeekdays.filter { (1...7).contains($0) }
            guard !weekdays.isEmpty else { continue }

            let firstDay = calendar.startOfDay(for: rule.startAt)
            guard firstDay <= today else { continue }

            let startHour = calendar.component(.hour, from: rule.startAt)
            let startMinute = calendar.component(.minute, from: rule.startAt)

            var cursor = firstDay
            while cursor <= today {
                let weekday = calendar.component(.weekday, from: cursor)
                if weekdays.contains(weekday),
                   let start = calendar.date(
                        bySettingHour: startHour,
                        minute: startMinute,
                        second: 0,
                        of: cursor
                   ),
                   start <= now {
                    completedDays.insert(calendar.startOfDay(for: cursor))
                }

                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                    break
                }
                cursor = calendar.startOfDay(for: next)
            }
        }

        return completedDays
    }
}
