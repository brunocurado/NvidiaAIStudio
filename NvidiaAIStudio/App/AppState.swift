import SwiftUI
import SwiftData

/// Global application state shared across the app via @Environment.
@Observable
final class AppState {
    // MARK: - Persistence
    let modelContainer: ModelContainer
    private let sessionStore: SwiftDataStore
    
    // MARK: - Swarm Engine
    let orchestrator: SwarmOrchestrator
    
    // MARK: - Knowledge Base
    let knowledgeManager = KnowledgeManager.shared
    
    // MARK: - Sessions
    var sessions: [Session] = []
    var activeSessionID: UUID? = nil
    
    init() {
        let schema = Schema([
            // Chat persistence (existing)
            SDSession.self, SDMessage.self, SDAttachment.self,
            SDToolCall.self, SDStatusBadge.self, SDBackgroundAgent.self,
            // Swarm architecture (Phase 1.2)
            AgentPersona.self, SwarmTask.self,
            SwarmMessage.self, SwarmDeliverable.self
        ])

        func makeContainer() throws -> ModelContainer {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        }

        let container: ModelContainer
        do {
            container = try makeContainer()
        } catch {
            // Schema changes can make SwiftData refuse to open the store. Keep a
            // backup before recreating so chat and swarm data is not silently lost.
            print("⚠️ SwiftData store failed to open — backing up and recreating: \(error)")
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeDir = appSupport
            let storeFiles = (try? FileManager.default.contentsOfDirectory(at: storeDir, includingPropertiesForKeys: nil)) ?? []
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupDir = appSupport.appendingPathComponent("NvidiaAIStudio-store-backup-\(stamp)", isDirectory: true)
            try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for file in storeFiles where file.lastPathComponent.hasPrefix("default") || file.lastPathComponent.hasPrefix("NvidiaAIStudio") {
                let destination = backupDir.appendingPathComponent(file.lastPathComponent)
                try? FileManager.default.copyItem(at: file, to: destination)
                try? FileManager.default.removeItem(at: file)
            }
            do {
                container = try makeContainer()
                print("✅ SwiftData store recreated. Backup kept at \(backupDir.path)")
            } catch {
                fatalError("Failed to initialize SwiftData container even after wiping store: \(error)")
            }
        }

        self.modelContainer = container
        self.sessionStore = SwiftDataStore(modelContainer: container)
        self.orchestrator = SwarmOrchestrator(modelContainer: container)
    }

    
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
        let allDefaults = AIModel.defaultModels + AIModel.anthropicModels + AIModel.openAIModels + AIModel.openRouterModels
        return allDefaults.filter { seen.insert($0.id).inserted }
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
        availableModels.filter { $0.provider == activeProvider }
    }

    func switchProvider(_ newProvider: Provider) {
        activeProvider = newProvider
        if let first = modelsForActiveProvider.first {
            selectedModelID = first.id
        }
        
        if let apiKey = activeAPIKey {
            Task {
                let customBaseURL = apiKeys.first { $0.provider == activeProvider && $0.isActive }?.customBaseURL
                let baseURL = customBaseURL ?? activeProvider.baseURL
                if let fetched = await ModelFetcher.fetchModels(apiKey: apiKey, baseURL: baseURL, provider: activeProvider) {
                    await MainActor.run {
                        availableModels = ModelFetcher.mergeModels(existing: availableModels, fetched: fetched)
                    }
                }
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
    var appMode: AppMode = .chat
    var isSidebarVisible = true
    var isRightPanelVisible = false
    var rightPanelMode: RightPanelMode = .diff
    var activeCanvasURL: URL? = nil
    var reasoningLevel: ReasoningLevel = .low
    var fileAccessLevel: FileAccessLevel = .fullAccess
    var currentBranch: String = "main"
    var availableBranches: [String] = []
    
    func refreshGitBranch() {
        let path = activeWorkspacePath
        Task {
            let result = await ShellHelper.runExecutable("git", arguments: ["branch", "--show-current"], workingDirectory: path)
            let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let branchesResult = await ShellHelper.runExecutable("git", arguments: ["branch"], workingDirectory: path)
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
            let result = await ShellHelper.runExecutable("git", arguments: ["checkout", branch], workingDirectory: path)
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
    
    // Debounce mechanism for saveActiveSession to prevent SwiftData merge conflicts
    // during rapid streaming updates. Saves are coalesced within a 500ms window.
    private var pendingSaveTask: Task<Void, Never>?
    private var lastSaveTime: Date = .distantPast
    private let saveDebounceInterval: TimeInterval = 0.5

    func saveActiveSession() {
        guard let session = activeSession else { return }

        // Cancel any pending save — we'll schedule a new one
        pendingSaveTask?.cancel()

        pendingSaveTask = Task { [weak self] in
            guard let self else { return }

            // Wait for the debounce interval to coalesce rapid saves
            try? await Task.sleep(for: .seconds(self.saveDebounceInterval))

            // Check if cancelled during sleep
            if Task.isCancelled { return }

            // Throttle: don't save more than once per interval
            let now = Date()
            if now.timeIntervalSince(self.lastSaveTime) < self.saveDebounceInterval {
                // Still too soon — reschedule
                self.saveActiveSession()
                return
            }

            self.lastSaveTime = now
            await self.sessionStore.save(session)
        }
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
        KeychainHelper.migrateIfNeeded()  // one-time migration to AfterFirstUnlock
        loadSessions()
        loadGitHubCredentials()
        loadAPIKeys()
        AppNotifications.requestPermission()
        MCPManager.shared.connectAll()
        
        // Start the Swarm Orchestrator polling loop
        orchestrator.configure(appState: self)
        orchestrator.start()
        
        // Seed standard Swarm agents if DB is empty
        seedDefaultAgents()

        if apiKeys.isEmpty, let envKey = EnvParser.loadNVIDIAKey() {
            let key = APIKey(provider: .nvidia, name: "NVIDIA (from .env)", key: envKey)
            apiKeys.append(key)
            saveAPIKeys()
        }
        
        loadModelPreferences()
        
        if let apiKey = activeAPIKey {
            Task {
                let customBaseURL = apiKeys.first { $0.provider == activeProvider && $0.isActive }?.customBaseURL
                let baseURL = customBaseURL ?? activeProvider.baseURL
                if let fetched = await ModelFetcher.fetchModels(apiKey: apiKey, baseURL: baseURL, provider: activeProvider) {
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
        
        let customContexts = Dictionary(availableModels.map { ($0.id, $0.contextWindow) }, uniquingKeysWith: { _, last in last })
        UserDefaults.standard.set(customContexts, forKey: "customModelContextWindows")
    }
    
    func loadModelPreferences() {
        let prefs = UserDefaults.standard.dictionary(forKey: "modelPreferences") as? [String: Bool]
        let customContexts = UserDefaults.standard.dictionary(forKey: "customModelContextWindows") as? [String: Int]
        
        for i in availableModels.indices {
            let modelId = availableModels[i].id
            if let saved = prefs?[modelId] {
                availableModels[i].isEnabled = saved
            }
            if let customContext = customContexts?[modelId] {
                availableModels[i].contextWindow = customContext
            }
        }
    }
    
    // MARK: - Swarm Seeding
    
    private func seedDefaultAgents() {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<AgentPersona>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        
        // Only seed if empty
        guard count == 0 else { return }
        
        let defaultAgents = [
            // DESIGN & UI/UX
            AgentPersona(
                name: "Jony",
                roleName: "Lead UI/UX Designer",
                systemPrompt: "You are a Lead UI/UX Designer obsessed with the Apple design ethos. You prioritize stunning aesthetics, glassmorphism, micro-animations, and pixel-perfect typography. Every interface you design must feel premium, responsive, and delightful.",
                accentColorHex: "#E91E63" // Pink
            ),
            AgentPersona(
                name: "Dieter",
                roleName: "Industrial & 3D Designer",
                systemPrompt: "You are an Industrial Designer focused on functionalism ('Less, but better'). You design 3D components, physical-digital bridges, and highly practical, intuitive user experiences.",
                accentColorHex: "#880E4F" // Dark Pink
            ),
            
            // ENGINEERING & ARCHITECTURE
            AgentPersona(
                name: "Ada",
                roleName: "Chief Architect (Software)",
                systemPrompt: "You are the Chief Software Architect. You break down complex requirements into robust, scalable system designs. Before writing code, you plan data structures, component boundaries, and security models.",
                accentColorHex: "#9C27B0" // Purple
            ),
            AgentPersona(
                name: "Alan",
                roleName: "Senior Full-Stack Developer",
                systemPrompt: "You are a Senior Full-Stack Developer. You write clean, performant, and well-documented Swift, Python, and React code. You prioritize best practices, modularity, and readable logic.",
                accentColorHex: "#2196F3" // Blue
            ),
            AgentPersona(
                name: "Linus",
                roleName: "Head of DevOps",
                systemPrompt: "You are a DevOps and Infrastructure Engineer. You specialize in CI/CD pipelines, containerization (Docker/K8s), deployment automation, and Linux server management.",
                accentColorHex: "#3F51B5" // Indigo
            ),
            AgentPersona(
                name: "Margaret",
                roleName: "Data Engineer",
                systemPrompt: "You are a Data Engineer. You build highly scalable data pipelines, optimize massive SQL queries, and manage vector databases for LLM retrieval and fast analytics.",
                accentColorHex: "#00BCD4" // Cyan
            ),
            AgentPersona(
                name: "Kevin",
                roleName: "Cybersecurity Analyst",
                systemPrompt: "You are a Cybersecurity Expert. You perform penetration testing, analyze code for vulnerabilities (XSS, SQLi, Auth bypass), and enforce zero-trust security architectures.",
                accentColorHex: "#607D8B" // BlueGrey
            ),
            
            // QUALITY ASSURANCE
            AgentPersona(
                name: "Grace",
                roleName: "QA Automation Lead",
                systemPrompt: "You are the QA Automation Engineer. You write comprehensive unit and end-to-end tests. You hunt for edge cases, memory leaks, and race conditions before any code is approved.",
                accentColorHex: "#4CAF50" // Green
            ),
            AgentPersona(
                name: "Miranda",
                roleName: "Brand QC & Editor",
                systemPrompt: "You are the Quality Check (QC) and Editor-In-Chief. You evaluate marketing copy, UI text, and deliverables for brand consistency, perfect grammar, and the right tone of voice.",
                accentColorHex: "#F44336" // Red
            ),
            
            // MARKETING & GROWTH
            AgentPersona(
                name: "Don",
                roleName: "Chief Marketer",
                systemPrompt: "You are a Chief Marketing Strategist. Your goal is to write highly converting, engaging, and persuasive copy. You focus on SEO, growth hacking, and deep psychological triggers.",
                accentColorHex: "#FF5722" // DeepOrange
            ),
            AgentPersona(
                name: "Sheryl",
                roleName: "Growth Operations",
                systemPrompt: "You are the Head of Growth Operations. You analyze user funnels, coordinate affiliate networks, optimize monetization metrics (CAC/LTV), and design viral loops.",
                accentColorHex: "#FF9800" // Orange
            ),
            AgentPersona(
                name: "Leo",
                roleName: "Social Media Strategist",
                systemPrompt: "You are a Social Media Native. You craft viral Twitter threads, TikTok scripts, and high-engagement LinkedIn posts. You know exactly what algorithms reward natively.",
                accentColorHex: "#FFC107" // Amber
            ),
            
            // RESEARCH & DATA
            AgentPersona(
                name: "Marie",
                roleName: "Research Scientist",
                systemPrompt: "You are a Research Scientist. You excel at taking a vague topic, conducting deep analysis, comparing differing methods, and synthesizing a comprehensive factual report.",
                accentColorHex: "#009688" // Teal
            ),
            AgentPersona(
                name: "Carl",
                roleName: "Astrophysicist & Quantum Analyst",
                systemPrompt: "You are a theoretical analyst. You apply physics and mathematics principles to solve extremely complex, non-standard logic problems and hardware optimizations.",
                accentColorHex: "#1A237E" // Deep Blue
            ),
            
            // LEGAL & FINANCE
            AgentPersona(
                name: "Harvey",
                roleName: "Corporate Counsel",
                systemPrompt: "You are a Corporate Lawyer. You draft terms of service, review NDAs, ensure GDPR compliance, and analyze software licenses (MIT vs GPL) for risk.",
                accentColorHex: "#795548" // Brown
            ),
            AgentPersona(
                name: "Warren",
                roleName: "CFO & Financial Analyst",
                systemPrompt: "You are the Chief Financial Officer. You calculate burn rates, build revenue projections, optimize subscription pricing models, and handle API token budgeting.",
                accentColorHex: "#8BC34A" // LightGreen
            ),
            
            // SPECIAL OPERATIONS
            AgentPersona(
                name: "Sun",
                roleName: "Competitive Strategist",
                systemPrompt: "You are a Competitive Strategist (inspired by Sun Tzu). You analyze competitor software, find their weak points, and advise the CEO on market positioning and tactical attacks.",
                accentColorHex: "#D32F2F" // Dark Red
            ),
            AgentPersona(
                name: "Lex",
                roleName: "SEO Specialist",
                systemPrompt: "You are a hardcore SEO Specialist. You generate keyword matrices, backlink strategies, and meta-tag structures to dominate Google Search rankings.",
                accentColorHex: "#00E676" // Neon Green
            ),
            AgentPersona(
                name: "Steve",
                roleName: "Product Visionary",
                systemPrompt: "You are the Product Visionary. You tell other agents to simplify. You cut unnecessary features. You demand magic. You ensure the final product is not just working, but revolutionary.",
                accentColorHex: "#000000" // Black
            ),
            AgentPersona(
                name: "Hermes",
                roleName: "Logistics Router",
                systemPrompt: "You are the Logistics API Integrator. You specialize in connecting multiple third-party systems (Stripe, Twilio, SendGrid) and mapping complex JSON endpoints reliably.",
                accentColorHex: "#9E9E9E" // Grey
            )
        ]
        
        for agent in defaultAgents {
            context.insert(agent)
        }
        
        do {
            try context.save()
            print("✅ Default agents seeded into Swarm Data Store")
        } catch {
            print("❌ Failed to seed default agents: \(error)")
        }
    }
}

// MARK: - Supporting Enums

enum AppMode: String, CaseIterable {
    case chat = "Chat"
    case warRoom = "War Room"
    
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right.fill"
        case .warRoom: return "shield.lefthalf.filled"
        }
    }
}

enum RightPanelMode: String, CaseIterable {
    case diff = "Diff"
    case terminal = "Terminal"
    case canvas = "Live Canvas"
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
