import Foundation

/// Protocol defining a skill that the AI agent can invoke via tool calls.
protocol Skill {
    var name: String { get }
    var description: String { get }
    var parameters: [String: Any] { get }
    func execute(arguments: String) async throws -> String
}

extension Skill {
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

@Observable
final class SkillRegistry {
    static let shared = SkillRegistry()
    
    private var skills: [String: any Skill] = [:]
    private var disabledSkills: Set<String> = []
    
    var registeredSkills: [String] { Array(skills.keys).sorted() }
    var allSkills: [any Skill] { Array(skills.values) }
    
    init() {
        register(ReadFileSkill())
        register(WriteFileSkill())
        register(ListDirectorySkill())
        register(SearchFilesSkill())
        register(RunCommandSkill())
        register(ImageGenerationSkill())
        register(GitSkill())
        register(SSHSkill())
        register(FetchURLSkill())
        register(FetchImagesSkill())
        register(WebSearchSkill())
        
        if let saved = UserDefaults.standard.dictionary(forKey: "skillStates") as? [String: Bool] {
            for (name, enabled) in saved where !enabled {
                disabledSkills.insert(name)
            }
        }
    }
    
    func register(_ skill: any Skill) { skills[skill.name] = skill }
    func unregister(_ name: String) { skills.removeValue(forKey: name); disabledSkills.remove(name) }
    func disable(_ name: String) { disabledSkills.insert(name) }
    func enable(_ name: String) { disabledSkills.remove(name) }
    func isEnabled(_ name: String) -> Bool { !disabledSkills.contains(name) }
    
    var toolDefinitions: [[String: Any]] {
        skills.values
            .filter { !disabledSkills.contains($0.name) }
            .map { $0.toolDefinition }
    }
    
    func execute(
        name: String,
        arguments: String,
        accessLevel: FileAccessLevel = .fullAccess,
        workspacePath: String = ""
    ) async throws -> String {
        guard let skill = skills[name] else { throw SkillError.unknownSkill(name) }
        if disabledSkills.contains(name) {
            throw SkillError.executionFailed("Skill '\(name)' is currently disabled.")
        }
        if accessLevel == .sandboxed {
            let sanitized = try sandboxedArguments(skillName: name, arguments: arguments, workspacePath: workspacePath)
            return try await skill.execute(arguments: sanitized)
        }
        return try await skill.execute(arguments: arguments)
    }
    
    private func sandboxedArguments(skillName: String, arguments: String, workspacePath: String) throws -> String {
        guard !workspacePath.isEmpty else {
            throw SkillError.permissionDenied("Sandboxed mode requires an active workspace.")
        }
        let workspace = (workspacePath as NSString).expandingTildeInPath
        var args = try SkillArgs.parse(arguments)
        switch skillName {
        case "read_file", "write_file", "list_directory", "search_files":
            guard let rawPath = args["path"] as? String else { break }
            let expanded = (rawPath as NSString).expandingTildeInPath
            guard expanded.hasPrefix(workspace) else {
                throw SkillError.permissionDenied("\u{1F512} Sandboxed: '\(rawPath)' is outside the workspace.")
            }
        case "run_command":
            args["working_directory"] = workspace
            return (try? String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)) ?? arguments
        case "git":
            if let rawDir = args["working_directory"] as? String {
                let expanded = (rawDir as NSString).expandingTildeInPath
                if !expanded.hasPrefix(workspace) {
                    throw SkillError.permissionDenied("\u{1F512} Sandboxed: git directory outside workspace.")
                }
            } else {
                args["working_directory"] = workspace
                return (try? String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)) ?? arguments
            }
        default: break
        }
        return arguments
    }
}

enum SkillError: LocalizedError {
    case unknownSkill(String)
    case invalidArguments(String)
    case fileNotFound(String)
    case permissionDenied(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .unknownSkill(let n):      return "Unknown skill: \(n)"
        case .invalidArguments(let m):  return "Invalid arguments: \(m)"
        case .fileNotFound(let p):      return "File not found: \(p)"
        case .permissionDenied(let p):  return "Permission denied: \(p)"
        case .executionFailed(let m):   return "Execution failed: \(m)"
        }
    }
}

enum SkillArgs {
    static func parse(_ arguments: String) throws -> [String: Any] {
        let trimmed = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Standard parse
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        
        // Fallback 1: Fix unescaped control characters in JSON string values.
        // Models often produce {"content": "line1\nline2"} with literal newlines
        // instead of escaped \\n, which breaks JSON parsing.
        if let fixed = fixUnescapedControlChars(trimmed),
           let data = fixed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        
        // Fallback 2: Single quotes → double quotes (common model mistake)
        let singleToDouble = trimmed.replacingOccurrences(of: "'", with: "\"")
        if let data = singleToDouble.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        
        // Fallback 3: Extract key-value pairs from partially valid JSON.
        // Handles cases like: {"path": "/some/file.md", "content": "...broken markdown..."}
        // by extracting the path and treating everything after "content": as the content value.
        if let extracted = extractWriteFileArgs(trimmed) {
            return extracted
        }
        
        // Fallback 4: Model sent a JSON-encoded string
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""),
           let inner = try? JSONSerialization.jsonObject(with: trimmed.data(using: .utf8)!) as? String,
           let data = inner.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        
        // Fallback 5: Model sent a plain string like "ls" — wrap as {"command":"..."}
        let bare = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if !bare.contains("{") && !bare.contains(":") && !bare.isEmpty {
            return ["command": bare]
        }
        
        throw SkillError.invalidArguments("Could not parse JSON: \(String(arguments.prefix(200)))")
    }
    
    /// Fix unescaped control characters (newlines, tabs) inside JSON string values.
    private static func fixUnescapedControlChars(_ json: String) -> String? {
        var result = ""
        var inString = false
        var prevChar: Character = "\0"
        
        for char in json {
            if char == "\"" && prevChar != "\\" {
                inString.toggle()
                result.append(char)
            } else if inString {
                switch char {
                case "\n": result.append("\\n")
                case "\r": result.append("\\r")
                case "\t": result.append("\\t")
                default: result.append(char)
                }
            } else {
                result.append(char)
            }
            prevChar = char
        }
        
        // Only return if we actually changed something
        return result != json ? result : nil
    }
    
    /// Extract path and content from a malformed write_file JSON.
    /// Uses regex to find "path": "..." and treats everything after "content": " as content.
    private static func extractWriteFileArgs(_ raw: String) -> [String: Any]? {
        // Must look like a write_file call with "path" and "content"
        guard raw.contains("\"path\"") && raw.contains("\"content\"") else { return nil }
        
        // Extract path value
        guard let pathMatch = raw.range(of: "\"path\"\\s*:\\s*\"([^\"]+)\"", options: .regularExpression),
              let pathValueRange = raw[pathMatch].range(of: "\"([^\"]+)\"\\s*$", options: .regularExpression) else {
            return nil
        }
        let pathValue = String(raw[pathValueRange]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        
        // Extract content: everything between "content": " and the last " (or end)
        guard let contentKeyRange = raw.range(of: "\"content\"\\s*:\\s*\"", options: .regularExpression) else {
            return nil
        }
        var contentStart = contentKeyRange.upperBound
        // Skip past the opening quote
        if contentStart < raw.endIndex {
            var content = String(raw[contentStart...])
            // Strip trailing "} or similar
            if content.hasSuffix("\"}") {
                content = String(content.dropLast(2))
            } else if content.hasSuffix("\"") {
                content = String(content.dropLast(1))
            }
            // Unescape the content
            content = content
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
            
            return ["path": pathValue, "content": content]
        }
        
        return nil
    }
    
    static func getString(_ args: [String: Any], key: String) throws -> String {
        guard let value = args[key] as? String else {
            throw SkillError.invalidArguments("Missing required string parameter: \(key)")
        }
        return value
    }
    static func getOptionalString(_ args: [String: Any], key: String) -> String? { args[key] as? String }
    static func getInt(_ args: [String: Any], key: String, defaultValue: Int) -> Int { args[key] as? Int ?? defaultValue }
    static func getBool(_ args: [String: Any], key: String, defaultValue: Bool) -> Bool { args[key] as? Bool ?? defaultValue }
}
