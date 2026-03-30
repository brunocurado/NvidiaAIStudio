import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    var attachments: [Attachment]
    let timestamp: Date
    var reasoning: String?
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var isStreaming: Bool
    var statusBadges: [StatusBadge]
    
    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachments: [Attachment] = [],
        timestamp: Date = Date(),
        reasoning: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        isStreaming: Bool = false,
        statusBadges: [StatusBadge] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
        self.reasoning = reasoning
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.isStreaming = isStreaming
        self.statusBadges = statusBadges
    }
    
    struct StatusBadge: Codable, Equatable, Identifiable {
        let id: UUID
        let text: String
        let icon: String?
        
        init(id: UUID = UUID(), text: String, icon: String? = nil) {
            self.id = id
            self.text = text
            self.icon = icon
        }
    }
    
    // Backwards-compatible decoding: old sessions won't have statusBadges
    enum CodingKeys: String, CodingKey {
        case id, role, content, attachments, timestamp, reasoning, toolCalls, toolCallId, isStreaming, statusBadges
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        reasoning = try c.decodeIfPresent(String.self, forKey: .reasoning)
        toolCalls = try c.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        toolCallId = try c.decodeIfPresent(String.self, forKey: .toolCallId)
        isStreaming = try c.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        statusBadges = try c.decodeIfPresent([StatusBadge].self, forKey: .statusBadges) ?? []
    }

    enum Role: String, Codable {
        case system
        case user
        case assistant
        case tool
    }
    
    struct Attachment: Identifiable, Codable, Equatable {
        let id: UUID
        let filename: String
        let mimeType: String
        let data: String
        
        init(id: UUID = UUID(), filename: String, mimeType: String, data: String) {
            self.id = id
            self.filename = filename
            self.mimeType = mimeType
            self.data = data
        }
    }
    
    struct ToolCall: Identifiable, Codable, Equatable {
        let id: String
        let name: String
        var arguments: String
        var result: String?
        var status: ToolCallStatus
        
        enum ToolCallStatus: String, Codable {
            case pending, running, completed, failed
        }
    }
    
    func toAPIDict() -> [String: Any] {
        var dict: [String: Any] = ["role": role.rawValue, "content": content]
        
        let imageAttachments = attachments.filter { $0.mimeType.starts(with: "image/") }
        
        // Multimodal content: supported for user and tool roles
        if !imageAttachments.isEmpty && (role == .user || role == .tool) {
            var contentParts: [[String: Any]] = []
            
            // Text part (tool results must always have text content)
            if !content.isEmpty {
                contentParts.append(["type": "text", "text": content])
            }
            
            for att in imageAttachments {
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(att.mimeType);base64,\(att.data)"]
                ])
            }
            
            dict["content"] = contentParts
        }
        
        // Assistant tool_calls
        if role == .assistant, let toolCalls = toolCalls, !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": ["name": tc.name, "arguments": Self.sanitizeArguments(tc.arguments)] as [String: Any]
                ]
            }
            if content.isEmpty { dict["content"] = NSNull() }
        }
        
        // Tool result: inject tool_call_id (mandatory)
        if role == .tool, let toolCallId = toolCallId {
            dict["tool_call_id"] = toolCallId
        }
        
        return dict
    }
    
    /// Ensures tool call arguments are valid JSON before sending to the API.
    /// Models sometimes produce malformed JSON (single quotes, unquoted keys, trailing commas, etc).
    private static func sanitizeArguments(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty or whitespace-only → valid empty object
        guard !trimmed.isEmpty else { return "{}" }
        
        // Try parsing as-is — if valid JSON, return it directly
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let clean = try? JSONSerialization.data(withJSONObject: obj),
           let result = String(data: clean, encoding: .utf8) {
            return result
        }
        
        // Common fix: single quotes → double quotes, unquoted keys
        var fixed = trimmed
        // Replace single-quoted strings with double-quoted
        fixed = fixed.replacingOccurrences(of: "'", with: "\"")
        // Remove trailing commas before } or ]
        fixed = fixed.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
        fixed = fixed.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
        
        if let data = fixed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data),
           let clean = try? JSONSerialization.data(withJSONObject: obj),
           let result = String(data: clean, encoding: .utf8) {
            return result
        }
        
        // Last resort: wrap as a raw_input parameter so the API at least gets valid JSON
        let escaped = trimmed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"raw_input\":\"\(escaped)\"}"
    }
}
