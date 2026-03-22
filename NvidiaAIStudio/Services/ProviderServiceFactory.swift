import Foundation

/// Creates the correct AIProvider service based on the active provider and API key.
enum ProviderServiceFactory {

    /// Returns an AIProvider for the given provider + key combination.
    static func make(provider: Provider, apiKey: String, customBaseURL: String? = nil) -> any AIProvider {
        switch provider {
        case .nvidia:
            let url = customBaseURL ?? Provider.nvidia.baseURL
            return NVIDIAAPIService(apiKey: apiKey, baseURL: url)
        case .anthropic:
            let url = customBaseURL ?? Provider.anthropic.baseURL
            return AnthropicAPIService(apiKey: apiKey, baseURL: url)
        case .openai:
            let url = customBaseURL ?? Provider.openai.baseURL
            return OpenAIAPIService(apiKey: apiKey, baseURL: url)
        case .custom:
            // Custom providers: try OpenAI-compatible format first
            let url = customBaseURL ?? ""
            return OpenAIAPIService(apiKey: apiKey, baseURL: url)
        }
    }

    /// Builds the service from AppState — picks the active provider and key automatically.
    static func makeFromAppState(_ appState: AppState) -> (any AIProvider)? {
        guard let key = appState.activeAPIKey ?? EnvParser.loadNVIDIAKey() else { return nil }
        let customURL = appState.apiKeys
            .first { $0.provider == appState.activeProvider && $0.isActive }?
            .customBaseURL
        return make(provider: appState.activeProvider, apiKey: key, customBaseURL: customURL)
    }
}
