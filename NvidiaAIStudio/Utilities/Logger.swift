import Foundation
import os

/// Centralized logging using Apple's unified logging system (os.Logger).
/// Logs appear in Console.app under subsystem "com.nvidia.aistudio".
enum AppLog {
    private static let subsystem = "com.nvidia.aistudio"

    /// Network/API calls (chat completions, streaming, retries)
    static let network = Logger(subsystem: subsystem, category: "network")

    /// Swarm orchestration (agent lifecycle, task dispatch, debates)
    static let swarm = Logger(subsystem: subsystem, category: "swarm")

    /// Chat system (messages, context management, compression)
    static let chat = Logger(subsystem: subsystem, category: "chat")

    /// Skills/tools execution (file ops, web search, etc.)
    static let skills = Logger(subsystem: subsystem, category: "skills")

    /// General app lifecycle
    static let app = Logger(subsystem: subsystem, category: "app")
}
