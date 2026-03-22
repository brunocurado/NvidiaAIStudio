import SwiftUI

/// Main chat view with message list, background agent panel, and input area.
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ChatViewModel()
    @State private var showExportPanel = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let session = appState.activeSession {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(session.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                            
                            // Streaming indicator
                            if viewModel.isStreaming {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text(viewModel.streamingStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .id("streaming-indicator")
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onChange(of: session.messages.count) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            if let lastID = session.messages.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isStreaming) {
                        if viewModel.isStreaming {
                            proxy.scrollTo("streaming-indicator", anchor: .bottom)
                        }
                    }
                }
                
                // Background agents panel (floating card)
                if !session.backgroundAgents.isEmpty {
                    BackgroundAgentsPanelView(agents: session.backgroundAgents)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                
            } else {
                // Empty state
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)
                    Text("Nvidia AI Studio")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Start a new thread or select one from the sidebar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Button("New Thread") {
                        let _ = appState.createSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                Spacer()
            }
            
            // Input area (always visible)
            InputAreaView(viewModel: viewModel)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .toolbar {
            if appState.activeSession != nil {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showExportPanel = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export conversation")
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
        }
        .fileExporter(
            isPresented: $showExportPanel,
            document: ConversationDocument(session: appState.activeSession),
            contentType: .plainText,
            defaultFilename: appState.activeSession?.title ?? "conversation"
        ) { _ in }
    }
}

// MARK: - Export Document

import UniformTypeIdentifiers

struct ConversationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    let text: String

    init(session: Session?) {
        guard let session else { self.text = ""; return }
        var lines: [String] = []
        lines.append("# \(session.title)")
        lines.append("Exported: \(Date().formatted(date: .long, time: .shortened))")
        lines.append("")
        for msg in session.messages where msg.role != .system {
            switch msg.role {
            case .user:      lines.append("## You")
            case .assistant: lines.append("## Assistant")
            case .tool:      lines.append("## Tool Result")
            default: continue
            }
            lines.append(msg.content)
            lines.append("")
        }
        self.text = lines.joined(separator: "\n")
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8)!)
    }
}

/// Floating background agents panel (matches reference: "2 background agents").
struct BackgroundAgentsPanelView: View {
    let agents: [BackgroundAgent]
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                    Text("\(agents.count) background agents")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            
            // Agent list
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                VStack(spacing: 8) {
                    ForEach(agents) { agent in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(agentColor(agent.status))
                                .frame(width: 8, height: 8)
                            
                            Text(agent.name)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            
                            Text("(\(agent.task))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("is \(agent.status.rawValue.lowercased())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .italic()
                            
                            Spacer()
                            
                            Button("Open") {
                                // TODO: Open agent detail
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func agentColor(_ status: BackgroundAgent.AgentStatus) -> Color {
        switch status {
        case .thinking: return .orange
        case .running: return .blue
        case .reading: return .purple
        case .completed: return .green
        case .failed: return .red
        }
    }
}


