import Foundation

/// Fetches available models from the NVIDIA NIM API on app launch.
/// Updates AppState.availableModels with live data while keeping user's
/// isEnabled preferences.
enum ModelFetcher {
    
    // MARK: - Known Context Windows
    
    /// Known context window sizes for models on the NVIDIA NIM platform.
    /// Keyed by substring match against model ID — first match wins.
    /// Models not matched here default to 128K.
    private static let knownContextWindows: [(pattern: String, contextWindow: Int)] = [
        // 1M+ context
        ("deepseek-v4",                 1_000_000),
        ("gpt-4.1",                     1_000_000),
        ("qwen3.6",                     1_000_000),
        ("minimax-m3",                  1_000_000),
        ("minimax-m4",                  1_000_000),
        ("llama-4",                     1_000_000),
        ("nemotron-ultra",              1_000_000),
        
        // 262K context
        ("kimi-k2",                     262_144),
        ("kami-k1.5",                   262_144),
        ("nemotron-3-super",            262_144),
        ("qwen3.5-122b",               262_144),
        ("gemma-4",                     262_144),
        
        // 200K context
        ("claude",                      200_000),
        
        // 131K context
        ("llama-3.3",                   131_072),
        ("llama-3.1",                   131_072),
        ("llama-3.2",                   131_072),
        ("mistral-large",               131_072),
        ("qwq-32b",                     131_072),
        ("qwen3-next",                  131_072),
        ("qwen3-coder",                 131_072),
        ("qwen3.5-397b",               131_072),
        ("seed-oss",                    131_072),
        ("glm5",                        131_072),
        ("gemma",                       131_072),
        
        // 128K context (default tier)
        ("deepseek",                    128_000),
        ("minimax",                     128_000),
        ("qwen2",                       128_000),
        
        // 32K context
        ("nemotron-nano",               32_768),
        ("nemotron-mini",               32_768),
        ("phi-3",                       32_768),
        ("phi-4",                       32_768),
        
        // 16K context
        ("yi-",                         16_384),
        
        // 8K context
        ("mistral-7b",                  8_192),
        ("codellama",                   8_192),
    ]
    
    // MARK: - Known Capabilities
    
    /// Patterns that indicate thinking/reasoning support
    private static let thinkingPatterns = [
        "thinking", "deepseek", "qwq", "kimi", "o1", "o3", "o4",
        "qwen3-next", "qwen3.5", "nemotron-3-super",
        "mistral-small-4", "mistral-medium-3", "mistral-large-3", "gemma-4",
        "minimax-m3", "minimax-m4"
    ]
    
    /// Patterns that indicate vision/multimodal support
    private static let visionPatterns = [
        "-vl", "vision", "multimodal", "qwen3.5-122b", "qwen3.5-397b",
        "mistral-large-3", "mistral-small-4", "mistral-medium-3",
        "nemotron-nano-12b-v2-vl", "gpt-4o", "gpt-4.1",
        "minimax-m3", "minimax-m4"
    ]
    
    // MARK: - Fetch
    
    /// Fetch the list of available models from the active API.
    static func fetchModels(apiKey: String, baseURL: String, provider: Provider) async -> [AIModel]? {
        // Skip Anthropic native API since it doesn't have a standard /v1/models endpoint
        if provider == .anthropic { return nil }
        
        let endpoint = baseURL.hasSuffix("/") ? "\(baseURL)models" : "\(baseURL)/models"
        guard let url = URL(string: endpoint) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLog.network.warning("ModelFetcher: Not an HTTP response")
                return nil
            }

            if httpResponse.statusCode != 200 {
                AppLog.network.warning("ModelFetcher: HTTP \(httpResponse.statusCode) from \(endpoint, privacy: .public)")
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else {
                AppLog.network.warning("ModelFetcher: JSON decode failed")
                return nil
            }
            
            let parsed = models.compactMap { modelDict -> AIModel? in
                guard let id = modelDict["id"] as? String else { return nil }
                
                // OpenRouter often adds name field
                let rawName = modelDict["name"] as? String ?? id
                let name = formatModelName(rawName.isEmpty ? id : rawName)
                
                var dynamicContext = modelDict["context_length"] as? Int
                if dynamicContext == nil, let topProv = modelDict["top_provider"] as? [String: Any] {
                    dynamicContext = topProv["context_length"] as? Int
                }
                if dynamicContext == nil, let arch = modelDict["architecture"] as? [String: Any] {
                    dynamicContext = arch["context_length"] as? Int
                }
                
                let contextWindow = dynamicContext ?? resolveContextWindow(for: id)
                
                let supportsThinking = thinkingPatterns.contains { id.lowercased().contains($0) }
                let supportsVision = visionPatterns.contains { id.lowercased().contains($0) }
                
                return AIModel(
                    id: id,
                    name: name,
                    provider: provider,
                    contextWindow: contextWindow,
                    supportsThinking: supportsThinking,
                    supportsVision: supportsVision,
                    isEnabled: true
                )
            }.sorted { $0.name < $1.name }
            
            AppLog.network.notice("ModelFetcher: Successfully fetched \(parsed.count) models!")
            return parsed

        } catch {
            AppLog.network.error("ModelFetcher: Network error - \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    // MARK: - Context Window Resolution
    
    /// Resolve the context window for a model ID by matching against known patterns.
    /// Falls back to 128K if no pattern matches.
    private static func resolveContextWindow(for modelID: String) -> Int {
        let lowered = modelID.lowercased()
        if let parsedSize = parseContextFromID(lowered) {
            return parsedSize
        }
        for entry in knownContextWindows {
            if lowered.contains(entry.pattern.lowercased()) {
                return entry.contextWindow
            }
        }
        return 128_000  // safe default
    }
    
    /// Extract context size from ID using regex (e.g. -1m, -256k)
    private static func parseContextFromID(_ id: String) -> Int? {
        let pattern = "(?:^|[^a-zA-Z0-9])(\\d+)(k|m)(?:$|[^a-zA-Z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(id.startIndex..<id.endIndex, in: id)
        if let match = regex.firstMatch(in: id, options: [], range: range) {
            if let numRange = Range(match.range(at: 1), in: id),
               let unitRange = Range(match.range(at: 2), in: id) {
                let numStr = String(id[numRange])
                let unitStr = String(id[unitRange]).lowercased()
                if let num = Int(numStr) {
                    if unitStr == "m" {
                        return num * 1_000_000
                    } else if unitStr == "k" {
                        switch num {
                        case 8: return 8_192
                        case 16: return 16_384
                        case 32: return 32_768
                        case 64: return 65_536
                        case 128: return 128_000
                        case 256: return 262_144
                        case 512: return 524_288
                        default: return num * 1000
                        }
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - Merge
    
    /// Merge fetched models with existing models, preserving user preferences.
    /// Guarantees no duplicate IDs in the result.
    static func mergeModels(existing: [AIModel], fetched: [AIModel]) -> [AIModel] {
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        
        var seenIDs = Set<String>()
        var merged: [AIModel] = []
        
        // Fetched models first (live from API)
        for var model in fetched {
            guard !seenIDs.contains(model.id) else { continue }
            seenIDs.insert(model.id)
            
            if let existing = existingByID[model.id] {
                // Curated models take priority for name and capabilities;
                // fetched model provides the context window if curated has default 128K
                let bestContext = existing.contextWindow != 128_000 ? existing.contextWindow : model.contextWindow
                model = AIModel(
                    id: model.id,
                    name: existing.name.isEmpty ? model.name : existing.name,
                    provider: model.provider,
                    contextWindow: bestContext,
                    supportsThinking: existing.supportsThinking || model.supportsThinking,
                    supportsVision: existing.supportsVision || model.supportsVision,
                    isEnabled: existing.isEnabled
                )
            }
            merged.append(model)
        }
        
        // Existing curated models not in API response
        for existing in existing {
            guard !seenIDs.contains(existing.id) else { continue }
            seenIDs.insert(existing.id)
            merged.append(existing)
        }
        
        return merged
    }
    
    // MARK: - Formatting
    
    /// Format a model ID like "deepseek-ai/deepseek-v3.2" into "DeepSeek V3.2"
    private static func formatModelName(_ id: String) -> String {
        let basename = id.split(separator: "/").last ?? Substring(id)
        return String(basename)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let w = String(word)
                if w.first?.isNumber == true { return w }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }
}
