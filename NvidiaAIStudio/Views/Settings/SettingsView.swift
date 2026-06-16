import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appThemeID") private var appThemeID: String = "liquid_glass_dark"
    @State private var selectedTab: SettingsTab = .general
    @State private var window: NSWindow?
    
    private var theme: AppTheme { AppTheme.find(id: appThemeID) }
    
    var body: some View {
        ZStack {
            SettingsClearGlassBackdrop()

            VStack(spacing: 0) {
                SettingsTabBar(selectedTab: $selectedTab)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                selectedContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .macModalGlass(cornerRadius: 28)
        }
        .frame(width: 620, height: 560)
        .contentShape(Rectangle())
        .background(WindowAccessor(window: $window))
        .onChange(of: window) { _, w in
            guard let w = w else { return }
            AppWindowStyler.applyToSettings(to: w, colorScheme: theme.colorScheme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                AppWindowStyler.applyToSettings(to: w, colorScheme: theme.colorScheme)
            }
        }
        .onChange(of: theme) { _, newTheme in
            guard let w = window else { return }
            AppWindowStyler.applyToSettings(to: w, colorScheme: newTheme.colorScheme)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AppWindowStyler.applyToSettings(to: w, colorScheme: newTheme.colorScheme)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                AppWindowStyler.applyToSettings(to: w, colorScheme: newTheme.colorScheme)
            }
        }
        // Force the app to re-evaluate the primary text color against the environment to fix macOS caching bug
        .foregroundStyle(.primary)
        .preferredColorScheme(theme.colorScheme)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .apiKeys:
            APIKeysSettingsView()
        case .models:
            ModelsSettingsView()
        case .general:
            GeneralSettingsView()
        case .gitHub:
            GitHubSettingsView()
        case .mcp:
            MCPSettingsView()
        case .ssh:
            SSHSettingsView()
        }
    }
}

private struct SettingsClearGlassBackdrop: View {
    var body: some View {
        Color.clear
            .glassEffect(.clear, in: Rectangle())
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

private struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: 16) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 23, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .primary.opacity(0.72))
                    .frame(width: 62, height: 58)
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .macControlPill(isSelected: selectedTab == tab, cornerRadius: 11)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case apiKeys
    case models
    case general
    case gitHub
    case mcp
    case ssh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apiKeys: return "API Keys"
        case .models: return "Models"
        case .general: return "General"
        case .gitHub: return "GitHub"
        case .mcp: return "MCP"
        case .ssh: return "SSH"
        }
    }

    var systemImage: String {
        switch self {
        case .apiKeys: return "key.fill"
        case .models: return "cpu.fill"
        case .general: return "gearshape.fill"
        case .gitHub: return "chevron.left.forwardslash.chevron.right"
        case .mcp: return "puzzlepiece.extension.fill"
        case .ssh: return "terminal.fill"
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.window = view.window }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { self.window = nsView.window }
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
            Text("API Keys").font(.headline)
            Text("Your keys are stored securely in the macOS Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            
            if appState.apiKeys.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "key.slash.fill").font(.largeTitle).foregroundStyle(.tertiary)
                        Text("No API keys configured").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ForEach(appState.apiKeys) { key in
                    HStack {
                        Image(systemName: key.provider.icon).foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text(key.name).font(.body)
                            Text(maskedKey(key.key)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { key.isActive },
                            set: { newValue in
                                if let idx = appState.apiKeys.firstIndex(where: { $0.id == key.id }) {
                                    appState.apiKeys[idx].isActive = newValue
                                    appState.saveAPIKeys()
                                }
                            }
                        )).labelsHidden()
                        Button(role: .destructive) {
                            KeychainHelper.deleteAPIKey(id: key.id)
                            appState.apiKeys.removeAll { $0.id == key.id }
                            appState.saveAPIKeys()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            if isAdding {
                VStack(spacing: 10) {
                    Picker("Provider", selection: $newKeyProvider) {
                        ForEach(Provider.allCases) { p in Text(p.rawValue).tag(p) }
                    }
                    TextField("Name (optional)", text: $newKeyName)
                    SecureField("API Key", text: $newKeyValue)
                    HStack {
                        Button("Cancel") { isAdding = false; newKeyValue = ""; newKeyName = "" }
                        Spacer()
                        Button("Save") {
                            let apiKey = APIKey(provider: newKeyProvider, name: newKeyName, key: newKeyValue)
                            appState.apiKeys.append(apiKey)
                            appState.saveAPIKeys()
                            isAdding = false; newKeyValue = ""; newKeyName = ""
                        }
                        .disabled(newKeyValue.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button("Add API Key") { isAdding = true }
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

struct IdentifiableString: Identifiable {
    let id: String
}

// MARK: - Models Tab

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var localModels: [AIModel] = []
    @State private var editingModelID: String? = nil
    @State private var customContextInput: String = ""

    private func updateModelContextWindow(id: String, newContext: Int) {
        if let idx = appState.availableModels.firstIndex(where: { $0.id == id }) {
            appState.availableModels[idx].contextWindow = newContext
            appState.saveModelPreferences()
        }
        if let idx = localModels.firstIndex(where: { $0.id == id }) {
            localModels[idx].contextWindow = newContext
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Models").font(.headline)
            Text("Select which models appear in the model picker. Preferences are saved automatically.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach($localModels) { $model in
                        HStack {
                            Toggle(model.name, isOn: $model.isEnabled)
                                .onChange(of: model.isEnabled) { _, newValue in
                                    if let idx = appState.availableModels.firstIndex(where: { $0.id == model.id }) {
                                        appState.availableModels[idx].isEnabled = newValue
                                        appState.saveModelPreferences()
                                    }
                                }
                            Spacer()
                            if model.supportsThinking {
                                Image(systemName: "brain.fill").font(.caption2).foregroundStyle(.orange).help("Supports reasoning")
                            }
                            if model.supportsVision {
                                Image(systemName: "eye.fill").font(.caption2).foregroundStyle(.purple).help("Supports vision")
                            }
                            
                            Menu {
                                Button("8K") { updateModelContextWindow(id: model.id, newContext: 8_192) }
                                Button("16K") { updateModelContextWindow(id: model.id, newContext: 16_384) }
                                Button("32K") { updateModelContextWindow(id: model.id, newContext: 32_768) }
                                Button("128K") { updateModelContextWindow(id: model.id, newContext: 128_000) }
                                Button("256K") { updateModelContextWindow(id: model.id, newContext: 262_144) }
                                Button("1M") { updateModelContextWindow(id: model.id, newContext: 1_000_000) }
                                Button("2M") { updateModelContextWindow(id: model.id, newContext: 2_000_000) }
                                
                                Divider()
                                
                                Button("Personalizado...") {
                                    customContextInput = "\(model.contextWindow / 1000)"
                                    editingModelID = model.id
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    let kTokens: String = {
                                        if model.contextWindow >= 1_000_000 {
                                            let millions = Double(model.contextWindow) / 1_000_000.0
                                            let formatted = String(format: "%.1f", millions)
                                            return formatted.hasSuffix(".0") ? "\(model.contextWindow / 1_000_000)M" : "\(formatted)M"
                                        } else {
                                            return "\(model.contextWindow / 1000)K"
                                        }
                                    }()
                                    Text(kTokens)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .opacity(0.6)
                                }
                                .contentShape(Rectangle())
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .onAppear { localModels = appState.availableModels }
        .popover(item: Binding(
            get: { editingModelID.map { IdentifiableString(id: $0) } },
            set: { editingModelID = $0?.id }
        )) { ident in
            VStack(alignment: .leading, spacing: 12) {
                Text("Editar Janela de Contexto")
                    .font(.headline)
                
                Text("Introduza o valor em milhares de tokens (ex: 128 para 128K, 1000 para 1M):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 250, alignment: .leading)
                
                HStack {
                    TextField("Ex: 128", text: $customContextInput)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("K Tokens")
                        .font(.body)
                }
                
                HStack {
                    Button("Cancelar") {
                        editingModelID = nil
                    }
                    Spacer()
                    Button("Guardar") {
                        let cleanInput = customContextInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let kValue = Int(cleanInput) {
                            updateModelContextWindow(id: ident.id, newContext: kValue * 1000)
                        }
                        editingModelID = nil
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 280)
        }
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @AppStorage("appThemeID") private var appThemeID: String = "liquid_glass_dark"
    @AppStorage("glassOpacity") private var glassOpacity: Double = 0.25
    @AppStorage("glassBlur") private var glassBlur: Double = 20.0
    @AppStorage("visionDelegateModelID") private var visionDelegateModelID = "nvidia/nemotron-nano-12b-v2-vl"
    @AppStorage("selectedImageModelID") private var selectedImageModelID = "flux.2-klein-4b"
    @Environment(AppState.self) private var appState
    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 8)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Appearance").font(.headline)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(AppTheme.all) { t in
                        ThemeCard(theme: t, isSelected: appThemeID == t.id)
                            .onTapGesture { appThemeID = t.id }
                    }
                }
                Divider()
                Text("Background Tint").font(.headline)
                VStack(spacing: 12) {
                    HStack {
                        Text("Opacity").font(.caption).frame(width: 90, alignment: .leading)
                        Slider(value: $glassOpacity, in: 0.0...0.8, step: 0.05)
                        Text("\(Int(glassOpacity / 0.8 * 100))%").font(.caption).foregroundStyle(.secondary).frame(width: 35)
                    }
                    HStack {
                        Text("Frosted").font(.caption).frame(width: 90, alignment: .leading)
                        Slider(value: $glassBlur, in: 0.0...50.0, step: 2.0)
                        Text("\(Int(glassBlur))").font(.caption).foregroundStyle(.secondary).frame(width: 35)
                    }
                    Text("Opacity controls the theme colour intensity. Frosted adds a subtle light wash that the Liquid Glass refracts.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Divider()
                Text("Vision Delegate").font(.headline)
                Text("When using a model without vision and attaching an image, this model will automatically analyze it.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Vision Model", selection: $visionDelegateModelID) {
                    ForEach(appState.availableModels.filter { $0.supportsVision }) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .frame(width: 350)
                
                Divider()
                Text("Geração de Imagem").font(.headline)
                Text("Selecione o modelo predefinido utilizado pela skill generate_image.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Modelo de Imagem", selection: $selectedImageModelID) {
                    ForEach(ImageModel.availableImageModels) { model in
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
                Text("GitHub Integration").font(.headline)
                Text("Connect your GitHub account to clone repositories, commit and push directly from the app.")
                    .font(.caption).foregroundStyle(.secondary)

                if let username = appState.gitHubUsername {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Connected as @\(username)").fontWeight(.semibold)
                            Text("Token stored securely in macOS Keychain").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Disconnect") { appState.disconnectGitHub() }
                            .buttonStyle(.bordered).foregroundStyle(.red)
                    }
                    .padding()
                    .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.2)))
                    Text("You can now use 'Clone Repository' in the toolbar and 'Commit & Push' to interact with GitHub.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Go to github.com/settings/tokens/new", systemImage: "1.circle.fill").font(.caption)
                        Label("Select scopes: repo and read:user", systemImage: "2.circle.fill").font(.caption)
                        Label("Click \"Generate token\" and paste it below", systemImage: "3.circle.fill").font(.caption)
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://github.com/settings/tokens/new?scopes=repo,read:user&description=Nvidia+AI+Studio")!)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open GitHub → New Token")
                            }.font(.caption)
                        }
                        .buttonStyle(.bordered).padding(.top, 4)
                    }
                    .foregroundStyle(.secondary).padding(12)
                    .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $patInput)
                            .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
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
                        Label(err, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red)
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
        isValidatingPAT = true; patError = nil
        Task {
            do {
                let username = try await GitHubService.shared.connectWithPAT(token)
                await MainActor.run {
                    appState.gitHubUsername = username; appState.gitHubToken = token
                    KeychainHelper.save(key: "github-oauth-token", string: token)
                    KeychainHelper.save(key: "github-username", string: username)
                    appState.showToast("GitHub connected as @\(username)", level: .success)
                    patInput = ""; isValidatingPAT = false
                }
            } catch {
                await MainActor.run { patError = error.localizedDescription; isValidatingPAT = false }
            }
        }
    }
}

// MARK: - MCP Settings Tab

struct MCPSettingsView: View {
    @State private var manager = MCPManager.shared
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MCP Servers").font(.headline)
                    Text("Connect external tools via Model Context Protocol.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showAddSheet = true } label: { Label("Add Server", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }

            if manager.serverConfigs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "puzzlepiece.extension").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("No MCP servers configured").foregroundStyle(.secondary)
                    Text("Add a server to give the AI access to databases, calendars, APIs, and more.")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(manager.serverConfigs) { config in MCPServerRow(config: config) }
                    }
                }
            }

            if manager.totalToolCount > 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(manager.totalToolCount) tools available to the AI").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showAddSheet) { AddMCPServerSheet(isPresented: $showAddSheet) }
    }
}

struct MCPServerRow: View {
    let config: MCPServerConfig
    @State private var manager = MCPManager.shared

    private var connection: MCPConnection? {
        manager.connections.first { $0.id == config.id }
    }

    @State private var showingEditSheet = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name).font(.body).fontWeight(.medium)
                Text(config.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                
                if let conn = connection {
                    if case .failed = conn.status, let err = conn.lastError {
                        Text(err).font(.caption).foregroundStyle(.red).lineLimit(2)
                    } else if !conn.discoveredTools.isEmpty {
                        Text("\(conn.discoveredTools.count) tools").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { manager.toggleServer(id: config.id, enabled: $0) }
            )).labelsHidden()
            Button { showingEditSheet = true } label: {
                Image(systemName: "pencil").font(.caption)
            }.buttonStyle(.borderless)
            Button(role: .destructive) { manager.removeServer(id: config.id) } label: {
                Image(systemName: "trash").font(.caption)
            }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 8))
        .sheet(isPresented: $showingEditSheet) {
            AddMCPServerSheet(isPresented: $showingEditSheet, editingConfig: config)
        }
    }

    private var statusColor: Color {
        switch connection?.status {
        case .connected:  return .green
        case .connecting: return .orange
        case .failed:     return .red
        default:          return config.isEnabled ? .orange : .gray
        }
    }
}

struct AddMCPServerSheet: View {
    @Binding var isPresented: Bool
    var editingConfig: MCPServerConfig? = nil

    @State private var manager = MCPManager.shared
    @State private var name = ""
    @State private var transportType = 0
    @State private var command = "npx"
    @State private var args = "-y @modelcontextprotocol/server-filesystem ~/projects"
    @State private var sseURL = "http://localhost:3000/sse"
    @State private var envText = ""

    private let presets: [(name: String, command: String, args: String)] = [
        ("Filesystem",   "npx", "-y @modelcontextprotocol/server-filesystem ~/projects"),
        ("Git",          "npx", "-y @modelcontextprotocol/server-git"),
        ("GitHub",       "npx", "-y @modelcontextprotocol/server-github"),
        ("Postgres",     "npx", "-y @modelcontextprotocol/server-postgres postgresql://localhost/mydb"),
        ("Brave Search", "npx", "-y @modelcontextprotocol/server-brave-search"),
        ("Puppeteer",    "npx", "-y @modelcontextprotocol/server-puppeteer"),
        ("Memory",       "npx", "-y @modelcontextprotocol/server-memory"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editingConfig == nil ? "Add MCP Server" : "Edit MCP Server").font(.headline)
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quick Add").font(.subheadline).fontWeight(.semibold)
                        Text("Puppeteer enables full browser automation for JavaScript-heavy pages (SPAs, Twitter, LinkedIn).")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                        ForEach(presets, id: \.name) { preset in
                            Button {
                                name = preset.name; command = preset.command
                                args = preset.args; transportType = 0
                            } label: {
                                Text(preset.name).font(.caption).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    Divider()
                    TextField("Server name", text: $name).textFieldStyle(.roundedBorder)
                    Picker("Transport", selection: $transportType) {
                        Text("stdio (local process)").tag(0)
                        Text("SSE (remote URL)").tag(1)
                    }.pickerStyle(.segmented)

                    if transportType == 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Command").font(.caption).foregroundStyle(.secondary)
                            TextField("npx / node / python", text: $command)
                                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                            Text("Arguments").font(.caption).foregroundStyle(.secondary)
                            TextField("-y @modelcontextprotocol/server-filesystem ~/projects", text: $args)
                                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                            
                            Text("Environment Variables").font(.caption).foregroundStyle(.secondary)
                            TextEditor(text: $envText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(height: 60)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                            Text("One per line. Format: KEY=VALUE").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SSE URL").font(.caption).foregroundStyle(.secondary)
                            TextField("http://localhost:3000/sse", text: $sseURL)
                                .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                        }
                    }

                    HStack {
                        Spacer()
                        Button(editingConfig == nil ? "Add & Connect" : "Save Changes") { saveServer() }
                            .buttonStyle(.borderedProminent).disabled(name.isEmpty).keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
            }
        }
        .frame(width: 480, height: 600)
        .onAppear {
            if let config = editingConfig {
                name = config.name
                switch config.transport {
                case .stdio(let cmd, let arguments, let env):
                    transportType = 0
                    command = cmd
                    args = arguments.joined(separator: " ")
                    envText = env.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
                case .sse(let url, _):
                    transportType = 1
                    sseURL = url
                }
            }
        }
    }

    private func saveServer() {
        let transport: MCPServerConfig.Transport
        if transportType == 0 {
            let argList = args.split(separator: " ").map(String.init)
            
            var parsedEnv: [String: String] = [:]
            for line in envText.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    parsedEnv[parts[0]] = parts[1]
                }
            }
            
            transport = .stdio(command: command, args: argList, env: parsedEnv)
        } else {
            transport = .sse(url: sseURL, headers: [:])
        }
        
        if let existing = editingConfig {
            let updated = MCPServerConfig(id: existing.id, name: name, transport: transport, isEnabled: existing.isEnabled)
            manager.updateServer(updated)
        } else {
            manager.addServer(MCPServerConfig(name: name, transport: transport))
        }
        
        isPresented = false
    }
}

// MARK: - Theme Card

struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.backgroundTint).frame(height: 44)
                .overlay(
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(theme.sidebarTint).frame(width: 18)
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 2).fill(theme.accentColor.opacity(0.7)).frame(height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.3)).frame(height: 5)
                            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.2)).frame(height: 5)
                        }
                        .padding(.trailing, 4)
                    }.padding(5)
                )
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? theme.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1))
            HStack(spacing: 4) {
                Image(systemName: theme.icon).font(.system(size: 9)).foregroundStyle(isSelected ? theme.accentColor : .secondary)
                Text(theme.name).font(.system(size: 10)).foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .contentShape(Rectangle())
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
            Text("SSH / VPS Connection").font(.headline)
            Text("Configure SSH connection for remote command execution. The AI can run commands on your VPS using the ssh_command skill.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                TextField("Host", text: $sshHost, prompt: Text("192.168.1.100 or myserver.com"))
                TextField("Username", text: $sshUser)
                TextField("Port", value: $sshPort, format: .number)
                TextField("SSH Key Path", text: $sshKeyPath, prompt: Text("~/.ssh/id_rsa"))
            }.formStyle(.grouped)
            HStack {
                Button("Test Connection") { testConnection() }.disabled(sshHost.isEmpty || isTesting)
                if isTesting { ProgressView().controlSize(.small).padding(.leading, 4) }
            }
            if !testResult.isEmpty {
                Text(testResult).font(.caption)
                    .foregroundStyle(testResult.contains("✅") ? .green : .red).padding(.top, 4)
            }
            Spacer()
        }
        .padding()
    }
    
    private func testConnection() {
        isTesting = true; testResult = ""
        let expandedKey = NSString(string: sshKeyPath).expandingTildeInPath
        Task {
            var args = ["-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"]
            if !expandedKey.isEmpty {
                args.append(contentsOf: ["-i", expandedKey])
            }
            args.append(contentsOf: ["-p", "\(sshPort)", "\(sshUser)@\(sshHost)", "echo connected"])
            let result = await ShellHelper.runExecutable("ssh", arguments: args)
            await MainActor.run {
                isTesting = false
                testResult = result.output.contains("connected")
                    ? "✅ Connection successful!"
                    : "❌ Connection failed: \(result.output.isEmpty ? result.error : result.output)"
            }
        }
    }
}
