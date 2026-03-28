import SwiftUI

/// Main chat view with message list, background agent panel, and input area.
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ChatViewModel()
    @State private var showExportPanel = false
    @State private var showNewAgentSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let session = appState.activeSession {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            // LazyVStack — renders only visible messages for performance.
                            LazyVStack(spacing: 16) {
                                ForEach(session.messages) { message in
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
                            Color.clear
                                .frame(height: 1)
                                .id("bottom-anchor")
                        }
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: session.messages.count) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onChange(of: viewModel.streamingStatus) {
                        guard viewModel.isStreaming else { return }
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onChange(of: viewModel.isStreaming) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onChange(of: viewModel.scrollTick) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onAppear {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                    .onChange(of: session.id) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            proxy.scrollTo("bottom-anchor", anchor: .bottom)
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


