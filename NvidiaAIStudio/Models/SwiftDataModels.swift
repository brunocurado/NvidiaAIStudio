import Foundation
import SwiftData

@Model
final class SDSession {
    @Attribute(.unique) var id: UUID
    var title: String
    var modelID: String
    var createdAt: Date
    var updatedAt: Date
    var projectPath: String?
    
    // Cascades messages upon session deletion
    @Relationship(deleteRule: .cascade) var messages: [SDMessage]
    @Relationship(deleteRule: .cascade) var backgroundAgents: [SDBackgroundAgent]
    
    init(id: UUID = UUID(), title: String, modelID: String, createdAt: Date, updatedAt: Date, projectPath: String? = nil, messages: [SDMessage] = [], backgroundAgents: [SDBackgroundAgent] = []) {
        self.id = id
        self.title = title
        self.modelID = modelID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectPath = projectPath
        self.messages = messages
        self.backgroundAgents = backgroundAgents
    }
}

@Model
final class SDMessage {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var timestamp: Date
    var reasoning: String?
    var toolCallId: String?
    var isStreaming: Bool
    
    @Relationship(deleteRule: .cascade) var attachments: [SDAttachment]
    @Relationship(deleteRule: .cascade) var toolCalls: [SDToolCall]?
    @Relationship(deleteRule: .cascade) var statusBadges: [SDStatusBadge]
    
    init(id: UUID = UUID(), roleRaw: String, content: String, timestamp: Date, reasoning: String? = nil, toolCallId: String? = nil, isStreaming: Bool = false, attachments: [SDAttachment] = [], toolCalls: [SDToolCall]? = nil, statusBadges: [SDStatusBadge] = []) {
        self.id = id
        self.roleRaw = roleRaw
        self.content = content
        self.timestamp = timestamp
        self.reasoning = reasoning
        self.toolCallId = toolCallId
        self.isStreaming = isStreaming
        self.attachments = attachments
        self.toolCalls = toolCalls
        self.statusBadges = statusBadges
    }
}

@Model
final class SDAttachment {
    @Attribute(.unique) var id: UUID
    var filename: String
    var mimeType: String
    var contentData: String
    
    init(id: UUID = UUID(), filename: String, mimeType: String, contentData: String) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.contentData = contentData
    }
}

@Model
final class SDToolCall {
    @Attribute(.unique) var idString: String
    var name: String
    var arguments: String
    var result: String?
    var statusRaw: String
    
    init(idString: String, name: String, arguments: String, result: String? = nil, statusRaw: String) {
        self.idString = idString
        self.name = name
        self.arguments = arguments
        self.result = result
        self.statusRaw = statusRaw
    }
}

@Model
final class SDStatusBadge {
    @Attribute(.unique) var id: UUID
    var text: String
    var icon: String?
    
    init(id: UUID = UUID(), text: String, icon: String? = nil) {
        self.id = id
        self.text = text
        self.icon = icon
    }
}

@Model
final class SDBackgroundAgent {
    @Attribute(.unique) var id: UUID
    var name: String
    var task: String
    var statusRaw: String
    
    init(id: UUID = UUID(), name: String, task: String, statusRaw: String) {
        self.id = id
        self.name = name
        self.task = task
        self.statusRaw = statusRaw
    }
}
