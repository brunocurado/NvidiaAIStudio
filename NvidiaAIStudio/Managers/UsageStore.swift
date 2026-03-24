import Foundation

/// Persists and aggregates token usage across sessions.
/// All data is stored locally in UserDefaults — nothing leaves the device.
final class UsageStore {
    static let shared = UsageStore()
    private let key = "usageRecords"
    private init() {}

    // MARK: - Record

    struct Record: Codable, Identifiable {
        let id: UUID
        let date: Date
        let provider: String          // Provider.rawValue
        let modelID: String
        let modelName: String
        let sessionTitle: String
        let promptTokens: Int
        let completionTokens: Int
        var totalTokens: Int { promptTokens + completionTokens }
    }

    // MARK: - Read / Write

    func load() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([Record].self, from: data) else {
            return []
        }
        return records
    }

    func append(_ record: Record) {
        var records = load()
        records.append(record)
        // Keep last 1000 records to avoid unbounded growth
        if records.count > 1000 { records = Array(records.suffix(1000)) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Aggregates

    /// Total tokens ever used.
    func totalTokens() -> Int {
        load().reduce(0) { $0 + $1.totalTokens }
    }

    /// Tokens used today.
    func tokensToday() -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return load()
            .filter { $0.date >= today }
            .reduce(0) { $0 + $1.totalTokens }
    }

    /// Tokens used in the last 7 days, grouped by day.
    /// Returns array of (date label, tokens) sorted oldest → newest.
    func tokensByDay(days: Int = 7) -> [(label: String, tokens: Int)] {
        let cal = Calendar.current
        let records = load()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<days).reversed().map { offset -> (String, Int) in
            let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date()))!
            let nextDay = cal.date(byAdding: .day, value: 1, to: day)!
            let total = records
                .filter { $0.date >= day && $0.date < nextDay }
                .reduce(0) { $0 + $1.totalTokens }
            return (formatter.string(from: day), total)
        }
    }

    /// Tokens grouped by provider.
    func tokensByProvider() -> [(provider: String, tokens: Int)] {
        var byProvider: [String: Int] = [:]
        for r in load() {
            byProvider[r.provider, default: 0] += r.totalTokens
        }
        return byProvider
            .map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }

    /// Top models by token usage.
    func topModels(limit: Int = 5) -> [(modelName: String, tokens: Int)] {
        var byModel: [String: (name: String, tokens: Int)] = [:]
        for r in load() {
            let existing = byModel[r.modelID]?.tokens ?? 0
            byModel[r.modelID] = (r.modelName, existing + r.totalTokens)
        }
        return byModel.values
            .sorted { $0.tokens > $1.tokens }
            .prefix(limit)
            .map { ($0.name, $0.tokens) }
    }

    // MARK: - Heatmap & Streaks

    /// Returns a 2D array for heatmap: [weekday 0-6][week 0-52] = token count
    func tokensByWeekdayAndWeek() -> [[Int]] {
        let calendar = Calendar.current
        let now = Date()
        var grid = Array(repeating: Array(repeating: 0, count: 53), count: 7)
        let records = load()

        for record in records {
            let weeksAgo = calendar.dateComponents([.weekOfYear], from: record.date, to: now).weekOfYear ?? 53
            guard weeksAgo < 53 && weeksAgo >= 0 else { continue }
            let weekday = (calendar.component(.weekday, from: record.date) + 5) % 7  // Mon=0, Sun=6
            let weekCol = 52 - weeksAgo
            grid[weekday][weekCol] += record.totalTokens
        }
        return grid
    }

    /// Total input tokens
    func totalInputTokens() -> Int {
        load().reduce(0) { $0 + $1.promptTokens }
    }

    /// Total output tokens
    func totalOutputTokens() -> Int {
        load().reduce(0) { $0 + $1.completionTokens }
    }

    /// Longest streak (consecutive days with usage)
    func longestStreak() -> Int {
        let records = load()
        let calendar = Calendar.current
        let uniqueDays = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted()
        guard !uniqueDays.isEmpty else { return 0 }

        var longest = 1, current = 1
        for i in 1..<uniqueDays.count {
            if let next = calendar.date(byAdding: .day, value: 1, to: uniqueDays[i-1]),
               calendar.isDate(uniqueDays[i], inSameDayAs: next) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    /// Current streak (consecutive days ending today or yesterday)
    func currentStreak() -> Int {
        let records = load()
        let calendar = Calendar.current
        let uniqueDays = Set(records.map { calendar.startOfDay(for: $0.date) }).sorted().reversed()
        guard let first = uniqueDays.first,
              calendar.isDateInToday(first) || calendar.isDateInYesterday(first) else { return 0 }

        var streak = 1
        var prev = first
        for day in uniqueDays.dropFirst() {
            if let expected = calendar.date(byAdding: .day, value: -1, to: prev),
               calendar.isDate(day, inSameDayAs: expected) {
                streak += 1
                prev = day
            } else {
                break
            }
        }
        return streak
    }

    /// Unique sessions in last 30 days
    func sessionsInLast30Days() -> Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return 0 }
        return Set(load().filter { $0.date >= cutoff }.map { $0.sessionTitle }).count
    }

    /// Message count in last 7 days
    func messagesInLast7Days() -> Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return load().filter { $0.date >= cutoff }.count
    }

    /// Week usage as percentage
    func weekUsagePercent() -> Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        guard let weekStart = calendar.date(from: startOfWeek) else { return 0 }
        let thisWeek = load().filter { $0.date >= weekStart }.reduce(0) { $0 + $1.totalTokens }
        let allTime = totalTokens()
        guard allTime > 0 else { return 0 }
        let firstDate = load().first?.date ?? Date()
        let weeks = max(1, calendar.dateComponents([.weekOfYear], from: firstDate, to: Date()).weekOfYear ?? 1)
        let avgWeekly = max(1, allTime / weeks)
        return min(100, thisWeek * 100 / avgWeekly)
    }

    /// Number of unique projects (workspace paths)
    func projectCount() -> Int {
        // Derive from session titles — unique first-word groupings
        Set(load().map { $0.provider }).count
    }

    /// Sessions active today
    func sessionsActiveToday() -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return Set(load().filter { $0.date >= today }.map { $0.sessionTitle }).count
    }
}
