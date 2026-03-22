import Foundation

/// A single chat message in a session.
struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    var attachments: [Attachment]
    let timestamp: Date
    
    /// Reasoning/thinking content (for models that support it)
    var reasoning: String?
    
    /// Tool calls made by the assistant
    var toolCalls: [ToolCall]?
    
    /// Tool call ID this message is responding to (for role == .tool)
    var toolCallId: String?
    
    /// Whether this message is currently being streamed
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
        /// Base64-encoded data for images, or path for files
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
        let arguments: String
        var result: String?
        var status: ToolCallStatus
        
        enum ToolCallStatus: String, Codable {
            case pending
            case running
            case completed
            case failed
        }
    }
    
    /// Converts to the format expected by the NVIDIA NIM API (OpenAI-compatible).
    func toAPIDict() -> [String: Any] {
        var dict: [String: Any] = [
            "role": role.rawValue,
            "content": content
        ]
        
        // For multimodal messages with image attachments
        let imageAttachments = attachments.filter { $0.mimeType.starts(with: "image/") }
        if !imageAttachments.isEmpty && role == .user {
            var contentParts: [[String: Any]] = [
                ["type": "text", "text": content]
            ]
            for attachment in imageAttachments {
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(attachment.mimeType);base64,\(attachment.data)"]
                ])
            }
            dict["content"] = contentParts
        }
        
        // For assistant messages with tool calls: inject the tool_calls array
        // (required by OpenAI-compatible APIs before the tool result messages)
        if role == .assistant, let toolCalls = toolCalls, !toolCalls.isEmpty {
            dict["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                [
                    "id": tc.id,
                    "type": "function",
                    "function": [
                        "name": tc.name,
                        "arguments": tc.arguments
                    ] as [String: Any]
                ]
            }
            // When the assistant is requesting tool calls, content should be null/empty
            if content.isEmpty {
                dict["content"] = NSNull()
            }
        }
        
        // For tool result messages: inject tool_call_id (mandatory)
        if role == .tool, let toolCallId = toolCallId {
            dict["tool_call_id"] = toolCallId
        }
        
        return dict
    }
}
