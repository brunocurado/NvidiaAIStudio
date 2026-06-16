import Foundation

/// Centralized configuration for prompt execution and agent behavior.
/// Adjust these values to tune the balance between cost, speed, and quality.
struct PromptConfig {
    // MARK: - Chat Settings

    /// Maximum iterations for the chat agent loop before forcing a stop.
    let maxChatIterations: Int

    /// Context usage threshold (0.0-1.0) at which auto-compaction triggers.
    let contextCompactionThreshold: Double

    /// Number of recent messages to keep verbatim during compaction.
    let compactionKeepLast: Int

    // MARK: - Swarm Settings

    /// Maximum iterations for a standard swarm task.
    let maxSwarmIterations: Int

    /// Maximum iterations for a debate task (per participant).
    let maxDebateIterations: Int

    /// Number of self-healing retries before a task is marked failed.
    let selfHealingRetries: Int

    // MARK: - Tool Execution

    /// Timeout for tool execution in the Chat system (seconds).
    let chatToolTimeout: TimeInterval

    /// Timeout for tool execution in the Swarm system (seconds).
    let swarmToolTimeout: TimeInterval

    // MARK: - Output Limits

    /// Default max output tokens for standard models.
    let defaultMaxOutputTokens: Int

    /// Max output tokens for large context (1M+) models.
    let largeContextMaxOutputTokens: Int

    // MARK: - Defaults

    static let `default` = PromptConfig(
        maxChatIterations: 50,
        contextCompactionThreshold: 0.8,
        compactionKeepLast: 6,
        maxSwarmIterations: 25,
        maxDebateIterations: 5,
        selfHealingRetries: 3,
        chatToolTimeout: 30,
        swarmToolTimeout: 60,
        defaultMaxOutputTokens: 8192,
        largeContextMaxOutputTokens: 16384
    )

    // MARK: - Presets

    /// Fast & cheap: lower iterations, smaller outputs, more aggressive compaction.
    static let fast = PromptConfig(
        maxChatIterations: 20,
        contextCompactionThreshold: 0.6,
        compactionKeepLast: 4,
        maxSwarmIterations: 15,
        maxDebateIterations: 3,
        selfHealingRetries: 2,
        chatToolTimeout: 20,
        swarmToolTimeout: 45,
        defaultMaxOutputTokens: 4096,
        largeContextMaxOutputTokens: 8192
    )

    /// Deep & thorough: higher iterations, larger outputs, less aggressive compaction.
    static let thorough = PromptConfig(
        maxChatIterations: 100,
        contextCompactionThreshold: 0.9,
        compactionKeepLast: 10,
        maxSwarmIterations: 50,
        maxDebateIterations: 10,
        selfHealingRetries: 5,
        chatToolTimeout: 60,
        swarmToolTimeout: 120,
        defaultMaxOutputTokens: 16384,
        largeContextMaxOutputTokens: 32768
    )
}
