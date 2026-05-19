import Foundation
import SwiftData

// MARK: - Agent Persona

/// Represents an AI agent identity in the Swarm — its personality, capabilities, and visual appearance.
@Model
final class AgentPersona {
    @Attribute(.unique) var name: String
    var roleName: String              // "Senior Frontend Developer"
    var systemPrompt: String
    var avatarAssetName: String       // Maps to an asset catalog image
    var accentColorHex: String        // Each agent gets a signature color
    var allowedTools: [String]        // ["write_file", "run_command"]
    var preferredModelId: String?     // The LLM optimal for this role
    var isActive: Bool
    
    // Spatial War Room Coordinates
    var canvasX: Double?
    var canvasY: Double?
    
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SwarmTask.assignedAgent)
    var tasks: [SwarmTask]
    
    @Relationship(deleteRule: .nullify, inverse: \SwarmTask.debateOpponent)
    var opponentTasks: [SwarmTask]

    init(
        name: String,
        roleName: String,
        systemPrompt: String,
        avatarAssetName: String = "agent_default",
        accentColorHex: String = "#76B900",
        allowedTools: [String] = [],
        preferredModelId: String? = nil,
        isActive: Bool = true,
        canvasX: Double? = nil,
        canvasY: Double? = nil,
        createdAt: Date = Date(),
        tasks: [SwarmTask] = [],
        opponentTasks: [SwarmTask] = []
    ) {
        self.name = name
        self.roleName = roleName
        self.systemPrompt = systemPrompt
        self.avatarAssetName = avatarAssetName
        self.accentColorHex = accentColorHex
        self.allowedTools = allowedTools
        self.preferredModelId = preferredModelId
        self.isActive = isActive
        self.canvasX = canvasX
        self.canvasY = canvasY
        self.createdAt = createdAt
        self.tasks = tasks
        self.opponentTasks = opponentTasks
    }
}

// MARK: - Swarm Task

/// A unit of work assigned to an agent. The Orchestrator picks up "pending" tasks and runs them.
@Model
final class SwarmTask {
    @Attribute(.unique) var id: UUID
    var taskDescription: String
    var status: String                // "pending", "running", "completed", "failed"
    var priority: Int                 // 0 = low, 1 = normal, 2 = urgent
    var type: String                  // "standard", "debate"
    var logs: [String]                // Append-only execution log
    var maxRounds: Int                // For debate tasks (default: 5)
    var additionalOpponentNames: [String] // For multi-agent debates (beyond the first opponent)
    var sharedCanvasContent: String?  // Stores the Shared State for Debate Split-Screen
    var createdAt: Date
    var completedAt: Date?
    var errorMessage: String?

    var assignedAgent: AgentPersona?
    var debateOpponent: AgentPersona?

    @Relationship(deleteRule: .cascade, inverse: \SwarmMessage.task)
    var messages: [SwarmMessage]

    @Relationship(deleteRule: .cascade, inverse: \SwarmDeliverable.task)
    var deliverables: [SwarmDeliverable]

    init(
        id: UUID = UUID(),
        taskDescription: String,
        status: String = "pending",
        priority: Int = 1,
        type: String = "standard",
        logs: [String] = [],
        maxRounds: Int = 5,
        additionalOpponentNames: [String] = [],
        sharedCanvasContent: String? = nil,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        assignedAgent: AgentPersona? = nil,
        debateOpponent: AgentPersona? = nil,
        messages: [SwarmMessage] = [],
        deliverables: [SwarmDeliverable] = []
    ) {
        self.id = id
        self.taskDescription = taskDescription
        self.status = status
        self.priority = priority
        self.type = type
        self.logs = logs
        self.maxRounds = maxRounds
        self.additionalOpponentNames = additionalOpponentNames
        self.sharedCanvasContent = sharedCanvasContent
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.assignedAgent = assignedAgent
        self.debateOpponent = debateOpponent
        self.messages = messages
        self.deliverables = deliverables
    }
}

// MARK: - Swarm Message

/// Messages within a Swarm task context (distinct from Chat `Message`).
/// Supports multi-agent conversations with sender identification.
@Model
final class SwarmMessage {
    @Attribute(.unique) var id: UUID
    var role: String                  // "user", "agent", "system", "moderator"
    var content: String
    var senderName: String            // Which agent name or "CEO" (the user)
    var timestamp: Date

    var task: SwarmTask?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        senderName: String,
        timestamp: Date = Date(),
        task: SwarmTask? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.senderName = senderName
        self.timestamp = timestamp
        self.task = task
    }
}

// MARK: - Swarm Deliverable

/// The "physical object" an agent places in the user's Inbox.
/// Can be a file, report, image, or extracted memory.
@Model
final class SwarmDeliverable {
    @Attribute(.unique) var id: UUID
    var title: String                 // "database_schema.sql"
    var type: String                  // "file", "report", "image", "memory"
    var content: String               // Raw content or file path
    var mimeType: String?             // "text/plain", "image/png"
    var isRead: Bool
    var createdAt: Date

    var task: SwarmTask?

    init(
        id: UUID = UUID(),
        title: String,
        type: String,
        content: String,
        mimeType: String? = nil,
        isRead: Bool = false,
        createdAt: Date = Date(),
        task: SwarmTask? = nil
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.content = content
        self.mimeType = mimeType
        self.isRead = isRead
        self.createdAt = createdAt
        self.task = task
    }
}
