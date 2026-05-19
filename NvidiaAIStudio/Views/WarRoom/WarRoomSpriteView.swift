import SwiftUI
import SpriteKit
import SwiftData

/// SwiftUI wrapper that owns the WarRoomScene and bridges SwiftData state into SpriteKit.
struct WarRoomSpriteView: View {
    @Environment(AppState.self) private var appState

    // Live SwiftData queries — the single source of truth
    @Query(sort: \AgentPersona.name) private var allPersonas: [AgentPersona]

    @Query(
        filter: #Predicate<SwarmTask> { $0.status == "running" || $0.status == "pending" },
        sort: \SwarmTask.createdAt, order: .reverse
    ) private var activeTasks: [SwarmTask]

    @Query(
        filter: #Predicate<SwarmTask> { $0.status == "running" },
        sort: \SwarmTask.createdAt, order: .reverse
    ) private var runningTasks: [SwarmTask]

    @Query(
        filter: #Predicate<SwarmTask> { $0.status == "running" && $0.type == "debate" },
        sort: \SwarmTask.createdAt, order: .reverse
    ) private var activeDebates: [SwarmTask]

    // The SpriteKit scene — created once, reused forever
    @State private var scene: WarRoomScene = {
        let s = WarRoomScene()
        s.scaleMode = .resizeFill
        s.anchorPoint = .zero
        return s
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── SpriteKit canvas ──────────────────────────────────
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .ignoresSafeArea()

                // ── Empty state (only if there are no agents registered) ────────────
                if allPersonas.isEmpty {
                    emptyStateOverlay
                }

                // ── Bottom status bar ─────────────────────────────────
                VStack {
                    Spacer()
                    ceoStatusBar
                }
            }
            .onAppear { scene.size = geo.size }
            .onChange(of: geo.size) { _, s in scene.size = s }
            // Sync all agents whenever task or persona list changes
            .onChange(of: activeTasks) { _, tasks in
                syncAgents(personas: allPersonas, tasks: tasks)
            }
            .onChange(of: allPersonas, initial: true) { _, personas in
                syncAgents(personas: personas, tasks: activeTasks)
            }
            // Debate lifecycle
            .onChange(of: activeDebates.first?.id, initial: true) { oldID, newID in
                let debateStarted: Bool = newID != nil && oldID != newID
                let debateEnded: Bool   = newID == nil && oldID != nil

                if debateStarted, let debate = activeDebates.first {
                    var names: [String] = [debate.assignedAgent?.name].compactMap { $0 }
                    if let opp = debate.debateOpponent?.name { names.append(opp) }
                    names.append(contentsOf: debate.additionalOpponentNames)
                    scene.startDebate(participants: names)
                } else if debateEnded {
                    scene.endDebate()
                }
            }
            // Active speaker bounce
            .onChange(of: appState.orchestrator.runningTasks.first?.agentName) { _, speakerName in
                let inDebate = !activeDebates.isEmpty
                for (name, pod) in scene.pods {
                    if pod.state == .speaking {
                        scene.setAgentState(name, state: inDebate ? .debating : .working)
                    }
                }
                if let name = speakerName {
                    scene.setAgentState(name, state: .speaking)
                }
            }
        }
        .background(Color(red: 0.04, green: 0.05, blue: 0.08))
    }

    // MARK: - Empty State

    private var emptyStateOverlay: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                // Pulsing outer ring
                Circle()
                    .strokeBorder(Color.cyan.opacity(0.15), lineWidth: 1)
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(Color.cyan.opacity(0.06))
                    .frame(width: 90, height: 90)

                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 36, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("War Room — Standby")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Deploy a task or launch a debate\nto summon your agents.")
                    .font(.system(size: 13))
                    .foregroundStyle(GlassTheme.textMuted)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - CEO Status Bar

    private var ceoStatusBar: some View {
        let running = runningTasks.count
        let pending = activeTasks.filter { $0.status == "pending" }.count
        let debating = !activeDebates.isEmpty

        return HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(debating ? Color.orange : running > 0 ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 7, height: 7)

                Group {
                    if debating {
                        Text("Debate Active — \(running) agent\(running == 1 ? "" : "s") live")
                    } else if running > 0 {
                        Text("\(running) working\(pending > 0 ? " · \(pending) queued" : "")")
                    } else {
                        Text("Virtual Office — \(allPersonas.count) agent\(allPersonas.count == 1 ? "" : "s") on standby")
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(GlassTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial.opacity(0.3), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Agent Sync

    private func syncAgents(personas: [AgentPersona], tasks: [SwarmTask]) {
        var activeTaskMap: [String: SwarmTask] = [:]
        for t in tasks {
            if let agent = t.assignedAgent {
                activeTaskMap[agent.name] = t
            }
        }

        // Spawn/update all personas
        for (idx, persona) in personas.enumerated() {
            if scene.pods[persona.name] == nil {
                scene.spawnAgent(
                    name: persona.name,
                    role: persona.roleName,
                    accentHex: persona.accentColorHex,
                    index: idx
                )
            }

            // Determine correct state and destination
            let activeTask = activeTaskMap[persona.name]
            let inDebate = activeDebates.first != nil && (
                activeDebates.first?.assignedAgent?.name == persona.name ||
                activeDebates.first?.debateOpponent?.name == persona.name ||
                (activeDebates.first?.additionalOpponentNames.contains(persona.name) ?? false)
            )

            if inDebate {
                scene.setAgentState(persona.name, state: .debating)
            } else if let task = activeTask {
                if task.status == "pending" {
                    let blockedBy = tasks.first(where: { $0.status == "running" })?.assignedAgent?.name ?? "queue"
                    scene.setAgentState(persona.name, state: .waiting(for: blockedBy))
                } else {
                    scene.setAgentState(persona.name, state: .working)
                }

                // Sincronizar o último log do terminal
                if task.status == "running", let lastLog = task.logs.last {
                    let cleanLog = lastLog.replacingOccurrences(of: "\\[\\d{2}:\\d{2}:\\d{2}\\] ", with: "", options: .regularExpression)
                    scene.updateTerminalLog(for: persona.name, text: cleanLog)
                }
            } else {
                scene.setAgentState(persona.name, state: .idle)
            }
        }

        // Clean up deleted personas
        let personaNames = Set(personas.map { $0.name })
        for name in Array(scene.pods.keys) where !personaNames.contains(name) {
            scene.removeAgent(name: name)
        }
    }
}
