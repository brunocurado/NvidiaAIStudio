import Foundation

/// Skill for generating images using NVIDIA's FLUX model.
/// The AI model calls this when the user requests image generation.
struct ImageGenerationSkill: Skill {
    let name = "generate_image"
    var description: String {
        let selectedModelID = UserDefaults.standard.string(forKey: "selectedImageModelID") ?? "flux.2-klein-4b"
        let modelName = ImageModel.availableImageModels.first(where: { $0.id == selectedModelID })?.name ?? "NVIDIA FLUX"
        return "Generate an image from a text prompt using \(modelName). Returns the image as a base64 string."
    }
    
    var parameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "prompt": [
                    "type": "string",
                    "description": "A detailed description of the image to generate"
                ] as [String: Any],
                "width": [
                    "type": "integer",
                    "description": "Image width in pixels. Default: 1024. Max: 1024."
                ] as [String: Any],
                "height": [
                    "type": "integer",
                    "description": "Image height in pixels. Default: 1024. Max: 1024."
                ] as [String: Any]
            ] as [String: Any],
            "required": ["prompt"]
        ]
    }
    
    func execute(arguments: String) async throws -> String {
        let args = try SkillArgs.parse(arguments)
        let prompt = try SkillArgs.getString(args, key: "prompt")
        let width = SkillArgs.getInt(args, key: "width", defaultValue: 1024)
        let height = SkillArgs.getInt(args, key: "height", defaultValue: 1024)

        let selectedModelID = UserDefaults.standard.string(forKey: "selectedImageModelID") ?? "flux.2-klein-4b"
        guard let imageModel = ImageModel.availableImageModels.first(where: { $0.id == selectedModelID }),
              let url = URL(string: imageModel.endpointURL) else {
            throw SkillError.executionFailed("Configuração de modelo de imagem inválida: \(selectedModelID)")
        }

        // Use NVIDIA API key from environment or keychain
        guard let apiKey = EnvParser.loadNVIDIAKey() else {
            throw SkillError.executionFailed("No NVIDIA API key available for image generation")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let payload: [String: Any] = [
            "prompt": prompt,
            "width": min(width, 1024),
            "height": min(height, 1024),
            "seed": Int.random(in: 0...999999),
            "steps": imageModel.steps
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkillError.executionFailed("Invalid response from NVIDIA NIM API")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            let helpMsg = httpResponse.statusCode == 404 ? " (O modelo selecionado pode não estar hospedado na nuvem pública trial da NVIDIA)" : ""
            throw SkillError.executionFailed("NVIDIA NIM API error \(httpResponse.statusCode): \(body)\(helpMsg)")
        }

        // Parse the response — NIM returns the image as base64
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillError.executionFailed("Could not parse NVIDIA NIM response")
        }

        // Response format: { "image": "<base64_data>" }  or { "artifacts": [{"base64": "..."}] }
        // The [IMAGE_GENERATED] prefix is parsed by ChatViewModel to extract the image as an attachment.
        // The model only sees a clean confirmation message, preventing hallucination.
        if let imageB64 = json["image"] as? String {
            return "[IMAGE_GENERATED]\ndata:image/png;base64,\(imageB64)"
        }

        if let artifacts = json["artifacts"] as? [[String: Any]],
           let first = artifacts.first,
           let b64 = first["base64"] as? String {
            return "[IMAGE_GENERATED]\ndata:image/png;base64,\(b64)"
        }

        return "[IMAGE_GENERATED]\nImage generated successfully but format unknown. Raw: \(String(data: data, encoding: .utf8)?.prefix(500) ?? "?")"
    }
}

// MARK: - Image Generation Result Parser

/// Parses the special [IMAGE_GENERATED] format returned by ImageGenerationSkill.
/// Returns the base64 data URL and a clean text description.
enum ImageGenerationResult {
    static let prefix = "[IMAGE_GENERATED]"

    /// Extracts the image data URL from a generate_image tool result.
    /// - Parameter rawResult: The raw string returned by the tool
    /// - Returns: A tuple with (dataURL, cleanText) or nil if not an image result
    static func parse(_ rawResult: String) -> (dataURL: String, cleanText: String)? {
        guard rawResult.hasPrefix(prefix) else { return nil }

        let lines = rawResult.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }

        let dataURL = lines[1]
        guard dataURL.hasPrefix("data:image/") else { return nil }

        return (dataURL, "✅ Image generated successfully")
    }
}
