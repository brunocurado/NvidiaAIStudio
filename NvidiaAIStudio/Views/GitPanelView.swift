import SwiftUI

/// Git Panel: shows changed files, commit message input, and push button.
struct GitPanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    
    @State private var commitMessage = ""
    @State private var changedFiles: [GitFileChange] = []
    @State private var isLoadingStatus = false
    @State private var isCommitting = false
    @State private var resultMessage: String? = nil
    @State private var showCloneSheet = false
    
    private var repoPath: String? {
        appState.activeSession?.projectPath ?? (
            appState.activeWorkspacePath == FileManager.default.currentDirectoryPath
                ? nil
                : appState.activeWorkspacePath
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                Text("Commit & Push")
                    .font(.headline)
                Spacer()
                
                // Clone button
                Button {
                    showCloneSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Clone Repo")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Button("Close") { dismiss() }
            }
            .padding()
            
            Divider()
            
            if let path = repoPath {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Repo info
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if isLoadingStatus {
                                ProgressView().controlSize(.mini)
                            } else {
                                Button {
                                    refreshStatus()
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        
                        // Changed files
                        if changedFiles.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.green)
                                    Text("Working tree clean")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Changed Files (\(changedFiles.count))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                
                                ForEach(changedFiles) { file in
                                    HStack(spacing: 8) {
                                        Text(file.statusSymbol)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(file.statusColor)
                                            .frame(width: 16)
                                        Text(file.path)
                                            .font(.system(size: 12, design: .monospaced))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        
                        Divider()
                            .padding(.horizontal, 16)
                        
                        // Commit message
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Commit Message")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                            
                            TextEditor(text: $commitMessage)
                                .font(.body)
                                .frame(minHeight: 80)
                                .padding(8)
                                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 16)
                        
                        // GitHub auth warning
                        if appState.gitHubToken == nil {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text("GitHub not connected. Push may fail. Go to Settings → GitHub.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        // Result
                        if let result = resultMessage {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(result.hasPrefix("✅") ? .green : (result.hasPrefix("ℹ️") ? .secondary : .red))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                        }
                        
                        // Actions
                        HStack {
                            Spacer()
                            if isCommitting {
                                ProgressView("Committing & pushing…")
                                    .controlSize(.small)
                            } else {
                                Button("Commit & Push") {
                                    commitAndPush()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || changedFiles.isEmpty)
                                .keyboardShortcut(.return, modifiers: .command)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
            } else {
                // No workspace / repo selected
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No Workspace Selected")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Open a workspace folder from the sidebar\nor clone a repository to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showCloneSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                            Text("Clone a Repository")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
        }
        .frame(width: 500, height: 560)
        .onAppear { refreshStatus() }
        .sheet(isPresented: $showCloneSheet) {
            CloneRepoView()
                .environment(appState)
        }
    }
    
    // MARK: - Actions
    
    private func refreshStatus() {
        guard let path = repoPath else { return }
        isLoadingStatus = true
        resultMessage = nil
        Task {
            let raw = await GitHubService.shared.status(repoPath: path)
            let files = parseGitStatus(raw)
            await MainActor.run {
                changedFiles = files
                isLoadingStatus = false
            }
        }
    }
    
    private func commitAndPush() {
        guard let path = repoPath else { return }
        let msg = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        
        isCommitting = true
        resultMessage = nil
        
        // Use token if available, otherwise rely on system git credentials
        let token = appState.gitHubToken ?? ""
        
        Task {
            do {
                let result = try await GitHubService.shared.commitAndPush(
                    repoPath: path,
                    message: msg,
                    token: token
                )
                await MainActor.run {
                    resultMessage = result
                    isCommitting = false
                    commitMessage = ""
                    refreshStatus()
                    appState.showToast("Pushed successfully", level: .success)
                }
            } catch {
                await MainActor.run {
                    resultMessage = "❌ \(error.localizedDescription)"
                    isCommitting = false
                }
            }
        }
    }
    
    // MARK: - Parse git status --porcelain
    
    private func parseGitStatus(_ raw: String) -> [GitFileChange] {
        guard raw != "[No changes]" else { return [] }
        return raw.split(separator: "\n").compactMap { line in
            let s = String(line)
            guard s.count >= 3 else { return nil }
            let xy = String(s.prefix(2))
            let path = String(s.dropFirst(3))
            return GitFileChange(id: UUID(), statusCode: xy, path: path)
        }
    }
}

// MARK: - Supporting Type

struct GitFileChange: Identifiable {
    let id: UUID
    let statusCode: String
    let path: String
    
    var statusSymbol: String {
        switch statusCode.trimmingCharacters(in: .whitespaces).first {
        case "M": return "M"
        case "A": return "A"
        case "D": return "D"
        case "R": return "R"
        case "?": return "?"
        default:  return "·"
        }
    }
    
    var statusColor: Color {
        switch statusCode.trimmingCharacters(in: .whitespaces).first {
        case "M": return .orange
        case "A": return .green
        case "D": return .red
        case "R": return .blue
        case "?": return .secondary
        default:  return .secondary
        }
    }
}
