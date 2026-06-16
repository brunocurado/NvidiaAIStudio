import SwiftUI

// MARK: - Agent Detail View

/// Full view of a running/completed background agent.
/// Uses SwarmOrchestrator as the single source of truth (replaces legacy AgentCoordinator).
struct AgentDetailView: View {
    let agentID: UUID
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var task: SwarmTask?
    @State private var refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var statusRaw: String { task?.status ?? "unknown" }
    private var statusLabel: String {
        switch statusRaw {
        case "running": return "Running"
        case "completed": return "Completed"
        case "failed": return "Failed"
        case "pending": return "Pending"
        default: return statusRaw.capitalized
        }
    }
    private var statusColor: Color {
        switch statusRaw {
        case "running": return .green
        case "completed": return .blue
        case "failed": return .red
        default: return .orange
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .symbolEffect(.pulse, isActive: statusRaw == "running")

                VStack(alignment: .leading, spacing: 2) {
                    Text(task?.taskDescription ?? "Agent")
                        .font(.headline)
                        .lineLimit(2)
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if statusRaw == "running" || statusRaw == "pending" {
                    Button("Cancel") {
                        appState.orchestrator.cancelBackgroundAgent(taskID: agentID)
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("Close") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()

            Divider()

            if let result = task?.errorMessage, !result.isEmpty {
                // Result banner
                VStack(alignment: .leading, spacing: 6) {
                    Label(statusRaw == "completed" ? "Completed" : "Result", systemImage: statusRaw == "completed" ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(statusRaw == "completed" ? .green : .secondary)
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .background((statusRaw == "completed" ? Color.green : Color.blue).opacity(0.08))

                Divider()
            }

            // Message history
            if let messages = task?.messages.filter({ $0.role != "system" }), !messages.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(messages) { msg in
                                AgentMessageRow(message: msg)
                                    .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .onAppear {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            } else {
                Spacer()
                VStack(spacing: 8) {
                    if statusRaw == "running" || statusRaw == "pending" {
                        ProgressView()
                        Text("Agent is working...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No messages yet")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .frame(width: 560, height: 500)
        .onAppear { refreshTask() }
        .onReceive(refreshTimer) { _ in refreshTask() }
    }

    private func refreshTask() {
        task = appState.orchestrator.backgroundAgentTask(id: agentID)
    }
}

struct AgentMessageRow: View {
    let message: SwarmMessage

    private var icon: String {
        switch message.role {
        case "user": return "person.circle.fill"
        case "tool": return "wrench.fill"
        case "moderator": return "crown.fill"
        default: return "cpu.fill"
        }
    }

    private var iconColor: Color {
        switch message.role {
        case "user": return .blue
        case "tool": return .orange
        case "moderator": return .yellow
        default: return .green
        }
    }

    private var label: String {
        switch message.role {
        case "user": return "User"
        case "tool": return "Tool Result"
        case "moderator": return "Moderator"
        default: return message.senderName.isEmpty ? "Agent" : message.senderName
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(iconColor)
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(message.role == "tool" ? 4 : nil)
                }
            }
        }
        .padding(8)
        .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - New Agent Sheet

struct NewAgentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var goal = ""
    @State private var selectedModelID: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "person.fill.badge.plus")
                    .foregroundStyle(.blue)
                Text("New Background Agent")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Describe what this agent should accomplish. It will work autonomously using all available skills.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $goal)
                        .font(.body)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(GlassTheme.flatStroke))
                }

                // Example goals
                VStack(alignment: .leading, spacing: 6) {
                    Text("Examples").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                    ForEach(exampleGoals, id: \.self) { example in
                        Button {
                            goal = example
                        } label: {
                            HStack {
                                Image(systemName: "lightbulb").font(.caption2)
                                Text(example).font(.caption).lineLimit(2)
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                                        .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                // Model picker
                HStack {
                    Text("Model").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $selectedModelID) {
                        ForEach(appState.modelsForActiveProvider.filter(\.isEnabled)) { m in
                            Text(m.name).tag(m.id)
                        }
                    }
                    .frame(width: 260)
                }

                HStack {
                    Spacer()
                    Button("Launch Agent") {
                        guard let session = appState.activeSession else { return }
                        let modelID = selectedModelID.isEmpty ? appState.selectedModelID : selectedModelID
                        let g = goal; let sid = session.id
                        Task {
                            await MainActor.run {
                                _ = appState.orchestrator.launchBackgroundAgent(goal: g, modelID: modelID, sessionID: sid, appState: appState)
                            }
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 460)
        .onAppear {
            selectedModelID = appState.selectedModelID
        }
    }

    private let exampleGoals = [
        "Analyse the code in the active workspace and create a SUMMARY.md with architecture overview",
        "Find all TODO comments in the project and create a todo.md file listing them with file paths",
        "Run the test suite and fix any failing tests automatically",
        "Review the git diff and write a detailed commit message for the staged changes",
    ]
}
