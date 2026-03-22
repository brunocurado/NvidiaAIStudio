import Foundation

// MARK: - Read File

struct ReadFileSkill: Skill {
    let name = "read_file"
    let description = "Read the contents of a file at the specified path. Returns the file's text content."
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Absolute path to the file to read"
                ] as [String: Any],
                "start_line": [
                    "type": "integer",
                    "description": "Optional: first line to read (1-indexed). Omit to read from the beginning."
                ] as [String: Any],
                "end_line": [
                    "type": "integer",
                    "description": "Optional: last line to read (1-indexed, inclusive). Omit to read to the end."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["path"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let path = try SkillArgs.getString(args, key: "path")
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw SkillError.fileNotFound(path)
        }
        
        let content = try String(contentsOfFile: expandedPath, encoding: .utf8)
        
        // Handle line range
        let startLine = SkillArgs.getInt(args, key: "start_line", defaultValue: 0)
        let endLine = SkillArgs.getInt(args, key: "end_line", defaultValue: 0)
        
        if startLine > 0 || endLine > 0 {
            let lines = content.components(separatedBy: "\n")
            let start = max(0, startLine - 1)
            let end = endLine > 0 ? min(lines.count, endLine) : lines.count
            
            guard start < lines.count else {
                return "File has \(lines.count) lines, requested start_line \(startLine) is out of range."
            }
            
            let slice = lines[start..<end]
            return slice.enumerated().map { "\(start + $0.offset + 1): \($0.element)" }.joined(separator: "\n")
        }
        
        // Truncate very large files
        if content.count > 50_000 {
            return String(content.prefix(50_000)) + "\n\n[... truncated at 50,000 chars. Use start_line/end_line to read specific sections.]"
        }
        
        return content
    }
}

// MARK: - Write File

struct WriteFileSkill: Skill {
    let name = "write_file"
    let description = "Write or overwrite content to a file. Creates parent directories if needed. Returns confirmation."
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Absolute path of the file to write"
                ] as [String: Any],
                "content": [
                    "type": "string",
                    "description": "The complete file content to write"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["path", "content"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let path = try SkillArgs.getString(args, key: "path")
        let content = try SkillArgs.getString(args, key: "content")
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        // Create parent directories
        let dir = (expandedPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
        return "Successfully wrote \(content.count) characters to \(path)"
    }
}

// MARK: - List Directory

struct ListDirectorySkill: Skill {
    let name = "list_directory"
    let description = "List files and subdirectories in a directory. Returns names, types, and sizes."
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Absolute path of the directory to list"
                ] as [String: Any],
                "recursive": [
                    "type": "boolean",
                    "description": "If true, list recursively (max 200 entries). Default: false."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["path"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let path = try SkillArgs.getString(args, key: "path")
        let recursive = SkillArgs.getBool(args, key: "recursive", defaultValue: false)
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir), isDir.boolValue else {
            throw SkillError.fileNotFound(path)
        }
        
        let fm = FileManager.default
        let entries: [String]
        
        if recursive {
            guard let enumerator = fm.enumerator(atPath: expandedPath) else {
                throw SkillError.executionFailed("Cannot enumerate \(path)")
            }
            var all: [String] = []
            while let item = enumerator.nextObject() as? String {
                // Skip hidden/build
                if item.hasPrefix(".") || item.contains("/.") { continue }
                all.append(item)
                if all.count >= 200 { break }
            }
            entries = all
        } else {
            entries = try fm.contentsOfDirectory(atPath: expandedPath)
                .filter { !$0.hasPrefix(".") }
                .sorted()
        }
        
        var result: [String] = []
        for entry in entries {
            let fullPath = (expandedPath as NSString).appendingPathComponent(entry)
            var entryIsDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &entryIsDir)
            
            if entryIsDir.boolValue {
                result.append("📁 \(entry)/")
            } else {
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let size = attrs?[.size] as? Int64 ?? 0
                let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                result.append("📄 \(entry)  (\(sizeStr))")
            }
        }
        
        return result.isEmpty ? "Directory is empty." : result.joined(separator: "\n")
    }
}

// MARK: - Search Files

struct SearchFilesSkill: Skill {
    let name = "search_files"
    let description = "Search for text patterns in files using grep. Returns matching lines with file paths and line numbers."
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "The text pattern to search for (supports basic regex)"
                ] as [String: Any],
                "path": [
                    "type": "string",
                    "description": "Directory or file to search in"
                ] as [String: Any],
                "file_pattern": [
                    "type": "string",
                    "description": "Optional: glob pattern to filter files (e.g. '*.swift')"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["pattern", "path"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let pattern = try SkillArgs.getString(args, key: "pattern")
        let path = try SkillArgs.getString(args, key: "path")
        let filePattern = SkillArgs.getOptionalString(args, key: "file_pattern")
        let expandedPath = NSString(string: path).expandingTildeInPath
        
        var cmd = "grep -rnI --color=never"
        if let fp = filePattern {
            cmd += " --include='\(fp)'"
        }
        cmd += " '\(pattern.replacingOccurrences(of: "'", with: "'\\''"))' '\(expandedPath)'"
        cmd += " 2>/dev/null | head -50"
        
        let result = await ShellHelper.run(cmd)
        
        if result.output.isEmpty {
            return "No matches found for '\(pattern)' in \(path)"
        }
        return result.output
    }
}

// MARK: - Run Command

struct RunCommandSkill: Skill {
    let name = "run_command"
    let description = "Execute a shell command and return its output. Use for build, test, git, and other CLI operations."
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": [
                    "type": "string",
                    "description": "The shell command to execute"
                ] as [String: Any],
                "working_directory": [
                    "type": "string",
                    "description": "Optional: working directory for the command"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["command"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let command = try SkillArgs.getString(args, key: "command")
        let workDir = SkillArgs.getOptionalString(args, key: "working_directory")
        
        // Safety: block dangerous commands
        let blocked = ["rm -rf /", "rm -rf /*", "mkfs", "dd if=", "> /dev/sda"]
        for b in blocked {
            if command.contains(b) {
                throw SkillError.permissionDenied("Blocked dangerous command: \(command)")
            }
        }
        
        var cmd = command
        if let dir = workDir {
            let expanded = NSString(string: dir).expandingTildeInPath
            cmd = "cd '\(expanded)' && \(command)"
        }
        
        // Timeout: kill after 30 seconds
        cmd = "timeout 30 \(cmd) 2>&1"
        
        let result = await ShellHelper.run(cmd)
        
        var output = ""
        if !result.output.isEmpty {
            output += result.output
        }
        if !result.error.isEmpty {
            output += "\n[STDERR] \(result.error)"
        }
        if result.exitCode != 0 {
            output += "\n[Exit code: \(result.exitCode)]"
        }
        
        // Truncate very long output
        if output.count > 20_000 {
            output = String(output.prefix(20_000)) + "\n\n[... truncated at 20,000 chars]"
        }
        
        return output.isEmpty ? "[No output]" : output
    }
}
