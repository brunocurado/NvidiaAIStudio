import SwiftUI
import SwiftData

/// The Operations Floor — shows all agents with their current status and task assignments.
/// Live-updating by observing the orchestrator state.
struct OperationsFloorView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTaskID: UUID?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Running Tasks
                if !appState.orchestrator.runningTasks.isEmpty {
                    sectionHeader("Active Agents", icon: "bolt.fill", color: .green)
                    
                    ForEach(appState.orchestrator.runningTasks) { task in
                        AgentTaskCard(snapshot: task, isSelected: selectedTaskID == task.id)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.2)) {
                                    selectedTaskID = task.id
                                    appState.rightPanelMode = .terminal
                                    if !appState.isRightPanelVisible {
                                        appState.isRightPanelVisible = true
                                    }
                                }
                            }
                    }
                }
                
                // Pending Queue
                let pending = fetchTasks(status: "pending")
                if !pending.isEmpty {
                    sectionHeader("Queue (\(pending.count))", icon: "clock.fill", color: .orange)
                    
                    ForEach(pending, id: \.id) { task in
                        PendingTaskRow(task: task)
                    }
                }
                
                // Recently Completed
                let completed = fetchTasks(status: "completed")
                if !completed.isEmpty {
                    sectionHeader("Completed", icon: "checkmark.circle.fill", color: .secondary)
                    
                    ForEach(completed.prefix(10), id: \.id) { task in
                        CompletedTaskRow(task: task)
                    }
                }
                
                // Empty State
                if appState.orchestrator.runningTasks.isEmpty && pending.isEmpty && completed.isEmpty {
                    emptyState
                }
            }
            .padding(20)
        }
    }
    
    private func fetchTasks(status: String) -> [SwarmTask] {
        let context = ModelContext(appState.modelContainer)
        let descriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.status == status },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
    
    // MARK: - Components
    
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 12))
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.top, 4)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.3))
            Text("No agents deployed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Create a task to deploy an agent.\nThey'll work autonomously in the background.")
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Agent Task Card (Active)

struct AgentTaskCard: View {
    let snapshot: SwarmTaskSnapshot
    let isSelected: Bool
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Agent avatar
                ZStack {
                    Circle()
                        .fill(Color(hex: snapshot.agentColor).opacity(0.2))
                        .frame(width: 36, height: 36)
                    Text(String(snapshot.agentName.prefix(1)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: snapshot.agentColor))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.agentName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: snapshot.agentColor))
                    Text(snapshot.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Live pulse
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: .green.opacity(0.6), radius: 3)
                    Text("LIVE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.green)
                }
            }
            
            // Progress log
            if !snapshot.progress.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(snapshot.progress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isSelected ? 0.08 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(hex: snapshot.agentColor).opacity(isSelected ? 0.4 : 0.15), lineWidth: 1)
                )
        )
        .glassEffect(
            isHovered || isSelected
                ? .clear.tint(Color.primary.opacity(0.08)).interactive()
                : .clear.interactive(),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .scaleEffect(isHovered ? 1.005 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Pending Task Row

struct PendingTaskRow: View {
    let task: SwarmTask
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.taskDescription)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let agent = task.assignedAgent {
                    Text("→ \(agent.name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            priorityBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 8))
    }
    
    @ViewBuilder
    private var priorityBadge: some View {
        let (label, color): (String, Color) = {
            switch task.priority {
            case 2: return ("URGENT", .red)
            case 0: return ("LOW", .secondary)
            default: return ("NORMAL", .blue)
            }
        }()
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Completed Task Row

struct CompletedTaskRow: View {
    let task: SwarmTask
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.status == "failed" ? "xmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(task.status == "failed" ? .red : .green)
                .font(.system(size: 12))
            Text(task.taskDescription)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let completed = task.completedAt {
                Text(completed, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
