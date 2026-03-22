import SwiftUI
import AppKit

@main
struct NvidiaAIStudioApp: App {
    @State private var appState = AppState()
    @State private var showSplash = true
    @AppStorage("theme") private var theme = "dark"
    
    // App delegate to handle activation
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    private var colorScheme: ColorScheme? {
        switch theme {
        case "dark": return .dark
        case "light": return .light
        default: return nil  // system
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(appState)
                    .opacity(showSplash ? 0 : 1)
                
                if showSplash {
                    SplashScreenView(isFinished: $showSplash)
                }
            }
            .frame(minWidth: 900, minHeight: 600)
            .preferredColorScheme(colorScheme)
            .onAppear {
                appState.bootstrap()
                
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApp.windows.first {
                        window.makeKeyAndOrderFront(nil)
                        window.isOpaque = false
                        window.backgroundColor = .clear
                        window.titlebarAppearsTransparent = true
                        window.titleVisibility = .hidden
                        window.styleMask.insert(.fullSizeContentView)
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        
        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

/// App delegate to handle activation lifecycle.
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
