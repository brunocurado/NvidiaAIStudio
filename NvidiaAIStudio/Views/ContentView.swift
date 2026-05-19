import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("appThemeID") private var appThemeID: String = "liquid_glass_dark"

    var showSplash: Bool = false
    @State private var showGitPanel = false
    @State private var showCloneSheet = false
    @State private var showUsagePanel = false
    @State private var showPromptLab = false
    @State private var rightPanelWidth: CGFloat = 400

    private var theme: AppTheme { AppTheme.find(id: appThemeID) }

    var body: some View {
        ZStack {
            // Glass refraction anchor — must be the FIRST layer
            GlassCanvasBackdrop()

            // Subtle theme tint overlay (semi-transparent per theme)
            theme.backgroundTint
                .ignoresSafeArea()

            HStack(spacing: 0) {
                if appState.isSidebarVisible {
                    SidebarView()
                        .frame(width: 260)
                        .macSidebarRail()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    Divider()
                        .transition(.opacity)
                }

                switch appState.appMode {
                case .chat:
                    ChatView()
                        .frame(maxWidth: .infinity)
                case .warRoom:
                    WarRoomView()
                        .frame(maxWidth: .infinity)
                        .environment(appState)
                }

                if appState.isRightPanelVisible {
                    // Draggable divider for right panel resize
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 6)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    let newWidth = rightPanelWidth - value.translation.width
                                    rightPanelWidth = max(250, min(800, newWidth))
                                }
                        )
                        .overlay(Divider())
                        .transition(.opacity)
                    
                    RightPanelView()
                        .frame(width: rightPanelWidth)
                        .macSidebarRail()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.12), value: appState.isSidebarVisible)
            .animation(.spring(duration: 0.4, bounce: 0.12), value: appState.isRightPanelVisible)

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
        .sheet(isPresented: $showUsagePanel) {
            UsagePanelView()
        }
        .sheet(isPresented: $showPromptLab) {
            PromptLabView()
                .environment(appState)
        }
        .toolbar(showSplash ? .hidden : .visible, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        appState.isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.glass)
                .help("Toggle Sidebar")

                Spacer()

                Button {
                    showGitPanel = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Commit")
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(theme.accentColor)
                }
                .buttonStyle(.glass)
                .help("Commit & Push")

                Button {
                    showCloneSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                }
                .buttonStyle(.glass)
                .help("Clone Repository")

                Button {
                    showPromptLab = true
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.glass)
                .help("Prompt Lab")

                Button {
                    showUsagePanel = true
                } label: {
                    Image(systemName: "doc.text.fill")
                }
                .buttonStyle(.glass)
                .help("Tokens & Usage")

                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        appState.isRightPanelVisible.toggle()
                    }
                } label: {
                    Image(systemName: "terminal.fill")
                }
                .buttonStyle(.glass)
                .help("Toggle Terminal/Diff")

                Button { } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "person.2.fill")
                        if let session = appState.activeSession, !session.backgroundAgents.isEmpty {
                            Text("\(session.backgroundAgents.count)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(theme.accentColor))
                                .offset(x: 6, y: -4)
                        }
                    }
                }
                .buttonStyle(.glass)
                .help("Agents")
            }
        }
    }
}
