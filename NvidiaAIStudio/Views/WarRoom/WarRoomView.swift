import SwiftUI
import SwiftData

/// The War Room — the spatial command center for managing swarm agents.
/// Composed of the Spatial Canvas and Archives (Inbox).
struct WarRoomView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: WarRoomTab = .canvas
    @State private var showNewTaskSheet = false
    @State private var newTaskInitialType = "standard"
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            warRoomHeader
            
            Divider()
            
            // Content — tab-driven
            Group {
                switch selectedTab {
                case .canvas:
                    WarRoomSpriteView()
                case .archives:
                    ArchivesView()
                case .debates:
                    DebateRoomView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewTaskSheet) {
            NewTaskSheet(initialTaskType: newTaskInitialType)
                .environment(appState)
        }
    }
    
    // MARK: - Header
    
    private var warRoomHeader: some View {
        HStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 2) {
                ForEach(WarRoomTab.allCases) { tab in
                    WarRoomTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        badge: badgeCount(for: tab)
                    ) {
                        withAnimation(.spring(duration: 0.3)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(3)
            .background(.ultraThinMaterial.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            
            Spacer()
            
            // Running agents indicator
            let running = appState.orchestrator.runningTasks.count
            if running > 0 {
                Menu {
                    ForEach(appState.orchestrator.runningTasks) { task in
                        Button(role: .destructive) {
                            appState.orchestrator.cancelAgent(for: task.id)
                        } label: {
                            Text("Stop \(task.agentName)")
                            Image(systemName: "xmark.octagon.fill")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("\(running) agent\(running == 1 ? "" : "s") active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                        }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.1), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            // Deploy button — context-aware
            Button {
                newTaskInitialType = (selectedTab == .debates) ? "debate" : "standard"
                showNewTaskSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: selectedTab == .debates ? "bubble.left.and.bubble.right.fill" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(selectedTab == .debates ? "New Debate" : "Deploy Task")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    selectedTab == .debates ? Color.purple.opacity(0.8) : Color.green.opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func badgeCount(for tab: WarRoomTab) -> Int {
        switch tab {
        case .canvas: return appState.orchestrator.runningTasks.count + appState.orchestrator.pendingCount
        case .archives: return appState.orchestrator.unreadDeliverableCount
        case .debates: return 0 // Can implement debate count later
        }
    }
}

// MARK: - Tab Enum

enum WarRoomTab: String, CaseIterable, Identifiable {
    case canvas = "Spatial Canvas"
    case archives = "Archives"
    case debates = "Debate Room"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .canvas: return "view.3d"
        case .archives: return "tray.full.fill"
        case .debates: return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Tab Button

struct WarRoomTabButton: View {
    let tab: WarRoomTab
    let isSelected: Bool
    var badge: Int = 0
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(tab == .archives ? Color.orange : Color.green, in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? RoundedRectangle(cornerRadius: 8).fill(GlassTheme.flatFill)
                    : nil
            )
            .glassEffect(isSelected ? .regular : (isHovered ? .regular : .identity), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
