import SwiftUI
import UniformTypeIdentifiers

/// Knowledge Base panel — drag & drop files, manage documents, trigger AI digestion.
struct KnowledgePanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isDragOver = false
    @State private var showFilePicker = false
    @State private var isDigesting = false
    @State private var showClearConfirm = false
    
    private var km: KnowledgeManager { appState.knowledgeManager }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider().opacity(0.3)
            
            if km.files.isEmpty {
                emptyState
            } else {
                // Stats bar
                statsBar
                
                Divider().opacity(0.2)
                
                // File list
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(km.files) { file in
                            FileRowView(file: file, onToggle: {
                                km.toggleFile(id: file.id)
                            }, onDelete: {
                                km.removeFile(id: file.id)
                            })
                        }
                    }
                    .padding(16)
                }
                
                Divider().opacity(0.3)
                
                // Action buttons
                actionBar
            }
        }
        .frame(width: 520, height: 600)
        .background(.ultraThinMaterial)
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.cyan, lineWidth: 2)
                    .fill(.cyan.opacity(0.05))
                    .padding(4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isDragOver)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: Self.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let accessed = urls.compactMap { url -> URL? in
                    guard url.startAccessingSecurityScopedResource() else { return nil }
                    return url
                }
                let _ = km.addFiles(accessed)
                accessed.forEach { $0.stopAccessingSecurityScopedResource() }
            }
        }
        .alert("Clear Knowledge Base?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) { km.clearAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all \(km.files.count) documents and their AI summaries. This cannot be undone.")
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "book.fill")
                        .font(.title3)
                        .foregroundStyle(.cyan)
                    Text("Knowledge Base")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                Text("Drop files to build your AI-powered reference library")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .foregroundStyle(.cyan.opacity(0.4))
                    .frame(height: 200)
                
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.cyan.opacity(0.6))
                    Text("Drop files here")
                        .font(.headline)
                        .fontWeight(.medium)
                    Text("PDF, TXT, Markdown, Swift, Python, and more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showFilePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Browse Files")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            
            VStack(spacing: 8) {
                Text("How it works")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 6) {
                    howItWorksRow(num: "1", text: "Drop your files (PDFs, docs, code)")
                    howItWorksRow(num: "2", text: "AI analyzes and creates structured summaries")
                    howItWorksRow(num: "3", text: "Ask questions — answers come from your documents")
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func howItWorksRow(num: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(num)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.cyan.opacity(0.6)))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Stats Bar
    
    private var statsBar: some View {
        HStack(spacing: 16) {
            statPill(icon: "doc.fill", value: "\(km.files.count)", label: "files")
            statPill(icon: "checkmark.circle.fill",
                     value: "\(km.completedCount)/\(km.files.count)",
                     label: "digested",
                     color: km.completedCount == km.files.count ? .green : .orange)
            statPill(icon: "text.word.spacing", value: "~\(formatTokens(km.estimatedTokens))", label: "tokens")
            
            Spacer()
            
            Button {
                showFilePicker = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            .help("Add files")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private func statPill(icon: String, value: String, label: String, color: Color = .cyan) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Action Bar
    
    private var actionBar: some View {
        HStack(spacing: 12) {
            if km.isDigesting {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing \(km.digestProgress.current)/\(km.digestProgress.total)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if km.pendingCount > 0 {
                Button {
                    startDigest()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "brain")
                        Text("Process \(km.pendingCount) files")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            } else if !km.files.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("All documents processed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if !km.files.isEmpty {
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear all files")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Helpers
    
    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else { return }
                
                DispatchQueue.main.async {
                    let _ = km.addFiles([url])
                }
            }
        }
    }
    
    private func startDigest() {
        guard let apiKey = appState.activeAPIKey ?? EnvParser.loadNVIDIAKey(),
              let model = appState.selectedModel
        else {
            appState.showToast("No API key or model selected", level: .error)
            return
        }
        
        let service = ProviderServiceFactory.make(
            provider: appState.activeProvider,
            apiKey: apiKey,
            customBaseURL: appState.apiKeys.first { $0.provider == appState.activeProvider && $0.isActive }?.customBaseURL
        )
        
        // Find vision model for PDF page analysis
        let visionModel = appState.availableModels.first { $0.supportsVision }
        
        Task {
            await km.digestAll(service: service, model: model, visionModel: visionModel)
            await MainActor.run {
                appState.showToast("Knowledge Base ready — \(km.completedCount) documents processed", level: .success)
            }
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
    
    // MARK: - Supported Types
    
    private static let supportedTypes: [UTType] = [
        .pdf, .plainText, .utf8PlainText, .sourceCode,
        .html, .xml, .json, .yaml,
        .png, .jpeg, .gif, .webP,
        .commaSeparatedText,
        UTType(filenameExtension: "md") ?? .plainText,
        UTType(filenameExtension: "swift") ?? .sourceCode,
        UTType(filenameExtension: "py") ?? .sourceCode,
        UTType(filenameExtension: "js") ?? .sourceCode,
        UTType(filenameExtension: "ts") ?? .sourceCode,
        UTType(filenameExtension: "rb") ?? .sourceCode,
        UTType(filenameExtension: "go") ?? .sourceCode,
        UTType(filenameExtension: "rs") ?? .sourceCode,
        UTType(filenameExtension: "rtf") ?? .plainText,
    ]
}

// MARK: - File Row

struct FileRowView: View {
    let file: KnowledgeFile
    let onToggle: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            // File icon
            Image(systemName: file.icon)
                .font(.system(size: 14))
                .foregroundStyle(statusColor)
                .frame(width: 20)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor)
                    
                    if file.pageCount > 0 {
                        Text("\(file.pageCount) pages")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("~\(file.estimatedTokens) tokens")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            // Processing indicator
            if file.digestStatus == .processing {
                ProgressView()
                    .scaleEffect(0.6)
            }
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { file.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .scaleEffect(0.7)
            .labelsHidden()
            
            // Delete
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? .white.opacity(0.05) : .clear)
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
    
    private var statusText: String {
        switch file.digestStatus {
        case .pending:    return "Pending"
        case .processing: return "Processing..."
        case .completed:  return "Ready"
        case .failed:     return "Failed"
        }
    }
    
    private var statusColor: Color {
        switch file.digestStatus {
        case .pending:    return .orange
        case .processing: return .blue
        case .completed:  return .green
        case .failed:     return .red
        }
    }
}
