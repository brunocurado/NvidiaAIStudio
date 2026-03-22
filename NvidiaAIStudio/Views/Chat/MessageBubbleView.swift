import SwiftUI
import MarkdownUI

/// A single message bubble in the chat.
struct MessageBubbleView: View {
    let message: Message
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 80)
            } else {
                // Assistant avatar
                Image(systemName: "cpu.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(width: 24, height: 24)
                    .background(.green.opacity(0.15), in: Circle())
                    .padding(.top, 4)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Reasoning/thinking (collapsible)
                if let reasoning = message.reasoning, !reasoning.isEmpty {
                    ReasoningView(content: reasoning)
                }
                
                // Content with Markdown rendering
                if !message.content.isEmpty {
                    Group {
                        if message.role == .assistant {
                            // Render markdown for assistant messages
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
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(message.role == .user
                                  ? Color.blue.opacity(0.6)
                                  : Color.white.opacity(0.08))
                    )
                    .foregroundStyle(message.role == .user ? Color.white : Color.primary)
                }
                
                // Tool calls
                if let toolCalls = message.toolCalls {
                    ForEach(toolCalls) { toolCall in
                        ToolCallView(toolCall: toolCall)
                    }
                }
                
                // Attachments
                ForEach(message.attachments) { attachment in
                    if attachment.mimeType.starts(with: "image/") {
                        if let imageData = Data(base64Encoded: attachment.data),
                           let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                // Streaming cursor
                if message.isStreaming {
                    StreamingDotsView()
                }
            }
            
            if message.role == .user {
                // User avatar
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .frame(width: 24, height: 24)
                    .background(.blue.opacity(0.15), in: Circle())
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 80)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Custom Markdown Theme

extension MarkdownUI.Theme {
    /// Dark theme matching the Nvidia AI Studio aesthetic.
    static let nvidia = Theme()
        .text {
            ForegroundColor(.primary)
            FontSize(14)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            ForegroundColor(Color(red: 0.4, green: 0.85, blue: 0.55)) // Green code text
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                // Code language label
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
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                    .frame(width: 6, height: 6)
                    .offset(y: animate ? -4 : 0)
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

struct ToolCallView: View {
    let toolCall: Message.ToolCall
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toolCall.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                
                if let result = toolCall.result {
                    Text(result.prefix(200))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
    }
    
    private var statusIcon: String {
        switch toolCall.status {
        case .pending: return "clock.fill"
        case .running: return "arrow.trianglehead.clockwise"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch toolCall.status {
        case .pending: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}
