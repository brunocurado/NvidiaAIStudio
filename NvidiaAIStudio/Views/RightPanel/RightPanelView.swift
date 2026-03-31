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
                
                TextField("Type here...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .onSubmit {
                        sendInput()
                    }
                
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
    
    private func sendInput() {
        let text = inputText
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

// MARK: - ANSI Parser + Terminal Line

struct TerminalOutputLine: Identifiable {
    let id = UUID()
    let raw: String
    
    /// Parse ANSI escape codes into a colored AttributedString.
    var attributed: AttributedString {
        ANSIParser.parse(raw)
    }
}

/// Parses ANSI escape sequences into styled AttributedString.
enum ANSIParser {
    // Regex to match ANSI escape sequences: ESC[ ... m
    private static let ansiPattern = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*m", options: [])
    // Also strip other escape sequences (cursor movement, etc.)
    private static let otherEscapes = try! NSRegularExpression(pattern: "\\x1B\\[[0-9;]*[A-HJKSTfn]|\\x1B\\].*?\\x07|\\x1B\\(B", options: [])
    
    static func parse(_ raw: String) -> AttributedString {
        let clean = otherEscapes.stringByReplacingMatches(
            in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: ""
        )
        
        var result = AttributedString()
        var currentColor: Color = .primary
        var isBold = false
        var isDim = false
        
        let nsString = clean as NSString
        let matches = ansiPattern.matches(in: clean, range: NSRange(location: 0, length: nsString.length))
        
        var lastEnd = 0
        
        for match in matches {
            // Text before this escape sequence
            if match.range.location > lastEnd {
                let textRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let text = nsString.substring(with: textRange)
                var attr = AttributedString(text)
                attr.foregroundColor = isDim ? currentColor.opacity(0.6) : currentColor
                if isBold { attr.font = .system(size: 12, weight: .bold, design: .monospaced) }
                result += attr
            }
            
            // Parse the escape code
            let code = nsString.substring(with: match.range)
            let numbers = code.dropFirst(2).dropLast()
                .split(separator: ";")
                .compactMap { Int($0) }
            
            for num in (numbers.isEmpty ? [0] : numbers) {
                switch num {
                case 0:  currentColor = .primary; isBold = false; isDim = false
                case 1:  isBold = true
                case 2:  isDim = true
                case 22: isBold = false; isDim = false
                case 30: currentColor = Color(.darkGray)
                case 31: currentColor = Color(.systemRed)
                case 32: currentColor = Color(.systemGreen)
                case 33: currentColor = Color(.systemYellow)
                case 34: currentColor = Color(.systemBlue)
                case 35: currentColor = Color(.systemPurple)
                case 36: currentColor = Color(.systemTeal)
                case 37: currentColor = .white
                case 39: currentColor = .primary
                case 90: currentColor = .gray
                case 91: currentColor = Color(.systemRed).opacity(0.8)
                case 92: currentColor = Color(.systemGreen).opacity(0.8)
                case 93: currentColor = Color(.systemYellow).opacity(0.8)
                case 94: currentColor = Color(.systemBlue).opacity(0.8)
                case 95: currentColor = Color(.systemPurple).opacity(0.8)
                case 96: currentColor = Color(.systemTeal).opacity(0.8)
                case 97: currentColor = .white
                default: break
                }
            }
            
            lastEnd = match.range.location + match.range.length
        }
        
        // Remaining text after last escape
        if lastEnd < nsString.length {
            let text = nsString.substring(from: lastEnd)
            var attr = AttributedString(text)
            attr.foregroundColor = isDim ? currentColor.opacity(0.6) : currentColor
            if isBold { attr.font = .system(size: 12, weight: .bold, design: .monospaced) }
            result += attr
        }
        
        // If no escapes found, just return plain text
        if matches.isEmpty && result.characters.isEmpty {
            result = AttributedString(clean)
        }
        
        return result
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
