import Foundation

/// Git operations skill for staging, committing, and pushing changes.
struct GitSkill: Skill {
    let name = "git"
    let description = "Run git operations: status, add, commit, push, pull, log, diff, branch. The command is passed as the 'operation' argument."
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "operation": [
                    "type": "string",
                    "description": "Git operation: 'status', 'add', 'commit', 'push', 'pull', 'log', 'diff', 'branch', or any valid git subcommand"
                ] as [String: Any],
                "args": [
                    "type": "string",
                    "description": "Additional arguments (e.g., commit message, file paths)"
                ] as [String: Any],
                "working_directory": [
                    "type": "string",
                    "description": "Git repository path (defaults to project path)"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["operation"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let operation = try SkillArgs.getString(args, key: "operation")
        let extraArgs = SkillArgs.getOptionalString(args, key: "args") ?? ""
        let workDir = SkillArgs.getOptionalString(args, key: "working_directory")
        
        guard !operation.contains(where: { $0.isWhitespace }) else {
            throw SkillError.invalidArguments("Git operation must be a single subcommand.")
        }
        
        let allowedOperations = Set(["status", "add", "commit", "push", "pull", "log", "diff", "branch", "checkout"])
        guard allowedOperations.contains(operation) else {
            throw SkillError.permissionDenied("Unsupported git operation: \(operation)")
        }
        
        let gitArgs = [operation] + Self.splitArguments(extraArgs)
        let workingDirectory = workDir.map { NSString(string: $0).expandingTildeInPath }
        let result = await ShellHelper.runExecutable("git", arguments: gitArgs, workingDirectory: workingDirectory)
        
        var output = result.output
        if result.exitCode != 0 && !result.error.isEmpty {
            output += "\n[STDERR] \(result.error)"
        }
        if result.exitCode != 0 {
            output += "\n[Exit code: \(result.exitCode)]"
        }
        
        return output.isEmpty ? "[No output]" : output
    }
    
    private static func splitArguments(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var isEscaped = false
        
        for char in raw {
            if isEscaped {
                current.append(char)
                isEscaped = false
                continue
            }
            if char == "\\" {
                isEscaped = true
                continue
            }
            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
                continue
            }
            if char == "\"" || char == "'" {
                quote = char
            } else if char.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
