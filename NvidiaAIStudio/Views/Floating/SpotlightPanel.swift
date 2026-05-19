import SwiftUI
import AppKit

/// A custom NSPanel configured to behave like Spotlight or Raycast.
class SpotlightPanel: NSPanel {
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: backing, defer: flag)
        
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        
        // Visuals
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isOpaque = false
    }
    
    // Allow key window status even without titlebars so TextFields can gain focus.
    override var canBecomeKey: Bool {
        return true
    }
    override var canBecomeMain: Bool {
        return true
    }
}

/// The root controller for managing the Spotlight Panel lifecycle.
class SpotlightManager: ObservableObject {
    static let shared = SpotlightManager()
    
    var panel: SpotlightPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    
    func setup(appState: AppState) {
        guard panel == nil else { return }
        
        let contentView = SpotlightContentView()
            .environment(appState)
            .environmentObject(self)
        
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame.size = NSSize(width: 650, height: 72)
        // Enable transparency in NSVisualEffectView hosting
        hostingController.view.layer?.cornerRadius = 16
        hostingController.view.layer?.masksToBounds = true
        
        let visualEffect = NSVisualEffectView(frame: hostingController.view.bounds)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.autoresizingMask = [.width, .height]
        
        // Wrap the hosting view in the visual effect
        let container = NSView(frame: hostingController.view.bounds)
        container.addSubview(visualEffect)
        container.addSubview(hostingController.view)
        
        // Center panel based on main screen
        let screenRect = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelRect = NSRect(x: screenRect.midX - 325, y: screenRect.midY + 100, width: 650, height: 72)
        
        let newPanel = SpotlightPanel(contentRect: panelRect, backing: .buffered, defer: false)
        newPanel.contentView = container
        newPanel.animationBehavior = .documentWindow
        
        self.panel = newPanel
        setupHotkeys()
    }
    
    func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    func showPanel() {
        guard let panel = panel else { return }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hidePanel() {
        panel?.orderOut(nil)
    }
    
    private func setupHotkeys() {
        // Global Hotkey: Cmd+Shift+Space
        // Needs Accessibility permission in macOS to capture globally
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
            // If Esc pressed while panel open, close it
            if event.keyCode == 53 && self?.panel?.isVisible == true {
                self?.hidePanel()
                return nil // Consume event
            }
            return event
        }
    }
    
    private func handleEvent(_ event: NSEvent) {
        // Cmd (1048576) + Shift (131072) == 1179648
        // Spacebar keyCode is 49
        if event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) && event.keyCode == 49 {
            DispatchQueue.main.async {
                self.togglePanel()
            }
        }
    }
}

// MARK: - SwiftUI Content View

struct SpotlightContentView: View {
    @Environment(AppState.self) private var appState
    @EnvironmentObject private var spotlightManager: SpotlightManager
    @AppStorage("appThemeID") private var appThemeID: String = "liquid_glass_dark"
    private var theme: AppTheme { AppTheme.find(id: appThemeID) }
    
    @State private var promptText = ""
    @State private var animateIn = false
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(.cyan)
                .padding(.leading, 4)
            
            TextField("Tell the Swarm...", text: $promptText)
                .font(.system(size: 24, weight: .regular, design: .default))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    executeDirective()
                }
            
            if !promptText.isEmpty {
                Button {
                    executeDirective()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(theme.accentColor))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(16)
        .background(theme.backgroundTint.opacity(0.85))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(theme.accentColor.opacity(0.4), lineWidth: 1)
        )
        .scaleEffect(animateIn ? 1.0 : 0.96)
        .opacity(animateIn ? 1.0 : 0.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7, blendDuration: 0), value: animateIn)
        .animation(.spring(duration: 0.2), value: promptText.isEmpty)
        .onAppear {
            isFocused = true
            animateIn = true
        }
        .onChange(of: spotlightManager.panel?.isVisible) { _, visible in
            if visible == true {
                isFocused = true
                animateIn = true
            } else {
                animateIn = false
            }
        }
    }
    
    private func executeDirective() {
        guard !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let directive = promptText
        promptText = ""
        spotlightManager.hidePanel()
        
        // Orchestrate background task injection
        Task {
            appState.orchestrator.autoDecompose(directive: directive)
            await MainActor.run {
                appState.showToast("Task dispatched to Swarm War Room.", level: .success)
            }
        }
    }
}
