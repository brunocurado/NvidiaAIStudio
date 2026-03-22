import Foundation

/// Protocol defining a skill that the AI agent can invoke via tool calls.
protocol Skill {
    /// Unique name matching the function name in the API tool call.
    var name: String { get }
    
    /// Human-readable description for the AI model.
    var description: String { get }
    
    /// JSON Schema for the tool's parameters.
    var parameters: [String: Any] { get }
    
    /// Execute the skill with the given JSON arguments string.
    func execute(arguments: String) async throws -> String
}

extension Skill {
    /// Converts this skill into the OpenAI-compatible tool definition format.
    var toolDefinition: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters,
            ] as [String: Any]
        ]
    }
}

/// Central registry that manages all available skills and dispatches tool calls.
@Observable
final class SkillRegistry {
    static let shared = SkillRegistry()
    
    private var skills: [String: any Skill] = [:]
    private var disabledSkills: Set<String> = []
    
    /// All registered skill names.
    var registeredSkills: [String] { Array(skills.keys).sorted() }
    
    /// All registered skills (including disabled).
    var allSkills: [any Skill] { Array(skills.values) }
    
    init() {
        // Register default skills
        register(ReadFileSkill())
        register(WriteFileSkill())
        register(ListDirectorySkill())
        register(SearchFilesSkill())
        register(RunCommandSkill())
        register(ImageGenerationSkill())
        register(GitSkill())
        register(SSHSkill())
        
        // Load saved disabled states
        if let saved = UserDefaults.standard.dictionary(forKey: "skillStates") as? [String: Bool] {
            for (name, enabled) in saved where !enabled {
                disabledSkills.insert(name)
            }
        }
    }
    
    /// Register a skill.
    func register(_ skill: any Skill) {
        skills[skill.name] = skill
    }

    /// Unregister a skill by name.
    func unregister(_ name: String) {
        skills.removeValue(forKey: name)
        disabledSkills.remove(name)
    }
    
    /// Disable a skill (won't appear in tool definitions).
    func disable(_ name: String) {
        disabledSkills.insert(name)
    }
    
    /// Enable a previously disabled skill.
    func enable(_ name: String) {
        disabledSkills.remove(name)
    }
    
    /// Check if a skill is enabled.
    func isEnabled(_ name: String) -> Bool {
        !disabledSkills.contains(name)
    }
    
    /// Get enabled tools as OpenAI-compatible tool definitions.
    var toolDefinitions: [[String: Any]] {
        skills.values
            .filter { !disabledSkills.contains($0.name) }
            .map { $0.toolDefinition }
    }
    
    /// Execute a tool call by name with the given arguments.
    /// accessLevel and workspacePath enforce Sandboxed mode restrictions.
    func execute(
        name: String,
        arguments: String,
        accessLevel: FileAccessLevel = .fullAccess,
        workspacePath: String = ""
    ) async throws -> String {
        guard let skill = skills[name] else {
            throw SkillError.unknownSkill(name)
        }
        if disabledSkills.contains(name) {
            throw SkillError.executionFailed("Skill '\(name)' is currently disabled. Enable it in the Skills panel.")
        }
        
        // Sandboxed enforcement: inject restrictions before execution
        if accessLevel == .sandboxed {
            let sanitized = try sandboxedArguments(
                skillName: name,
                arguments: arguments,
                workspacePath: workspacePath
            )
            return try await skill.execute(arguments: sanitized)
        }
        
        return try await skill.execute(arguments: arguments)
    }
    
    // MARK: - Sandbox Enforcement
    
    /// Validates and rewrites arguments for Sandboxed mode.
    /// - File skills: rejects paths outside the workspace
    /// - run_command: forces working_directory to workspace
    /// - ssh_command, image_generation: allowed (not filesystem ops)
    /// - git: allowed only within workspace
    private func sandboxedArguments(
        skillName: String,
        arguments: String,
        workspacePath: String
    ) throws -> String {
        guard !workspacePath.isEmpty else {
            throw SkillError.permissionDenied(
                "Sandboxed mode requires an active workspace. Use 'Open Workspace' in the sidebar first."
            )
        }
        
        let workspace = (workspacePath as NSString).expandingTildeInPath
        var args = try SkillArgs.parse(arguments)
        
        switch skillName {
            
        case "read_file", "write_file":
            guard let rawPath = args["path"] as? String else { break }
            let expanded = (rawPath as NSString).expandingTildeInPath
            guard expanded.hasPrefix(workspace) else {
                throw SkillError.permissionDenied(
                    "\u{1F512} Sandboxed: '\(rawPath)' is outside the workspace '\(workspace)'.\n" +
                    "Switch to Full Access or open the correct workspace."
                )
            }
            
        case "list_directory":
            guard let rawPath = args["path"] as? String else { break }
            let expanded = (rawPath as NSString).expandingTildeInPath
            guard expanded.hasPrefix(workspace) else {
                throw SkillError.permissionDenied(
                    "\u{1F512} Sandboxed: '\(rawPath)' is outside the workspace '\(workspace)'.\n" +
                    "Switch to Full Access or open the correct workspace."
                )
            }
            
        case "search_files":
            guard let rawPath = args["path"] as? String else { break }
            let expanded = (rawPath as NSString).expandingTildeInPath
            guard expanded.hasPrefix(workspace) else {
                throw SkillError.permissionDenied(
                    "\u{1F512} Sandboxed: search path '\(rawPath)' is outside the workspace '\(workspace)'."
                )
            }
            
        case "run_command":
            // Force working_directory to workspace — command itself is allowed
            args["working_directory"] = workspace
            return (try? String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)) ?? arguments
            
        case "git":
            // Force working_directory to workspace if not set or outside
            if let rawDir = args["working_directory"] as? String {
                let expanded = (rawDir as NSString).expandingTildeInPath
                if !expanded.hasPrefix(workspace) {
                    throw SkillError.permissionDenied(
                        "\u{1F512} Sandboxed: git working directory '\(rawDir)' is outside workspace."
                    )
                }
            } else {
                args["working_directory"] = workspace
                return (try? String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)) ?? arguments
            }
            
        default:
            // ssh_command, image_generation, etc. — not filesystem ops, allow freely
            break
        }
        
        return arguments // unchanged for allowed paths
    }
}

// MARK: - Errors

enum SkillError: LocalizedError {
    case unknownSkill(String)
    case invalidArguments(String)
    case fileNotFound(String)
    case permissionDenied(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unknownSkill(let name): return "Unknown skill: \(name)"
        case .invalidArguments(let msg): return "Invalid arguments: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .permissionDenied(let path): return "Permission denied: \(path)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        }
    }
}

// MARK: - Argument Parsing Helper

/// Parses JSON argument strings from tool calls.
enum SkillArgs {
    static func parse(_ arguments: String) throws -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillError.invalidArguments("Could not parse JSON: \(arguments)")
        }
        return json
    }
    
    static func getString(_ args: [String: Any], key: String) throws -> String {
        guard let value = args[key] as? String else {
            throw SkillError.invalidArguments("Missing required string parameter: \(key)")
        }
        return value
    }
    
    static func getOptionalString(_ args: [String: Any], key: String) -> String? {
        args[key] as? String
    }
    
    static func getInt(_ args: [String: Any], key: String, defaultValue: Int) -> Int {
        args[key] as? Int ?? defaultValue
    }
    
    static func getBool(_ args: [String: Any], key: String, defaultValue: Bool) -> Bool {
        args[key] as? Bool ?? defaultValue
    }
}
