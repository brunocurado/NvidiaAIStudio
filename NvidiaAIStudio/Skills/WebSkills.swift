import Foundation

// MARK: - Fetch URL

struct FetchURLSkill: Skill {
    let name = "fetch_url"
    let description = """
        Fetch the content of a web page or URL. Returns the page text with HTML tags stripped. \
        Use this to read documentation, GitHub repos, articles, or any public web page. \
        Does not execute JavaScript — for SPAs use MCP Puppeteer instead.
        """

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "url": ["type": "string", "description": "The full URL to fetch (must start with http:// or https://)"] as [String: Any],
                "extract_images": ["type": "boolean", "description": "If true, list image URLs found on the page. Default: false."] as [String: Any]
            ] as [String: Any],
            "required": ["url"]
        ]
    }

    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let urlString = try SkillArgs.getString(args, key: "url")
        let extractImages = SkillArgs.getBool(args, key: "extract_images", defaultValue: false)

        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else {
            throw SkillError.invalidArguments("Invalid URL: \(urlString)")
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"]
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkillError.executionFailed("Invalid response from \(urlString)")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw SkillError.executionFailed("HTTP \(httpResponse.statusCode) from \(urlString)")
        }
        let encoding = detectEncoding(from: httpResponse)
        guard let html = String(data: data, encoding: encoding) ?? String(data: data, encoding: .utf8) else {
            throw SkillError.executionFailed("Could not decode response")
        }

        var result = "URL: \(urlString)\nStatus: \(httpResponse.statusCode)\n\n"
        let title = extractTitle(from: html)
        if !title.isEmpty { result += "Title: \(title)\n\n" }
        let text = stripHTML(from: html)
        result += text.count > 30_000 ? String(text.prefix(30_000)) + "\n\n[... truncated]" : text

        if extractImages {
            let images = extractImageURLs(from: html, baseURL: url)
            if !images.isEmpty {
                result += "\n\n--- Images found (use fetch_images to analyse them visually) ---\n"
                result += images.prefix(20).joined(separator: "\n")
            }
        }
        return result
    }

    private func detectEncoding(from response: HTTPURLResponse) -> String.Encoding {
        if let ct = response.value(forHTTPHeaderField: "Content-Type"), ct.contains("charset=") {
            let charset = ct.components(separatedBy: "charset=").last?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if charset.contains("utf-8") || charset.contains("utf8") { return .utf8 }
            if charset.contains("iso-8859-1") { return .isoLatin1 }
        }
        return .utf8
    }

    private func extractTitle(from html: String) -> String {
        let lower = html.lowercased()
        guard let s = lower.range(of: "<title"),
              let te = html[s.upperBound...].range(of: ">"),
              let e = html[te.upperBound...].range(of: "</title>", options: .caseInsensitive)
        else { return "" }
        return String(html[te.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stripHTML(from html: String) -> String {
        var text = html
        for tag in ["script", "style", "nav", "footer", "header"] {
            while let open = text.range(of: "<\(tag)", options: .caseInsensitive),
                  let close = text.range(of: "</\(tag)>", options: .caseInsensitive, range: open.lowerBound..<text.endIndex) {
                text.removeSubrange(open.lowerBound...close.upperBound)
            }
        }
        for tag in ["</p>", "</div>", "</li>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "<br>", "<br/>", "<br />", "</tr>"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        var result = ""; var inTag = false
        for c in text {
            if c == "<" { inTag = true; continue }
            if c == ">" { inTag = false; continue }
            if !inTag { result.append(c) }
        }
        for (e, r) in [("&amp;","&"),("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'"),("&nbsp;"," "),("&mdash;","—"),("&ndash;","–"),("&hellip;","…")] {
            result = result.replacingOccurrences(of: e, with: r, options: .caseInsensitive)
        }
        let lines = result.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var deduped: [String] = []; var prev = false
        for line in lines {
            let empty = line.isEmpty
            if empty && prev { continue }
            deduped.append(line); prev = empty
        }
        return deduped.joined(separator: "\n")
    }

    func extractImageURLs(from html: String, baseURL: URL) -> [String] {
        var images: [String] = []
        var search = html[html.startIndex...]
        while let r = search.range(of: "<img", options: .caseInsensitive) {
            guard let end = search[r.upperBound...].range(of: ">") else { break }
            let tag = String(search[r.lowerBound..<end.upperBound])
            if let src = extractAttr("src", from: tag), let resolved = resolveURL(src, base: baseURL) { images.append(resolved) }
            search = search[end.upperBound...]
        }
        return images
    }

    private func extractAttr(_ attr: String, from tag: String) -> String? {
        for pattern in ["\(attr)=\"", "\(attr)='", "\(attr)="] {
            guard let s = tag.range(of: pattern, options: .caseInsensitive) else { continue }
            let after = tag[s.upperBound...]
            let quote = pattern.hasSuffix("\"") ? "\"" : (pattern.hasSuffix("'") ? "'" : " ")
            if let e = after.range(of: quote) ?? after.range(of: ">") { return String(after[after.startIndex..<e.lowerBound]) }
        }
        return nil
    }

    private func resolveURL(_ src: String, base: URL) -> String? {
        if src.hasPrefix("http://") || src.hasPrefix("https://") { return src }
        if src.hasPrefix("//") { return base.scheme! + ":" + src }
        if src.hasPrefix("/") { return base.scheme! + "://" + (base.host ?? "") + src }
        return URL(string: src, relativeTo: base)?.absoluteString
    }
}

// MARK: - Fetch Images

struct FetchImagesSkill: Skill {
    let name = "fetch_images"
    let description = """
        Download images from URLs and pass them to the model for visual analysis. \
        Requires a vision-capable model (Claude, GPT-4o, Qwen-VL, Nemotron-VL). \
        Use this when you need to actually see and analyse images from a web page or any URL. \
        Provide up to 4 image URLs — they will be embedded so the model can see them.
        """

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "urls": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "List of image URLs to fetch and analyse (max 4)",
                    "maxItems": 4
                ] as [String: Any],
                "description": [
                    "type": "string",
                    "description": "Optional context about what to look for in the images"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["urls"]
        ]
    }

    static let payloadPrefix = "[VISION_IMAGES]"

    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        guard let rawURLs = args["urls"] as? [String] else {
            throw SkillError.invalidArguments("Missing required 'urls' array")
        }
        let desc = SkillArgs.getOptionalString(args, key: "description") ?? ""
        let urls = Array(rawURLs.prefix(4))

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"]
        let session = URLSession(configuration: config)

        var payloads: [[String: String]] = []
        var errors: [String] = []

        for urlString in urls {
            guard let url = URL(string: urlString) else { errors.append("Invalid URL: \(urlString)"); continue }
            do {
                let (data, response) = try await session.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    errors.append("HTTP error for \(urlString)"); continue
                }
                let mime = detectMIME(from: httpResponse, url: url)
                guard mime.hasPrefix("image/") else { errors.append("Not an image: \(urlString)"); continue }
                guard data.count <= 5 * 1024 * 1024 else { errors.append("Image too large (>5MB): \(urlString)"); continue }
                payloads.append(["url": urlString, "mime": mime, "data": data.base64EncodedString()])
            } catch {
                errors.append("Failed \(urlString): \(error.localizedDescription)")
            }
        }

        if payloads.isEmpty {
            throw SkillError.executionFailed(errors.isEmpty ? "No images could be fetched." : errors.joined(separator: "; "))
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payloads),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            throw SkillError.executionFailed("Failed to encode image payloads")
        }

        var summary = "Fetched \(payloads.count) image(s) successfully."
        if !desc.isEmpty { summary += " Context: \(desc)" }
        if !errors.isEmpty { summary += " Skipped: \(errors.joined(separator: "; "))" }

        return "\(Self.payloadPrefix)\(jsonStr)\n\(summary)"
    }

    private func detectMIME(from response: HTTPURLResponse, url: URL) -> String {
        if let ct = response.value(forHTTPHeaderField: "Content-Type"), ct.hasPrefix("image/") {
            return ct.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ct
        }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        default:            return "image/jpeg"
        }
    }
}

// MARK: - Web Search

struct WebSearchSkill: Skill {
    let name = "web_search"
    let description = """
        Search the web for information. Returns a list of results with titles, URLs, and snippets. \
        Use this when you need current information, documentation, or to find relevant pages. \
        After searching, use fetch_url on the most relevant results to read them in full.
        """

    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "The search query"] as [String: Any],
                "num_results": ["type": "integer", "description": "Number of results to return (default: 8, max: 20)"] as [String: Any]
            ] as [String: Any],
            "required": ["query"]
        ]
    }

    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let query = try SkillArgs.getString(args, key: "query")
        let n = min(SkillArgs.getInt(args, key: "num_results", defaultValue: 8), 20)
        if let r = try? await ddgHTML(query: query, n: n) { return r }
        return try await ddgInstant(query: query)
    }

    private struct DDGResult { let title, url, snippet: String }

    private func ddgHTML(query: String, n: Int) async throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            throw SkillError.invalidArguments("Could not build URL")
        }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw SkillError.executionFailed("DDG search failed")
        }
        let results = parseDDG(html: html, limit: n)
        if results.isEmpty { throw SkillError.executionFailed("No results") }
        return "Search results for: \"\(query)\"\n\n" + results.enumerated().map { i, r in
            "\(i+1). \(r.title)\n   URL: \(r.url)\(r.snippet.isEmpty ? "" : "\n   \(r.snippet)")"
        }.joined(separator: "\n\n")
    }

    private func parseDDG(html: String, limit: Int) -> [DDGResult] {
        var results: [DDGResult] = []
        var search = html[html.startIndex...]
        while results.count < limit,
              let mr = search.range(of: "class=\"result__a\"", options: .caseInsensitive) {
            let before = search[search.startIndex..<mr.lowerBound]
            guard let aStart = before.range(of: "<a", options: [.caseInsensitive, .backwards]),
                  let aEnd = search[mr.upperBound...].range(of: "</a>", options: .caseInsensitive) else {
                search = search[mr.upperBound...]; continue
            }
            let tag = String(search[aStart.lowerBound..<aEnd.upperBound])
            var rawURL = ""
            if let hr = tag.range(of: "href=\"", options: .caseInsensitive) {
                let after = tag[hr.upperBound...]
                if let e = after.range(of: "\"") { rawURL = String(after[after.startIndex..<e.lowerBound]) }
            }
            if rawURL.contains("uddg="),
               let comps = URLComponents(string: rawURL),
               let uddg = comps.queryItems?.first(where: { $0.name == "uddg" })?.value { rawURL = uddg }
            guard !rawURL.isEmpty, rawURL.hasPrefix("http") else { search = search[aEnd.upperBound...]; continue }
            let title = stripHTML(tag).trimmingCharacters(in: .whitespacesAndNewlines)
            var snippet = ""
            let rem = search[aEnd.upperBound...]
            if let sc = rem.range(of: "result__snippet", options: .caseInsensitive),
               let ss = rem[sc.upperBound...].range(of: ">"),
               let se = rem[ss.upperBound...].range(of: "</", options: .caseInsensitive) {
                snippet = stripHTML(String(rem[ss.upperBound..<se.lowerBound])).trimmingCharacters(in: .whitespacesAndNewlines)
                if snippet.count > 200 { snippet = String(snippet.prefix(200)) + "…" }
            }
            results.append(DDGResult(title: title, url: rawURL, snippet: snippet))
            search = search[aEnd.upperBound...]
        }
        return results
    }

    private func ddgInstant(query: String) async throws -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else {
            throw SkillError.invalidArguments("Could not build URL")
        }
        var req = URLRequest(url: url); req.setValue("NvidiaAIStudio/1.0", forHTTPHeaderField: "User-Agent"); req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillError.executionFailed("Could not parse response")
        }
        var out = "Search results for: \"\(query)\"\n\n"; var has = false
        if let ab = json["Abstract"] as? String, !ab.isEmpty {
            out += "Summary: \(ab)\n"
            if let src = json["AbstractSource"] as? String { out += "Source: \(src)\n" }
            if let link = json["AbstractURL"] as? String, !link.isEmpty { out += "URL: \(link)\n" }
            out += "\n"; has = true
        }
        if let topics = json["RelatedTopics"] as? [[String: Any]] {
            var c = 0
            for t in topics where c < 8 {
                if let text = t["Text"] as? String, !text.isEmpty, let fu = t["FirstURL"] as? String {
                    out += "\(c+1). \(text)\n   URL: \(fu)\n\n"; c += 1; has = true
                }
            }
        }
        if !has { out += "No results found." }
        return out
    }

    private func stripHTML(_ html: String) -> String {
        var r = ""; var inTag = false
        for c in html {
            if c == "<" { inTag = true; continue }
            if c == ">" { inTag = false; continue }
            if !inTag { r.append(c) }
        }
        return r
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
