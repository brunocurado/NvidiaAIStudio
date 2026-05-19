import Foundation
import Combine

/// Manages a global PTY reference.
@MainActor
final class PTYManager: ObservableObject {
    static let shared = PTYManager()
    
    @Published var pty: PTYProcess
    @Published var activeURL: URL? = nil
    
    private var outputHistory: String = ""
    
    init() {
        self.pty = PTYProcess()
        
        self.pty.onOutput = { [weak self] text in
            self?.handleOutput(text)
        }
    }
    
    func start() {
        pty.start()
    }
    
    func stop() {
        pty.stop()
    }
    
    func write(_ command: String) {
        pty.write(command)
    }
    
    private func handleOutput(_ text: String) {
        // Look for localhost servers in the output to auto-bind the Live Canvas
        // Matches http://localhost:PORT or http://127.0.0.1:PORT
        if text.contains("http://localhost:") || text.contains("http://127.0.0.1:") {
            if let regex = try? NSRegularExpression(pattern: "http://(?:localhost|127\\.0\\.0\\.1):\\d+"),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text), let url = URL(string: String(text[range])) {
                    if self.activeURL != url {
                        self.activeURL = url
                        NotificationCenter.default.post(name: .devServerStarted, object: url)
                    }
                }
            }
        }
    }
}

// Ensure the notification is available globally
extension Notification.Name {
    static let devServerStarted = Notification.Name("devServerStarted")
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
