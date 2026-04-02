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
    @State private var pty = PTYProcess()
    @State private var outputLines: [TerminalOutputLine] = []
    @State private var inputText = ""
    @State private var isConnected = false
    @State private var commandHistory: [String] = []
    @State private var historyIndex = -1
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(outputLines) { line in
                            Text(line.attributed)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(12)
                }
                .onChange(of: outputLines.count) {
                    if let last = outputLines.last {
                        withAnimation(.easeOut(duration: 0.05)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider().opacity(0.3)
            
            // Input line
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? .green : .red)
                    .frame(width: 7, height: 7)
                
                TerminalInputArea(
                    text: $inputText,
                    onCommit: {
                        sendInput()
                    },
                    onUp: {
                        if !commandHistory.isEmpty {
                            historyIndex = min(historyIndex + 1, commandHistory.count - 1)
                            inputText = commandHistory[commandHistory.count - 1 - historyIndex]
                        }
                    },
                    onDown: {
                        if historyIndex > 0 {
                            historyIndex -= 1
                            inputText = commandHistory[commandHistory.count - 1 - historyIndex]
                        } else {
                            historyIndex = -1
                            inputText = ""
                        }
                    },
                    onTab: {
                        doAutocomplete()
                    }
                )
                .frame(height: 20)
                
                // Ctrl+C button
                Button {
                    pty.sendInterrupt()
                } label: {
                    Text("⌃C")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Send interrupt (Ctrl+C)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { startPTY() }
        .onDisappear { pty.stop() }
    }
    
    private func startPTY() {
        pty.onOutput = { text in
            // Handle native clear screen requests
            if text.contains("\u{1b}[2J") || text.contains("\u{1b}c") {
                outputLines.removeAll()
            }
            
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                if i == 0, let last = outputLines.last, !last.raw.hasSuffix("\n") {
                    // Append to last line (partial output)
                    let idx = outputLines.count - 1
                    outputLines[idx] = TerminalOutputLine(raw: outputLines[idx].raw + line)
                } else if !line.isEmpty || i < lines.count - 1 {
                    outputLines.append(TerminalOutputLine(raw: line))
                }
            }
            // Cap output to last 2000 lines
            if outputLines.count > 2000 {
                outputLines.removeFirst(outputLines.count - 1500)
            }
        }
        pty.start()
        isConnected = true
    }
    
    private func doAutocomplete() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        
        Task {
            let components = text.split(separator: " ", omittingEmptySubsequences: false)
            let isCommand = components.count == 1
            let lastWord = String(components.last ?? "")
            
            // compgen -c for commands, compgen -f for files
            let flag = isCommand ? "-c" : "-f"
            let escapedWord = lastWord.replacingOccurrences(of: "\"", with: "\\\"")
            // We use bash -c because compgen is a bash builtin
            let script = "bash -c 'compgen \(flag) \"\(escapedWord)\"'"
            let result = await ShellHelper.run(script)
            
            let matches = result.output.components(separatedBy: "\n").filter { !$0.isEmpty }
            if let bestMatch = matches.first {
                await MainActor.run {
                    if isCommand {
                        inputText = bestMatch
                    } else {
                        // Replace last word with completion
                        let prefix = components.dropLast().joined(separator: " ")
                        inputText = prefix + (prefix.isEmpty ? "" : " ") + bestMatch
                    }
                }
            }
        }
    }
    
    private func sendInput() {
        let text = inputText
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if commandHistory.last != text {
                commandHistory.append(text)
            }
            // Keep history sane
            if commandHistory.count > 100 {
                commandHistory.removeFirst(commandHistory.count - 100)
            }
        }
        historyIndex = -1
        inputText = ""
        pty.write(text + "\n")
    }
}

// MARK: - PTY Process

/// A real pseudo-terminal process using forkpty().
/// Supports interactive sessions: SSH, vim, htop, zsh, etc.
final class PTYProcess: @unchecked Sendable {
    private var masterFD: Int32 = -1
    private var childPID: pid_t = 0
    private var readThread: Thread?
    private var isRunning = false
    
    var onOutput: (@MainActor (String) -> Void)?
    
    func start(shell: String = "/bin/zsh") {
        guard !isRunning else { return }
        
        var ws = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        
        childPID = forkpty(&masterFD, nil, nil, &ws)
        
        if childPID == 0 {
            // Child process — exec the shell
            setenv("TERM", "xterm-256color", 1)
            setenv("LANG", "en_US.UTF-8", 1)
            setenv("LC_ALL", "en_US.UTF-8", 1)
            let homeDir = NSHomeDirectory()
            setenv("HOME", homeDir, 1)
            _ = chdir(homeDir)
            // Use execv with null-terminated argv array
            let args: [UnsafeMutablePointer<CChar>?] = [
                strdup(shell),
                strdup("--login"),
                nil
            ]
            execv(shell, args)
            _exit(1)
        }
        
        guard childPID > 0 else {
            print("[PTYProcess] forkpty failed")
            return
        }
        
        isRunning = true
        startReading()
    }
    
    func stop() {
        guard isRunning else { return }
        isRunning = false
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        if childPID > 0 {
            kill(childPID, SIGTERM)
            childPID = 0
        }
    }
    
    func write(_ text: String) {
        guard masterFD >= 0 else { return }
        text.withCString { ptr in
            let len = strlen(ptr)
            _ = Darwin.write(masterFD, ptr, len)
        }
    }
    
    func sendInterrupt() {
        // Send Ctrl+C (ETX character)
        write("\u{03}")
    }
    
    func resize(rows: Int, cols: Int) {
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }
    
    private func startReading() {
        let fd = masterFD
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while self.isRunning && fd >= 0 {
                let bytesRead = read(fd, &buffer, buffer.count)
                if bytesRead <= 0 { break }
                if let str = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
                    let output = str
                    Task { @MainActor in
                        self.onOutput?(output)
                    }
                }
            }
        }
        thread.qualityOfService = .userInteractive
        thread.name = "PTYReader"
        thread.start()
        readThread = thread
    }
    
    deinit {
        stop()
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

// MARK: - Helpers

/// Simple git diff helper
enum GitHelper {
    static func getChangedFiles() async -> [DiffFile] {
        let result = await ShellHelper.run("git diff HEAD --numstat 2>/dev/null || git diff --numstat 2>/dev/null")
        guard !result.output.isEmpty else { return [] }
        
        var files: [DiffFile] = []
        
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3 else { continue }
            
            let additions = Int(parts[0]) ?? 0
            let deletions = Int(parts[1]) ?? 0
            let filename = String(parts[2])
            
            // Get the actual diff for this file
            let diffResult = await ShellHelper.run("git diff HEAD -- \"\(filename)\" 2>/dev/null || git diff -- \"\(filename)\" 2>/dev/null")
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
                    
                    // Prevent deadlock: Read sequentially is usually fine if stderr is mostly empty.
                    // To be safe, we read output completely to drain the pipe, then error.
                    // GitHelper pipes 2>/dev/null anyway.
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    process.waitUntilExit()
                    
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

// MARK: - AppKit Wrappers

struct TerminalInputArea: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onUp: () -> Void
    var onDown: () -> Void
    var onTab: () -> Void
    
    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.focusRingType = .none
        tf.drawsBackground = false
        tf.isBordered = false
        tf.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tf.placeholderString = "Type here..."
        return tf
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TerminalInputArea
        init(_ parent: TerminalInputArea) { self.parent = parent }
        
        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.text = textView.string
                parent.onCommit()
                return true
            } else if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onUp()
                return true
            } else if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onDown()
                return true
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab()
                return true
            }
            return false
        }
    }
}
