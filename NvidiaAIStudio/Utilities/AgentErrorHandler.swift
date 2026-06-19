import Foundation

/// Centralized error handling for the chat agent loop.
/// Replaces 4 different error patterns with a single, consistent approach.
enum AgentErrorHandler {

    /// Categorizes an error and returns a user-friendly message.
    /// - Parameter error: The error to handle
    /// - Returns: A tuple with (userMessage, shouldRemovePlaceholder, isCancellation)
    static func handle(_ error: Error) -> (message: String, removePlaceholder: Bool, isCancellation: Bool) {
        // User-initiated cancellation
        if error is CancellationError {
            return ("", true, true)
        }

        // Network cancellation (URLSession)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return ("", true, true)
        }

        // API service errors with specific messages
        if let apiError = error as? APIServiceError {
            return (apiError.errorDescription ?? "API error", false, false)
        }

        // Generic error
        return (error.localizedDescription, false, false)
    }

    /// Formats a tool execution error for display in the chat.
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - toolName: Name of the tool that failed
    ///   - timeout: Optional timeout duration for timeout-specific messages
    /// - Returns: A formatted error string
    static func formatToolError(_ error: Error, toolName: String, timeout: TimeInterval? = nil) -> String {
        if error is CancellationError, let timeout = timeout {
            return "Error: \(toolName) timed out after \(Int(timeout)) seconds. Try a more specific command."
        }
        return "Error: \(toolName) failed — \(error.localizedDescription)"
    }
}
