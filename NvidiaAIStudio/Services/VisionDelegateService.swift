import Foundation

/// Automatically describes images using a vision-capable model when the active
/// model doesn't support vision. This enables any model to "see" images.
struct VisionDelegateService {
    
    /// Describe an image attachment using a vision model.
    /// Returns a text description that can be injected into the conversation.
    static func describeImage(
        base64Data: String,
        mimeType: String,
        apiKey: String,
        visionModelID: String = UserDefaults.standard.string(forKey: "visionDelegateModelID") ?? "nvidia/nemotron-nano-12b-v2-vl"
    ) async -> String? {
        let baseURL = "https://integrate.api.nvidia.com/v1"
        guard let url = URL(string: "\(baseURL)/chat/completions") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        let body: [String: Any] = [
            "model": visionModelID,
            "max_tokens": 500,
            "stream": false,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "Describe this image in detail for another AI model that cannot see images. Include: objects, text, layout, colors, mood, and any relevant details."
                        ],
                        [
                            "type": "image_url",
                            "image_url": ["url": "data:\(mimeType);base64,\(base64Data)"]
                        ]
                    ]
                ] as [String: Any]
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            
            return content
        } catch {
            return nil
        }
    }
}
