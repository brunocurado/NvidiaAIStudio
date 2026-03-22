import SwiftUI

/// Main 3-column layout matching the reference app design.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("glassOpacity") private var glassOpacity: Double = 0.25
    @AppStorage("glassBlur") private var glassBlur: Double = 20.0
    @State private var showGitPanel = false
    @State private var showCloneSheet = false
    
    var body: some View {
        ZStack {
            // Fundo glassmorphism: o ultraThinMaterial deixa ver o wallpaper
            // através da janela (blur nativo do macOS sobre o desktop).
            // glassOpacity controla a opacidade do tint de cor.
            // glassBlur controla quanto o material "fecha" — via opacidade do overlay branco.
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
            Color(red: 0.06, green: 0.06, blue: 0.16)
                .opacity(glassOpacity)
                .ignoresSafeArea()
            // O slider de blur fecha gradualmente o material (0 = totalmente translúcido, 50 = quase opaco)
            Color.white
                .opacity(glassBlur / 50.0 * 0.45)
                .ignoresSafeArea()

            HSplitView {
                // Left: Sidebar
                if appState.isSidebarVisible {
                    SidebarView()
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                }
                
                // Center: Chat area
                ChatView()
                    .frame(minWidth: 400)
                
                // Right: Diff/Terminal panel
                if appState.isRightPanelVisible {
                    RightPanelView()
                        .frame(minWidth: 300, idealWidth: 400, maxWidth: 600)
                }
            }
            
            // Toast overlay
            VStack {
                ForEach(appState.toasts) { toast in
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 8)
            .animation(.spring(duration: 0.3), value: appState.toasts.count)
        }
        .sheet(isPresented: $showGitPanel) {
            GitPanelView()
                .environment(appState)
        }
        .sheet(isPresented: $showCloneSheet) {
            CloneRepoView()
                .environment(appState)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
                
                Spacer()
                
                Button {
                    showGitPanel = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Commit")
                    }
                }
                .help("Commit & Push Changes")
                
                Button {
                    showCloneSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                }
                .help("Clone Repository")
                
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.isRightPanelVisible.toggle()
                    }
                } label: {
                    Image(systemName: "terminal.fill")
                }
                .help("Toggle Terminal/Diff")
            }
        }
    }
}


