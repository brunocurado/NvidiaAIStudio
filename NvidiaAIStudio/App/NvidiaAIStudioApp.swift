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
                    guard let window = NSApp.windows.first else { return }
                    AppWindowStyler.shared.install(on: window)
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

/// Applies transparent titlebar styling and reapplies it after fullscreen transitions.
final class AppWindowStyler: NSObject, NSWindowDelegate {
    static let shared = AppWindowStyler()

    func install(on window: NSWindow) {
        applyStyle(to: window)
        window.delegate = self
    }

    private func applyStyle(to window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // Hide the toolbar separator line
        window.toolbar?.showsBaselineSeparator = false
    }

    // Reapply after entering fullscreen — macOS resets transparency
    func windowDidEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { self.applyStyle(to: window) }
    }

    // Reapply after exiting fullscreen
    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { self.applyStyle(to: window) }
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
