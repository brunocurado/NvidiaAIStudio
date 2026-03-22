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
    
    // Thinking keyword detection (matches Python chat_worker.py)
    private let thinkingKeywords = ["deepseek", "kimi", "qwq"]
    private let thinkingQwenSuffix = "thinking"
    
    init(apiKey: String, baseURL: String = "https://integrate.api.nvidia.com/v1") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300  // 5 min — supports deep-thinking models (Kimi, DeepSeek R1, etc.)
        config.timeoutIntervalForResource = 600 // 10 min max for the full resource transfer
        self.session = URLSession(configuration: config)
    }
    
    /// Whether a model needs reasoning/thinking parameters.
    private func supportsThinking(modelID: String) -> Bool {
        let lower = modelID.lowercased()
        if lower.contains("qwen") {
            return lower.contains(thinkingQwenSuffix)
        }
        return thinkingKeywords.contains { lower.contains($0) }
    }
    
    func chat(
        messages: [Message],
        model: AIModel,
        tools: [[String: Any]]? = nil,
        reasoningLevel: ReasoningLevel = .medium
    ) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(messages: messages, model: model, tools: tools, reasoningLevel: reasoningLevel)
                    
                    let maxRetries = 5
                    var lastError: Error?
                    
                    for attempt in 0..<maxRetries {
                        do {
                            try await streamResponse(request: request, continuation: continuation)
                            return // Success
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
            "max_tokens": 16384
        ]
        
        // Convert messages to API format
        let apiMessages = messages.map { $0.toAPIDict() }
        body["messages"] = apiMessages
        
        // Add tools if provided and thinking allows
        if let tools, !tools.isEmpty, reasoningLevel == .off || !supportsThinking(modelID: model.id) {
            body["tools"] = tools
            body["tool_choice"] = "auto"
        }
        
        // Add thinking parameters
        if supportsThinking(modelID: model.id) && reasoningLevel != .off {
            let budget: Int
            switch reasoningLevel {
            case .high: budget = 10000
            case .medium: budget = 5000
            case .low: budget = 1024
            case .off: budget = 0
            }
            body["reasoning"] = ["type": "enabled", "max_tokens": budget]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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
            throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
        default:
            throw APIServiceError.serverError(statusCode: httpResponse.statusCode, message: "Unexpected status")
        }
        
        // Parse SSE stream using .lines (handles UTF-8 multi-byte characters correctly)
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
            
            // Parse tool calls
            var toolCalls: [Message.ToolCall]?
            if let tc = delta["tool_calls"] as? [[String: Any]] {
                toolCalls = tc.compactMap { call in
                    guard let id = call["id"] as? String,
                          let function = call["function"] as? [String: Any],
                          let name = function["name"] as? String else { return nil }
                    let args = function["arguments"] as? String ?? ""
                    return Message.ToolCall(id: id, name: name, arguments: args, status: .pending)
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

            if content != nil || reasoning != nil || toolCalls != nil || finishReason != nil || usage != nil {
                continuation.yield(ChatChunk(
                    content: content,
                    reasoning: reasoning,
                    toolCalls: toolCalls,
                    finishReason: finishReason,
                    usage: usage
                ))
            }
        }
        
        continuation.finish()
    }
}
