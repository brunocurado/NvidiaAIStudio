import Foundation

/// A lightweight heuristic-based token estimator to prevent API payload rejection and guide auto-compaction.
/// It mimics Claude Code's `@anthropic-ai/tokenizer` fallback logic.
struct TokenEstimator {
    
    /// Heuristically estimate token count for a raw string.
    /// Roughly ~4 chars per token for English, but we use a conservative 3.5 to be safe.
    /// (For CJK it's closer to ~2.5, but this is a generalized fallback).
    static func estimate(_ text: String) -> Int {
        if text.isEmpty { return 0 }
        // We use utf16.count which is faster and generally aligns well with character encoding bounds.
        let tokenCount = Double(text.utf16.count) / 3.5
        return max(1, Int(ceil(tokenCount)))
    }
    
    /// Estimate total tokens for a specific message, including its content, reasoning, and tool calls.
    static func estimate(_ message: Message) -> Int {
        var total = estimate(message.content)
        
        if let reasoning = message.reasoning {
            total += estimate(reasoning)
        }
        
        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                total += estimate(call.name)
                total += estimate(call.arguments)
                if let result = call.result {
                    total += estimate(result)
                }
            }
        }
        
        // Add flat overhead for message formatting boundaries
        total += 4
        return total
    }
    
    /// Estimate the context payload size of an entire multi-turn session.
    static func estimateSession(_ messages: [Message]) -> Int {
        let sum = messages.reduce(0) { $0 + estimate($1) }
        // Add typical system prompt and knowledge base injection overhead (~1500 tokens buffer)
        return sum + 1500
    }
}
