import SwiftUI

/// Sheet for browsing and cloning GitHub repositories.
struct CloneRepoView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var repos: [GitHubRepo] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedRepo: GitHubRepo? = nil
    @State private var cloneDestination: String = ""
    @State private var isCloning = false
    @State private var cloneResult: String? = nil
    @State private var errorMessage: String? = nil
    
    private var filtered: [GitHubRepo] {
        if searchText.isEmpty { return repos }
        return repos.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundStyle(.secondary)
                Text("Clone Repository")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            Divider()
            
            if isLoading {
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading repositories…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if repos.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("No repositories found")
                        .foregroundStyle(.secondary)
                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                Spacer()
            } else {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search repositories…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                // Repo list
                List(filtered, selection: $selectedRepo) { repo in
                    RepoRowView(repo: repo, isSelected: selectedRepo?.id == repo.id)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRepo = repo }
                }
                .listStyle(.plain)
            }
            
            // Clone destination + action
            if selectedRepo != nil {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    if let repo = selectedRepo {
                        HStack(spacing: 8) {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "lock.open")
                                .font(.caption)
                                .foregroundStyle(repo.isPrivate ? .orange : .secondary)
                            Text(repo.fullName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let lang = repo.language {
                                Text(lang)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.2), in: Capsule())
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        TextField("Clone destination path", text: $cloneDestination)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse…") {
                            pickDestination()
                        }
                    }
                    
                    if let result = cloneResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.hasPrefix("✅") ? .green : .red)
                    }
                    
                    HStack {
                        Spacer()
                        if isCloning {
                            ProgressView("Cloning…")
                                .controlSize(.small)
                        } else {
                            Button("Clone") {
                                cloneSelected()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(cloneDestination.isEmpty)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 560, height: 520)
        .onAppear { loadRepos() }
    }
    
    // MARK: - Actions
    
    private func loadRepos() {
        guard let token = appState.gitHubToken else {
            errorMessage = "GitHub not connected.\nGo to Settings → GitHub to connect your account."
            return
        }
        isLoading = true
        Task {
            do {
                let fetched = try await GitHubService.shared.listRepositories(token: token)
                await MainActor.run {
                    repos = fetched.sorted { $0.stargazersCount > $1.stargazersCount }
                    isLoading = false
                    // Default destination to active workspace
                    cloneDestination = appState.activeWorkspacePath
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func pickDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Destination"
        if panel.runModal() == .OK, let url = panel.url {
            cloneDestination = url.path
        }
    }
    
    private func cloneSelected() {
        guard let repo = selectedRepo, let token = appState.gitHubToken else { return }
        isCloning = true
        cloneResult = nil
        Task {
            do {
                let clonedPath = try await GitHubService.shared.cloneRepository(
                    repo: repo,
                    token: token,
                    destinationPath: cloneDestination
                )
                await MainActor.run {
                    cloneResult = "✅ Cloned to \(clonedPath)"
                    isCloning = false
                    // Open the cloned repo as a new workspace session
                    appState.activeWorkspacePath = clonedPath
                    var session = appState.createSession(title: repo.name)
                    session.projectPath = clonedPath
                    appState.activeSession = session
                    appState.showToast("Cloned \(repo.name) successfully", level: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                }
            } catch {
                await MainActor.run {
                    cloneResult = "❌ \(error.localizedDescription)"
                    isCloning = false
                }
            }
        }
    }
}

// MARK: - Repo Row

struct RepoRowView: View {
    let repo: GitHubRepo
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed.fill")
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repo.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected ? .white : .primary)
                    
                    if repo.isPrivate {
                        Text("private")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                }
                
                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                if let lang = repo.language {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }
                if repo.stargazersCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("\(repo.stargazersCount)")
                            .font(.caption2)
                    }
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.blue.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
