import Foundation

/// Shared tool execution logic used by both ChatViewModel and SwarmOrchestrator.
/// Eliminates duplication of concurrent/serial grouping, timeout handling, and result processing.
struct ToolExecutor {

    let skillRegistry: SkillRegistry
    let accessLevel: FileAccessLevel
    let workspacePath: String
    let timeout: TimeInterval

    /// Tools that can be safely executed concurrently (read-only, no side effects).
    static let readOnlyTools: Set<String> = [
        "read_file", "list_directory", "search_files",
        "web_search", "fetch_url", "fetch_images", "search_knowledge_base"
    ]

    init(
        skillRegistry: SkillRegistry = .shared,
        accessLevel: FileAccessLevel = .fullAccess,
        workspacePath: String = "",
        timeout: TimeInterval = PromptConfig.default.chatToolTimeout
    ) {
        self.skillRegistry = skillRegistry
        self.accessLevel = accessLevel
        self.workspacePath = workspacePath
        self.timeout = timeout
    }

    /// Splits tool calls into concurrent (read-only) and serial (write) groups.
    func partition(_ toolCalls: [Message.ToolCall]) -> (concurrent: [Message.ToolCall], serial: [Message.ToolCall]) {
        var concurrent: [Message.ToolCall] = []
        var serial: [Message.ToolCall] = []
        for tc in toolCalls {
            if Self.readOnlyTools.contains(tc.name) {
                concurrent.append(tc)
            } else {
                serial.append(tc)
            }
        }
        return (concurrent, serial)
    }

    /// Executes a single tool call with timeout protection.
    /// - Returns: The raw result string from the tool
    func execute(_ toolCall: Message.ToolCall) async -> String {
        do {
            let result = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    return try await self.skillRegistry.execute(
                        name: toolCall.name,
                        arguments: toolCall.arguments,
                        accessLevel: self.accessLevel,
                        workspacePath: self.workspacePath
                    )
                }
                let timeoutNanos = UInt64(self.timeout * 1_000_000_000)
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanos)
                    throw CancellationError()
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }

            // Truncate massively oversized outputs (except generate_image which returns base64)
            if result.count > 100_000 && toolCall.name != "generate_image" {
                return String(result.prefix(100_000)) + "\n\n... [TRUNCATED: Output exceeded 100,000 characters.]"
            }
            return result
        } catch is CancellationError {
            return AgentErrorHandler.formatToolError(CancellationError(), toolName: toolCall.name, timeout: timeout)
        } catch {
            return AgentErrorHandler.formatToolError(error, toolName: toolCall.name)
        }
    }

    /// Executes a batch of tool calls, running read-only ones concurrently and write ones serially.
    /// - Returns: Array of (toolCallID, result) tuples in execution order
    func executeBatch(_ toolCalls: [Message.ToolCall]) async -> [(String, String)] {
        let (concurrent, serial) = partition(toolCalls)
        var results: [(String, String)] = []

        // Concurrent group
        if !concurrent.isEmpty {
            await withTaskGroup(of: (String, String).self) { group in
                for tc in concurrent {
                    group.addTask { [self] in
                        let result = await self.execute(tc)
                        return (tc.id, result)
                    }
                }
                for await (id, result) in group {
                    results.append((id, result))
                }
            }
        }

        // Serial group
        for tc in serial {
            let result = await execute(tc)
            results.append((tc.id, result))
        }

        return results
    }
}
