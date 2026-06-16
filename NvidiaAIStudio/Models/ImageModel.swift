import Foundation

/// An image generation model available via NVIDIA NIM.
struct ImageModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let endpointURL: String
    let steps: Int
    
    init(id: String, name: String, endpointURL: String, steps: Int) {
        self.id = id
        self.name = name
        self.endpointURL = endpointURL
        self.steps = steps
    }
    
    /// Available Text-to-Image models from the NVIDIA NIM catalog.
    static let availableImageModels: [ImageModel] = [
        ImageModel(
            id: "flux.2-klein-4b",
            name: "FLUX.2 Klein 4B (Rápido)",
            endpointURL: "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.2-klein-4b",
            steps: 4
        ),
        ImageModel(
            id: "flux.1-schnell",
            name: "FLUX.1 Schnell (Rápido)",
            endpointURL: "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-schnell",
            steps: 4
        ),
        ImageModel(
            id: "flux.1-dev",
            name: "FLUX.1 Dev (Qualidade)",
            endpointURL: "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.1-dev",
            steps: 25
        )
    ]
}
