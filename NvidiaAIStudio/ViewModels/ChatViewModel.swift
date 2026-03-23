import SwiftUI

@Observable
final class ChatViewModel {
    var isStreaming = false
    var streamingStatus = "Thinking"
    var contextUsage: Double = 0.0
    
    private var streamTask: Task<Void, Never>?
    private let skillRegistry = SkillRegistry.shared
    
    @MainActor
    func sendMessage(_ text: String, attachments: [Message.Attachment] = [], appState: AppState) async {
        if appState.activeSessionID == nil {
            let _ = appState.createSession(title: String(text.prefix(40)))
        }
        let userMessage = Message(role: .user, content: text, attachments: attachments)
        appState.activeSession?.messages.append(userMessage)
        appState.activeSession?.updatedAt = Date()
        if appState.activeSession?.messages.count == 1 {
            appState.activeSession?.title = String(text.prefix(50))
        }
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
        let service = ProviderServiceFactory.make(
            provider: appState.activeProvider,
            apiKey: apiKey,
            customBaseURL: appState.apiKeys.first { $0.provider == appState.activeProvider && $0.isActive }?.customBaseURL
        )
        let tools = skillRegistry.toolDefinitions
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.agentLoop(service: service, model: model, tools: tools, appState: appState, reasoningLevel: appState.reasoningLevel)
        }
    }
    
    @MainActor
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    // MARK: - Agent Loop
    
    private func agentLoop(
        service: any AIProvider,
        model: AIModel,
        tools: [[String: Any]],
        appState: AppState,
        reasoningLevel: ReasoningLevel
    ) async {
        let maxIterations = 10
        
        for _ in 0..<maxIterations {
            if Task.isCancelled { break }
            
            let streamingID = UUID()
            await MainActor.run {
                appState.activeSession?.messages.append(Message(id: streamingID, role: .assistant, content: "", isStreaming: true))
                self.streamingStatus = model.supportsThinking ? "Thinking" : "Generating"
            }
            
            let messagesToSend = await MainActor.run {
                var msgs = [SystemPrompt.asMessage()]
                msgs += (appState.activeSession?.messages ?? [])
                    .filter { $0.id != streamingID && (!$0.content.isEmpty || $0.role == .system || $0.role == .tool) }
                return msgs
            }
            
            var accContent = ""
            var accReasoning: String? = nil
            var accToolCalls: [Message.ToolCall]? = nil
            var accUsage: TokenUsage? = nil
            
            do {
                let stream = service.chat(messages: messagesToSend, model: model, tools: tools.isEmpty ? nil : tools, reasoningLevel: reasoningLevel)
                
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let c = chunk.content { accContent += c; await MainActor.run { self.streamingStatus = "Writing" } }
                    if let r = chunk.reasoning { accReasoning = (accReasoning ?? "") + r; await MainActor.run { self.streamingStatus = "Thinking" } }
                    if let tc = chunk.toolCalls { accToolCalls = tc; await MainActor.run { self.streamingStatus = "Running tools" } }
                    if let u = chunk.usage { accUsage = u }
                    let snapContent = accContent
                    let snapReasoning = accReasoning
                    let snapToolCalls = accToolCalls
                    await MainActor.run {
                        self.updateMessage(id: streamingID, with: Message(id: streamingID, role: .assistant, content: snapContent, reasoning: snapReasoning, toolCalls: snapToolCalls, isStreaming: true), in: appState)
                    }
                }
                
                let finalContent = accContent
                let finalReasoning = accReasoning
                let finalToolCalls = accToolCalls
                await MainActor.run {
                    self.updateMessage(id: streamingID, with: Message(id: streamingID, role: .assistant, content: finalContent, reasoning: finalReasoning, toolCalls: finalToolCalls, isStreaming: false), in: appState)
                }
                
                if let toolCalls = accToolCalls, !toolCalls.isEmpty {
                    await MainActor.run { self.streamingStatus = "Executing tools (\(toolCalls.count))" }
                    
                    for toolCall in toolCalls {
                        await MainActor.run {
                            self.updateToolCallStatus(messageID: streamingID, toolCallID: toolCall.id, status: .running, in: appState)
                        }
                        let accessLevel = await MainActor.run { appState.fileAccessLevel }
                        let workspacePath = await MainActor.run { appState.activeWorkspacePath }
                        let supportsVision = await MainActor.run { appState.selectedModel?.supportsVision ?? false }
                        
                        let rawResult: String
                        do {
                            rawResult = try await skillRegistry.execute(name: toolCall.name, arguments: toolCall.arguments, accessLevel: accessLevel, workspacePath: workspacePath)
                            await MainActor.run {
                                self.updateToolCallResult(messageID: streamingID, toolCallID: toolCall.id, result: rawResult, status: .completed, in: appState)
                            }
                        } catch {
                            rawResult = "Error: \(error.localizedDescription)"
                            await MainActor.run {
                                self.updateToolCallResult(messageID: streamingID, toolCallID: toolCall.id, result: rawResult, status: .failed, in: appState)
                            }
                        }
                        
                        // Detect vision payload from fetch_images skill
                        let (textContent, imageAttachments) = extractVisionPayload(from: rawResult, supportsVision: supportsVision)
                        
                        await MainActor.run {
                            let toolResultMessage = Message(
                                role: .tool,
                                content: textContent,
                                attachments: imageAttachments,
                                toolCallId: toolCall.id
                            )
                            appState.activeSession?.messages.append(toolResultMessage)
                        }
                    }
                    continue
                }
                
                let doneContent = accContent
                let doneToolCalls = accToolCalls
                let doneUsage = accUsage
                await MainActor.run {
                    self.isStreaming = false
                    self.updateContextUsage(appState)
                    appState.saveActiveSession()
                    if let usage = doneUsage {
                        UsageStore.shared.append(UsageStore.Record(
                            id: UUID(), date: Date(),
                            provider: appState.activeProvider.rawValue,
                            modelID: model.id, modelName: model.name,
                            sessionTitle: appState.activeSession?.title ?? "Thread",
                            promptTokens: usage.promptTokens, completionTokens: usage.completionTokens
                        ))
                    }
                    if doneContent.isEmpty && doneToolCalls == nil { appState.showToast("Empty response from model", level: .warning) }
                    let cleanName = String(model.name.drop(while: { !$0.isLetter && !$0.isNumber }))
                        .components(separatedBy: "—").first?.trimmingCharacters(in: .whitespaces) ?? model.name
                    AppNotifications.sendResponseCompleted(modelName: cleanName)
                }
                return
                
            } catch {
                let errContent = accContent
                let errReasoning = accReasoning
                await MainActor.run {
                    let errorContent = errContent.isEmpty ? "⚠️ Error: \(error.localizedDescription)" : errContent + "\n\n⚠️ Error: \(error.localizedDescription)"
                    self.updateMessage(id: streamingID, with: Message(id: streamingID, role: .assistant, content: errorContent, reasoning: errReasoning, isStreaming: false), in: appState)
                    self.isStreaming = false
                    appState.showToast("API Error: \(error.localizedDescription)", level: .error)
                }
                return
            }
        }
        
        await MainActor.run {
            self.isStreaming = false
            appState.showToast("Agent loop reached maximum iterations (10)", level: .warning)
            appState.saveActiveSession()
        }
    }
    
    // MARK: - Vision Payload Extraction
    
    /// Parses the [VISION_IMAGES] payload from fetch_images skill results.
    /// Returns (textContent, imageAttachments) — images are only injected if model supports vision.
    private func extractVisionPayload(from result: String, supportsVision: Bool) -> (String, [Message.Attachment]) {
        let prefix = FetchImagesSkill.payloadPrefix
        guard result.hasPrefix(prefix) else { return (result, []) }
        
        // Split on first newline to separate JSON payload from human summary
        let withoutPrefix = String(result.dropFirst(prefix.count))
        let lines = withoutPrefix.components(separatedBy: "\n")
        let jsonLine = lines.first ?? ""
        let summary = lines.dropFirst().joined(separator: "\n")
        
        guard supportsVision,
              let jsonData = jsonLine.data(using: .utf8),
              let payloads = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: String]]
        else {
            // Model doesn't support vision or parse failed — return summary only
            let fallback = summary.isEmpty ? "Images were fetched but the current model does not support vision. Switch to a vision-capable model (Claude, GPT-4o, Qwen-VL) to analyse them." : summary
            return (fallback, [])
        }
        
        var attachments: [Message.Attachment] = []
        for (i, payload) in payloads.enumerated() {
            guard let mime = payload["mime"], let data = payload["data"] else { continue }
            let url = payload["url"] ?? "image_\(i+1)"
            let filename = URL(string: url)?.lastPathComponent ?? "image_\(i+1)"
            attachments.append(Message.Attachment(filename: filename, mimeType: mime, data: data))
        }
        
        let textContent = summary.isEmpty ? "Analysing \(attachments.count) image(s)..." : summary
        return (textContent, attachments)
    }
    
    // MARK: - Helpers
    
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
              let mi = session.messages.firstIndex(where: { $0.id == messageID }),
              let ti = session.messages[mi].toolCalls?.firstIndex(where: { $0.id == toolCallID }) else { return }
        session.messages[mi].toolCalls?[ti].status = status
        appState.activeSession = session
    }
    
    @MainActor
    private func updateToolCallResult(messageID: UUID, toolCallID: String, result: String, status: Message.ToolCall.ToolCallStatus, in appState: AppState) {
        guard var session = appState.activeSession,
              let mi = session.messages.firstIndex(where: { $0.id == messageID }),
              let ti = session.messages[mi].toolCalls?.firstIndex(where: { $0.id == toolCallID }) else { return }
        session.messages[mi].toolCalls?[ti].result = result
        session.messages[mi].toolCalls?[ti].status = status
        appState.activeSession = session
    }
    
    @MainActor
    private func updateContextUsage(_ appState: AppState) {
        guard let session = appState.activeSession, let model = appState.selectedModel else { return }
        let totalChars = session.messages.reduce(0) { $0 + $1.content.count + ($1.reasoning?.count ?? 0) }
        contextUsage = min(1.0, Double(totalChars / 4) / Double(model.contextWindow))
        if contextUsage >= 0.80 { Task { await self.compressContext(appState: appState) } }
    }
    
    // MARK: - Context Compression
    
    @MainActor
    func compressContext(appState: AppState) async {
        guard let session = appState.activeSession,
              let model = appState.selectedModel,
              let apiKey = appState.activeAPIKey ?? EnvParser.loadNVIDIAKey() else { return }
        let messages = session.messages
        let keepLast = 6
        guard messages.count > keepLast + 2 else { return }
        let toCompress = Array(messages.dropLast(keepLast))
        let toKeep = Array(messages.suffix(keepLast))
        let transcript = toCompress.compactMap { msg -> String? in
            switch msg.role {
            case .user:      return "User: \(msg.content)"
            case .assistant: return "Assistant: \(msg.content)"
            case .tool:      return "[Tool result: \(msg.content.prefix(200))]"
            case .system:    return nil
            }
        }.joined(separator: "\n")
        let summaryRequest = [
            Message(role: .system, content: "Summarise the following conversation history concisely in 3-5 sentences, preserving all key facts, decisions, file paths, and code discussed. Output only the summary."),
            Message(role: .user, content: transcript)
        ]
        streamingStatus = "Compressing context…"
        let service = ProviderServiceFactory.make(provider: appState.activeProvider, apiKey: apiKey)
        var summary = ""
        do {
            for try await chunk in service.chat(messages: summaryRequest, model: model, tools: nil, reasoningLevel: .off) {
                summary += chunk.content ?? ""
            }
        } catch {
            appState.showToast("Context compression failed: \(error.localizedDescription)", level: .warning)
            return
        }
        guard !summary.isEmpty else { return }
        appState.activeSession?.messages = [Message(role: .system, content: "📋 **[Conversation summary — earlier context compressed]**\n\n\(summary)")] + toKeep
        appState.saveActiveSession()
        updateContextUsage(appState)
        appState.showToast("Context compressed to free up space", level: .info)
    }
}
