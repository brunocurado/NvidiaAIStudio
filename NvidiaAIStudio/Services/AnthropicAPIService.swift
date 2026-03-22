import Foundation

/// Anthropic API service — uses the native /v1/messages endpoint with SSE streaming.
/// Supports all Claude models (claude-opus-4, claude-sonnet-4, claude-haiku-4, etc.)
/// Anthropic's API is NOT OpenAI-compatible, so this is a dedicated implementation.
final class AnthropicAPIService: AIProvider {
    let provider: Provider = .anthropic

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    private let anthropicVersion = "2023-06-01"

    init(apiKey: String, baseURL: String = "https://api.anthropic.com/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)
    }

    // MARK: - AIProvider

    func chat(
        messages: [Message],
        model: AIModel,
        tools: [[String: Any]]? = nil,
        reasoningLevel: ReasoningLevel = .medium
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try self.buildRequest(
                        messages: messages,
                        model: model,
                        tools: tools,
                        reasoningLevel: reasoningLevel
                    )
                    try await self.streamResponse(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func validateKey() async throws -> Bool {
        // Anthropic has no /models endpoint; validate with a minimal request
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw APIServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Minimal body — will get a 400 if key is wrong, 200 if valid
        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        // 401 = bad key, 200/400 = key accepted
        if http.statusCode == 401 { throw APIServiceError.unauthorized }
        return http.statusCode != 401
    }

    // MARK: - Private

    private func buildRequest(
        messages: [Message],
        model: AIModel,
        tools: [[String: Any]]?,
        reasoningLevel: ReasoningLevel
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw APIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Separate system messages from conversation
        let systemMessages = messages.filter { $0.role == .system }
        let conversationMessages = messages.filter { $0.role != .system }

        let systemText = systemMessages.map(\.content).joined(separator: "\n\n")

        // Convert messages to Anthropic format
        // Anthropic requires alternating user/assistant turns
        let anthropicMessages = buildAnthropicMessages(from: conversationMessages)

        var body: [String: Any] = [
            "model": model.id,
            "max_tokens": 16000,
            "stream": true,
            "messages": anthropicMessages
        ]

        if !systemText.isEmpty {
            body["system"] = systemText
        }

        // Extended thinking (claude-3-7-sonnet and later)
        if model.supportsThinking && reasoningLevel != .off {
            let budget: Int
            switch reasoningLevel {
            case .high:   budget = 10000
            case .medium: budget = 5000
            case .low:    budget = 1024
            case .off:    budget = 0
            }
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
        }

        // Tools
        if let tools, !tools.isEmpty {
            let anthropicTools = tools.compactMap { tool -> [String: Any]? in
                guard let fn = tool["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let desc = fn["description"] as? String,
                      let params = fn["parameters"] as? [String: Any] else { return nil }
                return ["name": name, "description": desc, "input_schema": params]
            }
            if !anthropicTools.isEmpty {
                body["tools"] = anthropicTools
                body["tool_choice"] = ["type": "auto"]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Converts our Message array to Anthropic's alternating role format.
    /// Anthropic requires: user → assistant → user → assistant…
    /// Tool results are embedded as user messages with type "tool_result".
    private func buildAnthropicMessages(from messages: [Message]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        for msg in messages {
            switch msg.role {
            case .user:
                // Handle image attachments
                let imageAttachments = msg.attachments.filter { $0.mimeType.starts(with: "image/") }
                if !imageAttachments.isEmpty {
                    var contentParts: [[String: Any]] = [
                        ["type": "text", "text": msg.content]
                    ]
                    for att in imageAttachments {
                        contentParts.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": att.mimeType,
                                "data": att.data
                            ]
                        ])
                    }
                    result.append(["role": "user", "content": contentParts])
                } else {
                    result.append(["role": "user", "content": msg.content])
                }

            case .assistant:
                // If the assistant called tools, include tool_use blocks
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    var contentParts: [[String: Any]] = []
                    if !msg.content.isEmpty {
                        contentParts.append(["type": "text", "text": msg.content])
                    }
                    for tc in toolCalls {
                        let input = (try? JSONSerialization.jsonObject(
                            with: tc.arguments.data(using: .utf8) ?? Data()
                        )) ?? [:]
                        contentParts.append([
                            "type": "tool_use",
                            "id": tc.id,
                            "name": tc.name,
                            "input": input
                        ])
                    }
                    result.append(["role": "assistant", "content": contentParts])
                } else {
                    result.append(["role": "assistant", "content": msg.content])
                }

            case .tool:
                // Tool results must be user messages with type "tool_result"
                let toolResultContent: [[String: Any]] = [[
                    "type": "tool_result",
                    "tool_use_id": msg.toolCallId ?? "",
                    "content": msg.content
                ]]
                result.append(["role": "user", "content": toolResultContent])

            case .system:
                break // Handled separately
            }
        }

        // Ensure conversation starts with a user message
        if result.first?["role"] as? String == "assistant" {
            result.insert(["role": "user", "content": "Continue."], at: 0)
        }

        return result
    }

    private func streamResponse(
        request: URLRequest,
        continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        switch http.statusCode {
        case 200: break
        case 401: throw APIServiceError.unauthorized
        case 429: throw APIServiceError.rateLimited(retryAfter: nil)
        case 400...599:
            throw APIServiceError.serverError(statusCode: http.statusCode, message: "HTTP \(http.statusCode)")
        default: break
        }

        // Anthropic SSE event types:
        // content_block_delta (text_delta / thinking_delta / input_json_delta)
        // message_delta (usage)
        // tool_use blocks arrive via content_block_start + input_json_delta

        var currentToolCallId = ""
        var currentToolName = ""
        var currentToolArgs = ""
        var inputTokens = 0
        var outputTokens = 0

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse event type
            if trimmed.hasPrefix("event: ") {
                continue // we key off the data lines below
            }

            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonStr = String(trimmed.dropFirst(6))
            guard jsonStr != "[DONE]",
                  let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = json["type"] as? String ?? ""

            switch type {

            case "content_block_start":
                if let block = json["content_block"] as? [String: Any],
                   block["type"] as? String == "tool_use" {
                    currentToolCallId = block["id"] as? String ?? UUID().uuidString
                    currentToolName = block["name"] as? String ?? ""
                    currentToolArgs = ""
                }

            case "content_block_delta":
                guard let delta = json["delta"] as? [String: Any] else { continue }
                let deltaType = delta["type"] as? String ?? ""

                if deltaType == "text_delta", let text = delta["text"] as? String {
                    continuation.yield(ChatChunk(
                        content: text, reasoning: nil, toolCalls: nil,
                        finishReason: nil, usage: nil
                    ))
                } else if deltaType == "thinking_delta", let thinking = delta["thinking"] as? String {
                    continuation.yield(ChatChunk(
                        content: nil, reasoning: thinking, toolCalls: nil,
                        finishReason: nil, usage: nil
                    ))
                } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                    currentToolArgs += partial
                }

            case "content_block_stop":
                // If we were accumulating a tool call, emit it now
                if !currentToolName.isEmpty {
                    let tc = Message.ToolCall(
                        id: currentToolCallId,
                        name: currentToolName,
                        arguments: currentToolArgs,
                        status: .pending
                    )
                    continuation.yield(ChatChunk(
                        content: nil, reasoning: nil, toolCalls: [tc],
                        finishReason: nil, usage: nil
                    ))
                    currentToolName = ""
                    currentToolCallId = ""
                    currentToolArgs = ""
                }

            case "message_delta":
                if let usage = json["usage"] as? [String: Any] {
                    outputTokens = usage["output_tokens"] as? Int ?? 0
                }
                if let stopReason = (json["delta"] as? [String: Any])?["stop_reason"] as? String {
                    let u = TokenUsage(promptTokens: inputTokens, completionTokens: outputTokens)
                    continuation.yield(ChatChunk(
                        content: nil, reasoning: nil, toolCalls: nil,
                        finishReason: stopReason, usage: u
                    ))
                }

            case "message_start":
                if let msg = json["message"] as? [String: Any],
                   let usage = msg["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? 0
                }

            case "message_stop":
                continuation.finish()
                return

            default:
                break
            }
        }

        continuation.finish()
    }
}
