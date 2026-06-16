import SwiftUI
import SwiftData

/// Archives — the CEO's inbox for agent deliverables.
/// Shows unread items first with a prominent badge, then all past deliverables.
struct ArchivesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SwarmDeliverable.createdAt, order: .reverse) private var deliverables: [SwarmDeliverable]
    
    @State private var selectedDeliverable: SwarmDeliverable?
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: deliverable list
            deliverableList
                .frame(width: 280)
            
            Divider()
            
            // Right: deliverable viewer
            if let deliverable = selectedDeliverable {
                DeliverableViewerView(deliverable: deliverable)
            } else {
                emptyViewer
            }
        }
    }
    
    // MARK: - List
    
    private var deliverableList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Inbox")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let unread = appState.orchestrator.unreadDeliverableCount
                if unread > 0 {
                    Text("\(unread) new")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if deliverables.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.title2)
                                .foregroundStyle(.secondary.opacity(0.3))
                            Text("Inbox empty")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Agent deliverables appear here\nwhen tasks complete.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }
                    
                    ForEach(deliverables) { deliverable in
                        DeliverableListItem(
                            deliverable: deliverable,
                            isSelected: selectedDeliverable?.id == deliverable.id
                        ) {
                            selectedDeliverable = deliverable
                            if !deliverable.isRead {
                                appState.orchestrator.markDeliverableRead(deliverable.id)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if selectedDeliverable?.id == deliverable.id {
                                    selectedDeliverable = nil
                                }
                                modelContext.delete(deliverable)
                                try? modelContext.save()
                                // The unread counter will automatically shrink next tick, no forced reload required mapped to @Query
                            } label: {
                                Label("Delete Archive", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
            }
        }
        .background(.ultraThinMaterial.opacity(0.2))
    }
    
    private var emptyViewer: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.2))
            Text("Select a deliverable")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Deliverable List Item

struct DeliverableListItem: View {
    let deliverable: SwarmDeliverable
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Type icon
                Image(systemName: typeIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(typeColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if !deliverable.isRead {
                            Circle()
                                .fill(.orange)
                                .frame(width: 6, height: 6)
                        }
                        Text(deliverable.title)
                            .font(.system(size: 12, weight: deliverable.isRead ? .regular : .bold))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 4) {
                        Text(deliverable.type.capitalized)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let agent = deliverable.task?.assignedAgent?.name {
                            Text("• \(agent)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
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
    }
    
    private var typeIcon: String {
        switch deliverable.type {
        case "file": return "doc.fill"
        case "image": return "photo.fill"
        case "memory": return "brain.head.profile.fill"
        default: return "doc.richtext.fill"
        }
    }
    
    private var typeColor: Color {
        switch deliverable.type {
        case "file": return .blue
        case "image": return .purple
        case "memory": return .cyan
        default: return .green
        }
    }
}

// MARK: - Deliverable Viewer

struct DeliverableViewerView: View {
    let deliverable: SwarmDeliverable
    @Environment(AppState.self) private var appState
    @State private var isCopied = false
    @State private var replyText = ""
    @FocusState private var isFocused: Bool
    @State private var showForwardSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "doc.richtext.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(deliverable.title)
                        .font(.headline)
                    if let agent = deliverable.task?.assignedAgent?.name {
                        Text("From: \(agent)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                
                Button {
                    showForwardSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.right")
                        Text("Forward")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.glass)
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(deliverable.content, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { isCopied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.glass)
            }
            .padding(16)
            
            Divider()
            
            // Content
            ScrollView {
                Text(deliverable.content)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            
            Divider()
            
            // Reply Box
            HStack(alignment: .bottom, spacing: 12) {
                if let agentName = deliverable.task?.assignedAgent?.name {
                    ChatTextEditor(
                        text: $replyText,
                        onSubmit: { sendReply() },
                        isFocused: _isFocused, // need to add @FocusState to DeliverableViewerView
                        onHeightChange: { _ in },
                        placeholder: "Reply directly to \(agentName)..."
                    )
                    .frame(height: max(22, min(50, CGFloat(replyText.split(separator: "\n").count * 16 + 10))))
                    
                    if !replyText.isEmpty {
                        Button {
                            sendReply()
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("Cannot reply: Agent no longer exists.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .italic()
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial.opacity(0.3))
        }
        .sheet(isPresented: $showForwardSheet) {
            ForwardDeliverableSheet(deliverable: deliverable)
                .environment(appState)
        }
    }
    
    private func sendReply() {
        guard let task = deliverable.task, let agent = task.assignedAgent, !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let contextualDescription = """
        [CONTEXT: This is a direct reply to your previous deliverable]
        Your previous output:
        \"\"\"
        \(deliverable.content)
        \"\"\"
        
        CEO Direct Order:
        \(replyText)
        """
        
        // Push the new message into the existing task context
        let msg = SwarmMessage(role: "user", content: contextualDescription, senderName: "CEO")
        task.messages.append(msg)
        
        // Add visual proof to the Agent's Thought Stream log
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        let ts = df.string(from: Date())
        task.logs.append("[\(ts)] 👑 CEO DIRECT OVERRIDE RECEIVED")
        task.logs.append("› \(replyText)")
        
        // Wake up the agent by changing status back to pending
        task.status = "pending"
        task.errorMessage = nil
        task.completedAt = nil
        
        // Because of SwiftData @Model observation, SwarmOrchestrator's FetchDescriptor 
        // will automatically detect this pending task on its next tick and launch the agent.
        appState.showToast("Reply dispatched to \(agent.name)!", level: .success)
        replyText = ""
    }
}

// MARK: - Forward Deliverable Sheet

struct ForwardDeliverableSheet: View {
    let deliverable: SwarmDeliverable
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var taskDescription = ""
    @State private var selectedPersonaNames: Set<String> = []
    @State private var priority: Int = 1
    
    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🚀 Forward as Task")
                        .font(.title3.weight(.bold))
                    Text("Review the plan, edit instructions, and assign it to the Swarm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Task Description
                    fieldSection(icon: "text.document", label: "Executive Action Plan / Intent", hint: "Edit the instructions before deploying") {
                        AnyView(
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(GlassTheme.flatFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(Color.blue.opacity(0.5), lineWidth: 1.5)
                                    )
                                
                                TextEditor(text: $taskDescription)
                                    .font(.system(size: 13, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                            }
                            .frame(minHeight: 220)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                        )
                    }
                    
                    // Assign Agent
                    fieldSection(icon: "person.2.fill", label: "Assign To", hint: "Select one or more agents to execute this task concurrently") {
                        let personas = fetchPersonas()
                        AnyView(
                            FlowLayout(spacing: 8) {
                                ForEach(personas, id: \.name) { persona in
                                    let isSelected = selectedPersonaNames.contains(persona.name)
                                    Button {
                                        if isSelected { selectedPersonaNames.remove(persona.name) }
                                        else { selectedPersonaNames.insert(persona.name) }
                                    } label: {
                                        HStack(spacing: 7) {
                                            Circle()
                                                .fill(Color(hex: persona.accentColorHex))
                                                .frame(width: 26, height: 26)
                                                .overlay(Text(String(persona.name.prefix(1))).font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(persona.name).font(.system(size: 12, weight: .bold)).foregroundStyle(.primary)
                                                Text(persona.roleName).font(.system(size: 10)).foregroundStyle(.secondary)
                                            }
                                            if isSelected {
                                                Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color(hex: persona.accentColorHex))
                                            }
                                        }
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(isSelected ? Color(hex: persona.accentColorHex).opacity(0.18) : GlassTheme.flatFill)
                                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color(hex: persona.accentColorHex).opacity(0.6) : GlassTheme.flatStroke, lineWidth: isSelected ? 1.5 : 1))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        )
                    }
                    
                    // Priority
                    fieldSection(icon: "exclamationmark.2", label: "Priority") {
                        AnyView(
                            Picker("", selection: $priority) {
                                Text("Low").tag(0)
                                Text("Normal").tag(1)
                                Text("Urgent").tag(2)
                            }
                            .pickerStyle(.segmented)
                        )
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.glass)
                Spacer()
                Button { forwardDeliverable() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text("Deploy to Swarm").fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(selectedPersonaNames.isEmpty || taskDescription.isEmpty)
                .opacity((selectedPersonaNames.isEmpty || taskDescription.isEmpty) ? 0.5 : 1)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 600, height: 650)
        .onAppear { setupInitialState() }
    }
    
    @ViewBuilder
    private func fieldSection<Content: View>(icon: String, label: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text(label).font(.system(size: 13, weight: .semibold))
                if let hint {
                    Text("–").foregroundStyle(.tertiary)
                    Text(hint).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }
    
    private func setupInitialState() {
        if taskDescription.isEmpty {
            taskDescription = """
            [CEO DIRECTIVE: Execute the plan detailed below]
            
            \(deliverable.content)
            """
            
            // Auto-select the agents that participated
            if let assigned = deliverable.task?.assignedAgent {
                selectedPersonaNames.insert(assigned.name)
            }
            if let opponents = deliverable.task?.additionalOpponentNames {
                for op in opponents { selectedPersonaNames.insert(op) }
            }
            if let op = deliverable.task?.debateOpponent {
                selectedPersonaNames.insert(op.name)
            }
        }
    }
    
    private func fetchPersonas() -> [AgentPersona] {
        let context = ModelContext(appState.modelContainer)
        return (try? context.fetch(FetchDescriptor<AgentPersona>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }
    
    private func forwardDeliverable() {
        let allPersonas = fetchPersonas()
        
        for personaName in selectedPersonaNames {
            if let persona = allPersonas.first(where: { $0.name == personaName }) {
                appState.orchestrator.createTask(description: taskDescription, persona: persona, priority: priority)
            }
        }
        
        appState.showToast("Deployed \(selectedPersonaNames.count) concurrent tasks!", level: .success)
        dismiss()
    }
}
