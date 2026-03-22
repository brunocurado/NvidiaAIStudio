import SwiftUI

/// Global application state shared across the app via @Environment.
@Observable
final class AppState {
    // MARK: - Persistence
    private let sessionStore = SessionStore()
    
    // MARK: - Sessions
    var sessions: [Session] = []
    var activeSessionID: UUID? = nil
    
    var activeSession: Session? {
        get { sessions.first { $0.id == activeSessionID } }
        set {
            if let newValue, let idx = sessions.firstIndex(where: { $0.id == newValue.id }) {
                sessions[idx] = newValue
            }
        }
    }
    
    // MARK: - Models
    // Deduplicate on init — prevents crash in saveModelPreferences if defaultModels ever has duplicate IDs
    var availableModels: [AIModel] = {
        var seen = Set<String>()
        return AIModel.defaultModels.filter { seen.insert($0.id).inserted }
    }()
    var selectedModelID: String = "deepseek-ai/deepseek-v3.2"
    
    var selectedModel: AIModel? {
        availableModels.first { $0.id == selectedModelID }
    }
    
    // MARK: - API Keys
    var apiKeys: [APIKey] = []
    var activeProvider: Provider = .nvidia
    
    var activeAPIKey: String? {
        apiKeys.first { $0.provider == activeProvider && $0.isActive }?.key
    }
    
    // MARK: - Workspace
    var activeWorkspacePath: String = FileManager.default.currentDirectoryPath
    
    // MARK: - GitHub
    var gitHubUsername: String? = nil
    var gitHubToken: String? = nil
    
    // MARK: - UI State
    var isSidebarVisible = true
    var isRightPanelVisible = false
    var rightPanelMode: RightPanelMode = .diff
    var reasoningLevel: ReasoningLevel = .medium
    var fileAccessLevel: FileAccessLevel = .fullAccess
    var currentBranch: String = "main"
    var availableBranches: [String] = []
    
    /// Reads the current git branch from the active workspace.
    func refreshGitBranch() {
        let path = activeWorkspacePath
        Task {
            let result = await ShellHelper.run("cd '\(path)' && git branch --show-current 2>/dev/null")
            let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let branchesResult = await ShellHelper.run("cd '\(path)' && git branch 2>/dev/null")
            let branches = branchesResult.output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "* ", with: "") }
                .filter { !$0.isEmpty }
            
            await MainActor.run {
                if !branch.isEmpty { self.currentBranch = branch }
                self.availableBranches = branches.isEmpty ? [self.currentBranch] : branches
            }
        }
    }
    
    /// Checks out a branch in the active workspace.
    func checkoutBranch(_ branch: String) {
        let path = activeWorkspacePath
        Task {
            let result = await ShellHelper.run("cd '\(path)' && git checkout '\(branch)' 2>&1")
            await MainActor.run {
                if result.exitCode == 0 {
                    self.currentBranch = branch
                    self.showToast("Switched to branch: \(branch)", level: .success)
                } else {
                    self.showToast("Checkout failed: \(result.output)", level: .error)
                }
            }
        }
    }
    
    // MARK: - Toast Notifications
    var toasts: [ToastMessage] = []
    
    func showToast(_ message: String, level: ToastMessage.Level = .info) {
        let toast = ToastMessage(message: message, level: level)
        toasts.append(toast)
        
        // Auto-dismiss after 4 seconds
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            toasts.removeAll { $0.id == toast.id }
        }
    }
    
    // MARK: - Session Management
    
    func createSession(title: String = "New Thread") -> Session {
        let session = Session(title: title, projectPath: activeWorkspacePath == FileManager.default.currentDirectoryPath ? nil : activeWorkspacePath)
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        Task { await sessionStore.save(session) }
        return session
    }
    
    /// Rename all sessions that belong to a given project folder name.
    func renameProject(from oldName: String, to newName: String) {
        for i in sessions.indices {
            guard let path = sessions[i].projectPath else { continue }
            let currentName = URL(fileURLWithPath: path).lastPathComponent
            if currentName == oldName {
                // Replace the last component with the new name
                let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
                let newPath = parent.appendingPathComponent(newName).path
                sessions[i].projectPath = newPath
                Task { await sessionStore.save(sessions[i]) }
            }
        }
    }
    
    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if activeSessionID == id {
            activeSessionID = sessions.first?.id
        }
        Task { await sessionStore.delete(id: id) }
    }
    
    /// Save the current active session to disk.
    func saveActiveSession() {
        guard let session = activeSession else { return }
        Task { await sessionStore.save(session) }
    }
    
    /// Load persisted sessions from disk.
    func loadSessions() {
        Task {
            let loaded = await sessionStore.loadAll()
            await MainActor.run {
                sessions = loaded
                if activeSessionID == nil {
                    activeSessionID = sessions.first?.id
                }
            }
        }
    }
    
    // MARK: - GitHub Auth
    
    func startGitHubOAuth() {
        // GitHub Device Flow: open browser for user code entry
        // Step 1: Request device & user code from GitHub
        Task {
            await GitHubService.shared.startDeviceFlow { [weak self] username, token in
                guard let self else { return }
                self.gitHubUsername = username
                self.gitHubToken = token
                // Persist token in Keychain
                KeychainHelper.save(key: "github-oauth-token", string: token)
                KeychainHelper.save(key: "github-username", string: username)
                self.showToast("GitHub connected as @\(username)", level: .success)
            }
        }
    }
    
    func disconnectGitHub() {
        gitHubUsername = nil
        gitHubToken = nil
        KeychainHelper.delete(key: "github-oauth-token")
        KeychainHelper.delete(key: "github-username")
        showToast("GitHub disconnected", level: .info)
    }
    
    func loadGitHubCredentials() {
        gitHubToken = KeychainHelper.loadString(key: "github-oauth-token")
        gitHubUsername = KeychainHelper.loadString(key: "github-username")
    }
    
    /// Initialize: load sessions, env-based API key, and fetch live models.
    func bootstrap() {
        loadSessions()
        loadGitHubCredentials()
        AppNotifications.requestPermission()
        
        // Auto-load API key from .env if no keys configured
        if apiKeys.isEmpty, let envKey = EnvParser.loadNVIDIAKey() {
            let key = APIKey(provider: .nvidia, name: "NVIDIA (from .env)", key: envKey)
            apiKeys.append(key)
        }
        
        // Restore saved model preferences
        loadModelPreferences()
        
        // Auto-fetch available models from NVIDIA NIM
        if let apiKey = activeAPIKey {
            Task {
                if let fetched = await ModelFetcher.fetchModels(apiKey: apiKey) {
                    await MainActor.run {
                        availableModels = ModelFetcher.mergeModels(existing: availableModels, fetched: fetched)
                        loadModelPreferences() // re-apply saved isEnabled after merge
                    }
                }
            }
        }
    }
    
    // MARK: - Model Preferences Persistence
    
    /// Save which models are enabled/disabled to UserDefaults.
    func saveModelPreferences() {
        // Use merging init to safely handle any duplicate IDs — last value wins.
        // This never crashes, unlike uniqueKeysWithValues which asserts on duplicates.
        let prefs = Dictionary(availableModels.map { ($0.id, $0.isEnabled) }, uniquingKeysWith: { _, last in last })
        UserDefaults.standard.set(prefs, forKey: "modelPreferences")
    }
    
    /// Load saved model enabled/disabled from UserDefaults.
    func loadModelPreferences() {
        guard let prefs = UserDefaults.standard.dictionary(forKey: "modelPreferences") as? [String: Bool] else { return }
        for i in availableModels.indices {
            if let saved = prefs[availableModels[i].id] {
                availableModels[i].isEnabled = saved
            }
        }
    }
}

// MARK: - Supporting Enums

enum RightPanelMode: String, CaseIterable {
    case diff = "Diff"
    case terminal = "Terminal"
}

enum ReasoningLevel: String, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case off = "Off"
    
    var icon: String {
        switch self {
        case .high: return "brain.head.profile.fill"
        case .medium: return "brain.head.profile"
        case .low: return "brain"
        case .off: return "brain.head.profile"
        }
    }
}

enum FileAccessLevel: String, CaseIterable {
    case fullAccess = "Full Access"
    case sandboxed = "Sandboxed"
    
    var icon: String {
        switch self {
        case .fullAccess: return "lock.open.fill"
        case .sandboxed: return "lock.fill"
        }
    }
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let message: String
    let level: Level
    let timestamp = Date()
    
    enum Level {
        case info, success, warning, error
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }
    }
}
