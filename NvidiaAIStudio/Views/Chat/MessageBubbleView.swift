import SwiftUI
import MarkdownUI

/// A single message bubble in the chat.
/// A single message bubble in the chat.
struct MessageBubbleView: View {
    let message: Message
    @State private var showToolDetail = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 80)
            } else {
                // Assistant avatar — subtle green glow
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }
                .padding(.top, 4)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Reasoning/thinking (collapsible)
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    ReasoningView(content: reasoning)
                }
                
                // Content with Markdown rendering
                if !message.content.isEmpty {
                    Group {
                        if message.role == .assistant {
                            Markdown(message.content)
                                .markdownTheme(.nvidia)
                                .textSelection(.enabled)
                        } else {
                            Text(message.content)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(
                        message.role == .user
                            ? .regular.tint(.blue.opacity(0.5))
                            : .regular,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                }
                
                // Tool calls — GlassCode-style inline diff pills
                if let toolCalls = message.toolCalls {
                    ForEach(toolCalls) { toolCall in
                        ToolCallPillView(toolCall: toolCall)
                    }
                }
                
                // Attachments — inline images
                ForEach(message.attachments) { attachment in
                    if attachment.mimeType.starts(with: "image/") {
                        if let imageData = Data(base64Encoded: attachment.data),
                           let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.caption)
                            Text(attachment.filename)
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                // "Worked for Xm Ys" timing badge (assistant only, non-streaming)
                if message.role == .assistant && !message.isStreaming && !message.content.isEmpty {
                    WorkedForBadge(timestamp: message.timestamp)
                }
                
                // Streaming cursor
                if message.isStreaming {
                    StreamingDotsView()
                }
            }
            
            if message.role == .user {
                ZStack {
                    Circle()
                        .fill(.blue.opacity(0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.blue)
                }
                .padding(.top, 4)
            } else {
                Spacer(minLength: 80)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - "Worked for Xm Ys" Badge

struct WorkedForBadge: View {
    let timestamp: Date
    
    private var duration: String {
        let elapsed = Date().timeIntervalSince(timestamp)
        if elapsed < 2 { return "" }
        let mins = Int(elapsed) / 60
        let secs = Int(elapsed) % 60
        if mins > 0 {
            return "Worked for \(mins)m \(secs)s"
        }
        return "Worked for \(secs)s"
    }
    
    var body: some View {
        if !duration.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                Text(duration)
                    .font(.system(size: 10))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7))
            }
            .foregroundStyle(.secondary.opacity(0.7))
            .padding(.top, 2)
        }
    }
}

// MARK: - GlassCode-style Tool Call Pill

/// Inline pill that looks like GlassCode's "Edited ThanosDustEffect.swift +14 -5 >"
struct ToolCallPillView: View {
    let toolCall: Message.ToolCall
    @State private var isExpanded = false
    
    private var isFileEdit: Bool {
        ["write_file", "edit_file", "replace_file"].contains(toolCall.name)
    }
    
    private var filename: String {
        // Extract filename from arguments JSON
        if let data = toolCall.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let path = json["path"] as? String ?? json["file_path"] as? String ?? json["filename"] as? String {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return toolCall.name
    }
    
    /// Parse additions/deletions from the tool result if available
    private var diffStats: (additions: Int, deletions: Int)? {
        guard let result = toolCall.result else { return nil }
        // Try to find +N -M patterns in the result
        let addPattern = try? NSRegularExpression(pattern: #"\+(\d+)"#)
        let delPattern = try? NSRegularExpression(pattern: #"\-(\d+)"#)
        let range = NSRange(result.startIndex..., in: result)
        
        let adds = addPattern?.firstMatch(in: result, range: range)
            .flatMap { Range($0.range(at: 1), in: result) }
            .flatMap { Int(result[$0]) } ?? 0
        let dels = delPattern?.firstMatch(in: result, range: range)
            .flatMap { Range($0.range(at: 1), in: result) }
            .flatMap { Int(result[$0]) } ?? 0
        
        return (adds > 0 || dels > 0) ? (adds, dels) : nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Status dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    
                    // Icon + label
                    if isFileEdit {
                        Text("Edited")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(filename)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.blue)
                    } else {
                        Image(systemName: toolIcon)
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                        Text(toolCall.name.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    
                    // +/- badges
                    if let stats = diffStats {
                        if stats.additions > 0 {
                            Text("+\(stats.additions)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if stats.deletions > 0 {
                            Text("-\(stats.deletions)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            // Expanded: show result
            if isExpanded, let result = toolCall.result {
                Divider().opacity(0.2).padding(.horizontal, 12)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(result.prefix(800))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(maxHeight: 150)
            }
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
    }
    
    private var statusColor: Color {
        switch toolCall.status {
        case .pending: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private var toolIcon: String {
        switch toolCall.name {
        case "read_file": return "doc.text.fill"
        case "list_directory": return "folder.fill"
        case "search_files": return "magnifyingglass"
        case "run_command": return "terminal.fill"
        case "generate_image": return "photo.fill"
        case "git": return "arrow.triangle.branch"
        default: return "puzzlepiece.fill"
        }
    }
}

// MARK: - Custom Markdown Theme

extension MarkdownUI.Theme {
    /// Dark theme matching the Nvidia AI Studio aesthetic.
    @MainActor static let nvidia = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            ForegroundColor(Color(red: 0.4, green: 0.85, blue: 0.55))
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                if let language = configuration.language, !language.isEmpty {
                    Text(language)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(13)
                            ForegroundColor(Color(red: 0.4, green: 0.85, blue: 0.55))
                        }
                        .padding(12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                }
                .padding(.bottom, 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17)
                }
                .padding(.bottom, 2)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 2, bottom: 2)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 3)
                
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                        FontSize(14)
                    }
                    .padding(.leading, 12)
            }
            .padding(.vertical, 4)
        }
}

// MARK: - Sub-views

/// Animated dots while streaming
struct StreamingDotsView: View {
    @State private var animate = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.blue.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .offset(y: animate ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .padding(.leading, 14)
        .onAppear { animate = true }
    }
}

struct ReasoningView: View {
    let content: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile.fill")
                        .font(.caption2)
                    Text("Thinking")
                        .font(.caption2)
                        .fontWeight(.medium)
                    
                    if !isExpanded {
                        Text("(\(content.count) characters)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.orange.opacity(0.8))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
    }
}
