import Foundation
import SwiftData

/// Manages SwiftData persistence, translating between value types (Session, Message) and SwiftData @Model ref types.
@ModelActor
actor SwiftDataStore {
    
    // MARK: - Load
    
    /// Load all sessions from SwiftData, sorted by update date.
    func loadAll() -> [Session] {
        let fetchDescriptor = FetchDescriptor<SDSession>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        
        guard let sdSessions = try? modelContext.fetch(fetchDescriptor) else { return [] }
        
        // Translate right away to pure Swift structs for UI binding and performance
        return sdSessions.map { translate(from: $0) }
    }
    
    // MARK: - Save / Delete
    
    /// Save a single session. This creates a new SDSession or updates an existing one.
    func save(_ session: Session) {
        let sessionID = session.id
        let fetchDescriptor = FetchDescriptor<SDSession>(predicate: #Predicate { $0.id == sessionID })
        
        let sdSession: SDSession
        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            sdSession = existing
        } else {
            sdSession = SDSession(title: session.title, modelID: session.modelID, createdAt: session.createdAt, updatedAt: session.updatedAt)
            modelContext.insert(sdSession)
        }
        
        // Update properties
        sdSession.title = session.title
        sdSession.modelID = session.modelID
        sdSession.updatedAt = session.updatedAt
        sdSession.projectPath = session.projectPath
        
        // Overwrite Messages
        // Delete old
        for oldMsg in sdSession.messages {
            modelContext.delete(oldMsg)
        }
        // Insert new
        sdSession.messages = session.messages.map { translate(from: $0) }
        
        // Overwrite background agents
        for oldAgent in sdSession.backgroundAgents {
            modelContext.delete(oldAgent)
        }
        sdSession.backgroundAgents = session.backgroundAgents.map { translate(from: $0) }
        
        try? modelContext.save()
    }
    
    /// Delete a session from disk by ID.
    func delete(id: UUID) {
        let fetchDescriptor = FetchDescriptor<SDSession>(predicate: #Predicate { $0.id == id })
        if let existing = try? modelContext.fetch(fetchDescriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }
    
    /// Delete all sessions (Wipe).
    func deleteAll() {
        try? modelContext.delete(model: SDToolCall.self)
        try? modelContext.delete(model: SDAttachment.self)
        try? modelContext.delete(model: SDStatusBadge.self)
        try? modelContext.delete(model: SDMessage.self)
        try? modelContext.delete(model: SDBackgroundAgent.self)
        try? modelContext.delete(model: SDSession.self)
        try? modelContext.save()
    }
    
    // MARK: - Translators (Model to Value Type)
    
    private func translate(from sd: SDSession) -> Session {
        Session(
            id: sd.id,
            title: sd.title,
            messages: sd.messages.sorted(by: { $0.timestamp < $1.timestamp }).map { translate(from: $0) },
            modelID: sd.modelID,
            createdAt: sd.createdAt,
            updatedAt: sd.updatedAt,
            projectPath: sd.projectPath,
            backgroundAgents: sd.backgroundAgents.map { translate(from: $0) }
        )
    }
    
    private func translate(from sd: SDMessage) -> Message {
        Message(
            id: sd.id,
            role: Message.Role(rawValue: sd.roleRaw) ?? .user,
            content: sd.content,
            attachments: sd.attachments.map { translate(from: $0) },
            timestamp: sd.timestamp,
            reasoning: sd.reasoning,
            toolCalls: sd.toolCalls?.map { translate(from: $0) },
            toolCallId: sd.toolCallId,
            isStreaming: sd.isStreaming,
            statusBadges: sd.statusBadges.map { translate(from: $0) }
        )
    }
    
    private func translate(from sd: SDAttachment) -> Message.Attachment {
        Message.Attachment(id: sd.id, filename: sd.filename, mimeType: sd.mimeType, data: sd.contentData)
    }
    
    private func translate(from sd: SDToolCall) -> Message.ToolCall {
        Message.ToolCall(
            id: sd.idString,
            name: sd.name,
            arguments: sd.arguments,
            result: sd.result,
            status: Message.ToolCall.ToolCallStatus(rawValue: sd.statusRaw) ?? .completed
        )
    }
    
    private func translate(from sd: SDStatusBadge) -> Message.StatusBadge {
        Message.StatusBadge(id: sd.id, text: sd.text, icon: sd.icon)
    }
    
    private func translate(from sd: SDBackgroundAgent) -> BackgroundAgent {
        BackgroundAgent(
            id: sd.id,
            name: sd.name,
            task: sd.task,
            status: BackgroundAgent.AgentStatus(rawValue: sd.statusRaw) ?? .completed
        )
    }
    
    // MARK: - Translators (Value Type to Model)
    
    private func translate(from m: Message) -> SDMessage {
        SDMessage(
            id: m.id,
            roleRaw: m.role.rawValue,
            content: m.content,
            timestamp: m.timestamp,
            reasoning: m.reasoning,
            toolCallId: m.toolCallId,
            isStreaming: m.isStreaming,
            attachments: m.attachments.map { translate(from: $0) },
            toolCalls: m.toolCalls?.map { translate(from: $0) },
            statusBadges: m.statusBadges.map { translate(from: $0) }
        )
    }
    
    private func translate(from a: Message.Attachment) -> SDAttachment {
        SDAttachment(id: a.id, filename: a.filename, mimeType: a.mimeType, contentData: a.data)
    }
    
    private func translate(from t: Message.ToolCall) -> SDToolCall {
        SDToolCall(idString: t.id, name: t.name, arguments: t.arguments, result: t.result, statusRaw: t.status.rawValue)
    }
    
    private func translate(from t: Message.StatusBadge) -> SDStatusBadge {
        SDStatusBadge(id: t.id, text: t.text, icon: t.icon)
    }
    
    private func translate(from b: BackgroundAgent) -> SDBackgroundAgent {
        SDBackgroundAgent(id: b.id, name: b.name, task: b.task, statusRaw: b.status.rawValue)
    }
}
