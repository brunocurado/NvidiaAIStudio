import SwiftUI

/// Sidebar with thread list grouped by project folders.
/// Design matches GlassCode: glassmorphism background, project folders,
/// threads with sub-agent nesting, timestamps, token badges.
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var hoveredSessionID: UUID?
    @State private var expandedProjects: Set<String> = []
    @State private var showSkillsPanel = false
    @State private var renamingProject: String? = nil
    @State private var renameText = ""
    @State private var showUsagePanel = false
    
    // Group sessions by project path
    private var groupedSessions: [(project: String, sessions: [Session])] {
        let filtered: [Session]
        if searchText.isEmpty {
            filtered = appState.sessions
        } else {
            filtered = appState.sessions.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Group by project (folder name)
        var groups: [String: [Session]] = [:]
        for session in filtered {
            let project = session.projectName
            groups[project, default: []].append(session)
        }
        
        // Sort: "General" always last, rest alphabetical
        return groups.sorted { a, b in
            if a.key == "General" { return false }
            if b.key == "General" { return true }
            return a.key < b.key
        }.map { (project: $0.key, sessions: $0.value) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top actions
            VStack(spacing: 2) {
                SidebarActionButton(icon: "plus.message.fill", label: "New thread", accentColor: .green) {
                    let _ = appState.createSession()
                }
                SidebarActionButton(icon: "folder.badge.plus", label: "Open Workspace", accentColor: .orange) {
                    openWorkspacePicker()
                }
                SidebarActionButton(icon: "sparkles", label: "Skills", accentColor: .purple) {
                    showSkillsPanel = true
                }
                SidebarActionButton(icon: "chart.bar.fill", label: "Usage", accentColor: .blue) {
                    showUsagePanel = true
                }

            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search threads...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            
            Divider()
                .padding(.vertical, 8)
            
            // Thread list grouped by projects
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(groupedSessions, id: \.project) { group in
                        ProjectFolderView(
                            projectName: group.project,
                            sessions: group.sessions,
                            isExpanded: expandedProjects.contains(group.project) || group.project == "General",
                            activeSessionID: appState.activeSessionID,
                            hoveredSessionID: hoveredSessionID,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedProjects.contains(group.project) {
                                        expandedProjects.remove(group.project)
                                    } else {
                                        expandedProjects.insert(group.project)
                                    }
                                }
                            },
                            onSelect: { session in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    appState.activeSessionID = session.id
                                }
                            },
                            onHover: { sessionID, isHovered in
                                hoveredSessionID = isHovered ? sessionID : nil
                            },
                            onDelete: { sessionID in
                                appState.deleteSession(sessionID)
                            },
                            onRenameFolder: { oldName, newName in
                                appState.renameProject(from: oldName, to: newName)
                                // Update expanded set
                                expandedProjects.remove(oldName)
                                expandedProjects.insert(newName)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            // Settings gear
            Divider()
            SettingsLink {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            for group in groupedSessions {
                expandedProjects.insert(group.project)
            }
        }
        .sheet(isPresented: $showSkillsPanel) {
            SkillsPanelView()
        }
        .sheet(isPresented: $showUsagePanel) {
            UsagePanelView()
        }
    }
    
    // MARK: - Open Workspace Picker
    
    private func openWorkspacePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Workspace"
        panel.message = "Choose a project folder to open as workspace"
        
        if panel.runModal() == .OK, let url = panel.url {
            appState.activeWorkspacePath = url.path
            var session = appState.createSession(title: "New Thread")
            session.projectPath = url.path
            appState.activeSession = session
            appState.showToast("Workspace: \(url.lastPathComponent)", level: .success)
            appState.refreshGitBranch()
        }
    }
}

// MARK: - Project Folder

struct ProjectFolderView: View {
    let projectName: String
    let sessions: [Session]
    let isExpanded: Bool
    let activeSessionID: UUID?
    let hoveredSessionID: UUID?
    let onToggle: () -> Void
    let onSelect: (Session) -> Void
    let onHover: (UUID, Bool) -> Void
    let onDelete: (UUID) -> Void
    var onRenameFolder: ((String, String) -> Void)? = nil
    
    @State private var isRenamingFolder = false
    @State private var folderRenameText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Folder header
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.caption)
                        .foregroundColor(projectName == "General" ? Color.secondary : Color.blue)
                    
                    if isRenamingFolder {
                        TextField("", text: $folderRenameText)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                if !folderRenameText.isEmpty {
                                    onRenameFolder?(projectName, folderRenameText)
                                }
                                isRenamingFolder = false
                            }
                            .onExitCommand { isRenamingFolder = false }
                    } else {
                        Text(projectName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }
                    
                    Text("\(sessions.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.08), in: Capsule())
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if projectName != "General" {
                    Button("Rename Folder") {
                        folderRenameText = projectName
                        isRenamingFolder = true
                    }
                    Divider()
                }
            }
            
            // Threads inside folder
            if isExpanded {
                ForEach(sessions) { session in
                    ThreadItemView(
                        session: session,
                        isSelected: activeSessionID == session.id,
                        isHovered: hoveredSessionID == session.id
                    )
                    .onTapGesture {
                        onSelect(session)
                    }
                    .onHover { isHovered in
                        onHover(session.id, isHovered)
                    }
                    .contextMenu {
                        Button("Rename") { /* TODO */ }
                        Button("Duplicate") { /* TODO */ }
                        Divider()
                        Button("Delete", role: .destructive) {
                            onDelete(session.id)
                        }
                    }
                    .padding(.leading, 8) // Indent under folder
                }
            }
        }
    }
}

// MARK: - Sidebar Sub-Components

struct SidebarActionButton: View {
    let icon: String
    let label: String
    var accentColor: Color = .blue
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
                    .frame(width: 16)
                Text(label)
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovered ? .white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct ThreadItemView: View {
    let session: Session
    let isSelected: Bool
    let isHovered: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                
                if !session.backgroundAgents.isEmpty {
                    Text("\(session.backgroundAgents.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.blue.opacity(0.6), in: Capsule())
                }
                
                Spacer()
                
                Text(session.relativeTime)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            
            // Sub-agents
            ForEach(session.backgroundAgents) { agent in
                HStack(spacing: 6) {
                    Circle()
                        .fill(agentStatusColor(agent.status))
                        .frame(width: 6, height: 6)
                    
                    Text(agent.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue)
                    
                    Text(agent.task)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? .white.opacity(0.12) : (isHovered ? .white.opacity(0.06) : .clear))
        )
    }
    
    private func agentStatusColor(_ status: BackgroundAgent.AgentStatus) -> Color {
        switch status {
        case .thinking: return .orange
        case .running: return .blue
        case .reading: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }
}
