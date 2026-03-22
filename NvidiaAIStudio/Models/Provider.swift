import Foundation

/// AI provider (NVIDIA NIM, Anthropic, OpenAI, or custom BYOK).
enum Provider: String, Codable, CaseIterable, Identifiable {
    case nvidia = "NVIDIA NIM"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var baseURL: String {
        switch self {
        case .nvidia: return "https://integrate.api.nvidia.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .custom: return ""
        }
    }
    
    var icon: String {
        switch self {
        case .nvidia: return "cpu.fill"
        case .anthropic: return "brain.fill"
        case .openai: return "sparkles"
        case .custom: return "server.rack"
        }
    }
    
    var accentColorName: String {
        switch self {
        case .nvidia: return "nvidia-green"
        case .anthropic: return "anthropic-orange"
        case .openai: return "openai-teal"
        case .custom: return "custom-purple"
        }
    }
}

/// An API key for a provider, stored in the Keychain.
struct APIKey: Identifiable, Codable, Equatable {
    let id: UUID
    var provider: Provider
    var name: String
    var key: String
    var isActive: Bool
    var customBaseURL: String?
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        provider: Provider,
        name: String = "",
        key: String,
        isActive: Bool = true,
        customBaseURL: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.name = name.isEmpty ? provider.rawValue : name
        self.key = key
        self.isActive = isActive
        self.customBaseURL = customBaseURL
        self.createdAt = createdAt
    }
    
    /// The effective base URL (custom override or provider default).
    var effectiveBaseURL: String {
        customBaseURL ?? provider.baseURL
    }
}
