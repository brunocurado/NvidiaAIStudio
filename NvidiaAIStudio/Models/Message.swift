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
    
    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachments: [Attachment] = [],
        timestamp: Date = Date(),
        reasoning: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        isStreaming: Bool = false
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
                    "function": ["name": tc.name, "arguments": tc.arguments] as [String: Any]
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
}
