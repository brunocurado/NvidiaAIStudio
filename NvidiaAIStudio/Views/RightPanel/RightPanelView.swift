import SwiftUI

/// Right panel with Diff and Terminal tabs.
struct RightPanelView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                Picker("Panel", selection: Bindable(appState).rightPanelMode) {
                    ForEach(RightPanelMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Spacer()
                
                // Refresh button
                Button {
                    if appState.rightPanelMode == .diff {
                        // Refresh git diff
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider().opacity(0.3)
            
            // Content
            switch appState.rightPanelMode {
            case .diff:
                DiffViewerContent()
            case .terminal:
                TerminalContent()
            }
        }
        .background(.ultraThinMaterial.opacity(0.6))
    }
}

// MARK: - Diff Viewer

struct DiffViewerContent: View {
    @State private var changedFiles: [DiffFile] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            if changedFiles.isEmpty && !isLoading {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green.opacity(0.6))
                    Text("No changes detected")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("All files are up to date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if isLoading {
                Spacer()
                ProgressView("Loading diff...")
                    .font(.caption)
                Spacer()
            } else {
                // Collapsible file sections
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(changedFiles) { file in
                            DiffFileSection(file: file)
                        }
                    }
                }

                Divider().opacity(0.3)

                // Action buttons — GlassCode style
                HStack(spacing: 16) {
                    Spacer()
                    Button {
                        // Revert all
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward.circle")
                                .font(.caption)
                            Text("Revert all")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        // Stage all
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption)
                            Text("Stage all")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear { loadDiff() }
        .onReceive(NotificationCenter.default.publisher(for: .diffShouldRefresh)) { _ in
            loadDiff()
        }
    }

    private func loadDiff() {
        isLoading = true
        Task {
            let files = await GitHelper.getChangedFiles()
            await MainActor.run {
                changedFiles = files
                isLoading = false
            }
        }
    }
}

/// Collapsible diff section per file — GlassCode style
struct DiffFileSection: View {
    let file: DiffFile
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Text(file.filename)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer()

                    if file.additions > 0 {
                        Text("+\(file.additions)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    if file.deletions > 0 {
                        Text("-\(file.deletions)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.red)
                    }

                    Button { /* discard */ } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }

            if isExpanded && !file.lines.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                        DiffLineView(line: line)
                    }
                }
                .padding(.horizontal, 4)
            }

            Divider().opacity(0.2)
        }
    }
}

struct DiffLineView: View {
    let line: DiffLine
    
    var body: some View {
        HStack(spacing: 0) {
            // Line numbers
            Text(line.oldNumber.map { String($0) } ?? "")
                .frame(width: 36, alignment: .trailing)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text(line.newNumber.map { String($0) } ?? "")
                .frame(width: 36, alignment: .trailing)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.5))
            
            // Content
            Text(line.content)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(line.type == .context ? Color.primary : Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
        }
        .padding(.vertical, 1)
        .background(lineBackground)
    }
    
    private var lineBackground: Color {
        switch line.type {
        case .addition: return .green.opacity(0.15)
        case .deletion: return .red.opacity(0.15)
        case .context: return .clear
        case .header: return .blue.opacity(0.1)
        }
    }
}

// MARK: - Terminal

struct TerminalContent: View {
    @State private var commandHistory: [TerminalLine] = [
        TerminalLine(text: "Welcome to Nvidia AI Studio Terminal", type: .output),
        TerminalLine(text: "Type a command and press Enter", type: .output),
    ]
    @State private var currentCommand = ""
    @State private var isRunning = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(commandHistory) { line in
                            HStack(spacing: 4) {
                                if line.type == .command {
                                    Text("$")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.green)
                                }
                                Text(line.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(line.type == .error ? .red : .primary)
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: commandHistory.count) {
                    if let last = commandHistory.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            
            Divider().opacity(0.3)
            
            // Command input
            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
                
                TextField("Enter command...", text: $currentCommand)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit {
                        runCommand()
                    }
                    .disabled(isRunning)
                
                if isRunning {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
    
    private func runCommand() {
        let cmd = currentCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        
        commandHistory.append(TerminalLine(text: cmd, type: .command))
        currentCommand = ""
        isRunning = true
        
        Task {
            let result = await ShellHelper.run(cmd)
            await MainActor.run {
                if !result.output.isEmpty {
                    commandHistory.append(TerminalLine(text: result.output, type: .output))
                }
                if !result.error.isEmpty {
                    commandHistory.append(TerminalLine(text: result.error, type: .error))
                }
                isRunning = false
            }
        }
    }
}

// MARK: - Models

struct DiffFile: Identifiable {
    let id = UUID()
    let filename: String
    let status: FileStatus
    let additions: Int
    let deletions: Int
    let lines: [DiffLine]
    
    enum FileStatus: String {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
    }
    
    var statusIcon: String {
        switch status {
        case .modified: return "pencil.circle.fill"
        case .added: return "plus.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        }
    }
}

struct DiffLine: Identifiable {
    let id = UUID()
    let content: String
    let type: LineType
    let oldNumber: Int?
    let newNumber: Int?
    
    enum LineType {
        case addition, deletion, context, header
    }
}

struct TerminalLine: Identifiable {
    let id = UUID()
    let text: String
    let type: LineType
    
    enum LineType {
        case command, output, error
    }
}

// MARK: - Helpers

/// Simple git diff helper
enum GitHelper {
    static func getChangedFiles() async -> [DiffFile] {
        let result = await ShellHelper.run("git diff --numstat 2>/dev/null")
        guard !result.output.isEmpty else { return [] }
        
        var files: [DiffFile] = []
        
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { continue }
            
            let additions = Int(parts[0]) ?? 0
            let deletions = Int(parts[1]) ?? 0
            let filename = String(parts[2])
            
            // Get the actual diff for this file
            let diffResult = await ShellHelper.run("git diff -- \"\(filename)\" 2>/dev/null")
            let diffLines = parseDiffLines(diffResult.output)
            
            files.append(DiffFile(
                filename: filename,
                status: .modified,
                additions: additions,
                deletions: deletions,
                lines: diffLines
            ))
        }
        
        // Also check for new (untracked) files
        let untrackedResult = await ShellHelper.run("git ls-files --others --exclude-standard 2>/dev/null")
        for line in untrackedResult.output.split(separator: "\n") {
            let filename = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filename.isEmpty else { continue }
            files.append(DiffFile(
                filename: filename,
                status: .added,
                additions: 0,
                deletions: 0,
                lines: []
            ))
        }
        
        return files
    }
    
    private static func parseDiffLines(_ raw: String) -> [DiffLine] {
        var lines: [DiffLine] = []
        var oldLine = 0
        var newLine = 0
        
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let str = String(line)
            
            if str.hasPrefix("@@") {
                // Parse hunk header: @@ -a,b +c,d @@
                let parts = str.split(separator: " ")
                if parts.count >= 3 {
                    let newPart = String(parts[2]).dropFirst() // remove +
                    let nums = newPart.split(separator: ",")
                    newLine = Int(nums.first ?? "0") ?? 0
                    let oldPart = String(parts[1]).dropFirst() // remove -
                    let oldNums = oldPart.split(separator: ",")
                    oldLine = Int(oldNums.first ?? "0") ?? 0
                }
                lines.append(DiffLine(content: str, type: .header, oldNumber: nil, newNumber: nil))
            } else if str.hasPrefix("+") && !str.hasPrefix("+++") {
                lines.append(DiffLine(content: String(str.dropFirst()), type: .addition, oldNumber: nil, newNumber: newLine))
                newLine += 1
            } else if str.hasPrefix("-") && !str.hasPrefix("---") {
                lines.append(DiffLine(content: String(str.dropFirst()), type: .deletion, oldNumber: oldLine, newNumber: nil))
                oldLine += 1
            } else if str.hasPrefix("diff") || str.hasPrefix("index") || str.hasPrefix("+++") || str.hasPrefix("---") {
                // Skip metadata lines
            } else {
                let content = str.hasPrefix(" ") ? String(str.dropFirst()) : str
                lines.append(DiffLine(content: content, type: .context, oldNumber: oldLine, newNumber: newLine))
                oldLine += 1
                newLine += 1
            }
        }
        
        return lines
    }
}

/// Simple shell command runner
enum ShellHelper {
    struct Result {
        let output: String
        let error: String
        let exitCode: Int32
    }
    
    static func run(_ command: String) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    continuation.resume(returning: Result(output: output, error: error, exitCode: process.terminationStatus))
                } catch {
                    continuation.resume(returning: Result(output: "", error: error.localizedDescription, exitCode: -1))
                }
            }
        }
    }
}
