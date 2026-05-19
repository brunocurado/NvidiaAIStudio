import Foundation

// MARK: - MCP Server Configuration

/// A configured MCP server the user wants to connect to.
struct MCPServerConfig: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var transport: Transport
    var isEnabled: Bool

    enum Transport: Codable, Equatable {
        /// Local process via stdio (e.g. npx @modelcontextprotocol/server-filesystem ~/projects)
        case stdio(command: String, args: [String], env: [String: String])
        /// Remote server via HTTP SSE
        case sse(url: String, headers: [String: String])
    }

    init(id: UUID = UUID(), name: String, transport: Transport, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.transport = transport
        self.isEnabled = isEnabled
    }

    /// Human-readable summary for display
    var summary: String {
        switch transport {
        case .stdio(let cmd, let args, _):
            return "\(cmd) \(args.joined(separator: " "))"
        case .sse(let url, _):
            return url
        }
    }
}

// MARK: - MCP Tool

/// A tool discovered from an MCP server.
struct MCPTool: Codable {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name, description, inputSchema = "inputSchema"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        // inputSchema is a freeform JSON object
        if let raw = try? c.decode(AnyDecodable.self, forKey: .inputSchema) {
            inputSchema = raw.value as? [String: Any] ?? [:]
        } else {
            inputSchema = ["type": "object", "properties": [:]]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
    }
}

// MARK: - MCP Skill (wraps an MCP tool as a native Skill)

/// Adapts a remote MCP tool into the app's Skill protocol.
/// The SkillRegistry treats it identically to built-in skills.
final class MCPSkill: Skill {
    let name: String
    let description: String
    let parameters: [String: Any]
    private weak var connection: MCPConnection?

    init(tool: MCPTool, connection: MCPConnection) {
        self.name = "mcp_\(connection.config.name)_\(tool.name)"
        self.description = "[\(connection.config.name)] \(tool.description)"
        self.parameters = tool.inputSchema
        self.connection = connection
    }

    func execute(arguments: String) async throws -> String {
        guard let connection else {
            throw SkillError.executionFailed("MCP server '\(name)' is not connected.")
        }
        // Extract the original tool name (strip "mcp_servername_" prefix)
        let parts = name.split(separator: "_", maxSplits: 2)
        let originalName = parts.count == 3 ? String(parts[2]) : name
        return try await connection.callTool(name: originalName, arguments: arguments)
    }
}

// MARK: - MCP Connection

/// Manages a single MCP server connection (stdio or SSE).
/// Handles the JSON-RPC 2.0 protocol, tool discovery, and tool invocation.
@Observable
final class MCPConnection: Identifiable {
    let id: UUID
    let config: MCPServerConfig
    var status: ConnectionStatus = .disconnected
    var discoveredTools: [MCPTool] = []
    var lastError: String? = nil

    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    // Stdio transport state
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var pendingRequests: [Int: CheckedContinuation<Any, Error>] = [:]
    private let pendingRequestsLock = NSLock()
    private var requestID = 0
    private var jsonBuffer = ""
    private var lineBuffer = Data()
    private let lineBufferLock = NSLock()

    // SSE transport state
    private var sseTask: Task<Void, Never>?

    init(config: MCPServerConfig) {
        self.id = config.id
        self.config = config
    }

    // MARK: - Connect

    func connect() async {
        await MainActor.run { status = .connecting; lastError = nil }
        do {
            switch config.transport {
            case .stdio: try await connectStdio()
            case .sse:   try await connectSSE()
            }
            try await initialize()
            let tools = try await listTools()
            await MainActor.run {
                discoveredTools = tools
                status = .connected
            }
        } catch {
            await MainActor.run {
                status = .failed(error.localizedDescription)
                if lastError == nil || !(lastError?.hasPrefix("RAW:") ?? false) {
                    lastError = error.localizedDescription
                }
            }
        }
    }

    func disconnect() {
        process?.terminate()
        process = nil
        sseTask?.cancel()
        sseTask = nil
        status = .disconnected
        discoveredTools = []
    }

    // MARK: - Stdio Transport

    private func connectStdio() async throws {
        guard case .stdio(let command, let args, let env) = config.transport else { return }

        let p = Process()
        let resolvedCmd = resolveCommand(command)
        p.executableURL = URL(fileURLWithPath: resolvedCmd)
        p.arguments = args

        // Build environment: inherit system env + inject nvm/node paths into PATH
        var environment = ProcessInfo.processInfo.environment
        let nodeBinDir = URL(fileURLWithPath: resolvedCmd).deletingLastPathComponent().path
        let existingPath = environment["PATH"] ?? "/usr/bin:/bin"
        environment["PATH"] = "\(nodeBinDir):/usr/local/bin:/opt/homebrew/bin:\(existingPath)"
        // Also set NODE_PATH for npx module resolution
        // Removed NODE_PATH override as it breaks global resolution in nvm
        for (k, v) in env { environment[k] = v }
        p.environment = environment

        // Set CWD to user's home directory so servers can write local DB files (e.g. Memory)
        p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe

        try p.run()

        self.process = p
        self.inputPipe = inPipe
        self.outputPipe = outPipe

        // Capture stderr for error diagnostics
        Task { [weak self] in
            do {
                for try await line in errPipe.fileHandleForReading.bytes.lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let strongSelf = self {
                        Task { @MainActor in 
                            if strongSelf.lastError == nil {
                                strongSelf.lastError = trimmed 
                            }
                        }
                    }
                }
            } catch {
                // Ignore errors from stderr stream
            }
        }

        // Start reading output via GCD readabilityHandler (more reliable than AsyncBytes for pipes)
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else {
                handle.readabilityHandler = nil
                return
            }
            self.lineBufferLock.withLock {
                self.lineBuffer.append(chunk)
            }
            // Process complete lines (under lock to prevent concurrent access)
            while true {
                let lineData: Data? = self.lineBufferLock.withLock {
                    guard let newlineRange = self.lineBuffer.range(of: Data([0x0A])) else { return nil }
                    let data = self.lineBuffer.subdata(in: self.lineBuffer.startIndex..<newlineRange.lowerBound)
                    self.lineBuffer.removeSubrange(self.lineBuffer.startIndex...newlineRange.lowerBound)
                    return data
                }
                guard let lineData else { break }
                if let lineStr = String(data: lineData, encoding: .utf8) {
                    let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { self.handleLine(trimmed) }
                }
            }
        }
    }

    private func resolveCommand(_ cmd: String) -> String {
        // If already an absolute path, use it directly
        if cmd.hasPrefix("/") {
            return cmd
        }
        // Otherwise search common locations for short names (npx, node, python, etc.)
        let userHome = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(userHome)/.nvm/versions/node/v22.21.1/bin/\(cmd)",
            "\(userHome)/.nvm/current/bin/\(cmd)",
            "/opt/homebrew/bin/\(cmd)",
            "/usr/local/bin/\(cmd)",
            "/usr/bin/\(cmd)",
            cmd
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? cmd
    }


    private func handleLine(_ line: String) {
        guard !line.isEmpty else { return }

        // Accumulate lines until we have a complete JSON object
        if line.starts(with: "{") && jsonBuffer.isEmpty {
            jsonBuffer = line
        } else if !jsonBuffer.isEmpty {
            jsonBuffer += "\n" + line
        } else {
            return // Non-JSON stderr noise, ignore
        }

        guard let data = jsonBuffer.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return // Incomplete JSON, wait for next chunk
        }

        jsonBuffer = ""

        var id = -1
        if let intId = json["id"] as? Int {
            id = intId
        } else if let strId = json["id"] as? String, let parsedId = Int(strId) {
            id = parsedId
        }

        let continuation = pendingRequestsLock.withLock {
            pendingRequests.removeValue(forKey: id)
        }

        if let continuation = continuation {
            if let error = json["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "MCP error"
                continuation.resume(throwing: SkillError.executionFailed(msg))
            } else {
                continuation.resume(returning: json["result"] ?? [:])
            }
        }
    }

    // MARK: - SSE Transport

    private func connectSSE() async throws {
        guard case .sse(let urlString, let headers) = config.transport,
              let url = URL(string: urlString) else {
            throw SkillError.executionFailed("Invalid SSE URL")
        }
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // SSE connection is maintained — for now we just verify it's reachable
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SkillError.executionFailed("SSE server returned non-200")
        }
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: [String: Any] = [:]) async throws -> Any {
        requestID += 1
        let id = requestID
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        
        let data = try JSONSerialization.data(withJSONObject: message)
        guard let line = String(data: data, encoding: .utf8) else {
            throw SkillError.executionFailed("Failed to encode request")
        }

        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { cont in
                pendingRequestsLock.withLock {
                    pendingRequests[id] = cont
                }
                
                let payload = (line + "\n").data(using: .utf8)!
                inputPipe?.fileHandleForWriting.write(payload)
                // Timeout after 120s (npx may need time to download on first run)
                Task {
                    try? await Task.sleep(for: .seconds(120))
                    
                    let removed = pendingRequestsLock.withLock {
                        self.pendingRequests.removeValue(forKey: id)
                    }
                    
                    if let cont = removed {
                        cont.resume(throwing: SkillError.executionFailed("MCP request timed out"))
                    }
                }
            }
        } onCancel: {
            let removed = pendingRequestsLock.withLock {
                self.pendingRequests.removeValue(forKey: id)
            }
            if let cont = removed {
                cont.resume(throwing: CancellationError())
            }
        }
    }

    private func initialize() async throws {
        _ = try await sendRequest(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "clientInfo": ["name": "NvidiaAIStudio", "version": "2.0.0"]
        ])
        let notifMsg: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:]]
        let notifData = try! JSONSerialization.data(withJSONObject: notifMsg)
        if let line = String(data: notifData, encoding: .utf8) {
            inputPipe?.fileHandleForWriting.write((line + "\n").data(using: .utf8)!)
        }
    }

    // MARK: - Tools

    func listTools() async throws -> [MCPTool] {
        let result = try await sendRequest(method: "tools/list")
        guard let dict = result as? [String: Any],
              let toolsArray = dict["tools"] as? [[String: Any]] else { return [] }
        let data = try JSONSerialization.data(withJSONObject: toolsArray)
        return (try? JSONDecoder().decode([MCPTool].self, from: data)) ?? []
    }

    func callTool(name: String, arguments: String) async throws -> String {
        var args = (try? JSONSerialization.jsonObject(with: arguments.data(using: .utf8) ?? Data())) as? [String: Any] ?? [:]
        
        // Auto-fix common LLM hallucinated arguments for standard MCP file tools
        if name == "read_file" || name == "write_file" || name == "edit_file" {
            if args["path"] == nil {
                if let fp = args["file_path"] { args["path"] = fp }
                else if let fp = args["filename"] { args["path"] = fp }
                else if let fp = args["file"] { args["path"] = fp }
                else if let fp = args["raw_input"] { args["path"] = fp }
            }
        }
        
        let result = try await sendRequest(method: "tools/call", params: [
            "name": name,
            "arguments": args
        ])
        guard let dict = result as? [String: Any] else { return String(describing: result) }
        // MCP tool result can be text content array or a direct value
        if let content = dict["content"] as? [[String: Any]] {
            return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return String(describing: dict)
    }
}

// MARK: - MCP Manager

/// Manages all MCP server connections and syncs their tools into SkillRegistry.
@Observable
final class MCPManager {
    static let shared = MCPManager()

    var connections: [MCPConnection] = []
    var serverConfigs: [MCPServerConfig] = []

    private init() {
        loadConfigs()
    }

    // MARK: - Config persistence

    func loadConfigs() {
        guard let data = UserDefaults.standard.data(forKey: "mcpServers"),
              let configs = try? JSONDecoder().decode([MCPServerConfig].self, from: data)
        else { return }
        serverConfigs = configs
    }

    func saveConfigs() {
        if let data = try? JSONEncoder().encode(serverConfigs) {
            UserDefaults.standard.set(data, forKey: "mcpServers")
        }
    }

    func addServer(_ config: MCPServerConfig) {
        serverConfigs.append(config)
        saveConfigs()
        if config.isEnabled { Task { await connectServer(config) } }
    }

    @MainActor
    func updateServer(_ config: MCPServerConfig) {
        if let idx = serverConfigs.firstIndex(where: { $0.id == config.id }) {
            let wasEnabled = serverConfigs[idx].isEnabled
            serverConfigs[idx] = config
            saveConfigs()
            
            // Reconnect if it was enabled
            if wasEnabled || config.isEnabled {
                connections.first { $0.id == config.id }?.disconnect()
                connections.removeAll { $0.id == config.id }
                if config.isEnabled {
                    Task { await connectServer(config) }
                } else {
                    syncSkills()
                }
            }
        }
    }

    @MainActor
    func removeServer(id: UUID) {
        connections.first { $0.id == id }?.disconnect()
        connections.removeAll { $0.id == id }
        serverConfigs.removeAll { $0.id == id }
        saveConfigs()
        syncSkills()
    }

    @MainActor
    func toggleServer(id: UUID, enabled: Bool) {
        if let idx = serverConfigs.firstIndex(where: { $0.id == id }) {
            serverConfigs[idx].isEnabled = enabled
            saveConfigs()
        }
        if enabled {
            if let config = serverConfigs.first(where: { $0.id == id }) {
                Task { await connectServer(config) }
            }
        } else {
            connections.first { $0.id == id }?.disconnect()
            connections.removeAll { $0.id == id }
            syncSkills()
        }
    }

    // MARK: - Connection lifecycle

    func connectAll() {
        for config in serverConfigs where config.isEnabled {
            Task { @MainActor in await connectServer(config) }
        }
    }

    private func connectServer(_ config: MCPServerConfig) async {
        // Don't double-connect
        if connections.contains(where: { $0.id == config.id }) { return }
        let conn = MCPConnection(config: config)
        await MainActor.run { connections.append(conn) }
        await conn.connect()
        await MainActor.run { syncSkills() }
    }

    // MARK: - Skill sync

    /// Registers all discovered MCP tools into the global SkillRegistry.
    /// MUST run on MainActor to prevent data races on SkillRegistry's dictionary.
    @MainActor
    func syncSkills() {
        let registry = SkillRegistry.shared
        // Remove old MCP skills
        let mcpSkills = registry.allSkills.filter { $0.name.hasPrefix("mcp_") }
        for skill in mcpSkills {
            registry.unregister(skill.name)
        }
        // Add current MCP skills
        for conn in connections where conn.status == .connected {
            for tool in conn.discoveredTools {
                registry.register(MCPSkill(tool: tool, connection: conn))
            }
        }
    }

    var totalToolCount: Int {
        connections.reduce(0) { $0 + $1.discoveredTools.count }
    }
}

// MARK: - AnyDecodable helper

private struct AnyDecodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { value = v }
        else if let v = try? c.decode(Int.self)    { value = v }
        else if let v = try? c.decode(Double.self) { value = v }
        else if let v = try? c.decode(String.self) { value = v }
        else if let v = try? c.decode([String: AnyDecodable].self) {
            value = v.mapValues { $0.value }
        } else if let v = try? c.decode([AnyDecodable].self) {
            value = v.map { $0.value }
        } else { value = "" }
    }
}
