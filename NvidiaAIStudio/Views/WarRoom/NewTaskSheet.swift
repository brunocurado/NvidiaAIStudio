import SwiftUI
import SwiftData

/// Sheet for creating a new Swarm task or Debate. Select personas, describe the task, set priority.
struct NewTaskSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var initialTaskType: String = "standard"

    @State private var taskDescription = ""
    @State private var selectedPersonaName: String?
    @State private var selectedOpponentNames: Set<String> = []
    @State private var priority: Int = 1
    @State private var taskType = "standard"
    @State private var maxRounds = 5

    // New persona creation
    @State private var showNewPersona = false
    @State private var newPersonaName = ""
    @State private var newPersonaRole = ""
    @State private var newPersonaPrompt = ""
    @State private var newPersonaColor = "#76B900"

    private var personas: [AgentPersona] { fetchPersonas() }

    private var canDeploy: Bool {
        guard !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard selectedPersonaName != nil else { return false }
        if taskType == "debate" { return selectedOpponentNames.count >= 2 }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(taskType == "debate" ? "⚔️ Configure Debate" : "🚀 Deploy Agent Task")
                        .font(.title3.weight(.bold))
                    Text(taskType == "debate"
                         ? "Set up a multi-agent intellectual battle"
                         : "Assign a task to an autonomous agent")
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

                    // ── Topic / Task Description ─────────────────────
                    fieldSection(
                        icon: "text.document",
                        label: taskType == "debate" ? "Debate Topic" : "Task Description",
                        hint: taskType == "debate"
                            ? "e.g. Is remote work better than office work?"
                            : "e.g. Write a REST API for user authentication"
                    ) {
                        AnyView(
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(GlassTheme.flatFill)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(
                                                taskDescription.isEmpty ? GlassTheme.flatStroke : Color.green.opacity(0.5),
                                                lineWidth: 1.5
                                            )
                                    )

                                if taskDescription.isEmpty {
                                    Text(taskType == "debate"
                                         ? "Enter the debate topic here..."
                                         : "Describe what the agent should do...")
                                        .font(.body)
                                        .foregroundStyle(GlassTheme.textMuted)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .allowsHitTesting(false)
                                }

                                TextEditor(text: $taskDescription)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                            }
                            .frame(minHeight: 100)
                        )
                    }

                    // ── Task Type ────────────────────────────────────
                    fieldSection(icon: "slider.horizontal.3", label: "Mode") {
                        AnyView(
                            HStack(spacing: 0) {
                                ForEach([("standard", "Standard Task", "checkmark.circle"), ("debate", "Debate", "bubble.left.and.bubble.right")], id: \.0) { type, label, icon in
                                    let isActive = taskType == type
                                    Button {
                                        withAnimation(.spring(duration: 0.25)) { taskType = type }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: icon).font(.system(size: 12))
                                            Text(label).font(.system(size: 13, weight: .semibold))
                                        }
                                        .foregroundStyle(isActive ? .white : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(
                                            isActive
                                                ? (type == "debate" ? Color.purple : Color.green)
                                                : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(4)
                            .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 10))
                        )
                    }

                    // ── Primary Agent (standard) or Moderator (debate) ────
                    fieldSection(
                        icon: taskType == "debate" ? "person.badge.shield.checkmark" : "person.fill",
                        label: taskType == "debate" ? "Moderator" : "Assign Agent",
                        hint: taskType == "debate" ? "Opens the debate. Does not argue." : "Who will execute this task"
                    ) {
                        AnyView(agentGrid(
                            agents: personas,
                            selectedNames: selectedPersonaName.map { Set([$0]) } ?? [],
                            multiSelect: false,
                            exclusions: selectedOpponentNames
                        ) { name in
                            if selectedPersonaName == name {
                                selectedPersonaName = nil
                            } else {
                                selectedPersonaName = name
                                selectedOpponentNames.remove(name)
                            }
                        })
                    }

                    // ── Opponents (Debate only) ──────────────────────
                    if taskType == "debate" {
                        fieldSection(
                            icon: "person.2.fill",
                            label: "Debaters",
                            hint: "These agents debate among themselves. Select 2+."
                        ) {
                            AnyView(
                                VStack(alignment: .leading, spacing: 10) {
                                    agentGrid(
                                        agents: personas.filter { $0.name != selectedPersonaName },
                                        selectedNames: selectedOpponentNames,
                                        multiSelect: true,
                                        exclusions: selectedPersonaName.map { Set([$0]) } ?? []
                                    ) { name in
                                        if selectedOpponentNames.contains(name) {
                                            selectedOpponentNames.remove(name)
                                        } else {
                                            selectedOpponentNames.insert(name)
                                        }
                                    }

                                    if personas.count < 2 {
                                        Label("Create at least 2 agents to act as debaters.", systemImage: "exclamationmark.triangle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    } else if selectedOpponentNames.count < 2 {
                                        Label("Select at least 2 debaters to argue against each other.", systemImage: "info.circle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        let count = selectedOpponentNames.count + 1
                                        Label("\(count) participants · \(maxRounds) rounds each = \(count * maxRounds) total LLM calls", systemImage: "info.circle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            )
                        }

                        // Rounds slider
                        fieldSection(icon: "arrow.clockwise", label: "Rounds Per Participant: \(maxRounds)") {
                            AnyView(
                                Slider(
                                    value: .init(get: { Double(maxRounds) }, set: { maxRounds = Int($0) }),
                                    in: 2...20, step: 1
                                )
                                .tint(Color.purple)
                            )
                        }
                    }

                    // ── New Persona Form ─────────────────────────────
                    Button {
                        withAnimation { showNewPersona.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showNewPersona ? "chevron.up" : "plus.circle.fill")
                                .font(.system(size: 12))
                            Text(showNewPersona ? "Cancel New Agent" : "Create New Agent")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)

                    if showNewPersona {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("New Agent")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)

                            HStack(spacing: 8) {
                                styledField("Name", text: $newPersonaName)
                                styledField("Role (e.g. Developer)", text: $newPersonaRole)
                            }
                            styledField("System Prompt", text: $newPersonaPrompt)

                            Button { createPersona() } label: {
                                Text("Create Agent")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.green, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .disabled(newPersonaName.isEmpty || newPersonaPrompt.isEmpty)
                        }
                        .padding(14)
                        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.green.opacity(0.2)))
                    }

                    // ── Priority ─────────────────────────────────────
                    if taskType == "standard" {
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
                }
                .padding(24)
            }

            Divider()

            // ── Footer ───────────────────────────────────────────────
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                Spacer()
                Button { deployTask() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: taskType == "debate" ? "flag.checkered" : "paperplane.fill")
                        Text(taskType == "debate" ? "Start Debate" : "Deploy")
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(
                        taskType == "debate" ? Color.purple : Color.green,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canDeploy)
                .opacity(canDeploy ? 1 : 0.5)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 580, height: taskType == "debate" ? 700 : 560)
        .onAppear { taskType = initialTaskType }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func fieldSection<Content: View>(
        icon: String,
        label: String,
        hint: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                if let hint {
                    Text("–")
                        .foregroundStyle(.tertiary)
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }

    @ViewBuilder
    private func agentGrid(
        agents: [AgentPersona],
        selectedNames: Set<String>,
        multiSelect: Bool,
        exclusions: Set<String>,
        onTap: @escaping (String) -> Void
    ) -> some View {
        if agents.isEmpty {
            Text("No agents available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(agents, id: \.name) { persona in
                    let isSelected = selectedNames.contains(persona.name)
                    let isExcluded = exclusions.contains(persona.name)
                    Button { if !isExcluded { onTap(persona.name) } } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(isExcluded ? Color.gray.opacity(0.4) : Color(hex: persona.accentColorHex))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Text(String(persona.name.prefix(1)))
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(persona.name)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(isExcluded ? .secondary : .primary)
                                Text(persona.roleName.isEmpty ? "Agent" : persona.roleName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(hex: persona.accentColorHex))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isSelected
                                      ? Color(hex: persona.accentColorHex).opacity(0.18)
                                      : GlassTheme.flatFill.opacity(isExcluded ? 0.5 : 1.0))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(
                                            isSelected
                                                ? Color(hex: persona.accentColorHex).opacity(0.6)
                                                : GlassTheme.flatStroke,
                                            lineWidth: isSelected ? 1.5 : 1
                                        )
                                )
                        )
                        .opacity(isExcluded ? 0.4 : 1.0)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .padding(10)
            .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(GlassTheme.flatStroke))
    }

    // MARK: - Actions

    private func fetchPersonas() -> [AgentPersona] {
        let context = ModelContext(appState.modelContainer)
        return (try? context.fetch(FetchDescriptor<AgentPersona>(sortBy: [SortDescriptor(\.name)]))) ?? []
    }

    private func createPersona() {
        let context = ModelContext(appState.modelContainer)
        let persona = AgentPersona(
            name: newPersonaName, roleName: newPersonaRole,
            systemPrompt: newPersonaPrompt, accentColorHex: newPersonaColor
        )
        context.insert(persona)
        try? context.save()
        selectedPersonaName = persona.name
        showNewPersona = false
        newPersonaName = ""; newPersonaRole = ""; newPersonaPrompt = ""
        appState.showToast("Agent '\(persona.name)' created", level: .success)
    }

    private func deployTask() {
        guard let personaName = selectedPersonaName else { return }
        let context = ModelContext(appState.modelContainer)
        guard let persona = (try? context.fetch(FetchDescriptor<AgentPersona>(
            predicate: #Predicate { $0.name == personaName }
        )))?.first else { return }

        if taskType == "debate" {
            let allOpponentNames = Array(selectedOpponentNames)
            let allPersonas = (try? context.fetch(FetchDescriptor<AgentPersona>())) ?? []
            let opponents = allOpponentNames.compactMap { name in allPersonas.first(where: { $0.name == name }) }
            guard !opponents.isEmpty else { return }

            let task = SwarmTask(
                taskDescription: taskDescription,
                priority: priority,
                type: "debate",
                maxRounds: maxRounds,
                additionalOpponentNames: opponents.dropFirst().map { $0.name },
                assignedAgent: persona,
                debateOpponent: opponents.first
            )
            context.insert(task)
            try? context.save()
            appState.orchestrator.refreshPublic()
            appState.showToast("Debate started with \(opponents.count + 1) participants!", level: .success)
        } else {
            appState.orchestrator.createTask(
                description: taskDescription, persona: persona, priority: priority, type: taskType
            )
            appState.showToast("Task deployed to \(persona.name)", level: .success)
        }
        dismiss()
    }
}

// MARK: - Flow Layout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? 0,
            height: rows.map { $0.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0 }.reduce(0, +)
                + CGFloat(max(rows.count - 1, 0)) * spacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        let maxWidth = proposal.width ?? 400
        for subview in subviews {
            let w = subview.sizeThatFits(.unspecified).width
            if rowWidth + w + (rows.last!.isEmpty ? 0 : spacing) > maxWidth, !rows.last!.isEmpty {
                rows.append([subview])
                rowWidth = w
            } else {
                rows[rows.count - 1].append(subview)
                rowWidth += w + (rows.last!.count > 1 ? spacing : 0)
            }
        }
        return rows.filter { !$0.isEmpty }
    }
}

// MARK: - Legacy PersonaChip (kept for ArchivesView/ForwardSheet compatibility)

struct PersonaChip: View {
    let persona: AgentPersona
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: persona.accentColorHex))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(persona.name.prefix(1)))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text(persona.name).font(.system(size: 11, weight: .bold))
                    Text(persona.roleName).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color(hex: persona.accentColorHex).opacity(0.15) : GlassTheme.flatFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? Color(hex: persona.accentColorHex).opacity(0.5) : .clear, lineWidth: 1.5)
                    )
            )
            .glassEffect(
                isSelected || isHovered
                    ? .clear.tint(Color.primary.opacity(0.08)).interactive()
                    : .clear.interactive(),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
