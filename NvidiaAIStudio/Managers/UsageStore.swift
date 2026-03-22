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
}
