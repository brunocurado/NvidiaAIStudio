import Foundation

/// Skill for generating images using NVIDIA's FLUX model.
/// The AI model calls this when the user requests image generation.
struct ImageGenerationSkill: Skill {
    let name = "generate_image"
    let description = "Generate an image from a text prompt using NVIDIA FLUX. Returns the image as a base64 string."
    
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
        
        guard let url = URL(string: "https://ai.api.nvidia.com/v1/genai/black-forest-labs/flux.2-klein-4b") else {
            throw SkillError.executionFailed("Invalid FLUX API URL")
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
            "steps": 4
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkillError.executionFailed("Invalid response from FLUX API")
        }
        
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw SkillError.executionFailed("FLUX API error \(httpResponse.statusCode): \(body)")
        }
        
        // Parse the response — FLUX returns the image as base64
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SkillError.executionFailed("Could not parse FLUX response")
        }
        
        // Response format: { "image": "<base64_data>" }  or { "artifacts": [{"base64": "..."}] }
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
