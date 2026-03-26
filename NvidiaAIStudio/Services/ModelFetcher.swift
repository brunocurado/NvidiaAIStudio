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
        ("gpt-4.1",                     1_000_000),
        
        // 262K context
        ("kimi-k2",                     262_144),
        ("kimi-k1.5",                   262_144),
        ("nemotron-3-super",            262_144),
        ("qwen3.5-122b",               262_144),
        
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
        "mistral-small-4", "mistral-medium-3", "mistral-large-3"
    ]
    
    /// Patterns that indicate vision/multimodal support
    private static let visionPatterns = [
        "-vl", "vision", "multimodal", "qwen3.5-122b", "qwen3.5-397b",
        "mistral-large-3", "mistral-small-4", "mistral-medium-3",
        "nemotron-nano-12b-v2-vl", "gpt-4o", "gpt-4.1"
    ]
    
    // MARK: - Fetch
    
    /// Fetch the list of available models from the NVIDIA NIM API.
    static func fetchModels(apiKey: String, baseURL: String = "https://integrate.api.nvidia.com/v1") async -> [AIModel]? {
        guard let url = URL(string: "\(baseURL)/models") else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = json["data"] as? [[String: Any]] else { return nil }
            
            return models.compactMap { modelDict -> AIModel? in
                guard let id = modelDict["id"] as? String else { return nil }
                
                let name = formatModelName(id)
                let contextWindow = resolveContextWindow(for: id)
                let supportsThinking = thinkingPatterns.contains { id.contains($0) }
                let supportsVision = visionPatterns.contains { id.contains($0) }
                
                return AIModel(
                    id: id,
                    name: name,
                    provider: .nvidia,
                    contextWindow: contextWindow,
                    supportsThinking: supportsThinking,
                    supportsVision: supportsVision,
                    isEnabled: true
                )
            }
            .sorted { $0.name < $1.name }
            
        } catch {
            return nil
        }
    }
    
    // MARK: - Context Window Resolution
    
    /// Resolve the context window for a model ID by matching against known patterns.
    /// Falls back to 128K if no pattern matches.
    private static func resolveContextWindow(for modelID: String) -> Int {
        let lowered = modelID.lowercased()
        for entry in knownContextWindows {
            if lowered.contains(entry.pattern.lowercased()) {
                return entry.contextWindow
            }
        }
        return 128_000  // safe default
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
