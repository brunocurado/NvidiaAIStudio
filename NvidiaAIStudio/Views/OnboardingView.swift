import SwiftUI

/// First-launch onboarding flow.
/// Shows once when the user has no API keys configured.
/// Guides through: welcome → choose provider → add key → done.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool

    @State private var step: Step = .welcome
    @State private var selectedProvider: Provider = .nvidia
    @State private var apiKeyInput = ""
    @State private var isValidating = false
    @State private var validationError: String? = nil

    enum Step { case welcome, chooseProvider, addKey, done }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.12)
                .ignoresSafeArea()
            Color.clear
                .glassEffect(.regular, in: .rect)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(stepIndex >= i ? Color.blue : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                            .animation(.easeInOut, value: stepIndex)
                    }
                }
                .padding(.top, 40)

                Spacer()

                Group {
                    switch step {
                    case .welcome:        welcomeStep
                    case .chooseProvider: chooseProviderStep
                    case .addKey:         addKeyStep
                    case .done:           doneStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                HStack(spacing: 12) {
                    if step != .welcome {
                        Button("Back") { withAnimation { goBack() } }
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    if step == .done {
                        Button("Get Started") {
                            withAnimation { isPresented = false }
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    } else if step == .addKey {
                        if isValidating {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Connect & Continue") { validateAndNext() }
                                .buttonStyle(.borderedProminent)
                                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .keyboardShortcut(.defaultAction)
                        }
                    } else {
                        Button("Continue") { withAnimation { goNext() } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.bottom, 40)
            }
        }
        .frame(width: 560, height: 520)
    }

    // MARK: - Steps

    @ViewBuilder
    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse)

            Text("Welcome to\nNvidia AI Studio")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("A native macOS AI coding assistant with access to your filesystem, GitHub, and the world's best AI models.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 24) {
                FeaturePill(icon: "brain.fill",            label: "16+ AI Models")
                FeaturePill(icon: "folder.fill",           label: "File Access")
                FeaturePill(icon: "arrow.triangle.branch", label: "Git + GitHub")
            }
        }
        .padding(.horizontal, 48)
    }

    @ViewBuilder
    private var chooseProviderStep: some View {
        VStack(spacing: 20) {
            Text("Choose your AI Provider")
                .font(.title2)
                .fontWeight(.bold)

            Text("You can add more providers later in Settings → API Keys.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach([Provider.nvidia, .anthropic, .openai], id: \.self) { p in
                    ProviderRow(
                        provider: p,
                        isSelected: selectedProvider == p,
                        onSelect: { selectedProvider = p }
                    )
                }
            }
            .padding(.horizontal, 40)
        }
        .padding(.horizontal, 48)
    }

    @ViewBuilder
    private var addKeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: selectedProvider.icon)
                .font(.system(size: 40))
                .foregroundStyle(.blue)

            Text("Add your \(selectedProvider.rawValue) API Key")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                switch selectedProvider {
                case .nvidia:
                    instructionRow("1", "Go to build.nvidia.com")
                    instructionRow("2", "Sign in and click your profile → API Keys")
                    instructionRow("3", "Generate a key starting with nvapi-")
                    Link("Open NVIDIA NIM →", destination: URL(string: "https://build.nvidia.com")!)
                        .font(.caption)
                        .padding(.top, 4)
                case .anthropic:
                    instructionRow("1", "Go to console.anthropic.com")
                    instructionRow("2", "Navigate to API Keys")
                    instructionRow("3", "Create a key starting with sk-ant-")
                    Link("Open Anthropic Console →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                        .font(.caption)
                        .padding(.top, 4)
                case .openai:
                    instructionRow("1", "Go to platform.openai.com")
                    instructionRow("2", "Navigate to API Keys")
                    instructionRow("3", "Create a key starting with sk-")
                    Link("Open OpenAI Platform →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                        .padding(.top, 4)
                case .custom:
                    instructionRow("1", "Enter your custom API key below")
                }
            }
            .padding(12)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 40)

            SecureField("Paste your API key here", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 40)

            if let err = validationError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var doneStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .symbolEffect(.bounce)

            Text("You're all set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Your API key has been saved securely in the macOS Keychain.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                TipRow(icon: "folder.badge.plus", text: "Open a workspace from the sidebar to give the AI context about your project")
                TipRow(icon: "sparkles",          text: "Enable Skills to let the AI read/write files, run commands, and use git")
                TipRow(icon: "arrow.up.circle",   text: "Use Commit & Push in the toolbar to push changes to GitHub")
            }
            .padding(.horizontal, 40)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - Helpers

    private var stepIndex: Int {
        switch step {
        case .welcome:        return 0
        case .chooseProvider: return 1
        case .addKey:         return 2
        case .done:           return 3
        }
    }

    private func goNext() {
        switch step {
        case .welcome:        step = .chooseProvider
        case .chooseProvider: step = .addKey
        case .addKey:         step = .done
        case .done:           isPresented = false
        }
    }

    private func goBack() {
        switch step {
        case .chooseProvider: step = .welcome
        case .addKey:         step = .chooseProvider
        case .done:           step = .addKey
        default: break
        }
    }

    private func validateAndNext() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isValidating = true
        validationError = nil

        Task {
            do {
                let service = ProviderServiceFactory.make(provider: selectedProvider, apiKey: key)
                _ = try await service.validateKey()
                await MainActor.run {
                    let apiKey = APIKey(provider: selectedProvider, name: selectedProvider.rawValue, key: key)
                    appState.apiKeys.append(apiKey)
                    appState.saveAPIKeys()
                    appState.switchProvider(selectedProvider)
                    isValidating = false
                    withAnimation { step = .done }
                }
            } catch {
                await MainActor.run {
                    let apiKey = APIKey(provider: selectedProvider, name: selectedProvider.rawValue, key: key)
                    appState.apiKeys.append(apiKey)
                    appState.saveAPIKeys()
                    appState.switchProvider(selectedProvider)
                    isValidating = false
                    withAnimation { step = .done }
                }
            }
        }
    }

    private func instructionRow(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num + ".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sub-components

private struct FeaturePill: View {
    let icon: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProviderRow: View {
    let provider: Provider
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.rawValue)
                        .fontWeight(.medium)
                    Text(providerDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(
                isSelected
                    ? Color.blue.opacity(0.12)
                    : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var providerDescription: String {
        switch provider {
        case .nvidia:    return "Free tier available · DeepSeek, Kimi, Qwen, Llama"
        case .anthropic: return "Claude Opus, Sonnet, Haiku · Best reasoning"
        case .openai:    return "GPT-4o, o3, GPT-4.1 · Most popular"
        case .custom:    return "Any OpenAI-compatible API"
        }
    }
}

private struct TipRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
