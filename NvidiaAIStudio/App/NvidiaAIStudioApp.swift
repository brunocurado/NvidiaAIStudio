import SwiftUI
import AppKit
import UserNotifications

@main
struct NvidiaAIStudioApp: App {
    @State private var appState = AppState()
    @State private var showSplash = true
    @State private var showOnboarding = false
    @AppStorage("appThemeID") private var appThemeID: String = "dark"
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var colorScheme: ColorScheme? {
        AppTheme.find(id: appThemeID).colorScheme
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(showSplash: showSplash)
                    .environment(appState)
                    .opacity(showSplash ? 0 : 1)
                
                if showSplash {
                    SplashScreenView(isFinished: $showSplash)
                }
                if showOnboarding {
                    OnboardingView(isPresented: $showOnboarding)
                        .environment(appState)
                        .transition(.opacity)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
            .preferredColorScheme(colorScheme)
            .onAppear {
                appState.bootstrap()
                if appState.apiKeys.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        showOnboarding = true
                    }
                }
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    AppWindowStyler.apply(to: NSApp.windows.first)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        
        Settings {
            SettingsView()
                .environment(appState)
        }
        
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Thread") {
                    let _ = appState.createSession()
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("Open Workspace") {
                    NotificationCenter.default.post(name: .openWorkspacePicker, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Commit & Push") {
                    NotificationCenter.default.post(name: .openGitPanel, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Window Styler

final class AppWindowStyler: NSObject, NSWindowDelegate {
    static let shared = AppWindowStyler()

    static func apply(to window: NSWindow?) {
        guard let w = window else { return }
        w.makeKeyAndOrderFront(nil)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.styleMask.insert(.fullSizeContentView)
        w.toolbarStyle = .unifiedCompact
        w.delegate = shared
    }

    private static func styleWindow(_ w: NSWindow) {
        w.isOpaque = false
        w.backgroundColor = .clear
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.styleMask.insert(.fullSizeContentView)

        // Torna a toolbar e titlebar completamente transparentes
        if let toolbar = w.toolbar {
            toolbar.showsBaselineSeparator = false
        }

        // Percorre a view hierarchy da titlebar e limpa todos os fundos
        func clearBackground(_ view: NSView) {
            view.wantsLayer = true
            view.layer?.backgroundColor = CGColor.clear
            view.layer?.borderWidth = 0
            for sub in view.subviews { clearBackground(sub) }
        }

        if let titlebarContainer = w.standardWindowButton(.closeButton)?.superview?.superview {
            clearBackground(titlebarContainer)
        }
        // Também limpa o contentView pai
        if let frameView = w.contentView?.superview {
            clearBackground(frameView)
        }
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        Self.styleWindow(w)
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        NSApp.presentationOptions = [.autoHideMenuBar, .autoHideToolbar]
        // Aplica em vários momentos — o macOS restaura valores durante a animação
        Self.styleWindow(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Self.styleWindow(w) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Self.styleWindow(w) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { Self.styleWindow(w) }
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        NSApp.presentationOptions = []
        Self.styleWindow(w)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        Self.styleWindow(w)
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openWorkspacePicker = Notification.Name("openWorkspacePicker")
    static let openGitPanel = Notification.Name("openGitPanel")
    static let responseCompleted = Notification.Name("responseCompleted")
}

// MARK: - Notifications helper

enum AppNotifications {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    static func sendResponseCompleted(modelName: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            guard NSApp.isHidden || NSApp.mainWindow?.isKeyWindow == false else { return }
            let content = UNMutableNotificationContent()
            content.title = "Response ready"
            content.body = "\(modelName) finished responding"
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
