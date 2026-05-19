import SwiftUI
import WebKit

/// Smart Canvas: detects the content type produced by agents and renders it visually.
/// Supports HTML (WKWebView), Markdown (AttributedString), code (syntax-coloured), and plain text.
struct SmartCanvasView: View {
    let content: String
    @Binding var editableContent: String
    var isEditing: Bool = false
    @FocusState.Binding var isFocused: Bool

    private enum ContentKind {
        case html, markdown, code(lang: String), plain
    }

    private var kind: ContentKind {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html") || trimmed.hasPrefix("<div") || trimmed.hasPrefix("<body") {
            return .html
        }
        if trimmed.contains("```") {
            // Extract language from first fence
            let lang = trimmed
                .components(separatedBy: "\n").first?
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespaces) ?? ""
            return .code(lang: lang)
        }
        if trimmed.hasPrefix("#") || trimmed.contains("**") || trimmed.contains("- ") {
            return .markdown
        }
        return .plain
    }

    var body: some View {
        Group {
            switch kind {
            case .html:
                HTMLCanvasView(html: content)
                    .overlay(alignment: .topTrailing) {
                        Label("Live Preview", systemImage: "globe")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }

            case .markdown:
                ScrollView {
                    MarkdownCanvasView(markdown: content)
                        .padding(14)
                }
                .overlay(alignment: .topTrailing) {
                    Label("Markdown", systemImage: "doc.richtext")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }

            case .code(let lang):
                ScrollView {
                    CodeBlockView(code: content, language: lang)
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    Label(lang.isEmpty ? "Code" : lang.uppercased(), systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                        .padding(6)
                }

            case .plain:
                // Fall back to a plain CEO-editable text editor
                TextEditor(text: $editableContent)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .focused($isFocused)
            }
        }
    }
}

// MARK: - HTML Renderer

struct HTMLCanvasView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            background: #080b10;
            color: #e8eaf6;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
            font-size: 13px;
            line-height: 1.6;
            padding: 16px;
          }
          h1, h2, h3 { color: #82b1ff; margin-bottom: 8px; margin-top: 18px; }
          a { color: #64ffda; }
          code { background: rgba(255,255,255,0.06); padding: 2px 6px; border-radius: 4px; font-family: 'SF Mono', monospace; }
          pre { background: rgba(255,255,255,0.04); padding: 12px; border-radius: 8px; overflow: auto; }
          pre code { background: none; padding: 0; }
          button, input[type=button], input[type=submit] {
            background: linear-gradient(135deg, #0d47a1, #1565c0);
            color: white; border: none; padding: 8px 16px;
            border-radius: 8px; cursor: pointer; font-size: 13px;
          }
          input[type=text], input[type=email], textarea, select {
            background: rgba(255,255,255,0.06);
            border: 1px solid rgba(255,255,255,0.15);
            color: #e8eaf6;
            padding: 8px 12px; border-radius: 8px; width: 100%; font-size: 13px;
          }
          .card {
            background: rgba(255,255,255,0.04);
            border: 1px solid rgba(255,255,255,0.08);
            border-radius: 12px;
            padding: 16px; margin: 8px 0;
          }
          table { width: 100%; border-collapse: collapse; }
          th, td { border: 1px solid rgba(255,255,255,0.1); padding: 8px 12px; text-align: left; }
          th { background: rgba(255,255,255,0.06); }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
        nsView.loadHTMLString(styledHTML, baseURL: nil)
    }
}

// MARK: - Markdown Renderer

struct MarkdownCanvasView: View {
    let markdown: String

    var attributed: AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }

    var body: some View {
        Text(attributed)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Code Block Renderer

struct CodeBlockView: View {
    let code: String
    let language: String

    // Strip outer fences
    private var cleanCode: String {
        var lines = code.components(separatedBy: "\n")
        if lines.first?.hasPrefix("```") == true { lines.removeFirst() }
        if lines.last?.hasPrefix("```") == true { lines.removeLast() }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                HStack {
                    Text(language.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                    Spacer()
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cleanCode, forType: .string)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(GlassTheme.flatFill)
            }

            ScrollView([.horizontal, .vertical]) {
                Text(cleanCode)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(GlassTheme.flatFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(GlassTheme.flatStroke, lineWidth: 1)
        )
    }
}
