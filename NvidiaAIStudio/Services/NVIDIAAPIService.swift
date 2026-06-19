import Foundation

/// A chunk received during streaming from the API.
struct ChatChunk {
    let content: String?
    let reasoning: String?
    let toolCalls: [Message.ToolCall]?
    let finishReason: String?
    let usage: TokenUsage?
}

/// Token usage reported by the API at the end of a response.
struct TokenUsage {
    let promptTokens: Int
    let completionTokens: Int
    var totalTokens: Int { promptTokens + completionTokens }
}

/// Protocol for AI providers (NVIDIA NIM, Anthropic, OpenAI).
protocol AIProvider {
    var provider: Provider { get }
    
    /// Stream a chat completion response.
    func chat(
        messages: [Message],
        model: AIModel,
        tools: [[String: Any]]?,
        reasoningLevel: ReasoningLevel
    ) -> AsyncThrowingStream<ChatChunk, Error>
    
    /// Validate the API key.
    func validateKey() async throws -> Bool
}

/// Errors from the API service layer.
enum APIServiceError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String)
    case invalidResponse
    case noAPIKey
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .unauthorized: return "Invalid API key"
        case .rateLimited: return "Rate limit exceeded — retrying..."
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .invalidResponse: return "Invalid response from server"
        case .noAPIKey: return "No API key configured"
        }
    }
}

/// NVIDIA NIM API service using OpenAI-compatible endpoint.
final class NVIDIAAPIService: AIProvider {
    let provider: Provider = .nvidia
    
    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    
    private static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 7200
        return URLSession(configuration: config)
    }()
    
    // Thinking keyword detection (matches Python chat_worker.py)
    private let thinkingKeywords = ["deepseek", "kimi", "qwq", "minimax-m3", "minimax-m4"]
    private let thinkingQwenSuffix = "thinking"
    
    // Models that use reasoning_effort instead of reasoning.type
    private let reasoningEffortModels = ["mistral-small-4", "mistral-medium-3", "mistral-large-3"]
    
    init(apiKey: String, baseURL: String = "https://integrate.api.nvidia.com/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = Self.sharedSession
    }
    
    /// Whether a model needs reasoning/thinking parameters.
    private func supportsThinking(modelID: String) -> Bool {
        let lower = modelID.lowercased()
        if lower.contains("qwen") {
            return lower.contains(thinkingQwenSuffix)
        }
        // Mistral models use reasoning_effort (handled separately)
        if usesReasoningEffort(modelID: lower) { return false }
        return thinkingKeywords.contains { lower.contains($0) }
    }
    
    /// Whether a model uses reasoning_effort parameter (Mistral-style).
    private func usesReasoningEffort(modelID: String) -> Bool {
        let lower = modelID.lowercased()
        return reasoningEffortModels.contains { lower.contains($0) }
    }
    
    func chat(
        messages: [Message],
        model: AIModel,
        tools: [[String: Any]]? = nil,
        reasoningLevel: ReasoningLevel = .medium
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                AppLog.network.info("Chat request: model=\(model.id, privacy: .public), messages=\(messages.count), tools=\(tools?.count ?? 0)")
                do {
                    let request = try buildRequest(messages: messages, model: model, tools: tools, reasoningLevel: reasoningLevel)

                    let maxRetries = 5
                    var lastError: Error?

                    for attempt in 0..<maxRetries {
                        do {
                            try await streamResponse(request: request, continuation: continuation)
                            AppLog.network.info("Chat completed: model=\(model.id, privacy: .public)")
                            return // Success
                        } catch let error as APIServiceError {
                            lastError = error
                            if case .rateLimited = error {
                                let delay = pow(2.0, Double(attempt))
                                AppLog.network.warning("Rate limited, retry \(attempt + 1)/\(maxRetries) after \(delay)s")
                                try await Task.sleep(for: .seconds(delay))
                                continue
                            }
                            AppLog.network.error("Chat failed: \(error.localizedDescription, privacy: .public)")
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
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        
        return httpResponse.statusCode == 200
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
        
        // Build request body
        var body: [String: Any] = [
            "model": model.id,
            "stream": true,
            "max_tokens": maxOutputTokens(reasoningLevel: reasoningLevel, model: model)
        ]
        
        // Convert messages to API format
        let apiMessages = messages.map { $0.toAPIDict() }
        body["messages"] = apiMessages
        
        // Add tools if provided
        // Most modern models support tools + reasoning simultaneously.
        // We always send tools, letting the API handle any incompatibility.
        // Only strip tools for models explicitly known to fail with both.
        if let tools, !tools.isEmpty {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        
        // Add thinking parameters
        if usesReasoningEffort(modelID: model.id) {
            // Mistral-style: only supports "high" and "none"
            switch reasoningLevel {
            case .max, .xhigh, .high, .medium: body["reasoning_effort"] = "high"
            case .low, .off: break // Mistral: omit param entirely for no reasoning
            }
        } else if supportsThinking(modelID: model.id) && reasoningLevel != .off {
            let lower = model.id.lowercased()
            if lower.contains("minimax-m3") || lower.contains("minimax-m4") {
                // MiniMax M3/M4: uses chat_template_kwargs with thinking_mode "enabled"/"disabled"
                let mode = reasoningLevel != .off ? "enabled" : "disabled"
                body["chat_template_kwargs"] = ["thinking_mode": mode]
            } else if model.id.contains("v4-pro") {
                // DeepSeek V4 reasoning uses chat_template_kwargs based on API docs
                let thinkingValue: Any
                switch reasoningLevel {
                case .max: thinkingValue = "max"
                case .xhigh: thinkingValue = "max"
                case .high: thinkingValue = "max"
                case .medium: thinkingValue = "high"
                case .low: thinkingValue = false
                case .off: thinkingValue = false
                }
                body["chat_template_kwargs"] = ["thinking": thinkingValue]
            } else {
                // Qwen/DeepSeek-style: uses reasoning object with budget
                let budget: Int
                switch reasoningLevel {
                case .max: budget = 16384
                case .xhigh: budget = 8192
                case .high: budget = 4096
                case .medium: budget = 2048
                case .low: budget = 512
                case .off: budget = 0
                }
                body["reasoning"] = ["type": "enabled", "max_tokens": budget]
            }
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    
    private func maxOutputTokens(reasoningLevel: ReasoningLevel, model: AIModel? = nil) -> Int {
        let contextWindow = model?.contextWindow ?? 128_000

        if contextWindow >= 1_000_000 {
            // 1M+ context models (MiniMax M3, DeepSeek V4, GPT-4.1): allow larger outputs
            let base = PromptConfig.default.largeContextMaxOutputTokens
            switch reasoningLevel {
            case .max: return Int(Double(base) * 1.5)
            case .xhigh: return Int(Double(base) * 1.25)
            case .high: return base
            case .medium: return Int(Double(base) * 0.75)
            case .low, .off: return Int(Double(base) * 0.5)
            }
        } else if contextWindow <= 32_768 {
            // Small context models: conservative output
            let base = PromptConfig.default.defaultMaxOutputTokens
            switch reasoningLevel {
            case .max: return Int(Double(base) * 0.75)
            case .xhigh: return Int(Double(base) * 0.6)
            case .high: return Int(Double(base) * 0.5)
            case .medium, .low, .off: return Int(Double(base) * 0.25)
            }
        } else {
            // Standard 128K-262K models
            let base = PromptConfig.default.defaultMaxOutputTokens
            switch reasoningLevel {
            case .max: return Int(Double(base) * 1.5)
            case .xhigh: return Int(Double(base) * 1.25)
            case .high: return base
            case .medium: return Int(Double(base) * 0.75)
            case .low, .off: return Int(Double(base) * 0.5)
            }
        }
    }
    
    private func streamResponse(request: URLRequest, continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async throws {
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200: break
        case 401: throw APIServiceError.unauthorized
        case 429: throw APIServiceError.rateLimited(retryAfter: nil)
        case 400...599:
            // Try to read error body for better diagnostics
            var errorBody = "HTTP \(httpResponse.statusCode)"
            var collectedLines: [String] = []
            for try await line in bytes.lines {
                collectedLines.append(line)
                if collectedLines.count > 5 { break }
            }
            if !collectedLines.isEmpty {
                errorBody = collectedLines.joined(separator: " ")
            }
            throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: errorBody)
        default:
            throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: "Unexpected status")
        }
        
        // Parse SSE stream using .lines (handles UTF-8 multi-byte characters correctly)
        var activeToolCalls: [Int: Message.ToolCall] = [:]
        
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            guard trimmed.hasPrefix("data: ") else { continue }
            let jsonString = String(trimmed.dropFirst(6))
            
            if jsonString == "[DONE]" {
                continuation.finish()
                return
            }
            
            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first else { continue }
            
            let delta = firstChoice["delta"] as? [String: Any] ?? [:]
            let finishReason = firstChoice["finish_reason"] as? String
            
            let content = delta["content"] as? String
            
            // Parse reasoning content
            var reasoning: String?
            if let reasoningContent = delta["reasoning_content"] as? String {
                reasoning = reasoningContent
            } else if let thinkingContent = (delta["thinking"] as? [String: Any])?["content"] as? String {
                reasoning = thinkingContent
            }
            
            // Parse tool calls with stateful accumulation
            var toolCallsUpdated = false
            if let tc = delta["tool_calls"] as? [[String: Any]] {
                for call in tc {
                    let index = call["index"] as? Int ?? 0
                    if let id = call["id"] as? String,
                       let function = call["function"] as? [String: Any],
                       let name = function["name"] as? String {
                        let args = function["arguments"] as? String ?? ""
                        activeToolCalls[index] = Message.ToolCall(id: id, name: name, arguments: args, status: .pending)
                        toolCallsUpdated = true
                    } else if let function = call["function"] as? [String: Any],
                              let argsDelta = function["arguments"] as? String {
                        if var existing = activeToolCalls[index] {
                            existing.arguments += argsDelta
                            activeToolCalls[index] = existing
                            toolCallsUpdated = true
                        }
                    }
                }
            }
            
            // Parse token usage (reported in the last chunk before [DONE])
            var usage: TokenUsage? = nil
            if let usageDict = json["usage"] as? [String: Any] {
                let prompt = usageDict["prompt_tokens"] as? Int ?? 0
                let completion = usageDict["completion_tokens"] as? Int ?? 0
                if prompt > 0 || completion > 0 {
                    usage = TokenUsage(promptTokens: prompt, completionTokens: completion)
                }
            }

            let currentToolCalls = toolCallsUpdated ? activeToolCalls.sorted(by: { $0.key < $1.key }).map { $0.value } : nil

            if content != nil || reasoning != nil || toolCallsUpdated || finishReason != nil || usage != nil {
                continuation.yield(ChatChunk(
                    content: content,
                    reasoning: reasoning,
                    toolCalls: currentToolCalls,
                    finishReason: finishReason,
                    usage: usage
                ))
            }
        }
        
        continuation.finish()
    }
}
