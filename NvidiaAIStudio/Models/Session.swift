import Foundation

/// A chat session (thread) containing messages.
struct Session: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var messages: [Message]
    var modelID: String
    let createdAt: Date
    var updatedAt: Date
    var projectPath: String?
    
    /// Active background agents for this session
    var backgroundAgents: [BackgroundAgent]
    
    init(
        id: UUID = UUID(),
        title: String = "New Thread",
        messages: [Message] = [],
        modelID: String = "deepseek-ai/deepseek-v3.2",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        projectPath: String? = nil,
        backgroundAgents: [BackgroundAgent] = []
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.modelID = modelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectPath = projectPath
        self.backgroundAgents = backgroundAgents
    }
    
    /// Returns a relative time string (e.g., "now", "2d", "1w")
    var relativeTime: String {
        let interval = Date().timeIntervalSince(updatedAt)
        switch interval {
        case ..<60: return "now"
        case ..<3600: return "\(Int(interval / 60))m"
        case ..<86400: return "\(Int(interval / 3600))h"
        case ..<604800: return "\(Int(interval / 86400))d"
        default: return "\(Int(interval / 604800))w"
        }
    }
    
    /// Project folder name extracted from projectPath, or "General" if none.
    var projectName: String {
        guard let path = projectPath, !path.isEmpty else { return "General" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}

/// A background agent running in a session (as seen in the reference UI).
struct BackgroundAgent: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let task: String
    var status: AgentStatus
    
    init(id: UUID = UUID(), name: String, task: String, status: AgentStatus = .thinking) {
        self.id = id
        self.name = name
        self.task = task
        self.status = status
    }
    
    enum AgentStatus: String, Codable {
        case thinking = "Thinking"
        case running = "Running"
        case reading = "Reading"
        case completed = "Completed"
        case failed = "Failed"
        
        var color: String {
            switch self {
            case .thinking: return "orange"
            case .running: return "blue"
            case .reading: return "purple"
            case .completed: return "green"
            case .failed: return "red"
            }
        }
    }
}
