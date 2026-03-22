import SwiftUI

// MARK: - Agent Detail View

/// Full view of a running/completed background agent.
struct AgentDetailView: View {
    let agentID: UUID
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = AgentCoordinator.shared

    private var task: AgentTask? { coordinator.task(id: agentID) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .symbolEffect(.pulse, isActive: task?.status == .running || task?.status == .thinking)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task?.goal ?? "Agent")
                        .font(.headline)
                        .lineLimit(2)
                    Text(statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if task?.status == .running || task?.status == .thinking || task?.status == .reading {
                    Button("Cancel") {
                        Task { await MainActor.run { coordinator.cancelAgent(id: agentID, appState: appState) } }
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

            if let result = task?.result, !result.isEmpty {
                // Result banner
                VStack(alignment: .leading, spacing: 6) {
                    Label(task?.status == .completed ? "Completed" : "Result", systemImage: task?.status == .completed ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(task?.status == .completed ? .green : .secondary)
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .background((task?.status == .completed ? Color.green : Color.blue).opacity(0.08))

                Divider()
            }

            // Message history
            if let messages = task?.messages.filter({ $0.role != .system }), !messages.isEmpty {
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
                    if task?.status == .thinking || task?.status == .running {
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
    }

    private var statusColor: Color {
        switch task?.status {
        case .thinking: return .orange
        case .running:  return .blue
        case .reading:  return .purple
        case .completed: return .green
        case .failed:   return .red
        default:        return .gray
        }
    }

    private var statusLabel: String {
        switch task?.status {
        case .thinking:  return "Thinking..."
        case .running:   return "Running tools..."
        case .reading:   return "Reading files..."
        case .completed: return "Completed"
        case .failed:    return "Failed"
        default:         return "Waiting"
        }
    }
}

struct AgentMessageRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.role == .user ? "person.circle.fill" : (message.role == .tool ? "wrench.fill" : "cpu.fill"))
                .font(.caption)
                .foregroundStyle(message.role == .user ? .blue : (message.role == .tool ? .orange : .green))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.role == .user ? "Goal" : (message.role == .tool ? "Tool Result" : "Agent"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)

                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(message.role == .tool ? 4 : nil)
                }
            }
        }
        .padding(8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - New Agent Sheet

struct NewAgentSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var goal = ""
    @State private var selectedModelID: String = ""
    @State private var coordinator = AgentCoordinator.shared

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
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.1)))
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
                        .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
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
                                _ = coordinator.launchAgent(goal: g, modelID: modelID, sessionID: sid, appState: appState)
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
