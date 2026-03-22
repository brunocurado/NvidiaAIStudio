import Foundation
import AppKit

/// GitHub OAuth Device Flow + REST API service.
/// Handles authentication, repository listing, clone, and push operations.
///
/// Authentication supports two methods:
///   1. Personal Access Token (PAT) — user creates token at github.com/settings/tokens
///   2. Device Flow OAuth — user authorizes via browser (no client_secret needed)
///
/// The clientID below is PUBLIC and safe to ship in open-source code.
/// It identifies the app to GitHub, but carries no secret.
/// Register your own OAuth App at: https://github.com/settings/applications/new
///   - Application name: Nvidia AI Studio
///   - Homepage URL: https://github.com/YOUR_USERNAME/nvidia-ai-studio
///   - No callback URL needed (Device Flow doesn't use one)
final class GitHubService {
    static let shared = GitHubService()
    
    // MARK: - OAuth Configuration
    //
    // This Client ID is PUBLIC — it is safe to commit and distribute.
    // It is NOT a secret. It only identifies the app name on GitHub's
    // authorization screen. There is no client_secret in Device Flow.
    //
    // To use your own: register at https://github.com/settings/applications/new
    // and replace the value below with your OAuth App's Client ID.
    static let deviceFlowClientID = "Ov23liBTp3pjtRs8oeQw" // safe to be public
    private var clientID: String { GitHubService.deviceFlowClientID }
    private let scope = "repo,read:user"
    
    private let deviceCodeURL = "https://github.com/login/device/code"
    private let accessTokenURL = "https://github.com/login/oauth/access_token"
    private let apiBase = "https://api.github.com"
    
    private init() {}
    
    // MARK: - PAT Authentication
    
    /// Validates a Personal Access Token and returns the username if valid.
    /// This is the simplest auth method — user creates token at github.com/settings/tokens
    /// with scopes: repo, read:user
    func connectWithPAT(_ token: String) async throws -> String {
        guard let username = try await fetchUsername(token: token) else {
            throw GitHubError.invalidToken
        }
        return username
    }
    
    // MARK: - Device Flow OAuth
    
    /// Initiates GitHub Device Flow:
    /// 1. Requests device + user codes from GitHub
    /// 2. Calls onUserCode with the code to show in UI
    /// 3. Polls until the user authorises or it times out
    /// 4. Calls completion with (username, token) on success
    func startDeviceFlow(
        onUserCode: (@Sendable (String, String) -> Void)? = nil,
        completion: @escaping @Sendable (String, String) async -> Void
    ) async {
        do {
            // Step 1: Get device code
            guard let deviceCodeReq = buildDeviceCodeRequest() else { return }
            let (deviceData, _) = try await URLSession.shared.data(for: deviceCodeReq)
            guard let deviceResponse = parseFormEncoded(deviceData) else { return }
            
            let userCode = deviceResponse["user_code"] ?? ""
            let deviceCode = deviceResponse["device_code"] ?? ""
            let verificationURI = deviceResponse["verification_uri"] ?? "https://github.com/login/device"
            let interval = Int(deviceResponse["interval"] ?? "5") ?? 5
            let expiresIn = Int(deviceResponse["expires_in"] ?? "900") ?? 900
            
            // Step 2: Expose user code to UI and copy to clipboard
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(userCode, forType: .string)
            }
            onUserCode?(userCode, verificationURI)
            print("[GitHub OAuth] User code: \(userCode) — open \(verificationURI)")
            
            // Step 3: Poll for access token
            let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
            while Date() < deadline {
                try await Task.sleep(for: .seconds(interval))
                
                if let (token, error) = try await pollForToken(deviceCode: deviceCode) {
                    if error == "authorization_pending" { continue }
                    if error == "slow_down" {
                        try await Task.sleep(for: .seconds(5))
                        continue
                    }
                    if let token = token {
                        // Step 4: Fetch username
                        if let username = try await fetchUsername(token: token) {
                            await completion(username, token)
                        }
                        return
                    }
                    // Any other error: abort
                    break
                }
            }
        } catch {
            print("[GitHub OAuth] Error: \(error)")
        }
    }
    
    // MARK: - Repository Listing
    
    /// Returns the authenticated user's repositories (owned + member).
    func listRepositories(token: String) async throws -> [GitHubRepo] {
        var allRepos: [GitHubRepo] = []
        var page = 1
        
        while true {
            guard let url = URL(string: "\(apiBase)/user/repos?per_page=100&page=\(page)&sort=updated") else { break }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            
            let (data, _) = try await URLSession.shared.data(for: req)
            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            allRepos.append(contentsOf: repos)
            
            if repos.count < 100 { break }
            page += 1
        }
        
        return allRepos
    }
    
    // MARK: - Clone Repository
    
    /// Clones a repository into the given local path using HTTPS + token auth.
    func cloneRepository(repo: GitHubRepo, token: String, destinationPath: String) async throws -> String {
        // Build authenticated HTTPS clone URL: https://TOKEN@github.com/owner/repo.git
        let cloneURL = "https://\(token)@github.com/\(repo.fullName).git"
        let expandedDest = NSString(string: destinationPath).expandingTildeInPath
        
        let result = await ShellHelper.run("git clone '\(cloneURL)' '\(expandedDest)/\(repo.name)' 2>&1")
        
        if result.exitCode != 0 {
            throw GitHubError.cloneFailed(result.output + result.error)
        }
        
        return "\(expandedDest)/\(repo.name)"
    }
    
    // MARK: - Commit & Push
    
    /// Stages all changes, commits with the given message, and pushes to origin.
    func commitAndPush(repoPath: String, message: String, token: String) async throws -> String {
        let path = NSString(string: repoPath).expandingTildeInPath
        
        // Configure git to use the token for this repo (credential via URL)
        let remote = await ShellHelper.run("cd '\(path)' && git remote get-url origin 2>&1")
        var remoteURL = remote.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Inject token into remote URL if not already present
        if remoteURL.hasPrefix("https://github.com") {
            remoteURL = remoteURL.replacingOccurrences(of: "https://github.com", with: "https://\(token)@github.com")
            let _ = await ShellHelper.run("cd '\(path)' && git remote set-url origin '\(remoteURL)' 2>&1")
        }
        
        let add = await ShellHelper.run("cd '\(path)' && git add -A 2>&1")
        let commit = await ShellHelper.run("cd '\(path)' && git commit -m '\(message.replacingOccurrences(of: "'", with: "\\'"))' 2>&1")
        
        if commit.exitCode != 0 && commit.output.contains("nothing to commit") {
            return "ℹ️ Nothing to commit — working tree clean."
        }
        
        let push = await ShellHelper.run("cd '\(path)' && git push 2>&1")
        
        if push.exitCode != 0 {
            throw GitHubError.pushFailed(push.output + push.error)
        }
        
        return "✅ Committed and pushed successfully.\n\(add.output)\n\(commit.output)\n\(push.output)"
    }
    
    // MARK: - Git Status
    
    func status(repoPath: String) async -> String {
        let path = NSString(string: repoPath).expandingTildeInPath
        let result = await ShellHelper.run("cd '\(path)' && git status --porcelain 2>&1")
        return result.output.isEmpty ? "[No changes]" : result.output
    }
    
    // MARK: - Private Helpers
    
    private func buildDeviceCodeRequest() -> URLRequest? {
        guard let url = URL(string: deviceCodeURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientID)&scope=\(scope)"
        req.httpBody = body.data(using: .utf8)
        return req
    }
    
    private func pollForToken(deviceCode: String) async throws -> (String?, String)? {
        guard let url = URL(string: accessTokenURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        req.httpBody = body.data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: req)
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let token = json["access_token"] as? String
            let error = json["error"] as? String ?? ""
            return (token, error)
        }
        
        // Try form-encoded response
        if let formResponse = parseFormEncoded(data) {
            let token = formResponse["access_token"]
            let error = formResponse["error"] ?? ""
            return (token, error)
        }
        
        return nil
    }
    
    private func fetchUsername(token: String) async throws -> String? {
        guard let url = URL(string: "\(apiBase)/user") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["login"] as? String
    }
    
    private func parseFormEncoded(_ data: Data) -> [String: String]? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for pair in str.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let val = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                result[key] = val
            }
        }
        return result.isEmpty ? nil : result
    }
}

// MARK: - Supporting Types

struct GitHubRepo: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let htmlURL: String
    let cloneURL: String
    let updatedAt: String?
    let language: String?
    let stargazersCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, language
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case cloneURL = "clone_url"
        case updatedAt = "updated_at"
        case stargazersCount = "stargazers_count"
    }
}

enum GitHubError: LocalizedError {
    case cloneFailed(String)
    case pushFailed(String)
    case notAuthenticated
    case invalidToken
    
    var errorDescription: String? {
        switch self {
        case .cloneFailed(let msg): return "Clone failed: \(msg)"
        case .pushFailed(let msg): return "Push failed: \(msg)"
        case .notAuthenticated: return "GitHub not connected. Go to Settings → GitHub."
        case .invalidToken: return "Invalid token. Check that it has 'repo' and 'read:user' scopes."
        }
    }
}
