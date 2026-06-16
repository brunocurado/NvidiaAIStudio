import SwiftUI

@Observable
final class ChatViewModel {
    var isStreaming = false
    var streamingStatus = "Thinking"
    var contextUsage: Double = 0.0
    var estimatedTokenCount: Int = 0
    var maxTokens: Int = 200_000
    var scrollTick: UInt = 0  // Increments periodically during streaming to trigger scroll
    
    private var streamTask: Task<Void, Never>?
    private let skillRegistry = SkillRegistry.shared
    private var lastScrollTime: ContinuousClock.Instant = .now
    private var lastUIUpdateTime: ContinuousClock.Instant = .now
    
    @MainActor
    func sendMessage(_ text: String, attachments: [Message.Attachment] = [], appState: AppState) async {
        if appState.activeSessionID == nil {
            let _ = appState.createSession(title: String(text.prefix(40)))
        }
        let userMessage = Message(role: .user, content: text, attachments: attachments)

        // FIX (v2.5.5): Pre-allocate the assistant placeholder in the SAME state
        // update as the user message. This eliminates the "enter flash" glitch caused
        // by the gap between user message insertion and the placeholder creation
        // (which previously happened inside agentLoop after validation work).
        let streamingID = UUID()
        let placeholder = Message(id: streamingID, role: .assistant, content: "", isStreaming: true)

        appState.mutateActiveSession { session in
            session.messages.append(userMessage)
            session.messages.append(placeholder)
            session.updatedAt = Date()
            if session.messages.count == 2 {
                session.title = String(text.prefix(50))
            }
        }

        let providerKey = appState.activeAPIKey
        guard let apiKey = providerKey ?? (appState.activeProvider == .nvidia ? EnvParser.loadNVIDIAKey() : nil) else {
            appState.mutateActiveSession { session in
                session.messages.removeAll { $0.id == streamingID }
            }
            let errorMsg = Message(role: .assistant, content: "⚠️ No API key configured for \(appState.activeProvider.rawValue).\n\nGo to **Settings → API Keys** to add your key.")
            appState.mutateActiveSession { $0.messages.append(errorMsg) }
            return
        }
        guard let model = appState.selectedModel else {
            appState.mutateActiveSession { session in
                session.messages.removeAll { $0.id == streamingID }
            }
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
            await self.agentLoop(streamingID: streamingID, service: service, model: model, tools: tools, appState: appState, reasoningLevel: appState.reasoningLevel)
        }
    }
    
    @MainActor
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
    
    private func extractLongCatToolCalls(from content: String) -> (toolCalls: [Message.ToolCall], cleanedContent: String) {
        let namePattern = #"<longcat_tool_call>\s*([^<]+?)\s*</longcat_tool_call>"#
        guard let nameRegex = try? NSRegularExpression(pattern: namePattern, options: [.dotMatchesLineSeparators]) else {
            return ([], content)
        }
        
        var cleanedContent = content
        var toolCalls: [Message.ToolCall] = []
        let nsContent = content as NSString
        let matches = nameRegex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        
        for (index, match) in matches.enumerated().reversed() {
            guard match.numberOfRanges == 2 else { continue }
            
            let name = nsContent.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let nextStart = index + 1 < matches.count ? matches[index + 1].range.location : nsContent.length
            let blockRange = NSRange(location: match.range.location, length: nextStart - match.range.location)
            let rawBlock = nsContent.substring(with: blockRange)
            let arguments = longCatArguments(from: rawBlock)
            
            guard !name.isEmpty else { continue }
            let id = "longcat_call_" + UUID().uuidString.prefix(8)
            toolCalls.insert(Message.ToolCall(id: String(id), name: name, arguments: arguments, status: .pending), at: 0)
            cleanedContent = (cleanedContent as NSString).replacingCharacters(in: blockRange, with: "")
        }
        
        return (toolCalls, cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    private func longCatArguments(from block: String) -> String {
        var args: [String: String] = [:]
        collectLongCatArguments(from: block, pattern: #"<longcat_arg_key>\s*([\s\S]*?)\s*</longcat_arg_key>\s*<longcat_arg_value>\s*([\s\S]*?)\s*</longcat_arg_value>"#, keyRange: 1, valueRange: 2, into: &args)
        collectLongCatArguments(from: block, pattern: #"<longcat_arg_value>\s*([\s\S]*?)\s*</longcat_arg_value>\s*<longcat_arg_key>\s*([\s\S]*?)\s*</longcat_arg_key>"#, keyRange: 2, valueRange: 1, into: &args)
        
        guard !args.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
    
    private func collectLongCatArguments(
        from block: String,
        pattern: String,
        keyRange: Int,
        valueRange: Int,
        into args: inout [String: String]
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }
        let nsBlock = block as NSString
        let matches = regex.matches(in: block, range: NSRange(location: 0, length: nsBlock.length))
        for match in matches where match.numberOfRanges > max(keyRange, valueRange) {
            let key = nsBlock.substring(with: match.range(at: keyRange)).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = nsBlock.substring(with: match.range(at: valueRange)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                args[key] = value
            }
        }
    }
    
    // MARK: - Agent Loop
    
    private func agentLoop(
        streamingID: UUID,
        service: any AIProvider,
        model: AIModel,
        tools: [[String: Any]],
        appState: AppState,
        reasoningLevel: ReasoningLevel
    ) async {
        let maxIterations = 50
        
        for _ in 0..<maxIterations {
            if Task.isCancelled { break }
            
            // streamingID comes from sendMessage (pre-allocated placeholder)
            // except on subsequent iterations where we keep reusing it
            
            // Collect messages to send BEFORE inserting the placeholder
            let messagesToSend = await MainActor.run {
                // Build system prompt with workspace context (dynamic injection)
                let systemContent = SystemPrompt.build(
                    workspacePath: appState.activeWorkspacePath,
                    branch: appState.currentBranch
                )
                var msgs = [SystemPrompt.asMessage(systemContent)]
                
                // Use the model's defined context window
                let resolvedMaxTokens = model.contextWindow
                
                // Context Manager: Tool Output Pruning
                let history = appState.activeSession?.messages ?? []
                let totalMessages = history.count
                var prunedHistory: [Message] = []
                
                for (index, msg) in history.enumerated() {
                    var finalMsg = msg
                    let turnAge = totalMessages - index
                    
                    // If a tool output is older than ~6 messages and is huge (e.g. source code), truncate it!
                    if finalMsg.role == .tool && finalMsg.content.count > 1500 && turnAge > 6 {
                        finalMsg.content = "[Context Manager Note: The raw output of this tool (\(finalMsg.content.count) bytes) was truncated to preserve Context Window limits because it exceeds an age of 6 turns. The agent can confidently assume it successfully executed this tool in the past. If the agent needs to re-read the exact content, it must invoke the tool again.]"
                    }
                    prunedHistory.append(finalMsg)
                }
                
                msgs += prunedHistory.filter { !$0.content.isEmpty || $0.role == .system || $0.role == .tool || $0.toolCalls != nil }
                
                // Token Estimation - Feature #2
                let tokenCount = TokenEstimator.estimateSession(msgs)
                self.estimatedTokenCount = tokenCount
                self.maxTokens = resolvedMaxTokens
                self.contextUsage = Double(tokenCount) / Double(resolvedMaxTokens)
                
                // Auto-Compaction threshold check - Feature #3
                // Use real LLM-based summarization instead of destructive content clearing
                if self.contextUsage > 0.8 {
                    let messagesToCompress = msgs
                    Task { @MainActor in
                        appState.showToast("Context hit 80%. Summarizing history...", level: .warning)
                        await self.compressContext(appState: appState)
                        self.contextUsage -= 0.2 // Approximate update for UI
                    }
                    // For this iteration, still send the messages but mark them as pending compaction
                    // The next iteration will pick up the compressed state
                    _ = messagesToCompress
                }
                
                // (Vision attachments from KB are now handled selectively by the tool or disabled to save tokens)
                
                return self.sanitizeMessages(msgs)
            }
            
            // Placeholder was pre-allocated in sendMessage (first iteration).
            // On subsequent iterations (after tool-use), just re-activate streaming.
            await MainActor.run {
                self.streamingStatus = model.supportsThinking ? "Thinking" : "Generating"
                // Check if our placeholder already exists from sendMessage
                let placeholderExists = appState.activeSession?.messages.contains { $0.id == streamingID } ?? false
                if !placeholderExists {
                    // Re-insert placeholder for second+ iteration (tool response loop)
                    appState.mutateActiveSession {
                        $0.messages.append(Message(id: streamingID, role: .assistant, content: "", isStreaming: true))
                    }
                } else {
                    // Re-activate streaming on existing placeholder
                    if let si = appState.sessions.firstIndex(where: { $0.id == appState.activeSessionID }),
                       let mi = appState.sessions[si].messages.firstIndex(where: { $0.id == streamingID }) {
                        appState.sessions[si].messages[mi].isStreaming = true
                    }
                }
            }
            
            var accContent = ""
            var accReasoning: String? = nil
            var accToolCalls: [Message.ToolCall]? = nil
            var accUsage: TokenUsage? = nil
            var accFinishReason: String? = nil
            
            do {
                let stream = service.chat(messages: messagesToSend, model: model, tools: tools.isEmpty ? nil : tools, reasoningLevel: reasoningLevel)
                
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    
                    if let r = chunk.reasoning {
                        accReasoning = (accReasoning ?? "") + r
                        await MainActor.run { self.streamingStatus = "Thinking" }
                    }
                    if let c = chunk.content { accContent += c; await MainActor.run { self.streamingStatus = "Writing" } }
                    if let tc = chunk.toolCalls { accToolCalls = tc; await MainActor.run { self.streamingStatus = "Running tools" } }
                    if let u = chunk.usage { accUsage = u }
                    if let fr = chunk.finishReason { accFinishReason = fr }
                    
                    // Throttle UI updates to ~6/sec (every 150ms)
                    let now = ContinuousClock.now
                    guard now - self.lastUIUpdateTime >= .milliseconds(150) else { continue }
                    self.lastUIUpdateTime = now
                    
                    let snapContent = accContent
                    let snapReasoning = accReasoning
                    let snapToolCalls = accToolCalls
                    
                    await MainActor.run {
                        self.updateMessage(id: streamingID, with: Message(id: streamingID, role: .assistant, content: snapContent, reasoning: snapReasoning, toolCalls: snapToolCalls, isStreaming: true), in: appState)
                        // Throttled scroll tick
                        if now - self.lastScrollTime >= .milliseconds(300) {
                            self.scrollTick &+= 1
                            self.lastScrollTime = now
                        }
                    }
                }
                
                // If stream was cancelled by user interrupt, clean up the placeholder and abort entirely
                if Task.isCancelled {
                    await MainActor.run {
                        self.isStreaming = false
                        appState.mutateActiveSession { session in
                            session.messages.removeAll(where: { $0.id == streamingID })
                        }
                    }
                    return
                }
                
                // Finalize: mark message as no longer streaming
                var finalContent = accContent
                let finalReasoning = accReasoning
                var extractedToolCalls = accToolCalls ?? []
                
                let longCatResult = extractLongCatToolCalls(from: finalContent)
                if !longCatResult.toolCalls.isEmpty {
                    extractedToolCalls.append(contentsOf: longCatResult.toolCalls)
                    finalContent = longCatResult.cleanedContent
                }
                
                // DeepSeek V4-Pro/Claude XML Tool Call Parser
                let pattern = "<tool_call\\s+name=\"([^\"]+)\">\\s*(.*?)\\s*</tool_call>"
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                    let nsString = finalContent as NSString
                    let matches = regex.matches(in: finalContent, range: NSRange(location: 0, length: nsString.length))
                    
                    for match in matches.reversed() {
                        if match.numberOfRanges == 3 {
                            let name = nsString.substring(with: match.range(at: 1))
                            let arguments = nsString.substring(with: match.range(at: 2))
                            let id = "xml_call_" + UUID().uuidString.prefix(8)
                            extractedToolCalls.append(Message.ToolCall(id: String(id), name: name, arguments: arguments, status: .pending))
                            finalContent = (finalContent as NSString).replacingCharacters(in: match.range, with: "")
                        }
                    }
                }
                
                // DeepSeek V4 Flash DSML Tool Call Parser
                let dsmlPattern = "<(?:｜|\\|)DSML(?:｜|\\|)invoke\\s+name=\"([^\"]+)\">\\s*(.*?)\\s*</(?:｜|\\|)DSML(?:｜|\\|)invoke>"
                if let dsmlRegex = try? NSRegularExpression(pattern: dsmlPattern, options: [.dotMatchesLineSeparators]) {
                    let nsString = finalContent as NSString
                    let matches = dsmlRegex.matches(in: finalContent, range: NSRange(location: 0, length: nsString.length))
                    
                    for match in matches.reversed() {
                        if match.numberOfRanges == 3 {
                            let name = nsString.substring(with: match.range(at: 1))
                            let innerContent = nsString.substring(with: match.range(at: 2))
                            var argsDict: [String: String] = [:]
                            
                            let paramPattern = "<(?:｜|\\|)DSML(?:｜|\\|)parameter\\s+name=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</(?:｜|\\|)DSML(?:｜|\\|)parameter>"
                            if let paramRegex = try? NSRegularExpression(pattern: paramPattern, options: [.dotMatchesLineSeparators]) {
                                let innerNSString = innerContent as NSString
                                let paramMatches = paramRegex.matches(in: innerContent, range: NSRange(location: 0, length: innerNSString.length))
                                for pMatch in paramMatches {
                                    if pMatch.numberOfRanges == 3 {
                                        let pName = innerNSString.substring(with: pMatch.range(at: 1))
                                        let pValue = innerNSString.substring(with: pMatch.range(at: 2))
                                        argsDict[pName] = pValue
                                    }
                                }
                            }
                            
                            let arguments = (try? String(data: JSONEncoder().encode(argsDict), encoding: .utf8)) ?? "{}"
                            let id = "dsml_call_" + UUID().uuidString.prefix(8)
                            extractedToolCalls.append(Message.ToolCall(id: String(id), name: name, arguments: arguments, status: .pending))
                            
                            finalContent = (finalContent as NSString).replacingCharacters(in: match.range, with: "")
                        }
                    }
                }
                
                // Clean up remaining DSML wrapper tags if any
                finalContent = finalContent.replacingOccurrences(of: "<｜DSML｜tool_calls>", with: "").replacingOccurrences(of: "</｜DSML｜tool_calls>", with: "")
                finalContent = finalContent.replacingOccurrences(of: "<|DSML|tool_calls>", with: "").replacingOccurrences(of: "</|DSML|tool_calls>", with: "")
                
                finalContent = finalContent.trimmingCharacters(in: .whitespacesAndNewlines)
                let completedContent = finalContent
                let finalToolCalls = extractedToolCalls.isEmpty ? nil : extractedToolCalls
                
                await MainActor.run {
                    self.updateMessage(id: streamingID, with: Message(id: streamingID, role: .assistant, content: completedContent, reasoning: finalReasoning, toolCalls: finalToolCalls, isStreaming: false), in: appState)
                }
                
                // Query Loop Recovery - Feature #1
                // If model output hit the maximum length limit, we prompt it to seamlessly continue.
                if accFinishReason == "length" || accFinishReason == "max_tokens" {
                    await MainActor.run {
                        appState.mutateActiveSession { session in
                            session.messages.append(Message(role: .user, content: "[System: Your response was truncated due to output length constraints. Please continue exactly where you left off without any preamble or apology, just resume code or text.]"))
                        }
                    }
                    // Loop again seamlessly!
                    continue
                }
                
                if let toolCalls = finalToolCalls, !toolCalls.isEmpty {
                    await MainActor.run { self.streamingStatus = "Executing tools (\(toolCalls.count))" }
                    
                    let readOnlyTools = ["read_file", "list_directory", "search_files", "web_search", "fetch_url", "fetch_images", "search_knowledge_base"]
                    var concurrentCalls: [Message.ToolCall] = []
                    var serialCalls: [Message.ToolCall] = []
                    
                    for tc in toolCalls {
                        if readOnlyTools.contains(tc.name) { concurrentCalls.append(tc) }
                        else { serialCalls.append(tc) }
                    }
                    
                    // Concurrent Group
                    if !concurrentCalls.isEmpty {
                        await withTaskGroup(of: Void.self) { group in
                            for toolCall in concurrentCalls {
                                group.addTask {
                                    await self.executeSingleTool(toolCall, streamingID: streamingID, appState: appState)
                                }
                            }
                        }
                    }
                    
                    // Serial Group
                    for toolCall in serialCalls {
                        await self.executeSingleTool(toolCall, streamingID: streamingID, appState: appState)
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
                    // Record usage: prefer API-reported tokens, fallback to local estimation
                    let promptTok: Int
                    let completionTok: Int
                    if let usage = doneUsage {
                        promptTok = usage.promptTokens
                        completionTok = usage.completionTokens
                    } else {
                        // Estimate from local context: input = all messages before response, output = response content
                        let inputChars = appState.activeSession?.messages
                            .filter { $0.role != .assistant || $0.id != streamingID }
                            .reduce(0) { $0 + $1.content.count + ($1.reasoning?.count ?? 0) } ?? 0
                        promptTok = max(1, inputChars / 4)
                        completionTok = max(1, doneContent.count / 4)
                    }
                    UsageStore.shared.append(UsageStore.Record(
                        id: UUID(), date: Date(),
                        provider: appState.activeProvider.rawValue,
                        modelID: model.id, modelName: model.name,
                        sessionTitle: appState.activeSession?.title ?? "Thread",
                        promptTokens: promptTok, completionTokens: completionTok
                    ))
                    if doneContent.isEmpty && doneToolCalls == nil { appState.showToast("Empty response from model", level: .warning) }
                    let cleanName = String(model.name.drop(while: { !$0.isLetter && !$0.isNumber }))
                        .components(separatedBy: "—").first?.trimmingCharacters(in: .whitespaces) ?? model.name
                    AppNotifications.sendResponseCompleted(modelName: cleanName)
                }
                
                return
            } catch let error as CancellationError {
                _ = error
                await MainActor.run {
                    self.isStreaming = false
                    appState.mutateActiveSession { session in
                        session.messages.removeAll(where: { $0.id == streamingID })
                    }
                }
                return
            } catch let error as NSError where error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                await MainActor.run {
                    self.isStreaming = false
                    appState.mutateActiveSession { session in
                        session.messages.removeAll(where: { $0.id == streamingID })
                    }
                }
                return
            } catch {
                let errContent = accContent
                let errReasoning = accReasoning
                await MainActor.run {
                    let errorContent = errContent.isEmpty ? "⚠️ Error: \(error.localizedDescription)" : errContent + "\n\n⚠️ Error: \(error.localizedDescription)"
                    let errorMsg = Message(id: streamingID, role: .assistant, content: errorContent, reasoning: errReasoning, isStreaming: false)
                    self.updateMessage(id: streamingID, with: errorMsg, in: appState)
                    self.isStreaming = false
                    appState.showToast("API Error: \(error.localizedDescription)", level: .error)
                }
                return
            }
        }
        
        await MainActor.run {
            self.isStreaming = false
            appState.showToast("Agent loop reached maximum iterations (\(maxIterations))", level: .warning)
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
    
    // MARK: - Message Sanitization
    
    /// Ensures the message array has valid role ordering for strict APIs (Mistral, etc).
    /// Rules enforced:
    ///   1. `tool` messages must be preceded by `assistant` with `toolCalls`
    ///   2. `tool` messages must NOT be directly followed by `user` — an `assistant` bridge is injected
    ///   3. Orphaned `tool` messages (no preceding assistant+toolCalls) are removed
    private func sanitizeMessages(_ messages: [Message]) -> [Message] {
        var result: [Message] = []
        
        for msg in messages {
            // Rule 1: tool must follow assistant with toolCalls or another tool message
            if msg.role == .tool {
                var valid = false
                if let prev = result.last {
                    if prev.role == .assistant && prev.toolCalls != nil {
                        valid = true
                    } else if prev.role == .tool {
                        valid = true // Allow consecutive tool results
                    }
                }
                guard valid else { continue }
            }
            // Rule 2: Merge consecutive same-role messages (except tool)
            if let prev = result.last, prev.role == msg.role, msg.role != .tool {
                result[result.count - 1] = Message(
                    id: prev.id, role: prev.role,
                    content: prev.content + "\n" + msg.content,
                    attachments: prev.attachments + msg.attachments,
                    timestamp: prev.timestamp,
                    reasoning: msg.reasoning ?? prev.reasoning,
                    toolCalls: msg.toolCalls ?? prev.toolCalls,
                    toolCallId: msg.toolCallId ?? prev.toolCallId,
                    isStreaming: prev.isStreaming || msg.isStreaming,
                    statusBadges: prev.statusBadges + msg.statusBadges
                )
                continue
            }
            // Rule 3: Bridge tool→user with assistant
            if msg.role == .user, let prev = result.last, prev.role == .tool {
                result.append(Message(role: .assistant, content: "Understood. Continuing..."))
            }
            result.append(msg)
        }
        
        // Rule 4: Strip unmatched tool_calls (Mistral requires exact match)
        var toolResponseIds = Set<String>()
        for msg in result where msg.role == .tool {
            if let tcId = msg.toolCallId { toolResponseIds.insert(tcId) }
        }
        
        return result.map { msg in
            guard msg.role == .assistant, let toolCalls = msg.toolCalls, !toolCalls.isEmpty else {
                return msg
            }
            let matched = toolCalls.filter { toolResponseIds.contains($0.id) }
            if matched.count == toolCalls.count { return msg }
            var cleaned = msg
            if matched.isEmpty {
                cleaned.toolCalls = nil
                if cleaned.content.isEmpty {
                    cleaned.content = "I attempted to use tools but encountered an issue."
                }
            } else {
                cleaned.toolCalls = matched
            }
            return cleaned
        }
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func updateMessage(id: UUID, with message: Message, in appState: AppState) {
        guard let si = appState.sessions.firstIndex(where: { $0.id == appState.activeSessionID }),
              let mi = appState.sessions[si].messages.firstIndex(where: { $0.id == id })
        else { return }
        appState.sessions[si].messages[mi] = message
    }
    
    @MainActor
    private func updateToolCallStatus(messageID: UUID, toolCallID: String, status: Message.ToolCall.ToolCallStatus, in appState: AppState) {
        guard let si = appState.sessions.firstIndex(where: { $0.id == appState.activeSessionID }),
              let mi = appState.sessions[si].messages.firstIndex(where: { $0.id == messageID }),
              let ti = appState.sessions[si].messages[mi].toolCalls?.firstIndex(where: { $0.id == toolCallID })
        else { return }
        appState.sessions[si].messages[mi].toolCalls?[ti].status = status
    }
    
    @MainActor
    private func updateToolCallResult(messageID: UUID, toolCallID: String, result: String, status: Message.ToolCall.ToolCallStatus, in appState: AppState) {
        guard let si = appState.sessions.firstIndex(where: { $0.id == appState.activeSessionID }),
              let mi = appState.sessions[si].messages.firstIndex(where: { $0.id == messageID }),
              let ti = appState.sessions[si].messages[mi].toolCalls?.firstIndex(where: { $0.id == toolCallID })
        else { return }
        appState.sessions[si].messages[mi].toolCalls?[ti].result = result
        appState.sessions[si].messages[mi].toolCalls?[ti].status = status
    }
    
    @MainActor
    private func updateContextUsage(_ appState: AppState) {
        guard let session = appState.activeSession, let model = appState.selectedModel else { return }
        let totalChars = session.messages.reduce(0) { $0 + $1.content.count + ($1.reasoning?.count ?? 0) }
        let tokens = totalChars / 4
        estimatedTokenCount = tokens
        maxTokens = model.contextWindow
        contextUsage = min(1.0, Double(tokens) / Double(model.contextWindow))
        if contextUsage >= 0.80 { Task { await self.compressContext(appState: appState) } }
    }
    
    // MARK: - Context Compression
    
    @MainActor
    func compressContext(appState: AppState) async {
        guard let session = appState.activeSession,
              let model = appState.selectedModel,
              let service = ProviderServiceFactory.makeFromAppState(appState) else { return }
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
        appState.mutateActiveSession { $0.messages = [Message(role: .system, content: "📋 **[Conversation summary — earlier context compressed]**\n\n\(summary)")] + toKeep }
        appState.saveActiveSession()
        updateContextUsage(appState)
        appState.showToast("Context compressed to free up space", level: .info)
    }
    
    // MARK: - Status Badge Helpers
    
    private func badgeTextForTool(_ toolCall: Message.ToolCall) -> String {
        let filename = extractFilename(from: toolCall.arguments)
        switch toolCall.name {
        case "read_file":
            return "Explored \(filename ?? "file")"
        case "list_directory":
            return "Exploring directory..."
        case "run_command":
            let cmd = extractCommand(from: toolCall.arguments) ?? "command"
            return "Running: \(String(cmd.prefix(40)))"
        case "write_file", "edit_file", "replace_file":
            return "Editing \(filename ?? "file")..."
        case "search_files":
            return "Searching files..."
        case "web_search":
            return "Searching the web..."
        case "generate_image":
            return "Generating image..."
        case "git":
            return "Running git..."
        case "fetch_url":
            return "Fetching URL..."
        default:
            return "Running \(toolCall.name)..."
        }
    }
    
    private func iconForTool(_ name: String) -> String {
        switch name {
        case "read_file":       return "doc.text.magnifyingglass"
        case "write_file", "edit_file", "replace_file": return "square.and.pencil"
        case "list_directory":  return "folder.fill"
        case "search_files":    return "magnifyingglass"
        case "run_command":     return "terminal.fill"
        case "generate_image":  return "photo.fill"
        case "git":             return "arrow.triangle.branch"
        case "fetch_url":       return "globe"
        case "web_search":      return "magnifyingglass.circle.fill"
        default:                return "puzzlepiece.fill"
        }
    }
    
    private func extractFilename(from arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = json["path"] as? String ?? json["file_path"] as? String ?? json["filename"] as? String
        else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    
    private func extractCommand(from arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json["command"] as? String
    }
    
    // MARK: - Extracted Concurrent Tool Execution
    private func executeSingleTool(_ toolCall: Message.ToolCall, streamingID: UUID, appState: AppState) async {
        await MainActor.run {
            let badgeText = self.badgeTextForTool(toolCall)
            let badgeIcon = self.iconForTool(toolCall.name)
            if let si = appState.sessions.firstIndex(where: { $0.id == appState.activeSessionID }),
               let mi = appState.sessions[si].messages.firstIndex(where: { $0.id == streamingID }) {
                appState.sessions[si].messages[mi].statusBadges.append(
                    Message.StatusBadge(text: badgeText, icon: badgeIcon)
                )
            }
            self.updateToolCallStatus(messageID: streamingID, toolCallID: toolCall.id, status: .running, in: appState)
        }
        
        let accessLevel = await MainActor.run { appState.fileAccessLevel }
        let workspacePath = await MainActor.run { appState.activeWorkspacePath }
        let supportsVision = await MainActor.run { appState.selectedModel?.supportsVision ?? false }
        
        let rawResult: String
        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    return try await self.skillRegistry.execute(name: toolCall.name, arguments: toolCall.arguments, accessLevel: accessLevel, workspacePath: workspacePath)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds timeout
                    throw CancellationError()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
            
            // UI & Memory Protection: Truncate massively oversized tool outputs
            if result.count > 100_000 && toolCall.name != "generate_image" {
                rawResult = String(result.prefix(100_000)) + "\n\n... [TRUNCATED: The output exceeded 100,000 characters and was truncated to protect application memory. This usually happens when listing a massive directory. Please use `run_command` with constraints (e.g. find . -maxdepth 2) instead.]"
            } else {
                rawResult = result
            }
            
            await MainActor.run {
                self.updateToolCallResult(messageID: streamingID, toolCallID: toolCall.id, result: rawResult, status: .completed, in: appState)
                if ["write_file", "edit_file", "replace_file"].contains(toolCall.name) {
                    NotificationCenter.default.post(name: .diffShouldRefresh, object: nil)
                }
            }
        } catch is CancellationError {
            rawResult = "Error: Tool execution timed out after 30 seconds. The operation took too long (this often happens when running directory trees on massive folders like node_modules). Please try a more specific command."
            await MainActor.run {
                self.updateToolCallResult(messageID: streamingID, toolCallID: toolCall.id, result: rawResult, status: .failed, in: appState)
            }
        } catch {
            rawResult = "Error: \(error.localizedDescription)"
            await MainActor.run {
                self.updateToolCallResult(messageID: streamingID, toolCallID: toolCall.id, result: rawResult, status: .failed, in: appState)
            }
        }
        
        let (textContent, imageAttachments) = self.extractVisionPayload(from: rawResult, supportsVision: supportsVision)
        
        await MainActor.run {
            let toolResultMessage = Message(
                role: .tool,
                content: textContent,
                attachments: imageAttachments,
                toolCallId: toolCall.id
            )
            appState.mutateActiveSession { $0.messages.append(toolResultMessage) }
        }
    }
}
