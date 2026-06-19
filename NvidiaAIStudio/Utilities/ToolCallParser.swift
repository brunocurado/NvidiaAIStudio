import Foundation

/// Unified tool call parser using a single standardized XML format.
///
/// All models (including those without native tool calling support) are instructed
/// via the system prompt to emit tool calls in this format:
///
///     <tool name="tool_name">
///     <arg1>value1</arg1>
///     <arg2>value2</arg2>
///    </tool>
///
/// This replaces 3 fragile parsers (LongCat, DeepSeek XML, DSML) with one simple,
/// robust parser that works with any model that can follow instructions.
enum ToolCallParser {

    /// Extracts tool calls from model output and returns the cleaned content.
    /// - Parameter content: Raw model output that may contain tool calls
    /// - Returns: Tuple of (toolCalls, cleanedContent) where cleanedContent has tool call syntax removed
    static func parse(_ content: String) -> (toolCalls: [Message.ToolCall], cleanedContent: String) {
        var toolCalls: [Message.ToolCall] = []
        var cleaned = content

        // Match: <tool name="..."></tool>
        let pattern = #"<tool\s+name=\"([^\"]+)\">([\s\S]*?)</tool>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ([], content)
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches.reversed() {
            guard match.numberOfRanges == 3 else { continue }

            let name = nsContent.substring(with: match.range(at: 1))
            let innerContent = nsContent.substring(with: match.range(at: 2))

            // Parse inner XML arguments: <key>value</key>
            let arguments = parseArguments(innerContent)

            let id = "tool_" + UUID().uuidString.prefix(8)
            toolCalls.append(Message.ToolCall(
                id: String(id),
                name: name,
                arguments: arguments,
                status: .pending
            ))

            cleaned = (cleaned as NSString).replacingCharacters(in: match.range, with: "")
        }

        return (toolCalls, cleaned.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Parses inner XML arguments into a JSON string.
    /// Example: `<path>/foo</path><content>bar</content>` → `{"path":"/foo","content":"bar"}`
    private static func parseArguments(_ inner: String) -> String {
        var args: [String: String] = [:]
        let pattern = #"<([a-zA-Z_][a-zA-Z0-9_]*)>([\s\S]*?)</\1>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return "{}"
        }

        let nsInner = inner as NSString
        let matches = regex.matches(in: inner, range: NSRange(location: 0, length: nsInner.length))

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let key = nsInner.substring(with: match.range(at: 1))
            let value = nsInner.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            args[key] = value
        }

        guard !args.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: args),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }
}
