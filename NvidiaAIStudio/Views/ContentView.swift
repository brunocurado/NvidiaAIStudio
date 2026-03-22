import SwiftUI
import AppKit

/// NSVisualEffectView wrapper — allows smooth alpha control of the blur/vibrancy
/// material that SwiftUI's .ultraThinMaterial cannot expose directly.
struct VisualEffectBackground: NSViewRepresentable {
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var material: NSVisualEffectView.Material = .underWindowBackground
    var alphaValue: CGFloat = 1.0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = blendingMode
        v.material = material
        v.state = .active
        v.alphaValue = alphaValue
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.blendingMode = blendingMode
        nsView.material = material
        nsView.alphaValue = alphaValue
    }
}

/// Main 3-column layout matching the reference app design.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("glassOpacity") private var glassOpacity: Double = 0.25
    @AppStorage("glassBlur") private var glassBlur: Double = 20.0
    @State private var showGitPanel = false
    @State private var showCloneSheet = false

    var body: some View {
        ZStack {
            // Glassmorphism background via native NSVisualEffectView.
            // glassOpacity slider (0–1) maps directly to the view's alphaValue:
            //   1.0 = fully opaque frosted material
            //   0.0 = completely transparent (no material at all)
            // This gives a perfectly smooth, linear fade with no cliff edges.
            VisualEffectBackground(alphaValue: CGFloat(glassOpacity))
                .ignoresSafeArea()
            // Dark tint layer — scales with opacity so it also fades out cleanly
            Color(red: 0.06, green: 0.06, blue: 0.16)
                .opacity(glassOpacity * 0.6)
                .ignoresSafeArea()
            // Frosted overlay
            if glassBlur > 0 {
                Color.white
                    .opacity(glassBlur / 50.0 * 0.35)
                    .ignoresSafeArea()
            }

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
        .onReceive(NotificationCenter.default.publisher(for: .openGitPanel)) { _ in
            showGitPanel = true
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


