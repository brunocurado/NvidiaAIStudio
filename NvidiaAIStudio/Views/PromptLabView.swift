import SwiftUI

/// Prompt Lab — a panel for refining rough ideas into production-ready prompts.
/// Uses the current model to generate the optimized prompt via Prompt Master system prompt.
struct PromptLabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appThemeID") private var appThemeID: String = "dark"

    @State private var userInput: String = ""
    @State private var generatedPrompt: String = ""
    @State private var isGenerating = false
    @State private var targetTool: String = "Auto-detect"
    @State private var showCopiedToast = false

    private var theme: AppTheme { AppTheme.find(id: appThemeID) }

    private let toolOptions = [
        "Auto-detect",
        "Claude / Claude Code",
        "ChatGPT / GPT-5.x",
        "Cursor / Windsurf",
        "Midjourney",
        "DALL-E 3",
        "Stable Diffusion",
        "Sora / Runway",
        "Gemini",
        "DeepSeek-R1",
        "Perplexity",
        "This App (Nvidia AI Studio)",
        "Other"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider().opacity(0.3)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Target tool picker
                    targetToolPicker
                    
                    // Input section
                    inputSection
                    
                    // Generate button
                    generateButton
                    
                    // Output section
                    if !generatedPrompt.isEmpty {
                        outputSection
                    }
                }
                .padding()
            }
            
            Divider().opacity(0.3)
            
            // Footer
            footerView
        }
        .frame(width: 560, height: 640)
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Prompt Lab").font(.headline)
                    Text("Transform rough ideas into optimized prompts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
    }
    
    // MARK: - Target Tool Picker
    
    private var targetToolPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Target Tool")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            Picker("", selection: $targetTool) {
                ForEach(toolOptions, id: \.self) { tool in
                    Text(tool).tag(tool)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Input Section
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Your Idea")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(userInput.count) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $userInput)
                    .font(.system(.body, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                
                if userInput.isEmpty {
                    Text("Describe what you need...\ne.g. \"Create an image of a futuristic city\" or \"Refactor auth module to use JWT\"")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 120)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Generate Button
    
    private var generateButton: some View {
        Button {
            Task { await generatePrompt() }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isGenerating ? "Generating..." : "Generate Prompt")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(
            LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
        )
        .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
    }
    
    // MARK: - Output Section
    
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("Optimized Prompt")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                
                if showCopiedToast {
                    Text("Copied!")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale))
                }
            }

            TextEditor(text: $generatedPrompt)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 180)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generatedPrompt, forType: .string)
                    withAnimation(.spring(duration: 0.3)) { showCopiedToast = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { showCopiedToast = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                
                Button {
                    useInChat()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                        Text("Use in Chat")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentColor)
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
                .font(.caption)
                .foregroundStyle(.purple.opacity(0.7))
            Text("Powered by Prompt Master · Prompts are editable before use")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
    
    // MARK: - Actions
    
    private func generatePrompt() async {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isGenerating = true
        generatedPrompt = ""
        
        defer { isGenerating = false }
        
        // Load the Prompt Master system prompt
        let skillContent = PromptMasterLoader.loadSkill()
        
        let systemMessage = Message(role: .system, content: skillContent)
        
        var userContent = userInput
        if targetTool != "Auto-detect" {
            userContent = "Target tool: \(targetTool)\n\n\(userInput)"
        }
        let userMessage = Message(role: .user, content: userContent)
        
        // Use the currently selected model and API key
        guard let model = appState.selectedModel,
              let apiKey = appState.activeAPIKey else {
            generatedPrompt = "⚠️ No model or API key selected. Configure in Settings."
            return
        }
        
        let service = NVIDIAAPIService(apiKey: apiKey)
        let stream = service.chat(
            messages: [systemMessage, userMessage],
            model: model,
            tools: nil,
            reasoningLevel: .off
        )
        
        do {
            for try await chunk in stream {
                if let content = chunk.content {
                    await MainActor.run {
                        generatedPrompt += content
                    }
                }
            }
        } catch {
            await MainActor.run {
                generatedPrompt = "⚠️ Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func useInChat() {
        guard !generatedPrompt.isEmpty else { return }
        
        // If no active session, create one
        if appState.activeSession == nil {
            _ = appState.createSession(title: "Prompt Lab")
        }
        
        // Add the generated prompt as a user message
        let message = Message(role: .user, content: generatedPrompt)
        appState.mutateActiveSession { session in
            session.messages.append(message)
        }
        
        // Dismiss the panel
        dismiss()
        
        appState.showToast("Prompt added to chat — press Send to execute", level: .info)
    }
}

// MARK: - Prompt Master Resource Loader

enum PromptMasterLoader {
    static func loadSkill() -> String {
        // SPM bundles resources under Bundle.module
        if let url = Bundle.module.url(forResource: "SKILL", withExtension: "md", subdirectory: "PromptMaster"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        
        // Fallback: try Bundle.main (for Xcode builds) and direct path
        let fallbackPaths = [
            Bundle.main.bundlePath + "/Contents/Resources/PromptMaster/SKILL.md",
            Bundle.main.bundlePath + "/Contents/Resources/NvidiaAIStudio_NvidiaAIStudio.bundle/PromptMaster/SKILL.md"
        ]
        
        for path in fallbackPaths {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content
            }
        }
        
        // Hardcoded minimal fallback
        return """
        You are a prompt engineer. Take the user's rough idea, identify the target AI tool, and output a single production-ready prompt optimized for that tool.
        
        Output format: 
        1. A single copyable prompt block
        2. 🎯 Target: [tool], 💡 [what was optimized]
        
        Rules: Be specific, add constraints, specify output format, add scope locks for code. Never add CoT to reasoning models.
        """
    }
}
