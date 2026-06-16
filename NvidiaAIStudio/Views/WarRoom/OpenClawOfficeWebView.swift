import SwiftUI
import WebKit

struct OpenClawOfficeWebView: View {
    @AppStorage("openClawOfficeURL") private var urlString = "http://localhost:5173"
    @State private var webView = WKWebView()
    @State private var isLoading = false
    @State private var loadError: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Address Bar & Controls
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                
                TextField("OpenClaw Office URL", text: $urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit {
                        loadURL()
                    }
                
                Button(action: loadURL) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("r", modifiers: .command)
                .help("Reload web page (⌘R)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial.opacity(0.5))
            
            Divider()
            
            // WebView Content
            ZStack {
                OpenClawRepresentableWebView(webView: webView, isLoading: $isLoading, loadError: $loadError)
                    .id(urlString) // Forces refresh if URL updates
                
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("A ligar ao OpenClaw Office...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
                }
                
                if let errorDescription = loadError {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        
                        VStack(spacing: 6) {
                            Text("Não foi possível ligar")
                                .font(.system(size: 14, weight: .bold))
                            
                            Text(errorDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                            
                            Text("Certifica-te de que o servidor web do OpenClaw está a correr localmente (geralmente via npm run dev ou docker) no URL especificado.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 340)
                                .padding(.top, 4)
                        }
                        
                        Button("Tentar Novamente", action: loadURL)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    .padding(32)
                    .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(GlassTheme.flatStroke, lineWidth: 1)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            loadURL()
        }
    }
    
    private func loadURL() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            loadError = "URL inválido"
            return
        }
        loadError = nil
        isLoading = true
        
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
        webView.load(request)
    }
}

// MARK: - NSViewRepresentable Bridge

struct OpenClawRepresentableWebView: NSViewRepresentable {
    let webView: WKWebView
    @Binding var isLoading: Bool
    @Binding var loadError: String?
    
    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background support
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: OpenClawRepresentableWebView
        
        init(_ parent: OpenClawRepresentableWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.loadError = nil
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.loadError = error.localizedDescription
            }
        }
    }
}
