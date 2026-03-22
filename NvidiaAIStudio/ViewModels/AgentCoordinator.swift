import Foundation
import SwiftUI

// MARK: - Agent Task

struct AgentTask: Identifiable, Codable {
    let id: UUID
    var goal: String
    var modelID: String
    var messages: [Message]
    var status: BackgroundAgent.AgentStatus
    var result: String?
    var createdAt: Date
    var updatedAt: Date
    var sessionID: UUID

    init(id: UUID = UUID(), goal: String, modelID: String, sessionID: UUID) {
        self.id = id; self.goal = goal; self.modelID = modelID
        self.messages = []; self.status = .thinking
        self.result = nil; self.createdAt = Date(); self.updatedAt = Date()
        self.sessionID = sessionID
    }
}

// MARK: - Agent Runner

final class AgentRunner {
    let task: AgentTask
    private var runnerTask: Task<Void, Never>?
    private weak var coordinator: AgentCoordinator?

    init(task: AgentTask, coordinator: AgentCoordinator) {
        self.task = task
        self.coordinator = coordinator
    }

    func start(appState: AppState) {
        runnerTask = Task { [weak self] in
            guard let self else { return }
            await self.run(appState: appState)
        }
    }

    func cancel() { runnerTask?.cancel() }

    private func run(appState: AppState) async {
        // Capture values from MainActor context
        let apiKey = await MainActor.run { appState.activeAPIKey ?? EnvParser.loadNVIDIAKey() }
        let model  = await MainActor.run { appState.availableModels.first { $0.id == task.modelID } ?? appState.selectedModel }
        let provider = await MainActor.run { appState.activeProvider }
        let accessLevel = await MainActor.run { appState.fileAccessLevel }
        let workspacePath = await MainActor.run { appState.activeWorkspacePath }

        guard let apiKey, let model else {
            await coordinator?.set(id: task.id, status: .failed, result: "No API key or model available.")
            return
        }

        let service = ProviderServiceFactory.make(provider: provider, apiKey: apiKey)
        let tools = SkillRegistry.shared.toolDefinitions
        let maxIterations = 15

        var messages: [Message] = [
            Message(role: .system, content: """
                You are an autonomous background agent. Your goal is:
                \(task.goal)
                Work independently, use available tools, and complete the goal.
                When done, summarise what you accomplished in your final message.
                """),
            Message(role: .user, content: task.goal)
        ]

        await coordinator?.set(id: task.id, status: .running, result: nil)

        for i in 0..<maxIterations {
            if Task.isCancelled { break }
            await coordinator?.set(id: task.id, status: i < 2 ? .thinking : .running, result: nil)

            var content = ""
            var toolCalls: [Message.ToolCall]? = nil

            do {
                let stream = service.chat(messages: messages, model: model,
                                          tools: tools.isEmpty ? nil : tools, reasoningLevel: .off)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    content += chunk.content ?? ""
                    if let tc = chunk.toolCalls { toolCalls = (toolCalls ?? []) + tc }
                }
            } catch {
                await coordinator?.set(id: task.id, status: .failed, result: "Error: \(error.localizedDescription)")
                return
            }

            messages.append(Message(role: .assistant, content: content, toolCalls: toolCalls))

            if let tcs = toolCalls, !tcs.isEmpty {
                await coordinator?.set(id: task.id, status: .reading, result: nil)
                for tc in tcs {
                    let result: String
                    do {
                        result = try await SkillRegistry.shared.execute(
                            name: tc.name, arguments: tc.arguments,
                            accessLevel: accessLevel, workspacePath: workspacePath)
                    } catch { result = "Error: \(error.localizedDescription)" }
                    messages.append(Message(role: .tool, content: result, toolCallId: tc.id))
                }
                continue
            }

            // Done — no more tool calls
            await coordinator?.set(id: task.id, status: .completed, result: content)
            await coordinator?.setMessages(id: task.id, messages: messages)
            AppNotifications.sendResponseCompleted(modelName: "Agent: \(String(task.goal.prefix(30)))")
            return
        }

        // Max iterations reached
        let lastContent = messages.last?.content ?? "(none)"
        await coordinator?.set(id: task.id, status: .completed,
                               result: "Reached max iterations. Last: \(lastContent)")
        await coordinator?.setMessages(id: task.id, messages: messages)
    }
}

// MARK: - Agent Coordinator

@Observable
final class AgentCoordinator {
    static let shared = AgentCoordinator()

    var tasks: [AgentTask] = []
    private var runners: [UUID: AgentRunner] = [:]
    private init() {}

    // MARK: - Launch

    @MainActor
    func launchAgent(goal: String, modelID: String, sessionID: UUID, appState: AppState) -> AgentTask {
        let task = AgentTask(goal: goal, modelID: modelID, sessionID: sessionID)
        tasks.append(task)

        let agent = BackgroundAgent(id: task.id,
                                    name: String(goal.split(separator: " ").prefix(3).joined(separator: " ")),
                                    task: String(goal.prefix(50)))
        if let idx = appState.sessions.firstIndex(where: { $0.id == sessionID }) {
            appState.sessions[idx].backgroundAgents.append(agent)
        }

        let runner = AgentRunner(task: task, coordinator: self)
        runners[task.id] = runner
        runner.start(appState: appState)
        return task
    }

    @MainActor
    func cancelAgent(id: UUID, appState: AppState) {
        runners[id]?.cancel()
        runners.removeValue(forKey: id)
        // Update synchronously on MainActor
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].status = .failed
            tasks[idx].result = "Cancelled by user."
        }
        for idx in appState.sessions.indices {
            appState.sessions[idx].backgroundAgents.removeAll { $0.id == id }
        }
    }

    // MARK: - Nonisolated updates — safe to call from any async context

    nonisolated func set(id: UUID, status: BackgroundAgent.AgentStatus, result: String?) async {
        await MainActor.run {
            guard let idx = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            self.tasks[idx].status = status
            self.tasks[idx].updatedAt = Date()
            if let result { self.tasks[idx].result = result }
        }
    }

    nonisolated func setMessages(id: UUID, messages: [Message]) async {
        await MainActor.run {
            guard let idx = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            self.tasks[idx].messages = messages
        }
    }

    func task(id: UUID) -> AgentTask? {
        tasks.first { $0.id == id }
    }
}
