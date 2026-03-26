import Foundation

/// OpenAI API service — uses the standard /v1/chat/completions endpoint.
/// Compatible with OpenAI and any OpenAI-compatible provider (Groq, Together, etc.)
/// The implementation is nearly identical to NVIDIAAPIService since both use
/// the same OpenAI wire format.
final class OpenAIAPIService: AIProvider {
    let provider: Provider = .openai

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession

    init(apiKey: String, baseURL: String = "https://api.openai.com/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 7200
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

                    let maxRetries = 3
                    var lastError: Error?
                    for attempt in 0..<maxRetries {
                        do {
                            try await self.streamResponse(request: request, continuation: continuation)
                            return
                        } catch let error as APIServiceError {
                            lastError = error
                            if case .rateLimited = error {
                                let delay = pow(2.0, Double(attempt))
                                try await Task.sleep(for: .seconds(delay))
                                continue
                            }
                            throw error
                        }
                    }
                    throw lastError ?? APIServiceError.invalidResponse
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func validateKey() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/models") else {
            throw APIServiceError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        if http.statusCode == 401 { throw APIServiceError.unauthorized }
        return http.statusCode == 200
    }

    // MARK: - Private

    private func buildRequest(
        messages: [Message],
        model: AIModel,
        tools: [[String: Any]]?,
        reasoningLevel: ReasoningLevel
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw APIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model.id,
            "stream": true,
            "stream_options": ["include_usage": true], // get token counts in stream
        ]

        // Max tokens — o1/o3 models use max_completion_tokens
        let isReasoningModel = model.id.hasPrefix("o1") || model.id.hasPrefix("o3")
        if isReasoningModel {
            body["max_completion_tokens"] = 16000
        } else {
            body["max_tokens"] = 16000
        }

        body["messages"] = messages.map { $0.toAPIDict() }

        // Tools (not supported on o1/o3 reasoning models)
        if let tools, !tools.isEmpty, !isReasoningModel {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }

        // Reasoning effort for o1/o3 models
        if isReasoningModel && reasoningLevel != .off {
            let effort: String
            switch reasoningLevel {
            case .high:   effort = "high"
            case .medium: effort = "medium"
            case .low:    effort = "low"
            case .off:    effort = "low"
            }
            body["reasoning_effort"] = effort
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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

        // Standard OpenAI SSE parsing (identical to NVIDIAAPIService)
        var activeToolCalls: [Int: Message.ToolCall] = [:]
        
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonStr = String(trimmed.dropFirst(6))
            if jsonStr == "[DONE]" {
                continuation.finish()
                return
            }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first
            else { continue }

            let delta = first["delta"] as? [String: Any] ?? [:]
            let finishReason = first["finish_reason"] as? String
            let content = delta["content"] as? String

            // OpenAI reasoning models stream reasoning via "reasoning" key
            let reasoning: String? = delta["reasoning"] as? String

            // Tool calls
            var toolCallsUpdated = false
            if let tc = delta["tool_calls"] as? [[String: Any]] {
                for call in tc {
                    let index = call["index"] as? Int ?? 0
                    if let id = call["id"] as? String,
                       let fn = call["function"] as? [String: Any],
                       let name = fn["name"] as? String {
                        let args = fn["arguments"] as? String ?? ""
                        activeToolCalls[index] = Message.ToolCall(id: id, name: name, arguments: args, status: .pending)
                        toolCallsUpdated = true
                    } else if let fn = call["function"] as? [String: Any],
                              let argsDelta = fn["arguments"] as? String {
                        if var existing = activeToolCalls[index] {
                            existing.arguments += argsDelta
                            activeToolCalls[index] = existing
                            toolCallsUpdated = true
                        }
                    }
                }
            }

            // Usage (included in last chunk via stream_options)
            var usage: TokenUsage?
            if let u = json["usage"] as? [String: Any] {
                let p = u["prompt_tokens"] as? Int ?? 0
                let c = u["completion_tokens"] as? Int ?? 0
                if p > 0 || c > 0 { usage = TokenUsage(promptTokens: p, completionTokens: c) }
            }

            let currentToolCalls = toolCallsUpdated ? activeToolCalls.sorted(by: { $0.key < $1.key }).map { $0.value } : nil

            if content != nil || reasoning != nil || toolCallsUpdated || finishReason != nil || usage != nil {
                continuation.yield(ChatChunk(
                    content: content, reasoning: reasoning, toolCalls: currentToolCalls,
                    finishReason: finishReason, usage: usage
                ))
            }
        }

        continuation.finish()
    }
}
