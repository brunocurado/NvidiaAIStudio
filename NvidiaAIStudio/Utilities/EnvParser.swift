import Foundation

/// Parses .env files to load environment variables (API keys, config).
enum EnvParser {
    
    /// Load a .env file and return a dictionary of key-value pairs.
    static func parse(at path: URL) -> [String: String] {
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return [:]
        }
        
        var result: [String: String] = [:]
        
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            
            // Split on first '='
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            
            let key = String(trimmed[trimmed.startIndex..<equalsIndex])
                .trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: equalsIndex)...])
                .trimmingCharacters(in: .whitespaces)
            
            // Remove surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            
            result[key] = value
        }
        
        return result
    }
    
    /// Load the NVIDIA NIM API key from multiple fallback locations.
    static func loadNVIDIAKey() -> String? {
        let fm = FileManager.default
        
        var searchPaths: [URL] = [
            // 1. App bundle Resources
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/.env"),
            // 2. Current working directory (where `swift run` is executed)
            URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".env"),
            // 3. Known project directory
            URL(fileURLWithPath: "/Users/mac/projects/Claude Code Local/.env"),
            // 4. Home directory config
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".nvidia_ai_studio/.env"),
        ]
        
        // 5. Also check the executable's parent directory
        let executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        searchPaths.insert(
            executableURL.deletingLastPathComponent().appendingPathComponent(".env"),
            at: 1
        )
        
        for path in searchPaths {
            let env = parse(at: path)
            if let key = env["NVIDIA_NIM_API_KEY"], !key.isEmpty {
                print("[EnvParser] Found API key at: \(path.path)")
                return key
            }
        }
        
        // Fallback: environment variable
        if let envKey = ProcessInfo.processInfo.environment["NVIDIA_NIM_API_KEY"], !envKey.isEmpty {
            print("[EnvParser] Found API key from environment variable")
            return envKey
        }
        
        print("[EnvParser] ⚠️ No NVIDIA API key found in any location")
        return nil
    }
}
