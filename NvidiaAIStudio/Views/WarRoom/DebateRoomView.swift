import SwiftUI
import SwiftData

enum CanvasDisplayMode { case preview, edit }

/// Debate Room — shows multi-agent conversations for debate-type tasks.
/// Each debate has a moderator (the CEO/user) and multiple agents exchanging arguments.
struct DebateRoomView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedDebateID: UUID?
    @State private var debates: [SwarmTask] = []
    private let refreshTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 0) {
            debateList.frame(width: 220)
            Divider()
            if let debateID = selectedDebateID {
                DebateConversationView(taskID: debateID)
            } else {
                emptyState
            }
        }
        .onAppear { refreshDebates() }
        .onReceive(refreshTimer) { _ in refreshDebates() }
    }
    
    private func refreshDebates() {
        let context = ModelContext(appState.modelContainer)
        let debateType = "debate"
        let descriptor = FetchDescriptor<SwarmTask>(
            predicate: #Predicate { $0.type == debateType },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        debates = (try? context.fetch(descriptor)) ?? []
        // Auto-select the newest debate if none selected
        if selectedDebateID == nil, let first = debates.first {
            selectedDebateID = first.id
        }
    }
    
    // MARK: - Debate List
    
    private var debateList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Debates")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if debates.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title2)
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("No debates yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                    
                    ForEach(debates, id: \.id) { task in
                        DebateListItem(
                            task: task,
                            isSelected: selectedDebateID == task.id,
                            onSelect: { selectedDebateID = task.id },
                            onDelete: { deleteDebate(task) }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
        }
        .background(.ultraThinMaterial.opacity(0.2))
    }
    
    private func deleteDebate(_ task: SwarmTask) {
        // Stop the agent if running
        appState.orchestrator.cancelAgent(for: task.id)
        // Delete from SwiftData
        let context = ModelContext(appState.modelContainer)
        let taskID = task.id
        let descriptor = FetchDescriptor<SwarmTask>(predicate: #Predicate { $0.id == taskID })
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
            try? context.save()
        }
        if selectedDebateID == task.id { selectedDebateID = nil }
        refreshDebates()
        appState.showToast("Debate deleted", level: .info)
    }
    
    private var emptyState: some View {

        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.2))
            Text("Select a debate")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Deploy a debate task from the Operations Floor\nto see agents argue back and forth.")
                .font(.subheadline)
                .foregroundStyle(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Debate List Item

struct DebateListItem: View {
    let task: SwarmTask
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.taskDescription)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 9))
                        .foregroundStyle(statusColor)
                    Text(task.status.capitalized)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                    Spacer()
                    Text("\(task.messages.count) msgs")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.15))
                    : nil
            )
            .glassEffect(
                isSelected || isHovered
                    ? .clear.tint(Color.primary.opacity(0.08)).interactive()
                    : .clear.interactive(),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Debate", systemImage: "trash")
            }
        }
    }
    
    private var statusIcon: String {
        switch task.status {
        case "running": return "bolt.fill"
        case "completed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        default: return "clock.fill"
        }
    }
    
    private var statusColor: Color {
        switch task.status {
        case "running": return .green
        case "completed": return .blue
        case "failed": return .red
        default: return .orange
        }
    }
}

// MARK: - Debate Conversation View

struct DebateConversationView: View {
    @Environment(AppState.self) private var appState
    let taskID: UUID
    @State private var ceoInput = ""
    @State private var messages: [SwarmMessage] = []
    @State private var task: SwarmTask?
    @State private var localCanvasEditor: String = ""
    @FocusState private var isCanvasFocused: Bool
    @State private var canvasMode: CanvasDisplayMode = .preview
    
    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HSplitView {
            // Left Pane: The Debate Chat
            VStack(spacing: 0) {
                // Turn Indicator Banner
                if let task, task.status == "running" {
                    let agentMessages = messages.filter { $0.role == "agent" }
                    let debaterNames: [String] = {
                        var names: [String] = []
                        if let opp = task.debateOpponent { names.append(opp.name) }
                        names += task.additionalOpponentNames
                        return names
                    }()
                    let moderatorName = task.assignedAgent?.name ?? ""
                    let speakingNow = debaterNames.isEmpty ? moderatorName
                        : debaterNames[agentMessages.count % max(debaterNames.count, 1)]
                    let currentRound = agentMessages.count / max(debaterNames.count, 1) + 1
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.green)
                            .frame(width: 7, height: 7)
                            .shadow(color: .green.opacity(0.8), radius: 4)
                        Text("\(speakingNow) is arguing...")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.green)
                        Spacer()
                        Text("Round \(currentRound) of \(task.maxRounds)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.08))
                }
                
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(messages, id: \.id) { msg in
                                DebateMessageBubble(
                                    message: msg,
                                    primaryName: task?.assignedAgent?.name ?? ""
                                )
                                .id(msg.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
                
                Divider()
                
                // CEO directive input
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 12))
                    
                    TextField("Send a directive to this debate...", text: $ceoInput)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .onSubmit { sendDirective() }
                    
                    Button(action: sendDirective) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .disabled(ceoInput.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial.opacity(0.3))
            }
            .frame(minWidth: 350)
            
            // Right Pane: Shared Canvas Blueprint
            VStack(spacing: 0) {
                // ── Canvas header ──────────────────────────────────────
                HStack {
                    Image(systemName: "square.and.pencil")
                        .foregroundStyle(.white)
                    Text("Shared Canvas Blueprint")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    // Mode toggle
                    Picker("", selection: $canvasMode) {
                        Image(systemName: "eye").tag(CanvasDisplayMode.preview)
                        Image(systemName: "pencil").tag(CanvasDisplayMode.edit)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 70)
                    .scaleEffect(0.85)
                    
                    if task?.status == "running" {
                        Text("Agents modifying…")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial.opacity(0.4))

                Divider()

                // ── Canvas content ─────────────────────────────────────
                let displayContent = localCanvasEditor.isEmpty ? "*Agents will project their ideas here…*" : localCanvasEditor
                if canvasMode == .preview {
                    SmartCanvasView(
                        content: displayContent,
                        editableContent: $localCanvasEditor,
                        isEditing: false,
                        isFocused: $isCanvasFocused
                    )
                } else {
                    TextEditor(text: $localCanvasEditor)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .focused($isCanvasFocused)
                        .onChange(of: localCanvasEditor) { _, newValue in
                            if isCanvasFocused {
                                task?.sharedCanvasContent = newValue
                                try? task?.modelContext?.save()
                            }
                        }
                }
            }
            .frame(minWidth: 250)
            .background(Color.black.opacity(0.2))
        }
        .onChange(of: task?.sharedCanvasContent) { _, newValue in
            // Hydrate the editor from DB only when the CEO is NOT actively typing
            if !isCanvasFocused {
                localCanvasEditor = newValue ?? ""
            }
        }
        .onAppear { refreshMessages() }
        .onReceive(refreshTimer) { _ in refreshMessages() }
    }
    
    private func refreshMessages() {
        let context = ModelContext(appState.modelContainer)
        let descriptor = FetchDescriptor<SwarmMessage>(sortBy: [SortDescriptor(\.timestamp)])
        let all = (try? context.fetch(descriptor)) ?? []
        messages = all.filter { $0.task?.id == taskID }
        
        let taskDesc = FetchDescriptor<SwarmTask>(predicate: #Predicate { $0.id == taskID })
        task = try? context.fetch(taskDesc).first
    }
    
    private func sendDirective() {
        guard !ceoInput.isEmpty else { return }
        // CEO Priority Override: Immediately interrupts the stream
        appState.orchestrator.forceInterrupt(taskID: taskID, directive: ceoInput)
        ceoInput = ""
        appState.showToast("CEO Override active", level: .success)
    }
}

// MARK: - Debate Message Bubble

struct DebateMessageBubble: View {
    let message: SwarmMessage
    var primaryName: String = ""
    
    private var isAgent: Bool { message.role == "agent" }
    private var isCEO: Bool { message.senderName == "CEO" || message.role == "moderator" }
    private var isPrimary: Bool { message.senderName == primaryName }
    
    // Primary agent sits on the left, opponent on the right
    private var alignLeft: Bool { isCEO ? false : isPrimary }
    
    private var bubbleColor: Color {
        if isCEO { return .yellow.opacity(0.10) }
        if isPrimary { return .cyan.opacity(0.10) }
        return .purple.opacity(0.10)
    }
    
    private var nameColor: Color {
        if isCEO { return .yellow }
        if isPrimary { return .cyan }
        return .purple
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if !alignLeft { Spacer(minLength: 40) }
            
            VStack(alignment: alignLeft ? .leading : .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if isCEO {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    } else {
                        Circle()
                            .fill(nameColor)
                            .frame(width: 7, height: 7)
                    }
                    Text(message.senderName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(nameColor)
                }
                
                Text(message.content)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: alignLeft ? .leading : .trailing)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bubbleColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(nameColor.opacity(0.2), lineWidth: 1)
                    )
            )
            
            if alignLeft { Spacer(minLength: 40) }
        }
    }
}
