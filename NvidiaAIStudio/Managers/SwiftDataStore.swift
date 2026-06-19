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

        reconcileMessages(on: sdSession, with: session.messages)
        reconcileBackgroundAgents(on: sdSession, with: session.backgroundAgents)

        // Save with proper error handling to prevent crashes from merge conflicts
        do {
            try modelContext.save()
        } catch {
            // Log the error but don't crash — the session is still in memory
            AppLog.app.error("⚠️ SwiftDataStore.save failed for session \(sessionID): \(error.localizedDescription, privacy: .public)")
            // Rollback the context to a clean state for the next save attempt
            modelContext.rollback()
        }
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
    
    private func reconcileMessages(on session: SDSession, with messages: [Message]) {
        var existingByID = Dictionary(uniqueKeysWithValues: session.messages.map { ($0.id, $0) })
        var nextMessages: [SDMessage] = []
        
        for message in messages {
            if let existing = existingByID.removeValue(forKey: message.id) {
                update(existing, from: message)
                nextMessages.append(existing)
            } else {
                nextMessages.append(translate(from: message))
            }
        }
        
        for stale in existingByID.values {
            modelContext.delete(stale)
        }
        session.messages = nextMessages
    }
    
    private func update(_ sd: SDMessage, from message: Message) {
        sd.roleRaw = message.role.rawValue
        sd.content = message.content
        sd.timestamp = message.timestamp
        sd.reasoning = message.reasoning
        sd.toolCallId = message.toolCallId
        sd.isStreaming = message.isStreaming
        reconcileAttachments(on: sd, with: message.attachments)
        reconcileToolCalls(on: sd, with: message.toolCalls)
        reconcileStatusBadges(on: sd, with: message.statusBadges)
    }
    
    private func reconcileAttachments(on message: SDMessage, with attachments: [Message.Attachment]) {
        var existingByID = Dictionary(uniqueKeysWithValues: message.attachments.map { ($0.id, $0) })
        var nextAttachments: [SDAttachment] = []
        
        for attachment in attachments {
            if let existing = existingByID.removeValue(forKey: attachment.id) {
                existing.filename = attachment.filename
                existing.mimeType = attachment.mimeType
                existing.contentData = attachment.data
                nextAttachments.append(existing)
            } else {
                nextAttachments.append(translate(from: attachment))
            }
        }
        
        for stale in existingByID.values {
            modelContext.delete(stale)
        }
        message.attachments = nextAttachments
    }
    
    private func reconcileToolCalls(on message: SDMessage, with toolCalls: [Message.ToolCall]?) {
        var existingByID = Dictionary(uniqueKeysWithValues: (message.toolCalls ?? []).map { ($0.idString, $0) })
        var nextToolCalls: [SDToolCall] = []
        
        for toolCall in toolCalls ?? [] {
            if let existing = existingByID.removeValue(forKey: toolCall.id) {
                existing.name = toolCall.name
                existing.arguments = toolCall.arguments
                existing.result = toolCall.result
                existing.statusRaw = toolCall.status.rawValue
                nextToolCalls.append(existing)
            } else {
                nextToolCalls.append(translate(from: toolCall))
            }
        }
        
        for stale in existingByID.values {
            modelContext.delete(stale)
        }
        message.toolCalls = toolCalls == nil ? nil : nextToolCalls
    }
    
    private func reconcileStatusBadges(on message: SDMessage, with statusBadges: [Message.StatusBadge]) {
        var existingByID = Dictionary(uniqueKeysWithValues: message.statusBadges.map { ($0.id, $0) })
        var nextStatusBadges: [SDStatusBadge] = []
        
        for badge in statusBadges {
            if let existing = existingByID.removeValue(forKey: badge.id) {
                existing.text = badge.text
                existing.icon = badge.icon
                nextStatusBadges.append(existing)
            } else {
                nextStatusBadges.append(translate(from: badge))
            }
        }
        
        for stale in existingByID.values {
            modelContext.delete(stale)
        }
        message.statusBadges = nextStatusBadges
    }
    
    private func reconcileBackgroundAgents(on session: SDSession, with agents: [BackgroundAgent]) {
        var existingByID = Dictionary(uniqueKeysWithValues: session.backgroundAgents.map { ($0.id, $0) })
        var nextAgents: [SDBackgroundAgent] = []
        
        for agent in agents {
            if let existing = existingByID.removeValue(forKey: agent.id) {
                existing.name = agent.name
                existing.task = agent.task
                existing.statusRaw = agent.status.rawValue
                nextAgents.append(existing)
            } else {
                nextAgents.append(translate(from: agent))
            }
        }
        
        for stale in existingByID.values {
            modelContext.delete(stale)
        }
        session.backgroundAgents = nextAgents
    }
}
