import Foundation

/// SSH skill that runs commands on a remote VPS.
/// Uses SSH configuration from UserDefaults.
struct SSHSkill: Skill {
    let name = "ssh_command"
    let description = "Execute a command on a remote VPS via SSH. Configure SSH connection in Settings."
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "command": [
                    "type": "string",
                    "description": "The shell command to run on the remote server"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["command"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let command = try SkillArgs.getString(args, key: "command")
        
        // Load SSH config from UserDefaults
        let host = UserDefaults.standard.string(forKey: "sshHost") ?? ""
        let user = UserDefaults.standard.string(forKey: "sshUser") ?? "root"
        let port = UserDefaults.standard.integer(forKey: "sshPort")
        let sshPort = port > 0 ? port : 22
        let keyPath = UserDefaults.standard.string(forKey: "sshKeyPath") ?? ""
        
        guard !host.isEmpty else {
            throw SkillError.executionFailed("SSH not configured. Go to Settings → SSH and add your VPS details.")
        }
        
        var sshArgs = ["-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10"]
        if !keyPath.isEmpty {
            let expanded = NSString(string: keyPath).expandingTildeInPath
            sshArgs.append(contentsOf: ["-i", expanded])
        }
        sshArgs.append(contentsOf: ["-p", "\(sshPort)", "\(user)@\(host)", command])
        
        let result = await ShellHelper.runExecutable("ssh", arguments: sshArgs)
        
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
