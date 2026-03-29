import SwiftUI

/// Main chat view with message list, background agent panel, and input area.
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ChatViewModel()
    @State private var showExportPanel = false
    @State private var showNewAgentSheet = false
    @State private var visibleMessageCount = 20
    @State private var isUserNearBottom = true
    
    var body: some View {
        VStack(spacing: 0) {
            if let session = appState.activeSession {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // "Load earlier messages" button
                            let totalMessages = session.messages.count
                            
                            if totalMessages > visibleMessageCount {
                                Button {
                                    withAnimation(.spring(duration: 0.3)) {
                                        visibleMessageCount += 20
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.up.circle")
                                            .font(.caption)
                                        Text("Load \(min(20, totalMessages - visibleMessageCount)) earlier messages")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 16)
                                    .background(.white.opacity(0.05), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 8)
                            }
                            
                            // LazyVStack — renders only visible messages for performance.
                            LazyVStack(spacing: 16) {
                                ForEach(Array(session.messages.suffix(visibleMessageCount))) { message in
                                    MessageBubbleView(message: message)
                                        .id(message.id)
                                }
                            }
                            
                            // Streaming status pill — outside LazyVStack so always visible
                            if viewModel.isStreaming {
                                HStack(spacing: 8) {
                                    ProgressView().scaleEffect(0.7)
                                    Text(viewModel.streamingStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 8)
                            }
                            
                            // Bottom anchor — OUTSIDE LazyVStack so always rendered
                            // Also serves as a visibility sentinel: when on-screen, user is "near bottom"
                            Color.clear
                                .frame(height: 1)
                                .id("bottom-anchor")
                                .onAppear { isUserNearBottom = true }
                                .onDisappear { isUserNearBottom = false }
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: session.messages.count) {
                        // Always scroll on new messages (user sent or assistant replied)
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.streamingStatus) {
                        guard viewModel.isStreaming, isUserNearBottom else { return }
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.isStreaming) {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.scrollTick) {
                        guard isUserNearBottom else { return }
                        scrollToBottom(proxy)
                    }
                    .onAppear {
                        scrollToBottom(proxy)
                    }
                    .onChange(of: session.id) {
                        visibleMessageCount = 20  // Reset on thread switch
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToBottom(proxy)
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
                        showNewAgentSheet = true
                    } label: {
                        Image(systemName: "person.fill.badge.plus")
                    }
                    .help("New Background Agent (⌘⇧A)")
                    .keyboardShortcut("a", modifiers: [.command, .shift])

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
        .sheet(isPresented: $showNewAgentSheet) {
            NewAgentSheet()
                .environment(appState)
        }
    }
    
    /// Smooth scroll to bottom — avoids abrupt jumps.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
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
    @Environment(AppState.self) private var appState
    let agents: [BackgroundAgent]
    @State private var isExpanded = true
    @State private var selectedAgentID: UUID? = nil
    @State private var showAgentDetail = false
    
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
                            
                            if agent.status == .thinking || agent.status == .running || agent.status == .reading {
                                Button("Stop") {
                                    appState.mutateActiveSession { session in
                                        if let idx = session.backgroundAgents.firstIndex(where: { $0.id == agent.id }) {
                                            session.backgroundAgents[idx].status = .failed
                                        }
                                    }
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                            }
                            
                            Button(agent.status == .completed || agent.status == .failed ? "Remove" : "Open") {
                                if agent.status == .completed || agent.status == .failed {
                                    appState.mutateActiveSession { session in
                                        session.backgroundAgents.removeAll { $0.id == agent.id }
                                    }
                                } else {
                                    selectedAgentID = agent.id
                                    showAgentDetail = true
                                }
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .sheet(isPresented: $showAgentDetail) {
            if let id = selectedAgentID {
                AgentDetailView(agentID: id)
                    .environment(appState)
            }
        }
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


