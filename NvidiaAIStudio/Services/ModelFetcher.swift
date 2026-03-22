import Foundation

/// Fetches available models from the NVIDIA NIM API on app launch.
/// Updates AppState.availableModels with live data while keeping user's
/// isEnabled preferences.
enum ModelFetcher {
    
    /// Fetch the list of available models from the NVIDIA NIM API.
    /// Returns an array of AIModel, or nil if the fetch failed.
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
                
                // Derive display name from the model ID
                let name = formatModelName(id)
                
                // Try to detect context window and capabilities from the ID
                let supportsThinking = id.contains("thinking") || id.contains("deepseek") || id.contains("qwq") || id.contains("kimi")
                let supportsVision = id.contains("-vl") || id.contains("vision")
                
                return AIModel(
                    id: id,
                    name: name,
                    provider: .nvidia,
                    contextWindow: 128_000,
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
    
    /// Merge fetched models with existing models, preserving user preferences.
    /// Guarantees no duplicate IDs in the result.
    static func mergeModels(existing: [AIModel], fetched: [AIModel]) -> [AIModel] {
        // Build lookup of existing models — safe merge, last entry wins on duplicate IDs
        let existingByID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        
        // Track which IDs we've already added to prevent duplicates
        var seenIDs = Set<String>()
        var merged: [AIModel] = []
        
        // First pass: fetched models (prefer these as they are live from the API)
        for var model in fetched {
            guard !seenIDs.contains(model.id) else { continue }
            seenIDs.insert(model.id)
            
            // Preserve the user's isEnabled preference and curated metadata
            if let existing = existingByID[model.id] {
                model = AIModel(
                    id: model.id,
                    name: existing.name.isEmpty ? model.name : existing.name,
                    provider: model.provider,
                    contextWindow: existing.contextWindow > 0 ? existing.contextWindow : model.contextWindow,
                    supportsThinking: existing.supportsThinking || model.supportsThinking,
                    supportsVision: existing.supportsVision || model.supportsVision,
                    isEnabled: existing.isEnabled
                )
            }
            merged.append(model)
        }
        
        // Second pass: add any existing (curated) models not returned by the API
        for existing in existing {
            guard !seenIDs.contains(existing.id) else { continue }
            seenIDs.insert(existing.id)
            merged.append(existing)
        }
        
        return merged
    }
    
    /// Format a model ID like "deepseek-ai/deepseek-v3.2" into "DeepSeek V3.2"
    private static func formatModelName(_ id: String) -> String {
        let basename = id.split(separator: "/").last ?? Substring(id)
        return String(basename)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let w = String(word)
                // Capitalize first letter, keep version numbers as-is
                if w.first?.isNumber == true { return w }
                return w.prefix(1).uppercased() + w.dropFirst()
            }
            .joined(separator: " ")
    }
}
