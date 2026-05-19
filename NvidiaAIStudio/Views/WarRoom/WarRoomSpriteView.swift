import SwiftUI
import SpriteKit
import SwiftData

/// SwiftUI wrapper that owns the WarRoomScene and bridges SwiftData state into SpriteKit.
struct WarRoomSpriteView: View {
    @Environment(AppState.self) private var appState

    // Live SwiftData queries — the single source of truth
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

                // ── Empty state (no tasks) ────────────────────────────
                if activeTasks.isEmpty {
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
            // Sync all agents whenever any task changes
            .onChange(of: activeTasks, initial: true) { _, tasks in
                syncAgents(tasks: tasks)
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
                        Text("Standby")
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

    private func syncAgents(tasks: [SwarmTask]) {
        let activeNames = Set(tasks.compactMap { $0.assignedAgent?.name })

        // Spawn new agents and update their states
        var idx = scene.pods.count
        for (taskIdx, task) in tasks.enumerated() {
            guard let persona = task.assignedAgent else { continue }

            if scene.pods[persona.name] == nil {
                scene.spawnAgent(
                    name: persona.name,
                    role: persona.roleName,
                    accentHex: persona.accentColorHex,
                    index: taskIdx
                )
                idx += 1
            }

            // Set correct state based on task status
            let inDebate = activeDebates.contains { $0.id == task.id }
            if inDebate {
                scene.setAgentState(persona.name, state: .debating)
            } else if task.status == "pending" {
                // Show who they're waiting for (could be the previous task's agent)
                let blockedBy = tasks.first(where: { $0.status == "running" })?.assignedAgent?.name ?? "queue"
                scene.setAgentState(persona.name, state: .waiting(for: blockedBy))
            } else {
                scene.setAgentState(persona.name, state: .working)
            }
        }

        // Remove agents whose tasks are completely gone
        for name in Array(scene.pods.keys) where !activeNames.contains(name) {
            scene.removeAgent(name: name)
        }
    }
}
