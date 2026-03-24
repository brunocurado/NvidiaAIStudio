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
    
    /// Mutate the active session in-place without replacing the entire struct.
    /// This avoids full SwiftUI re-renders on every streaming chunk.
    @MainActor
    func mutateActiveSession(_ transform: (inout Session) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        transform(&sessions[idx])
    }
    
    // MARK: - Models
    var availableModels: [AIModel] = {
        var seen = Set<String>()
        return AIModel.defaultModels.filter { seen.insert($0.id).inserted }
    }()
    var selectedModelID: String = UserDefaults.standard.string(forKey: "savedSelectedModelID") ?? "deepseek-ai/deepseek-v3.2" {
        didSet {
            UserDefaults.standard.set(selectedModelID, forKey: "savedSelectedModelID")
        }
    }    
    var selectedModel: AIModel? {
        availableModels.first { $0.id == selectedModelID }
    }
    
    // MARK: - API Keys
    var apiKeys: [APIKey] = []
    var activeProvider: Provider = .nvidia
    
    var activeAPIKey: String? {
        apiKeys.first { $0.provider == activeProvider && $0.isActive }?.key
    }

    var modelsForActiveProvider: [AIModel] {
        switch activeProvider {
        case .nvidia:    return availableModels.filter { $0.provider == .nvidia }
        case .anthropic: return AIModel.anthropicModels
        case .openai:    return AIModel.openAIModels
        case .custom:    return availableModels.filter { $0.provider == .custom }
        }
    }

    func switchProvider(_ newProvider: Provider) {
        activeProvider = newProvider
        if let first = modelsForActiveProvider.first {
            selectedModelID = first.id
        }
        let toMerge: [AIModel]
        switch newProvider {
        case .anthropic: toMerge = AIModel.anthropicModels
        case .openai:    toMerge = AIModel.openAIModels
        default:         toMerge = []
        }
        for model in toMerge {
            if !availableModels.contains(where: { $0.id == model.id }) {
                availableModels.append(model)
            }
        }
    }

    // MARK: - API Keys Persistence

    private static let apiKeysMetadataKey = "savedAPIKeysMetadata"

    /// Persist all API keys: metadata in UserDefaults, secrets in Keychain.
    func saveAPIKeys() {
        struct APIKeyMetadata: Codable {
            let id: UUID
            let provider: Provider
            let name: String
            let isActive: Bool
            let customBaseURL: String?
            let createdAt: Date
        }
        let metadata = apiKeys.map {
            APIKeyMetadata(
                id: $0.id,
                provider: $0.provider,
                name: $0.name,
                isActive: $0.isActive,
                customBaseURL: $0.customBaseURL,
                createdAt: $0.createdAt
            )
        }
        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: Self.apiKeysMetadataKey)
        }
        for key in apiKeys {
            KeychainHelper.saveAPIKey(key)
        }
    }

    /// Load API keys from UserDefaults (metadata) + Keychain (secrets).
    func loadAPIKeys() {
        struct APIKeyMetadata: Codable {
            let id: UUID
            let provider: Provider
            let name: String
            let isActive: Bool
            let customBaseURL: String?
            let createdAt: Date
        }
        guard
            let data = UserDefaults.standard.data(forKey: Self.apiKeysMetadataKey),
            let metadata = try? JSONDecoder().decode([APIKeyMetadata].self, from: data)
        else { return }

        var loaded: [APIKey] = []
        for m in metadata {
            guard let secret = KeychainHelper.loadAPIKey(id: m.id) else { continue }
            let key = APIKey(
                id: m.id,
                provider: m.provider,
                name: m.name,
                key: secret,
                isActive: m.isActive,
                customBaseURL: m.customBaseURL,
                createdAt: m.createdAt
            )
            loaded.append(key)
        }
        if !loaded.isEmpty {
            apiKeys = loaded
        }
    }
    
    // MARK: - Workspaces
    var activeWorkspacePath: String = FileManager.default.currentDirectoryPath

    var savedWorkspaces: [SavedWorkspace] = {
        guard let data = UserDefaults.standard.data(forKey: "savedWorkspaces"),
              let decoded = try? JSONDecoder().decode([SavedWorkspace].self, from: data)
        else { return [] }
        return decoded
    }()

    func addWorkspace(path: String) {
        let ws = SavedWorkspace(path: path)
        if !savedWorkspaces.contains(where: { $0.path == path }) {
            savedWorkspaces.insert(ws, at: 0)
            persistWorkspaces()
        }
        switchWorkspace(path: path)
    }

    func removeWorkspace(_ ws: SavedWorkspace) {
        savedWorkspaces.removeAll { $0.id == ws.id }
        persistWorkspaces()
    }

    func switchWorkspace(path: String) {
        activeWorkspacePath = path
        if let idx = savedWorkspaces.firstIndex(where: { $0.path == path }) {
            savedWorkspaces[idx].lastUsed = Date()
            persistWorkspaces()
        }
        refreshGitBranch()
    }

    private func persistWorkspaces() {
        if let data = try? JSONEncoder().encode(savedWorkspaces) {
            UserDefaults.standard.set(data, forKey: "savedWorkspaces")
        }
    }
    
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
    
    func renameProject(from oldName: String, to newName: String) {
        for i in sessions.indices {
            guard let path = sessions[i].projectPath else { continue }
            let currentName = URL(fileURLWithPath: path).lastPathComponent
            if currentName == oldName {
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
    
    func saveActiveSession() {
        guard let session = activeSession else { return }
        Task { await sessionStore.save(session) }
    }
    
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
        Task {
            await GitHubService.shared.startDeviceFlow { [weak self] username, token in
                guard let self else { return }
                self.gitHubUsername = username
                self.gitHubToken = token
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
    
    /// Initialize: load sessions, API keys, env-based API key fallback, and fetch live models.
    func bootstrap() {
        loadSessions()
        loadGitHubCredentials()
        loadAPIKeys()
        AppNotifications.requestPermission()
        MCPManager.shared.connectAll()

        if apiKeys.isEmpty, let envKey = EnvParser.loadNVIDIAKey() {
            let key = APIKey(provider: .nvidia, name: "NVIDIA (from .env)", key: envKey)
            apiKeys.append(key)
            saveAPIKeys()
        }
        
        loadModelPreferences()
        
        if let apiKey = activeAPIKey {
            Task {
                if let fetched = await ModelFetcher.fetchModels(apiKey: apiKey) {
                    await MainActor.run {
                        availableModels = ModelFetcher.mergeModels(existing: availableModels, fetched: fetched)
                        loadModelPreferences()
                    }
                }
            }
        }
    }
    
    // MARK: - Model Preferences Persistence
    
    func saveModelPreferences() {
        let prefs = Dictionary(availableModels.map { ($0.id, $0.isEnabled) }, uniquingKeysWith: { _, last in last })
        UserDefaults.standard.set(prefs, forKey: "modelPreferences")
    }
    
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

// MARK: - Saved Workspace

struct SavedWorkspace: Identifiable, Codable, Equatable {
    let id: UUID
    let path: String
    var lastUsed: Date

    init(id: UUID = UUID(), path: String, lastUsed: Date = Date()) {
        self.id = id
        self.path = path
        self.lastUsed = lastUsed
    }

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var displayPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
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
