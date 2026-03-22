import SwiftUI

/// Settings view for managing API keys, models, theme, and app preferences.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        TabView {
            APIKeysSettingsView()
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }
            
            ModelsSettingsView()
                .tabItem {
                    Label("Models", systemImage: "cpu.fill")
                }
            
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape.fill")
                }
            
            GitHubSettingsView()
                .tabItem {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            
            SSHSettingsView()
                .tabItem {
                    Label("SSH", systemImage: "terminal.fill")
                }
        }
        .frame(width: 580, height: 540)
    }
}

// MARK: - API Keys Tab

struct APIKeysSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var newKeyProvider: Provider = .nvidia
    @State private var newKeyValue = ""
    @State private var newKeyName = ""
    @State private var isAdding = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Keys")
                .font(.headline)
            
            Text("Your keys are stored securely in the macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Existing keys
            if appState.apiKeys.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "key.slash.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No API keys configured")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ForEach(appState.apiKeys) { key in
                    HStack {
                        Image(systemName: key.provider.icon)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(key.name)
                                .font(.body)
                            Text(maskedKey(key.key))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { key.isActive },
                            set: { newValue in
                                if let idx = appState.apiKeys.firstIndex(where: { $0.id == key.id }) {
                                    appState.apiKeys[idx].isActive = newValue
                                }
                            }
                        ))
                        .labelsHidden()
                        
                        Button(role: .destructive) {
                            _ = KeychainHelper.deleteAPIKey(id: key.id)
                            appState.apiKeys.removeAll { $0.id == key.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Add new key
            if isAdding {
                VStack(spacing: 10) {
                    Picker("Provider", selection: $newKeyProvider) {
                        ForEach(Provider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    
                    TextField("Name (optional)", text: $newKeyName)
                    SecureField("API Key", text: $newKeyValue)
                    
                    HStack {
                        Button("Cancel") {
                            isAdding = false
                            newKeyValue = ""
                            newKeyName = ""
                        }
                        Spacer()
                        Button("Save") {
                            let apiKey = APIKey(
                                provider: newKeyProvider,
                                name: newKeyName,
                                key: newKeyValue
                            )
                            _ = KeychainHelper.saveAPIKey(apiKey)
                            appState.apiKeys.append(apiKey)
                            isAdding = false
                            newKeyValue = ""
                            newKeyName = ""
                        }
                        .disabled(newKeyValue.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button("Add API Key") {
                    isAdding = true
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func maskedKey(_ key: String) -> String {
        let visible = min(8, key.count)
        return String(key.prefix(visible)) + String(repeating: "•", count: max(0, key.count - visible))
    }
}

// MARK: - Models Tab

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState
    // Local snapshot — ForEach iterates this stable copy.
    // Changes are written back to appState immediately but the
    // list source never mutates mid-render, eliminating the crash.
    @State private var localModels: [AIModel] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Models")
                .font(.headline)

            Text("Select which models appear in the model picker. Preferences are saved automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach($localModels) { $model in
                        HStack {
                            Toggle(model.name, isOn: $model.isEnabled)
                                .onChange(of: model.isEnabled) { _, newValue in
                                    // Write-back to the global state + persist
                                    if let idx = appState.availableModels.firstIndex(where: { $0.id == model.id }) {
                                        appState.availableModels[idx].isEnabled = newValue
                                        appState.saveModelPreferences()
                                    }
                                }

                            Spacer()

                            if model.supportsThinking {
                                Image(systemName: "brain.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .help("Supports reasoning")
                            }
                            if model.supportsVision {
                                Image(systemName: "eye.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                                    .help("Supports vision")
                            }

                            Text("\(model.contextWindow / 1000)K")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Take a stable snapshot when the view appears
            localModels = appState.availableModels
        }
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("glassOpacity") private var glassOpacity: Double = 0.25
    @AppStorage("glassBlur") private var glassBlur: Double = 20.0
    @AppStorage("visionDelegateModelID") private var visionDelegateModelID = "nvidia/nemotron-nano-12b-v2-vl"
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Theme
                Text("Appearance")
                    .font(.headline)
                
                Picker("Theme", selection: $theme) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                // Glassmorphism sliders
                Divider()
                
                Text("Glassmorphism")
                    .font(.headline)
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Opacity")
                            .font(.caption)
                            .frame(width: 90, alignment: .leading)
                        // glassOpacity mapeia directamente para NSVisualEffectView.alphaValue
                        // 0 = totalmente transparente, 0.8 = opaco
                        // Slider: esquerda = transparente, direita = opaco
                        Slider(value: $glassOpacity, in: 0.0...0.8, step: 0.05)
                        Text("\(Int(glassOpacity / 0.8 * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 35)
                    }
                    
                    HStack {
                        Text("Frosted")
                            .font(.caption)
                            .frame(width: 90, alignment: .leading)
                        Slider(value: $glassBlur, in: 0.0...50.0, step: 2.0)
                        Text("\(Int(glassBlur))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 35)
                    }
                    
                    Text("Opacity 0% = fully transparent window. Higher frosted = more milky glass.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                
                // Vision Delegate
                Divider()
                
                Text("Vision Delegate")
                    .font(.headline)
                
                Text("When using a model without vision and attaching an image, this model will automatically analyze it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Vision Model", selection: $visionDelegateModelID) {
                    ForEach(appState.availableModels.filter { $0.supportsVision }) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .frame(width: 350)
                
                Spacer()
            }
            .padding()
        }
    }
}

// MARK: - GitHub Tab

struct GitHubSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var patInput = ""
    @State private var isValidatingPAT = false
    @State private var patError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("GitHub Integration")
                    .font(.headline)

                Text("Connect your GitHub account to clone repositories, commit and push directly from the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // ── Connected State ──
                if let username = appState.gitHubUsername {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connected as @\(username)")
                                .fontWeight(.semibold)
                            Text("Token stored securely in macOS Keychain")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") {
                            appState.disconnectGitHub()
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(.red)
                    }
                    .padding()
                    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.2)))

                    Text("You can now use 'Clone Repository' in the toolbar and 'Commit & Push' to interact with GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                } else {
                    // ── PAT Instructions ──
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Go to github.com/settings/tokens/new", systemImage: "1.circle.fill")
                            .font(.caption)
                        Label("Select scopes: repo and read:user", systemImage: "2.circle.fill")
                            .font(.caption)
                        Label("Click \"Generate token\" and paste it below", systemImage: "3.circle.fill")
                            .font(.caption)

                        Button {
                            NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:user&description=Nvidia+AI+Studio")!)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open GitHub → New Token")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                    // ── Token Input ──
                    HStack(spacing: 8) {
                        SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $patInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        if isValidatingPAT {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Connect") { validatePAT() }
                                .buttonStyle(.borderedProminent)
                                .disabled(patInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .keyboardShortcut(.defaultAction)
                        }
                    }

                    if let err = patError {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private func validatePAT() {
        let token = patInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        isValidatingPAT = true
        patError = nil
        Task {
            do {
                let username = try await GitHubService.shared.connectWithPAT(token)
                await MainActor.run {
                    appState.gitHubUsername = username
                    appState.gitHubToken = token
                    KeychainHelper.save(key: "github-oauth-token", string: token)
                    KeychainHelper.save(key: "github-username", string: username)
                    appState.showToast("GitHub connected as @\(username)", level: .success)
                    patInput = ""
                    isValidatingPAT = false
                }
            } catch {
                await MainActor.run {
                    patError = error.localizedDescription
                    isValidatingPAT = false
                }
            }
        }
    }
}

// MARK: - SSH Tab

struct SSHSettingsView: View {
    @AppStorage("sshHost") private var sshHost = ""
    @AppStorage("sshUser") private var sshUser = "root"
    @AppStorage("sshPort") private var sshPort = 22
    @AppStorage("sshKeyPath") private var sshKeyPath = "~/.ssh/id_rsa"
    @State private var testResult = ""
    @State private var isTesting = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SSH / VPS Connection")
                .font(.headline)
            
            Text("Configure SSH connection for remote command execution. The AI can run commands on your VPS using the ssh_command skill.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Form {
                TextField("Host", text: $sshHost, prompt: Text("192.168.1.100 or myserver.com"))
                TextField("Username", text: $sshUser)
                TextField("Port", value: $sshPort, format: .number)
                TextField("SSH Key Path", text: $sshKeyPath, prompt: Text("~/.ssh/id_rsa"))
            }
            .formStyle(.grouped)
            
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(sshHost.isEmpty || isTesting)
                
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }
            }
            
            if !testResult.isEmpty {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testResult.contains("✅") ? .green : .red)
                    .padding(.top, 4)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func testConnection() {
        isTesting = true
        testResult = ""
        
        Task {
            let result = await ShellHelper.run(
                "timeout 5 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -p \(sshPort) \(sshUser)@\(sshHost) 'echo connected' 2>&1"
            )
            
            await MainActor.run {
                isTesting = false
                if result.output.contains("connected") {
                    testResult = "✅ Connection successful!"
                } else {
                    testResult = "❌ Connection failed: \(result.output.isEmpty ? result.error : result.output)"
                }
            }
        }
    }
}
