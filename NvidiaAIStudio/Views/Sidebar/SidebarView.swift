import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var hoveredSessionID: UUID?
    @State private var expandedProjects: Set<String> = []
    @State private var showSkillsPanel = false
    @State private var renamingProject: String? = nil
    @State private var renameText = ""
    @State private var showUsagePanel = false
    @State private var renamingSession: Session? = nil
    @State private var renameSessionText = ""
    
    private var groupedSessions: [(project: String, sessions: [Session])] {
        let filtered = searchText.isEmpty ? appState.sessions : appState.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
        var groups: [String: [Session]] = [:]
        for session in filtered { groups[session.projectName, default: []].append(session) }
        return groups.sorted { a, b in
            if a.key == "General" { return false }
            if b.key == "General" { return true }
            return a.key < b.key
        }.map { (project: $0.key, sessions: $0.value) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header — matches GlassCode "Threads" title
            HStack {
                Text("Threads")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    exportActiveThread()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Export Threads")
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 4)
            VStack(spacing: 2) {
                SidebarActionButton(icon: "plus.message.fill", label: "New thread", accentColor: .green) {
                    // Create thread in the currently active session's project (or General)
                    let projectPath = appState.activeSession?.projectPath
                    var session = appState.createSession()
                    session.projectPath = projectPath
                    appState.activeSession = session
                }
                WorkspaceSidebarButton(onOpenPicker: openWorkspacePicker)
                SidebarActionButton(icon: "sparkles", label: "Skills", accentColor: .purple) {
                    showSkillsPanel = true
                }
                SidebarActionButton(icon: "chart.bar.fill", label: "Usage", accentColor: .blue) {
                    showUsagePanel = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search threads...", text: $searchText).textFieldStyle(.plain).font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            
            Divider().padding(.vertical, 8)
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(groupedSessions, id: \.project) { group in
                        ProjectFolderView(
                            projectName: group.project,
                            sessions: group.sessions,
                            isExpanded: expandedProjects.contains(group.project),
                            activeSessionID: appState.activeSessionID,
                            hoveredSessionID: hoveredSessionID,
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedProjects.contains(group.project) { expandedProjects.remove(group.project) }
                                    else { expandedProjects.insert(group.project) }
                                }
                            },
                            onSelect: { session in withAnimation(.easeInOut(duration: 0.15)) { appState.activeSessionID = session.id } },
                            onHover: { sessionID, isHovered in hoveredSessionID = isHovered ? sessionID : nil },
                            onDelete: { appState.deleteSession($0) },
                            onRenameFolder: { old, new in
                                appState.renameProject(from: old, to: new)
                                expandedProjects.remove(old); expandedProjects.insert(new)
                            },
                            onRenameThread: { session in renamingSession = session; renameSessionText = session.title },
                            onNewThread: { projectPath in
                                var session = appState.createSession()
                                session.projectPath = projectPath
                                appState.activeSession = session
                            },
                            onRemoveWorkspace: { projectName in
                                // Remove all sessions in this workspace and the workspace itself
                                let toRemove = appState.sessions.filter { $0.projectName == projectName }
                                for s in toRemove { appState.deleteSession(s.id) }
                                if let ws = appState.savedWorkspaces.first(where: { $0.name == projectName }) {
                                    appState.removeWorkspace(ws)
                                }
                                appState.showToast("Removed workspace: \(projectName)", level: .info)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            Divider()
            SettingsLink {
                HStack {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .background(.clear)
        .onAppear { for group in groupedSessions { expandedProjects.insert(group.project) } }
        .sheet(isPresented: $showSkillsPanel) { SkillsPanelView() }
        .onReceive(NotificationCenter.default.publisher(for: .openWorkspacePicker)) { _ in openWorkspacePicker() }
        .sheet(isPresented: $showUsagePanel) { UsagePanelView() }
        .alert("Rename Thread", isPresented: Binding(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("Thread name", text: $renameSessionText)
            Button("Rename") {
                if let session = renamingSession, !renameSessionText.isEmpty {
                    if let idx = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                        appState.sessions[idx].title = renameSessionText
                        appState.saveActiveSession()
                    }
                }
                renamingSession = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) { renamingSession = nil }
        }
    }
    
    private func openWorkspacePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Workspace"
        panel.message = "Choose a project folder to open as workspace"
        if panel.runModal() == .OK, let url = panel.url {
            appState.addWorkspace(path: url.path)
            var session = appState.createSession(title: "New Thread")
            session.projectPath = url.path
            appState.activeSession = session
            appState.showToast("Workspace: \(url.lastPathComponent)", level: .success)
        }
    }
    
    private func exportActiveThread() {
        guard let session = appState.activeSession else {
            appState.showToast("No active thread to export", level: .warning)
            return
        }
        let text = session.messages.map { msg -> String in
            let role = msg.role.rawValue.capitalized
            return "[\(role)] \(msg.content)"
        }.joined(separator: "\n\n---\n\n")
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(session.title).txt"
        panel.message = "Export thread as text"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
            appState.showToast("Thread exported to \(url.lastPathComponent)", level: .success)
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
    var onRenameThread: ((Session) -> Void)? = nil
    var onNewThread: ((String?) -> Void)? = nil
    var onRemoveWorkspace: ((String) -> Void)? = nil
    
    @State private var isRenamingFolder = false
    @State private var folderRenameText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "folder.fill" : "folder")
                        .font(.caption)
                        .foregroundColor(projectName == "General" ? Color.secondary : Color.blue)
                    if isRenamingFolder {
                        TextField("", text: $folderRenameText)
                            .font(.caption).fontWeight(.semibold).textFieldStyle(.plain)
                            .onSubmit { if !folderRenameText.isEmpty { onRenameFolder?(projectName, folderRenameText) }; isRenamingFolder = false }
                            .onExitCommand { isRenamingFolder = false }
                    } else {
                        Text(projectName).font(.caption).fontWeight(.semibold).lineLimit(1)
                    }
                    Text("\(sessions.count)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.white.opacity(0.08), in: Capsule())
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("New Thread") {
                    onNewThread?(projectName == "General" ? nil : sessions.first?.projectPath)
                }
                Divider()
                if projectName != "General" {
                    Button("Rename Folder") { folderRenameText = projectName; isRenamingFolder = true }
                    Divider()
                    Button("Remove Workspace", role: .destructive) {
                        onRemoveWorkspace?(projectName)
                    }
                }
            }
            
            if isExpanded {
                ForEach(sessions) { session in
                    ThreadItemView(session: session, isSelected: activeSessionID == session.id, isHovered: hoveredSessionID == session.id)
                        .onTapGesture { onSelect(session) }
                        .onHover { onHover(session.id, $0) }
                        .contextMenu {
                            Button("Rename") { onRenameThread?(session) }
                            Divider()
                            Button("Delete", role: .destructive) { onDelete(session.id) }
                        }
                        .padding(.leading, 8)
                }
                
                // GlassCode-style "Show less" toggle
                if sessions.count > 1 {
                    Button(action: onToggle) {
                        Text("Show less")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                    .padding(.vertical, 4)
                }
            } else if !sessions.isEmpty {
                // "Show more" when collapsed
                Button(action: onToggle) {
                    Text("Show more")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Sidebar Action Button

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
                Text(label).font(.caption)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(isHovered ? .regular : .identity, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Workspace Button

struct WorkspaceSidebarButton: View {
    @Environment(AppState.self) private var appState
    let onOpenPicker: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .frame(width: 16)
                Text("Open Workspace").font(.caption)
                Spacer()
                if !appState.savedWorkspaces.isEmpty {
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .glassEffect(isHovered ? .regular : .identity, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func showMenu() {
        WorkspaceMenuCoordinator.shared.show(
            workspaces: Array(appState.savedWorkspaces.prefix(8)),
            activeWorkspacePath: appState.activeWorkspacePath,
            onBrowse: onOpenPicker,
            onSelect: { path in
                appState.switchWorkspace(path: path)
                appState.showToast("Workspace: \(URL(fileURLWithPath: path).lastPathComponent)", level: .success)
            },
            onClear: {
                appState.savedWorkspaces.removeAll()
                UserDefaults.standard.removeObject(forKey: "savedWorkspaces")
            }
        )
    }
}

@MainActor
final class WorkspaceMenuCoordinator: NSObject, NSMenuDelegate {
    static let shared = WorkspaceMenuCoordinator()

    private var onBrowse: (() -> Void)?
    private var onSelect: ((String) -> Void)?
    private var onClear: (() -> Void)?

    func show(
        workspaces: [SavedWorkspace],
        activeWorkspacePath: String,
        onBrowse: @escaping () -> Void,
        onSelect: @escaping (String) -> Void,
        onClear: @escaping () -> Void
    ) {
        self.onBrowse = onBrowse
        self.onSelect = onSelect
        self.onClear = onClear

        let m = NSMenu()
        m.delegate = self

        let browseItem = NSMenuItem(title: "Browse\u{2026}", action: #selector(handleBrowse), keyEquivalent: "")
        browseItem.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
        browseItem.target = self
        m.addItem(browseItem)

        if !workspaces.isEmpty {
            m.addItem(.separator())
            let header = NSMenuItem(title: "Recent Workspaces", action: nil, keyEquivalent: "")
            header.isEnabled = false
            m.addItem(header)
            for ws in workspaces {
                let item = NSMenuItem(title: ws.name, action: #selector(handleSelect(_:)), keyEquivalent: "")
                item.image = NSImage(systemSymbolName: ws.path == activeWorkspacePath ? "folder.fill" : "folder", accessibilityDescription: nil)
                item.representedObject = ws.path
                item.target = self
                m.addItem(item)
            }
            m.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear Recent", action: #selector(handleClear), keyEquivalent: "")
            clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            clearItem.target = self
            m.addItem(clearItem)
        }

        m.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func handleBrowse() { onBrowse?() }
    @objc private func handleSelect(_ item: NSMenuItem) {
        guard let path = item.representedObject as? String else { return }
        onSelect?(path)
    }
    @objc private func handleClear() { onClear?() }
}

// MARK: - Thread Item

struct ThreadItemView: View {
    let session: Session
    let isSelected: Bool
    let isHovered: Bool
    var onRename: ((String) -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    @State private var isRenaming = false
    @State private var renameText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                if !session.backgroundAgents.isEmpty {
                    Text("\(session.backgroundAgents.count)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.blue.opacity(0.6), in: Capsule())
                }
                Spacer()
                Text(session.relativeTime).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ForEach(session.backgroundAgents) { agent in
                HStack(spacing: 6) {
                    Circle().fill(agentStatusColor(agent.status)).frame(width: 6, height: 6)
                    Text(agent.name).font(.system(size: 10, weight: .medium)).foregroundStyle(.blue)
                    Text(agent.task).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .glassEffect(isSelected ? .regular.tint(.blue.opacity(0.15)) : (isHovered ? .regular : .identity), in: RoundedRectangle(cornerRadius: 8))
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
