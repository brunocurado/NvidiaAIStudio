import SwiftUI
import AppKit

/// Floating input area at the bottom of the chat view.
/// Uses a custom NSTextView wrapper for proper Shift+Enter support and paste performance.
struct InputAreaView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var pendingAttachments: [Message.Attachment] = []
    @State private var editorHeight: CGFloat = 22
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Attachment previews
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            AttachmentPreview(attachment: attachment) {
                                pendingAttachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                }
                
                // Vision warning
                if let model = appState.selectedModel, !model.supportsVision,
                   pendingAttachments.contains(where: { $0.mimeType.starts(with: "image/") }) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Current model doesn't support vision — images will be analyzed by the Vision Delegate")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                }
            }
            
            // Text input
            HStack(alignment: .bottom, spacing: 8) {
                // Attach button
                Button { openFilePicker() } label: {
                    Image(systemName: "plus")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Attach files")
                
                // Altura controlada por @State — o NSTextView reporta a altura real
                // via onHeightChange e o SwiftUI aplica-a diretamente, sem conflitos
                ChatTextEditor(
                    text: $inputText,
                    onSubmit: { sendMessage() },
                    isFocused: _isFocused,
                    onHeightChange: { h in
                        editorHeight = min(h, 300)
                    }
                )
                .frame(height: editorHeight)
                
                // Send / Stop button
                Button {
                    if viewModel.isStreaming {
                        viewModel.stopStreaming()
                    } else {
                        sendMessage()
                    }
                } label: {
                    Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(inputText.isEmpty && !viewModel.isStreaming ? Color.secondary : Color.white)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty && !viewModel.isStreaming)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
                .opacity(0.3)
            
            // Bottom toolbar: Model, Reasoning, Access, Branch, Context
            HStack(spacing: 12) {
                // Model picker
                Menu {
                    ForEach(appState.availableModels.filter(\.isEnabled)) { model in
                        Button {
                            appState.selectedModelID = model.id
                        } label: {
                            HStack {
                                Text(model.name)
                                if model.id == appState.selectedModelID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu.fill")
                            .font(.caption2)
                        Text(shortModelName)
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Reasoning level
                if appState.selectedModel?.supportsThinking == true {
                    Menu {
                        ForEach(ReasoningLevel.allCases, id: \.self) { level in
                            Button {
                                appState.reasoningLevel = level
                            } label: {
                                HStack {
                                    Text(level.rawValue)
                                    if level == appState.reasoningLevel {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "brain")
                                .font(.caption2)
                            Text(appState.reasoningLevel.rawValue)
                                .font(.caption)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                // File access level
                Menu {
                    ForEach(FileAccessLevel.allCases, id: \.self) { level in
                        Button {
                            appState.fileAccessLevel = level
                        } label: {
                            HStack {
                                Text(level.rawValue)
                                if level == appState.fileAccessLevel {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: appState.fileAccessLevel.icon)
                            .font(.caption2)
                        Text(appState.fileAccessLevel.rawValue)
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                Spacer()
                
                // Git branch — clicável, mostra branches disponíveis
                Menu {
                    if appState.availableBranches.isEmpty {
                        Text("No git repo in workspace")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.availableBranches, id: \.self) { branch in
                            Button {
                                appState.checkoutBranch(branch)
                            } label: {
                                HStack {
                                    Text(branch)
                                    if branch == appState.currentBranch {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Refresh branches") {
                            appState.refreshGitBranch()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(appState.currentBranch)
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .onAppear { appState.refreshGitBranch() }
                
                // Context usage ring
                ContextIndicatorView(usage: viewModel.contextUsage)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isFocused = true
            }
        }
    }
    
    private var shortModelName: String {
        guard let model = appState.selectedModel else { return "Model" }
        let name = model.name
        let cleaned = name.drop(while: { !$0.isLetter && !$0.isNumber })
        let parts = cleaned.split(separator: "—").first ?? Substring(cleaned)
        return String(parts).trimmingCharacters(in: .whitespaces)
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        let attachments = pendingAttachments
        inputText = ""
        pendingAttachments = []
        editorHeight = 22
        
        Task {
            await viewModel.sendMessage(text, attachments: attachments, appState: appState)
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .image, .plainText, .sourceCode, .json, .pdf
        ]
        
        guard panel.runModal() == .OK else { return }
        
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let filename = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            
            var mimeType: String
            switch ext {
            case "png": mimeType = "image/png"
            case "jpg", "jpeg": mimeType = "image/jpeg"
            case "gif": mimeType = "image/gif"
            case "webp": mimeType = "image/webp"
            case "pdf": mimeType = "application/pdf"
            case "json": mimeType = "application/json"
            default: mimeType = "text/plain"
            }
            
            let base64 = data.base64EncodedString()
            let attachment = Message.Attachment(
                filename: filename,
                mimeType: mimeType,
                data: base64
            )
            pendingAttachments.append(attachment)
        }
    }
}

/// Removable thumbnail preview for a pending attachment.
struct AttachmentPreview: View {
    let attachment: Message.Attachment
    let onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if attachment.mimeType.starts(with: "image/"),
               let imageData = Data(base64Encoded: attachment.data),
               let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.title3)
                    Text(attachment.filename)
                        .font(.system(size: 8))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .background(Circle().fill(.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }
}

// MARK: - Custom NSTextView wrapper for Enter/Shift+Enter and paste performance

/// A performant text editor that:
/// - Sends on Enter (calls onSubmit)
/// - Inserts newline on Shift+Enter
/// - Handles large paste efficiently (native NSTextView, no SwiftUI layout thrashing)
struct ChatTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    @FocusState var isFocused: Bool
    var onHeightChange: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        let textView = ChatNSTextView()
        textView.delegate = context.coordinator
        textView.onHeightChange = onHeightChange
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        
        // Placeholder
        textView.placeholderString = "Message this thread..."
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChatNSTextView else { return }
        
        // Only update if text changed externally (e.g., cleared after send)
        if textView.string != text {
            textView.string = text
        }
        
        if isFocused {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? ChatNSTextView else { return }
            text = tv.string
            // Reporta a altura calculada ao SwiftUI no ciclo seguinte
            DispatchQueue.main.async {
                let h = tv.calculatedHeight()
                tv.onHeightChange?(h)
            }
        }
    }
}

/// Custom NSTextView that intercepts Enter vs Shift+Enter.
class ChatNSTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onHeightChange: ((CGFloat) -> Void)?
    var placeholderString: String = ""

    func calculatedHeight() -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else { return 22 }
        lm.ensureLayout(for: tc)
        let h = lm.usedRect(for: tc).height + textContainerInset.height * 2
        return max(h, 22)
    }
    
    override func keyDown(with event: NSEvent) {
        // Enter key (Return)
        if event.keyCode == 36 {
            if event.modifierFlags.contains(.shift) {
                // Shift+Enter: insert newline
                insertNewline(nil)
            } else {
                // Enter: submit message
                onSubmit?()
            }
            return
        }
        
        super.keyDown(with: event)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw placeholder when empty
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: font ?? .systemFont(ofSize: 14)
            ]
            let placeholder = NSAttributedString(string: placeholderString, attributes: attrs)
            placeholder.draw(at: NSPoint(
                x: textContainerInset.width + 5,
                y: textContainerInset.height
            ))
        }
    }
    
    override var intrinsicContentSize: NSSize {
        // Retorna noIntrinsicMetric — a altura é gerida pelo SwiftUI via onHeightChange
        return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

/// Circular context usage indicator (green → yellow → red).
struct ContextIndicatorView: View {
    let usage: Double // 0.0 to 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: 2.5)
            
            Circle()
                .trim(from: 0, to: usage)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: usage)
        }
        .frame(width: 20, height: 20)
        .help("Context: \(Int(usage * 100))%")
    }
    
    private var ringColor: Color {
        switch usage {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }
}
