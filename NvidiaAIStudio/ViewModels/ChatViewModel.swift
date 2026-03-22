import SwiftUI

/// ViewModel for the chat, managing message streaming and the agentic tool-use loop.
@Observable
final class ChatViewModel {
    var isStreaming = false
    var streamingStatus = "Thinking"
    var contextUsage: Double = 0.0
    
    private var streamTask: Task<Void, Never>?
    private let skillRegistry = SkillRegistry.shared
    
    /// Send a user message and get a streamed response (with tool-call loop).
    @MainActor
    func sendMessage(_ text: String, attachments: [Message.Attachment] = [], appState: AppState) async {
        if appState.activeSessionID == nil {
            let _ = appState.createSession(title: String(text.prefix(40)))
        }
        
        // Add user message
        let userMessage = Message(role: .user, content: text, attachments: attachments)
        appState.activeSession?.messages.append(userMessage)
        appState.activeSession?.updatedAt = Date()
        
        // Auto-title the session from first message
        if appState.activeSession?.messages.count == 1 {
            appState.activeSession?.title = String(text.prefix(50))
        }
        
        // Get API key
        guard let apiKey = appState.activeAPIKey ?? EnvParser.loadNVIDIAKey() else {
            let errorMsg = Message(role: .assistant, content: "⚠️ No API key configured.\n\nGo to **Settings → API Keys** to add your NVIDIA NIM key, or place it in a `.env` file:\n```\nNVIDIA_NIM_API_KEY=nvapi-...\n```")
            appState.activeSession?.messages.append(errorMsg)
            return
        }
        
        guard let model = appState.selectedModel else {
            appState.showToast("No model selected", level: .error)
            return
        }
        
        isStreaming = true

        // Use the factory to get the correct service for the active provider
        let service = ProviderServiceFactory.make(
            provider: appState.activeProvider,
            apiKey: apiKey,
            customBaseURL: appState.apiKeys
                .first { $0.provider == appState.activeProvider && $0.isActive }?
                .customBaseURL
        )
        let tools = skillRegistry.toolDefinitions

        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.agentLoop(
                service: service,
                model: model,
                tools: tools,
                appState: appState,
                reasoningLevel: appState.reasoningLevel
            )
        }
    }
    
    /// Stop the current streaming response.
    @MainActor
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    // MARK: - Agent Loop
    
    /// Agentic loop: stream → if tool_calls → execute tools → feed results → stream again.
    /// Max 10 iterations to prevent infinite loops.
    private func agentLoop(
        service: any AIProvider,
        model: AIModel,
        tools: [[String: Any]],
        appState: AppState,
        reasoningLevel: ReasoningLevel
    ) async {
        let maxIterations = 10
        
        for iteration in 0..<maxIterations {
            if Task.isCancelled { break }
            
            // Create streaming placeholder
            let streamingID = UUID()
            await MainActor.run {
                let streamingMessage = Message(id: streamingID, role: .assistant, content: "", isStreaming: true)
                appState.activeSession?.messages.append(streamingMessage)
                self.streamingStatus = model.supportsThinking ? "Thinking" : "Generating"
            }
            
            // Build messages for the API
            let messagesToSend = await MainActor.run {
                var msgs = [SystemPrompt.asMessage()]
                msgs += (appState.activeSession?.messages ?? [])
                    .filter { $0.id != streamingID && (!$0.content.isEmpty || $0.role == .system || $0.role == .tool) }
                return msgs
            }
            
            // Stream the response
            var accumulatedContent = ""
            var accumulatedReasoning: String? = nil
            var accumulatedToolCalls: [Message.ToolCall]? = nil
            var accumulatedUsage: TokenUsage? = nil
            
            do {
                let stream = service.chat(
                    messages: messagesToSend,
                    model: model,
                    tools: tools.isEmpty ? nil : tools,
                    reasoningLevel: reasoningLevel
                )
                
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    if let content = chunk.content {
                        accumulatedContent += content
                        await MainActor.run { self.streamingStatus = "Writing" }
                    }
                    
                    if let reasoning = chunk.reasoning {
                        accumulatedReasoning = (accumulatedReasoning ?? "") + reasoning
                        await MainActor.run { self.streamingStatus = "Thinking" }
                    }
                    
                    if let toolCalls = chunk.toolCalls {
                        accumulatedToolCalls = (accumulatedToolCalls ?? []) + toolCalls
                        await MainActor.run { self.streamingStatus = "Running tools" }
                    }
                    if let usage = chunk.usage {
                        accumulatedUsage = usage
                    }
                    
                    // Update the streaming message live
                    await MainActor.run {
                        let updatedMessage = Message(
                            id: streamingID,
                            role: .assistant,
                            content: accumulatedContent,
                            reasoning: accumulatedReasoning,
                            toolCalls: accumulatedToolCalls,
                            isStreaming: true
                        )
                        self.updateMessage(id: streamingID, with: updatedMessage, in: appState)
                    }
                }
                
                // Finalize the assistant message
                await MainActor.run {
                    let finalMessage = Message(
                        id: streamingID,
                        role: .assistant,
                        content: accumulatedContent,
                        reasoning: accumulatedReasoning,
                        toolCalls: accumulatedToolCalls,
                        isStreaming: false
                    )
                    self.updateMessage(id: streamingID, with: finalMessage, in: appState)
                }
                
                // If there are tool calls, execute them and continue the loop
                if let toolCalls = accumulatedToolCalls, !toolCalls.isEmpty {
                    await MainActor.run { self.streamingStatus = "Executing tools (\(toolCalls.count))" }
                    
                    for toolCall in toolCalls {
                        // Mark as running
                        await MainActor.run {
                            self.updateToolCallStatus(messageID: streamingID, toolCallID: toolCall.id, status: .running, in: appState)
                        }
                        
                        // Execute the skill — capture access level + workspace for sandbox enforcement
                        let accessLevel = await MainActor.run { appState.fileAccessLevel }
                        let workspacePath = await MainActor.run { appState.activeWorkspacePath }
                        let result: String
                        do {
                            result = try await skillRegistry.execute(
                                name: toolCall.name,
                                arguments: toolCall.arguments,
                                accessLevel: accessLevel,
                                workspacePath: workspacePath
                            )
                            
                            // Mark as completed
                            await MainActor.run {
                                self.updateToolCallResult(messageID: streamingID, toolCallID: toolCall.id, result: result, status: .completed, in: appState)
                            }
                        } catch {
                            result = "Error: \(error.localizedDescription)"
                            await MainActor.run {
                                self.updateToolCallResult(messageID: streamingID, toolCallID: toolCall.id, result: result, status: .failed, in: appState)
                            }
                        }
                        
                        // Add tool result message for the next API call
                        // toolCallId is MANDATORY for OpenAI-compatible APIs (HTTP 400 otherwise)
                        await MainActor.run {
                            let toolResultMessage = Message(
                                role: .tool,
                                content: result,
                                toolCallId: toolCall.id
                            )
                            appState.activeSession?.messages.append(toolResultMessage)
                        }
                    }
                    
                    // Continue the loop — the model will see the tool results
                    continue
                }
                
                // No tool calls — we're done
                await MainActor.run {
                    self.isStreaming = false
                    self.updateContextUsage(appState)
                    appState.saveActiveSession()
                    
                    // Persist real token usage if the API reported it
                    if let usage = accumulatedUsage {
                        let record = UsageStore.Record(
                            id: UUID(),
                            date: Date(),
                            provider: appState.activeProvider.rawValue,
                            modelID: model.id,
                            modelName: model.name,
                            sessionTitle: appState.activeSession?.title ?? "Thread",
                            promptTokens: usage.promptTokens,
                            completionTokens: usage.completionTokens
                        )
                        UsageStore.shared.append(record)
                    }
                    
                    if accumulatedContent.isEmpty && accumulatedToolCalls == nil {
                        appState.showToast("Empty response from model", level: .warning)
                    }
                    // Notify user if app is in background
                    let cleanName = String(model.name
                        .drop(while: { !$0.isLetter && !$0.isNumber }))
                        .components(separatedBy: "—").first?
                        .trimmingCharacters(in: .whitespaces) ?? model.name
                    AppNotifications.sendResponseCompleted(modelName: cleanName)
                }
                return
                
            } catch {
                await MainActor.run {
                    let errorContent = accumulatedContent.isEmpty
                        ? "⚠️ Error: \(error.localizedDescription)"
                        : accumulatedContent + "\n\n⚠️ Error: \(error.localizedDescription)"
                    
                    let errorMessage = Message(
                        id: streamingID,
                        role: .assistant,
                        content: errorContent,
                        reasoning: accumulatedReasoning,
                        isStreaming: false
                    )
                    self.updateMessage(id: streamingID, with: errorMessage, in: appState)
                    self.isStreaming = false
                    appState.showToast("API Error: \(error.localizedDescription)", level: .error)
                }
                return
            }
        }
        
        // Max iterations reached
        await MainActor.run {
            self.isStreaming = false
            appState.showToast("Agent loop reached maximum iterations (10)", level: .warning)
            appState.saveActiveSession()
        }
    }
    
    // MARK: - Private Helpers
    
    @MainActor
    private func updateMessage(id: UUID, with message: Message, in appState: AppState) {
        guard var session = appState.activeSession,
              let idx = session.messages.firstIndex(where: { $0.id == id }) else { return }
        session.messages[idx] = message
        appState.activeSession = session
    }
    
    @MainActor
    private func updateToolCallStatus(messageID: UUID, toolCallID: String, status: Message.ToolCall.ToolCallStatus, in appState: AppState) {
        guard var session = appState.activeSession,
              let msgIdx = session.messages.firstIndex(where: { $0.id == messageID }),
              let tcIdx = session.messages[msgIdx].toolCalls?.firstIndex(where: { $0.id == toolCallID }) else { return }
        session.messages[msgIdx].toolCalls?[tcIdx].status = status
        appState.activeSession = session
    }
    
    @MainActor
    private func updateToolCallResult(messageID: UUID, toolCallID: String, result: String, status: Message.ToolCall.ToolCallStatus, in appState: AppState) {
        guard var session = appState.activeSession,
              let msgIdx = session.messages.firstIndex(where: { $0.id == messageID }),
              let tcIdx = session.messages[msgIdx].toolCalls?.firstIndex(where: { $0.id == toolCallID }) else { return }
        session.messages[msgIdx].toolCalls?[tcIdx].result = result
        session.messages[msgIdx].toolCalls?[tcIdx].status = status
        appState.activeSession = session
    }
    
    @MainActor
    private func updateContextUsage(_ appState: AppState) {
        guard let session = appState.activeSession,
              let model = appState.selectedModel else { return }
        let totalChars = session.messages.reduce(0) { $0 + $1.content.count + ($1.reasoning?.count ?? 0) }
        let estimatedTokens = totalChars / 4
        contextUsage = min(1.0, Double(estimatedTokens) / Double(model.contextWindow))
        
        // Auto-compress when context reaches 80%
        if contextUsage >= 0.80 {
            Task { await self.compressContext(appState: appState) }
        }
    }
    
    // MARK: - Context Compression
    
    /// Compresses old messages into a rolling summary to free up context space.
    /// Strategy:
    ///   1. Keep the system prompt and the last 6 messages intact (recent context)
    ///   2. Take all messages before those 6 (the "old" part)
    ///   3. Ask the model to summarise them in a compact paragraph
    ///   4. Replace those old messages with a single system-style summary message
    ///   5. The context indicator drops back, reflecting the freed space
    @MainActor
    func compressContext(appState: AppState) async {
        guard let session = appState.activeSession,
              let model = appState.selectedModel,
              let apiKey = appState.activeAPIKey ?? EnvParser.loadNVIDIAKey() else { return }
        
        let messages = session.messages
        let keepLast = 6
        guard messages.count > keepLast + 2 else { return } // nothing meaningful to compress
        
        let toCompress = Array(messages.dropLast(keepLast))
        let toKeep = Array(messages.suffix(keepLast))
        
        // Build a plain-text transcript of the messages to compress
        let transcript = toCompress.map { msg -> String in
            switch msg.role {
            case .user:      return "User: \(msg.content)"
            case .assistant: return "Assistant: \(msg.content)"
            case .tool:      return "[Tool result: \(msg.content.prefix(200))]"
            case .system:    return ""
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n")
        
        let summaryRequest = [
            Message(role: .system, content: "You are a conversation summariser. Summarise the following conversation history concisely in 3-5 sentences, preserving all key facts, decisions, file paths, and code discussed. Output only the summary, nothing else."),
            Message(role: .user, content: transcript)
        ]
        
        streamingStatus = "Compressing context\u{2026}"
        
        let service = ProviderServiceFactory.make(
            provider: appState.activeProvider,
            apiKey: apiKey
        )
        var summary = ""
        
        do {
            let stream = service.chat(
                messages: summaryRequest,
                model: model,
                tools: nil,
                reasoningLevel: .off
            )
            for try await chunk in stream {
                summary += chunk.content ?? ""
            }
        } catch {
            // If compression fails, just warn and continue — never lose messages
            appState.showToast("Context compression failed: \(error.localizedDescription)", level: .warning)
            return
        }
        
        guard !summary.isEmpty else { return }
        
        // Replace the old messages with a single compact summary
        let summaryMessage = Message(
            role: .system,
            content: "\u{1F4CB} **[Conversation summary — earlier context compressed]**\n\n\(summary)"
        )
        
        appState.activeSession?.messages = [summaryMessage] + toKeep
        appState.saveActiveSession()
        updateContextUsage(appState)
        appState.showToast("Context compressed to free up space", level: .info)
    }
}
