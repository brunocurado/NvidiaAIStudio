import SwiftUI
import SwiftData

/// The Swarm Orchestrator — a singleton that polls for pending tasks and executes them
/// using background agents. Each agent runs in its own Task with an isolated ModelContext.
///
/// Architecture:
/// - Polls every 2 seconds for `SwarmTask` where `status == "pending"`
/// - Picks the highest-priority task and runs the agent loop
/// - Uses the same `AIProvider` + `SkillRegistry` infrastructure as `ChatViewModel`
/// - Supports mid-execution directives via the Event Bus (Mailbox)
///
/// Thread Safety:
/// - Each agent task creates its own `ModelContext` from the shared `ModelContainer`
/// - UI updates are dispatched to `@MainActor`
@Observable
final class SwarmOrchestrator {
    
    // MARK: - Public State (UI-bindable)
    
    /// Currently running agent tasks (for UI display)
    var runningTasks: [SwarmTaskSnapshot] = []
    
    /// Total pending tasks in queue
    var pendingCount: Int = 0
    
    /// Unread deliverables count (for badge display)
    var unreadDeliverableCount: Int = 0
    
    /// Is the orchestrator actively polling?
    var isActive: Bool = false
    
    // MARK: - Event Bus (Mailbox)

    /// The mailbox: UI writes here, the running agent reads it at its next natural pause.
    /// Key: Task ID, Value: Directive/Message
    /// Marked @MainActor for thread safety — accessed from UI and agent loops.
    @MainActor
    private var pendingDirectives: [UUID: String] = [:]

    // Interrupt flags for immediate "CEO Priority Override" during API streams
    @MainActor
    private var interruptFlags: [UUID: Bool] = [:]

    /// Post a directive to a running agent. It will see it between tool executions.
    @MainActor
    func postDirective(to taskID: UUID, message: String) {
        pendingDirectives[taskID] = message
    }
    
    // MARK: - Private
    
    private let modelContainer: ModelContainer
    private let skillRegistry = SkillRegistry.shared
    private var pollTask: Task<Void, Never>?
    private var activeTasks: Set<UUID> = []  // Prevent double-pickup
    private weak var appState: AppState?
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    /// Wire the orchestrator to the AppState (called from bootstrap).
    func configure(appState: AppState) {
        self.appState = appState
        setupObservers()
    }
    
    // MARK: - Event Observers
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(
            forName: .canvasJSErrorDetected,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleVisualError(note: note)
        }
    }
    
    private func handleVisualError(note: Notification) {
        guard let userInfo = note.userInfo,
              let trace = userInfo["trace"] as? String else { return }
        
        // We only want to inject an emergency if there's an ACTIVE agent
        // and if it's the one that spawned it? Actually, if any agent is running
        // the CEO could just broadcast this back.
        
        guard let activeTask = activeTasks.first else { return }

        AppLog.swarm.notice("🛑 Orchestrator intercepting Visual Error: Injecting to task \(activeTask, privacy: .public)")

        // Inject as a system directive directly (thread-safe via MainActor)
        Task { @MainActor in
            self.postDirective(to: activeTask, message: "[URGENT VISUAL OVERRIDE] Dev server triggered a JS exception: \n\(trace)\nFix this issue immediately.")
        }
    }
    
    private var activeJobHandles: [UUID: Task<Void, Never>] = [:]
    
    // MARK: - Lifecycle
    
    /// Start the polling loop. Call from AppState.bootstrap().
    func start() {
        guard pollTask == nil else { return }
        isActive = true
        
        // Clean up zombie tasks from previous run/crashes
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SwarmTask>(predicate: #Predicate { $0.status == "running" })
        if let zombies = try? context.fetch(descriptor) {
            for z in zombies {
                z.status = "failed"
                z.errorMessage = "Cancelled due to system restart"
            }
            try? context.save()
        }
        
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    
    /// Stop the polling loop.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isActive = false
        // cancel all active jobs too
        for handle in activeJobHandles.values {
            handle.cancel()
        }
        activeJobHandles.removeAll()
        activeTasks.removeAll()
    }
    
    // MARK: - Polling Tick
    
    /// Single tick: fetch pending tasks, dispatch agents for new ones.
    @MainActor
    private func tick() async {
        let context = ModelContext(modelContainer)
        
        // Fetch pending tasks sorted by priority (highest first)
        let descriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.status == "pending" },
            sortBy: [SortDescriptor(\.priority, order: .reverse)]
        )
        
        guard let pendingTasks = try? context.fetch(descriptor) else { return }
        
        self.pendingCount = pendingTasks.count
        
        // Fetch unread deliverables
        let delivDescriptor = FetchDescriptor<SwarmDeliverable>(
            predicate: #Predicate { $0.isRead == false }
        )
        self.unreadDeliverableCount = (try? context.fetchCount(delivDescriptor)) ?? 0
        
        // Dispatch agents for tasks not already running
        for task in pendingTasks {
            guard !activeTasks.contains(task.id) else { continue }
            activeTasks.insert(task.id)
            
            // Launch agent in background
            let handle = Task {
                await self.runAgent(for: task.id)
                await MainActor.run {
                    self.activeTasks.remove(task.id)
                    self.activeJobHandles.removeValue(forKey: task.id)
                    self.refreshSnapshots()
                }
            }
            activeJobHandles[task.id] = handle
        }
        
        refreshSnapshots()
    }
    
    public func cancelAgent(for taskID: UUID) {
        // 1. Cancel the local Swift Concurrency Task if it exists
        if let handle = activeJobHandles[taskID] {
            handle.cancel()
            activeJobHandles.removeValue(forKey: taskID)
        }
        
        activeTasks.remove(taskID)
        
        // 2. Force the DB to mark it as cancelled (fixes zombies from app reloads)
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        if let task = try? context.fetch(descriptor).first {
            task.status = "failed"
            task.errorMessage = "Cancelled by CEO"
            try? context.save()
        }
        
        Task { @MainActor in self.refreshSnapshots() }
    }
    
    /// Triggered by the UI when the CEO wants to immediately interrupt a speaking agent and inject a directive
    @MainActor
    public func forceInterrupt(taskID: UUID, directive: String) {
        pendingDirectives[taskID] = directive
        interruptFlags[taskID] = true
    }
    
    // MARK: - Agent Execution
    
    /// Run a single agent for a SwarmTask. Uses its own ModelContext for thread safety.
    private func runAgent(for taskID: UUID) async {
        // Create isolated ModelContext for this agent
        let context = ModelContext(modelContainer)
        
        // Fetch the task
        let descriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        guard let task = try? context.fetch(descriptor).first else {
            await appendLog(taskID: taskID, context: context, entry: "❌ Task not found")
            return
        }
        
        // Fetch the assigned agent persona
        guard let persona = task.assignedAgent else {
            await markFailed(task: task, context: context, error: "No agent assigned to this task")
            return
        }
        
        // Mark as running
        task.status = "running"
        task.logs.append("[\(Self.timestamp)] 🚀 Agent '\(persona.name)' starting task")
        try? context.save()
        
        await MainActor.run { self.refreshSnapshots() }
        
        // Build the AI service and resolve model from AppState
        guard let service = await MainActor.run(body: { [weak self] () -> (any AIProvider)? in
            guard let appState = self?.appState else { return nil }
            return ProviderServiceFactory.makeFromAppState(appState)
        }) else {
            await markFailed(task: task, context: context, error: "No AI service configured")
            return
        }
        let safePreferredModelId = persona.preferredModelId
        let accessLevel = await MainActor.run { [weak self] in self?.appState?.fileAccessLevel ?? .fullAccess }
        let workspacePath = await MainActor.run { [weak self] in self?.appState?.activeWorkspacePath ?? "" }
        let reasoningLevel = await MainActor.run { [weak self] in self?.appState?.reasoningLevel ?? .low }
        
        let agentModel = await MainActor.run { [weak self] () -> AIModel in
            guard let self = self, let appState = self.appState else {
                return AIModel.defaultModels.first!
            }
            // 1. If persona explicitly requests a model, try to match it in available
            if let preferredId = safePreferredModelId,
               let matched = appState.availableModels.first(where: { $0.id == preferredId }) {
                return matched
            }
            // 2. Otherwise fallback to the globally selected model
            if let selected = appState.selectedModel {
                return selected
            }
            return AIModel.defaultModels.first ?? AIModel(
                id: "qwen/qwen3-235b-a22b",
                name: "Qwen 3 235B",
                provider: .nvidia,
                contextWindow: 128_000
            )
        }
        
        // Build tool list filtered by agent's allowed tools
        let allTools = skillRegistry.toolDefinitions
        let agentTools: [[String: Any]]
        if persona.allowedTools.isEmpty {
            agentTools = allTools  // No restriction = full access
        } else {
            agentTools = allTools.filter { toolDef in
                guard let function = toolDef["function"] as? [String: Any],
                      let name = function["name"] as? String else { return false }
                return persona.allowedTools.contains(name)
            }
        }
        
        let isDebate = task.type == "debate" && task.debateOpponent != nil
        
        // In debate mode: assignedAgent = Moderator (opens & closes, does NOT argue)
        // debateOpponent + additionalOpponentNames = the actual debaters
        var debateParticipants: [AgentPersona] = []
        if isDebate {
            if let opp = task.debateOpponent { debateParticipants.append(opp) }
            // Resolve additional debaters by name
            let extraNames = task.additionalOpponentNames
            if !extraNames.isEmpty {
                let extraDesc = FetchDescriptor<AgentPersona>()
                let allPersonas = (try? context.fetch(extraDesc)) ?? []
                for name in extraNames {
                    if let p = allPersonas.first(where: { $0.name == name }) {
                        debateParticipants.append(p)
                    }
                }
            }
        }
        
        let maxIterations = isDebate ? task.maxRounds * max(debateParticipants.count, 1) : PromptConfig.default.maxSwarmIterations
        var selfHealingRetries = PromptConfig.default.selfHealingRetries
        var debateOpened = false   // tracks if moderator has already injected the opening
        
        for iteration in 0..<maxIterations {
            if Task.isCancelled { break }
            
            // 1. Determine active persona
            let currentPersona: AgentPersona
            if isDebate && !debateParticipants.isEmpty {
                // Moderator injects an opening brief on the very first turn only
                if !debateOpened {
                    let openingMsg = SwarmMessage(
                        role: "moderator",
                        content: "[DEBATE OPENED BY \(persona.name.uppercased())] Topic: \(task.taskDescription)\n\nAll participants, please argue your position on this topic. Be sharp, factual, and build on each other's arguments.",
                        senderName: persona.name
                    )
                    task.messages.append(openingMsg)
                    try? context.save()
                    debateOpened = true
                    task.logs.append("[\(Self.timestamp)] 🎙️ \(persona.name) opened the debate")
                }
                currentPersona = debateParticipants[iteration % debateParticipants.count]
            } else {
                currentPersona = persona
            }
            let activeTools = isDebate ? nil : (agentTools.isEmpty ? nil : agentTools)
            
            // 2. Build Perspective Matrix messages
            var messages: [Message] = []
            
            if isDebate {
                let otherNames = debateParticipants.filter { $0.name != currentPersona.name }.map { $0.name }.joined(separator: ", ")
                let moderatorName = persona.name
                var debateContext = "\n\n[DEBATE MODE] You are in a structured debate moderated by \(moderatorName). Debating against: \(otherNames). Topic: \(task.taskDescription). Read ALL previous arguments carefully and respond to the most recent ones. BE PRAGMATIC AND DIRECT. DO NOT use conversational filler (e.g. 'I agree with', 'That is an excellent point'). DO NOT write conclusions or summaries. State ONLY your technical objections or counter-proposals. Limit your response to mostly 2 or 3 crisp paragraphs of highly actionable insight to maintain dynamic pace."
                
                if let canvas = task.sharedCanvasContent, !canvas.isEmpty {
                    debateContext += "\n\n[SHARED CANVAS STATE]\n\(canvas)\n\nIf your proposal requires updating the shared blueprint/state, rewrite the necessary parts and wrap the ENTIRE updated content strictly within <canvas></canvas> XML tags."
                } else {
                    debateContext += "\n\n[SHARED CANVAS STATE]\n(Empty)\n\nIf you propose a concrete architecture, list, or blueprint, define it and wrap it strictly within <canvas></canvas> XML tags so it renders dynamically on the CEO's Shared Canvas."
                }
                
                messages.append(Message(role: .system, content: currentPersona.systemPrompt + debateContext))
                
                // Repetition detection — last 2 messages from this agent
                let myPriorMessages = task.messages
                    .filter { $0.role == "agent" && $0.senderName == currentPersona.name }
                    .sorted(by: { $0.timestamp < $1.timestamp })
                if myPriorMessages.count >= 2 {
                    let lastTwo = myPriorMessages.suffix(2).map { $0.content }
                    let similarity = lastTwo[0].prefix(200) == lastTwo[1].prefix(200)
                    if similarity {
                        messages.append(Message(role: .system, content: "You have already stated this point. You are repeating yourself. Offer a new perspective, a concrete example, or yield the floor gracefully."))
                    }
                }
            } else {
                messages.append(Message(role: .system, content: currentPersona.systemPrompt))
                messages.append(Message(role: .user, content: task.taskDescription))
            }
            
            // Reconstruct the LLM thread dynamically based on currentPersona's perspective
            for swarmMsg in task.messages.sorted(by: { $0.timestamp < $1.timestamp }) {
                if swarmMsg.role == "moderator" || swarmMsg.senderName == "CEO" {
                    messages.append(Message(role: .user, content: swarmMsg.content))
                } else if swarmMsg.role == "agent_tool_call" {
                    if let toolCalls = Self.decodeToolCallEnvelope(swarmMsg.content) {
                        messages.append(Message(role: .assistant, content: "", toolCalls: toolCalls))
                    }
                } else if swarmMsg.role == "tool" {
                    messages.append(Message(role: .tool, content: swarmMsg.content, toolCallId: swarmMsg.senderName))
                } else if swarmMsg.role == "agent" {
                    if swarmMsg.senderName == currentPersona.name {
                        messages.append(Message(role: .assistant, content: swarmMsg.content))
                    } else {
                        messages.append(Message(role: .user, content: "[\(swarmMsg.senderName)]: \(swarmMsg.content)"))
                    }
                }
            }
            
            // Check Event Bus for directives
            if let directive = await MainActor.run(body: { self.pendingDirectives.removeValue(forKey: taskID) }) {
                let directiveMsg = SwarmMessage(role: "moderator", content: directive, senderName: "CEO")
                task.messages.append(directiveMsg)
                messages.append(Message(role: .user, content: "[CEO Directive]: \(directive)"))
                task.logs.append("[\(Self.timestamp)] 📋 CEO directive injected")
                try? context.save()
            }
            
            task.logs.append("[\(Self.timestamp)] 🔄 Iteration \(iteration + 1)")
            try? context.save()
            
            // Stream LLM response
            var accContent = ""
            var accToolCalls: [Message.ToolCall]? = nil
            var accFinishReason: String? = nil
            
            do {
                    let stream = service.chat(
                        messages: messages,
                        model: agentModel,
                        tools: activeTools,
                        reasoningLevel: reasoningLevel
                    )
                
                for try await chunk in stream {
                    if Task.isCancelled { break }

                    // CEO Priority Override Detection (thread-safe access via MainActor)
                    let shouldInterrupt = await MainActor.run { self.interruptFlags[taskID] == true }
                    if shouldInterrupt {
                        await MainActor.run { self.interruptFlags[taskID] = false }
                        // Inject the tag so we know it was cut off
                        accContent += "...\n[INCOMPLETE: INTERRUPTED BY CEO INJECTION]"
                        break
                    }

                    if let c = chunk.content { accContent += c }
                    if let tc = chunk.toolCalls { accToolCalls = tc }
                    if let fr = chunk.finishReason { accFinishReason = fr }
                }
                
            } catch {
                await markFailed(task: task, context: context, error: error.localizedDescription)
                return
            }
            
            // Parse <canvas> block if present
            if let startRange = accContent.range(of: "<canvas>"),
               let endRange = accContent.range(of: "</canvas>") {
                let canvasContent = String(accContent[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Save to shared state
                task.sharedCanvasContent = canvasContent
                task.logs.append("[\(Self.timestamp)] 🖼️ Shared Canvas updated by \(currentPersona.name)")
                
                // Strip the exact canvas XML from chat bubble so it stays clean
                let fullRange = startRange.lowerBound..<endRange.upperBound
                accContent.removeSubrange(fullRange)
                accContent = accContent.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Save agent response as SwarmMessage
            if !accContent.isEmpty {
                let agentMsg = SwarmMessage(role: "agent", content: accContent, senderName: currentPersona.name)
                task.messages.append(agentMsg)
                try? context.save()
            }
            
            // Handle finish_reason == "length" (Query Loop Recovery)
            if accFinishReason == "length" || accFinishReason == "max_tokens" {
                messages.append(Message(role: .assistant, content: accContent))
                messages.append(Message(role: .user, content: "[System: Continue exactly where you left off.]"))
                task.logs.append("[\(Self.timestamp)] ♻️ Length recovery triggered")
                try? context.save()
                continue
            }
            
            // Execute tool calls
            if let toolCalls = accToolCalls, !toolCalls.isEmpty {
                messages.append(Message(role: .assistant, content: accContent, toolCalls: toolCalls))
                task.messages.append(SwarmMessage(
                    role: "agent_tool_call",
                    content: Self.encodeToolCallEnvelope(toolCalls),
                    senderName: currentPersona.name
                ))
                
                task.logs.append("[\(Self.timestamp)] 🔧 Executing \(toolCalls.count) tool(s)")
                try? context.save()
                
                // Execute tools (concurrent read-only, serial write)
                let readOnlyTools = ["read_file", "list_directory", "search_files", "web_search", "fetch_url", "fetch_images", "search_knowledge_base"]
                var concurrentCalls: [Message.ToolCall] = []
                var serialCalls: [Message.ToolCall] = []
                
                for tc in toolCalls {
                    if readOnlyTools.contains(tc.name) { concurrentCalls.append(tc) }
                    else { serialCalls.append(tc) }
                }
                
                // Concurrent group
                if !concurrentCalls.isEmpty {
                    await withTaskGroup(of: (String, String).self) { group in
                        for tc in concurrentCalls {
                            group.addTask { [skillRegistry] in
                                let result = (try? await skillRegistry.execute(
                                    name: tc.name,
                                    arguments: tc.arguments,
                                    accessLevel: accessLevel,
                                    workspacePath: workspacePath
                                )) ?? "Error executing \(tc.name)"
                                return (tc.id, result)
                            }
                        }
                        for await (toolID, result) in group {
                            messages.append(Message(role: .tool, content: result, toolCallId: toolID))
                            task.messages.append(SwarmMessage(role: "tool", content: result, senderName: toolID))
                        }
                        try? context.save()
                    }
                }
                
                // Serial group
                for tc in serialCalls {
                    let result = (try? await skillRegistry.execute(
                        name: tc.name,
                        arguments: tc.arguments,
                        accessLevel: accessLevel,
                        workspacePath: workspacePath
                    )) ?? "Error executing \(tc.name)"
                    messages.append(Message(role: .tool, content: result, toolCallId: tc.id))
                    task.messages.append(SwarmMessage(role: "tool", content: result, senderName: tc.id))
                    task.logs.append("[\(Self.timestamp)] ✅ \(tc.name) completed")
                    try? context.save()
                }
                
                // Self-Healing Evaluation
                var hasCriticalFailure = false
                let recentTools = messages.suffix(toolCalls.count)
                
                for tm in recentTools where tm.role == .tool {
                    let text = tm.content.lowercased()
                    if text.contains("error executing") || text.contains("build failed") || text.contains("fatal error:") || (text.contains("error:") && text.contains("exit")) {
                        hasCriticalFailure = true
                    }
                }
                
                if hasCriticalFailure {
                    selfHealingRetries -= 1
                    if selfHealingRetries <= 0 {
                        task.status = "failed"
                        task.errorMessage = "Agent failed to self-heal after catastrophic tool errors."
                        task.completedAt = Date()
                        task.logs.append("[\(Self.timestamp)] ❌ Self-Healing Aborted: Out of retries.")
                        try? context.save()
                        await MainActor.run { self.refreshSnapshots() }
                        return
                    } else {
                        messages.append(Message(role: .system, content: "CRITICAL SYSTEM INTERVENTION: Your previous tool execution resulted in a catastrophic failure or build error. You have \(selfHealingRetries) attempts remaining. Analyze the stack trace carefully and execute a correction."))
                        task.logs.append("[\(Self.timestamp)] ⚠️ Self-Healing Triggered (\(selfHealingRetries) left)")
                        try? context.save()
                    }
                }
                
                continue  // Loop back for next LLM call with tool results
            }
            
            // No tool calls and content received — standard task complete
            if !isDebate {
                task.status = "completed"
                task.completedAt = Date()
                task.logs.append("[\(Self.timestamp)] ✅ Task completed successfully")
                
                if !accContent.isEmpty {
                    let deliverable = SwarmDeliverable(
                        title: String(task.taskDescription.prefix(50)),
                        type: "report",
                        content: accContent,
                        mimeType: "text/markdown",
                        task: task
                    )
                    task.deliverables.append(deliverable)
                }
                
                try? context.save()
                await MainActor.run { self.refreshSnapshots() }
                return
            }
            // In debate mode, no tool calls = just another turn, keep looping
        }
        
        // Max iterations reached
        task.status = "completed"
        task.completedAt = Date()
        
        if isDebate {
            // Build the full debate transcript as a deliverable
            let sorted = task.messages.sorted(by: { $0.timestamp < $1.timestamp })
            var transcript = "# Debate Transcript: \(task.taskDescription)\n\n"
            for msg in sorted where msg.role == "agent" {
                transcript += "## \(msg.senderName)\n\(msg.content)\n\n---\n\n"
            }
            let deliverable = SwarmDeliverable(
                title: "Debate: \(String(task.taskDescription.prefix(40)))",
                type: "debate",
                content: transcript,
                mimeType: "text/markdown",
                task: task
            )
            task.deliverables.append(deliverable)
            
            task.logs.append("[\(Self.timestamp)] 🧠 Moderator synthesizing final Executive Action Plan...")
            try? context.save()
            await MainActor.run { self.refreshSnapshots() }
            
            let synthesisPrompt = """
            You are the Moderator. The debate has concluded successfully.
            Based on the entire transcript below, write a definitive 'Executive Action Plan' and an executable Blueprint for the engineering team.
            Focus entirely on actionable, step-by-step technological instructions, removing all conversational filler.
            Make it ready to be sent directly to the development agent.
            
            Transcript:
            \(transcript)
            """
            let synthesisMessages = [Message(role: .system, content: synthesisPrompt)]
            var synthesisContent = ""
            do {
                let stream = service.chat(messages: synthesisMessages, model: agentModel, tools: nil, reasoningLevel: reasoningLevel)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    if let c = chunk.content { synthesisContent += c }
                }
                if !synthesisContent.isEmpty {
                    let execDeliverable = SwarmDeliverable(
                        title: "Executive Action Plan: \(String(task.taskDescription.prefix(20)))",
                        type: "plan",
                        content: synthesisContent,
                        mimeType: "text/markdown",
                        task: task
                    )
                    task.deliverables.append(execDeliverable)
                    task.logs.append("[\(Self.timestamp)] 📄 Executive Action Plan generated")
                }
            } catch {
                task.logs.append("[\(Self.timestamp)] ⚠️ Failed to generate Executive Action Plan: \(error.localizedDescription)")
            }

            task.logs.append("[\(Self.timestamp)] 🏁 Debate concluded after \(task.maxRounds) rounds")
        } else {
            task.logs.append("[\(Self.timestamp)] ⚠️ Max iterations reached")
        }
        try? context.save()
        await MainActor.run { self.refreshSnapshots() }
    }
    
    // MARK: - The COO Engine (Auto-Decomposition)

    /// Validates and parses the COO LLM output into a structured task array.
    /// Returns nil if the output is malformed or doesn't match the expected schema.
    private func validateCOOOutput(_ content: String) -> [[String: Any]]? {
        let cleanJson = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleanJson.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        // Validate schema: each task must have taskDescription and roleName
        for task in parsed {
            guard let desc = task["taskDescription"] as? String, !desc.isEmpty,
                  let role = task["roleName"] as? String, !role.isEmpty else {
                return nil
            }
        }

        return parsed.isEmpty ? nil : parsed
    }

    /// Phase 4: Takes a global directive, uses an LLM to break it into sub-tasks, matches to models, and spawns agents.
    func autoDecompose(directive: String) {
        // Placeholder for UI feedback if needed
        Task {
            guard let appState = await MainActor.run(body: { self.appState }),
                  let service = await MainActor.run(body: { ProviderServiceFactory.makeFromAppState(appState) }) else { return }

            let modelsList = await MainActor.run { appState.availableModels.map { "\($0.name) (\($0.id))" }.joined(separator: ", ") }
            let cooModel = await MainActor.run { appState.selectedModel ?? AIModel.defaultModels.first! }
            let reasoningLevel = await MainActor.run { appState.reasoningLevel }

            let cooPrompt = """
            You are the Swarm Chief Operating Officer (COO).
            The CEO has given you a high-level directive.
            Break this down into specific parallel or sequential sub-tasks for specialized agents.

            Available LLM Models for routing:
            \(modelsList)

            Return ONLY a raw JSON array of objects representing the tasks. Do not use markdown blocks.
            Format:
            [
              {
                "taskDescription": "Instructions for the agent...",
                "roleName": "e.g. Frontend Developer",
                "suggestedModelId": "Exact selected model ID from the list... (e.g. meta-llama/llama-3-405b-instruct)"
              }
            ]
            """

            await MainActor.run { appState.showToast("COO: Analysing Directive & Routing Models...", level: .info) }

            let messages = [
                Message(role: .system, content: cooPrompt),
                Message(role: .user, content: directive)
            ]

            // Retry up to 3 times if the LLM produces invalid JSON
            var decodedTasks: [[String: Any]]? = nil
            var lastError: String = ""

            for attempt in 1...3 {
                do {
                    var accContent = ""
                    let stream = service.chat(messages: messages, model: cooModel, tools: nil, reasoningLevel: reasoningLevel)
                    for try await chunk in stream {
                        if let c = chunk.content { accContent += c }
                    }

                    if let parsed = validateCOOOutput(accContent) {
                        decodedTasks = parsed
                        break
                    } else {
                        lastError = "Invalid JSON schema"
                        AppLog.swarm.warning("⚠️ COO attempt \(attempt): \(lastError, privacy: .public)")
                    }
                } catch {
                    lastError = error.localizedDescription
                    AppLog.swarm.error("⚠️ COO attempt \(attempt) error: \(lastError, privacy: .public)")
                }
            }

            guard let decodedTasks = decodedTasks else {
                let errorMessage = lastError
                await MainActor.run {
                    appState.showToast("COO: Failed after 3 attempts. \(errorMessage)", level: .error)
                }
                return
            }

            await MainActor.run {
                let context = ModelContext(self.modelContainer)
                for t in decodedTasks {
                    guard let desc = t["taskDescription"] as? String,
                          let role = t["roleName"] as? String else { continue }
                    let mod = t["suggestedModelId"] as? String

                    let workspacePath = appState.activeSession?.projectPath ?? ""
                    let treeMap = workspacePath.isEmpty ? "No active workspace mapped." : self.scanWorkspace(path: workspacePath)

                    let persona = AgentPersona(
                        name: "Temp-\(Int.random(in: 100...999))",
                        roleName: role,
                        systemPrompt: """
You are a specialized \(role).
You MUST strictly use the native JSON tool schema provided. DO NOT simulate tools. DO NOT describe in prose what a function call 'does'.
If you need to search, read, write to a file, or run terminal commands, execute the actual tool natively. Output your final work in plain text unless told otherwise.

Current Codebase Layout Context:
```text
\(treeMap)
```

Strict mandate: \(desc)
""",
                        accentColorHex: ["#FF9800", "#E91E63", "#00BCD4", "#8BC34A", "#9C27B0"].randomElement()!,
                        preferredModelId: mod
                    )
                    context.insert(persona)

                    let task = SwarmTask(taskDescription: desc, priority: 1, type: "standard", assignedAgent: persona)
                    context.insert(task)

                    // Tell the War Room to visibly spawn this agent on the Canvas Grid
                    NotificationCenter.default.post(name: NSNotification.Name("SpawnCanvasNode"), object: persona)
                }
                try? context.save()
                self.refreshSnapshots()
                appState.showToast("COO created \(decodedTasks.count) agents and micro-tasks!", level: .success)
            }
        }
    }
    
    // MARK: - Task Management (Public API)
    
    /// Create a new Swarm task and assign it to a persona.
    @MainActor
    func createTask(
        description: String,
        persona: AgentPersona,
        opponent: AgentPersona? = nil,
        additionalOpponents: [AgentPersona] = [],
        priority: Int = 1,
        type: String = "standard"
    ) {
        let context = ModelContext(modelContainer)
        let allOpponents = ([opponent].compactMap { $0 } + additionalOpponents)
        let task = SwarmTask(
            taskDescription: description,
            priority: priority,
            type: type,
            additionalOpponentNames: allOpponents.dropFirst().map { $0.name },
            assignedAgent: persona,
            debateOpponent: allOpponents.first
        )
        context.insert(task)
        try? context.save()
        refreshSnapshots()
    }

    /// Launch a background agent for the Chat system (replaces legacy AgentCoordinator).
    /// Creates a temporary persona and a SwarmTask, then returns the task for UI tracking.
    @MainActor
    func launchBackgroundAgent(goal: String, modelID: String, sessionID: UUID, appState: AppState) -> SwarmTask? {
        let context = ModelContext(modelContainer)

        // Create a temporary persona for this background agent
        let shortID = UUID().uuidString.prefix(4)
        let persona = AgentPersona(
            name: "BG-\(shortID)",
            roleName: "Background Agent",
            systemPrompt: """
            You are an autonomous background agent. Your goal is:
            \(goal)
            Work independently, use available tools, and complete the goal.
            When done, summarise what you accomplished in your final message.
            """,
            accentColorHex: "#76B900",
            preferredModelId: modelID
        )
        context.insert(persona)

        // Create the task
        let task = SwarmTask(
            taskDescription: goal,
            priority: 1,
            type: "background",
            assignedAgent: persona
        )
        context.insert(task)

        do {
            try context.save()
        } catch {
            AppLog.swarm.error("⚠️ Failed to launch background agent: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        refreshSnapshots()
        return task
    }

    /// Cancel a background agent by task ID.
    @MainActor
    func cancelBackgroundAgent(taskID: UUID) {
        cancelAgent(for: taskID)
    }

    /// Fetch a SwarmTask by ID (for UI display).
    @MainActor
    func backgroundAgentTask(id: UUID) -> SwarmTask? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }
    
    /// Fetch all agent personas from SwiftData.
    @MainActor
    func fetchPersonas() -> [AgentPersona] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AgentPersona>(
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Fetch all tasks with optional status filter.
    @MainActor
    func fetchTasks(status: String? = nil) -> [SwarmTask] {
        let context = ModelContext(modelContainer)
        var descriptor: FetchDescriptor<SwarmTask>
        if let status {
            descriptor = FetchDescriptor<SwarmTask>(
                predicate: #Predicate { $0.status == status },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<SwarmTask>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        }
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Fetch unread deliverables.
    @MainActor
    func fetchUnreadDeliverables() -> [SwarmDeliverable] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SwarmDeliverable>(
            predicate: #Predicate { $0.isRead == false },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Mark a deliverable as read.
    @MainActor
    func markDeliverableRead(_ deliverableID: UUID) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SwarmDeliverable>(
            predicate: #Predicate { $0.id == deliverableID }
        )
        if let deliverable = try? context.fetch(descriptor).first {
            deliverable.isRead = true
            try? context.save()
            refreshSnapshots()
        }
    }
    
    // MARK: - Helpers
    
    /// Mark a task as failed with an error message.
    private func markFailed(task: SwarmTask, context: ModelContext, error: String) async {
        task.status = "failed"
        task.errorMessage = error
        task.completedAt = Date()
        task.logs.append("[\(Self.timestamp)] ❌ Failed: \(error)")
        try? context.save()
        await MainActor.run { self.refreshSnapshots() }
    }
    
    /// Append a log entry to a task.
    private func appendLog(taskID: UUID, context: ModelContext, entry: String) async {
        let descriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.id == taskID }
        )
        if let task = try? context.fetch(descriptor).first {
            task.logs.append("[\(Self.timestamp)] \(entry)")
            try? context.save()
        }
    }
    
    /// Public entry point for external callers (e.g. NewTaskSheet) to refresh UI state.
    @MainActor func refreshPublic() { refreshSnapshots() }
    
    /// Refresh the UI-friendly snapshots from SwiftData.
    @MainActor
    private func refreshSnapshots() {

        let context = ModelContext(modelContainer)
        let runningDescriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.status == "running" }
        )
        if let running = try? context.fetch(runningDescriptor) {
            self.runningTasks = running.map { SwarmTaskSnapshot(from: $0) }
        }
        
        let pendingDescriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.status == "pending" }
        )
        self.pendingCount = (try? context.fetchCount(pendingDescriptor)) ?? 0
        
        let delivDescriptor = FetchDescriptor<SwarmDeliverable>(
            predicate: #Predicate { $0.isRead == false }
        )
        self.unreadDeliverableCount = (try? context.fetchCount(delivDescriptor)) ?? 0
    }
    
    private static var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
    
    // MARK: - AST Workspace Scanner
    
    private func scanWorkspace(path: String, maxDepth: Int = 3) -> String {
        let fileManager = FileManager.default
        var output = ""
        
        func scanDirectory(url: URL, prefix: String, currentDepth: Int) {
            if currentDepth > maxDepth { return }
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            
            let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for (index, item) in sorted.enumerated() {
                let isLast = index == sorted.count - 1
                let name = item.lastPathComponent
                
                // Skip common heavy directories
                if name == "DerivedData" || name == ".build" || name == "Pods" || name == "build" { continue }
                
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        output += "\(prefix)\(isLast ? "└── " : "├── ")\(name)/\n"
                        scanDirectory(url: item, prefix: prefix + (isLast ? "    " : "│   "), currentDepth: currentDepth + 1)
                    } else if name.hasSuffix(".swift") || name.hasSuffix(".md") || name.hasSuffix(".json") {
                        output += "\(prefix)\(isLast ? "└── " : "├── ")\(name)\n"
                    }
                }
            }
        }
        
        let rootURL = URL(fileURLWithPath: path)
        output += "\(rootURL.lastPathComponent)/\n"
        scanDirectory(url: rootURL, prefix: "", currentDepth: 1)
        return output
    }
    
    private static func encodeToolCallEnvelope(_ toolCalls: [Message.ToolCall]) -> String {
        guard let data = try? JSONEncoder().encode(toolCalls),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
    
    private static func decodeToolCallEnvelope(_ raw: String) -> [Message.ToolCall]? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([Message.ToolCall].self, from: data)
    }
}

// MARK: - UI Snapshot (Value Type for SwiftUI)

/// A lightweight, value-type snapshot of a SwarmTask for UI rendering.
/// Avoids passing @Model reference types across actor boundaries.
struct SwarmTaskSnapshot: Identifiable {
    let id: UUID
    let type: String
    let description: String
    let status: String
    let agentName: String
    let agentColor: String
    let progress: String  // Last log entry
    let createdAt: Date
    let debateParticipants: [String]
    
    init(from task: SwarmTask) {
        self.id = task.id
        self.type = task.type
        self.description = task.taskDescription
        self.status = task.status
        self.agentName = task.assignedAgent?.name ?? "Unassigned"
        self.agentColor = task.assignedAgent?.accentColorHex ?? "#76B900"
        self.progress = task.logs.last ?? ""
        self.createdAt = task.createdAt
        
        var participants: [String] = []
        if let first = task.assignedAgent?.name { participants.append(first) }
        if let second = task.debateOpponent?.name { participants.append(second) }
        participants.append(contentsOf: task.additionalOpponentNames)
        self.debateParticipants = participants
    }
}
