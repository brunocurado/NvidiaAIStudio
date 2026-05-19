import SwiftUI
import WebKit

struct LiveCanvasView: View {
    @Environment(AppState.self) private var appState
    
    var body: some View {
        VStack(spacing: 0) {
            if let url = appState.activeCanvasURL {
                WebViewRepresentable(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No Dev Server Found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Start a web server using the PTY to automatically bind the Live Canvas.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - WebView Representable

struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        
        // Inject JS to capture errors
        let scriptSource = """
        window.onerror = function(message, source, lineno, colno, error) {
            window.webkit.messageHandlers.errorCatcher.postMessage({
                "type": "onerror",
                "message": message,
                "source": source,
                "lineno": lineno,
                "colno": colno,
                "stack": error ? error.stack : null
            });
            return false; // let the error continue to actual console
        };
        
        const originalConsoleError = console.error;
        console.error = function() {
            var msgs = [];
            for (var i = 0; i < arguments.length; i++) {
                msgs.push(String(arguments[i]));
            }
            window.webkit.messageHandlers.errorCatcher.postMessage({
                "type": "console.error",
                "message": msgs.join(' ')
            });
            originalConsoleError.apply(console, arguments);
        };
        """
        
        let userScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(userScript)
        
        let webView = WKWebView(frame: .zero, configuration: config)
        
        // Set the message handler to our coordinator
        webView.configuration.userContentController.add(context.coordinator, name: "errorCatcher")
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url?.absoluteString != url.absoluteString {
            webView.load(URLRequest(url: url))
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "errorCatcher",
                  let body = message.body as? [String: Any],
                  let msgType = body["type"] as? String,
                  let errorMsg = body["message"] as? String else { return }
            
            // Reconstruct a helpful trace
            var trace = "[WKWebView \(msgType)] \(errorMsg)"
            if let stack = body["stack"] as? String, !stack.isEmpty {
                trace += "\nStack trace:\n\(stack)"
            }
            
            // Avoid pinging trivial layout warnings
            let ignoreList = ["favicon.ico", "sockjs-node", "webpack-internal"]
            if ignoreList.contains(where: { errorMsg.contains($0) }) { return }
            
            print("🛑 [Live Canvas] Captured JS Error: \(trace)")
            
            // Post notification for the Exterminator Loop
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .canvasJSErrorDetected,
                    object: nil,
                    userInfo: ["trace": trace, "webView": message.webView as Any]
                )
            }
        }
    }
}

extension Notification.Name {
    static let canvasJSErrorDetected = Notification.Name("canvasJSErrorDetected")
}

