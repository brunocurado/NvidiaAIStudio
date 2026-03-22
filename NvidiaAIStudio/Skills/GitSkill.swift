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
        
        var cmd = "git \(operation)"
        if !extraArgs.isEmpty {
            cmd += " \(extraArgs)"
        }
        
        if let dir = workDir {
            let expanded = NSString(string: dir).expandingTildeInPath
            cmd = "cd '\(expanded)' && \(cmd)"
        }
        
        let result = await ShellHelper.run(cmd + " 2>&1")
        
        var output = result.output
        if result.exitCode != 0 && !result.error.isEmpty {
            output += "\n[STDERR] \(result.error)"
        }
        if result.exitCode != 0 {
            output += "\n[Exit code: \(result.exitCode)]"
        }
        
        return output.isEmpty ? "[No output]" : output
    }
}
