import Foundation

/// Persists sessions to disk as JSON files.
/// Each session is saved to: ~/Library/Application Support/NvidiaAIStudio/sessions/<id>.json
actor SessionStore {
    
    private let sessionsDir: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        sessionsDir = appSupport.appendingPathComponent("NvidiaAIStudio/sessions", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
    }
    
    /// Load all sessions from disk, sorted by update date.
    /// Only loads metadata (title, dates, id) — messages are loaded on demand.
    func loadAll() -> [Session] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        
        let sessions: [Session] = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let session = try? decoder.decode(Session.self, from: data)
                else { return nil }
                return session
            }
            .sorted { $0.updatedAt > $1.updatedAt }
        
        // Trim: keep only the last 50 messages per session in memory
        return sessions.map { session in
            var trimmed = session
            if trimmed.messages.count > 50 {
                let kept = Array(trimmed.messages.suffix(50))
                trimmed.messages = kept
            }
            return trimmed
        }
    }
    
    /// Save a single session to disk.
    func save(_ session: Session) {
        let fileURL = sessionsDir.appendingPathComponent("\(session.id.uuidString).json")
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
    
    /// Delete a session from disk.
    func delete(id: UUID) {
        let fileURL = sessionsDir.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Save all sessions.
    func saveAll(_ sessions: [Session]) {
        for session in sessions {
            save(session)
        }
    }
}
