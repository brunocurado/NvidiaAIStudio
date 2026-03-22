import Foundation

/// An AI model available via NVIDIA NIM or other providers.
struct AIModel: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let provider: Provider
    let contextWindow: Int
    let supportsThinking: Bool
    let supportsVision: Bool
    var isEnabled: Bool
    
    init(
        id: String,
        name: String,
        provider: Provider = .nvidia,
        contextWindow: Int = 128_000,
        supportsThinking: Bool = false,
        supportsVision: Bool = false,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.contextWindow = contextWindow
        self.supportsThinking = supportsThinking
        self.supportsVision = supportsVision
        self.isEnabled = isEnabled
    }
    
    /// Curated default models matching the Python `models.py` list.
    static let defaultModels: [AIModel] = [
        // ── Flagship / Daily Drivers ──
        AIModel(id: "deepseek-ai/deepseek-v3.2", name: "🔮 DeepSeek V3.2 — Raciocínio de topo", contextWindow: 128_000, supportsThinking: true),
        AIModel(id: "deepseek-ai/deepseek-v3.1", name: "🧠 DeepSeek V3.1 — Versão estável", contextWindow: 128_000, supportsThinking: true),
        AIModel(id: "meta/llama-3.3-70b-instruct", name: "⚡ Llama 3.3 70B — Rápido e fiável", contextWindow: 131_072),
        AIModel(id: "mistralai/mistral-large-3-675b-instruct-2512", name: "🦾 Mistral Large 3 — Peso Pesado Europeu", contextWindow: 131_072, supportsVision: true),
        AIModel(id: "minimaxai/minimax-m2.5", name: "🕵️ MiniMax M2.5 — Leve e versátil", contextWindow: 128_000),
        
        // ── Thinking / Reasoning ──
        AIModel(id: "moonshotai/kimi-k2-thinking", name: "🌙 Kimi K2 Thinking — Raciocínio 256K", contextWindow: 262_144, supportsThinking: true),
        AIModel(id: "moonshotai/kimi-k2.5", name: "🌙 Kimi K2.5 — Rápido 256K", contextWindow: 262_144),
        AIModel(id: "qwen/qwq-32b", name: "🤔 QwQ 32B — Raciocínio Matemático", contextWindow: 131_072, supportsThinking: true),
        AIModel(id: "qwen/qwen3-next-80b-a3b-thinking", name: "🦸 Qwen Next Thinking — Profundo", contextWindow: 131_072, supportsThinking: true),
        
        // ── Code ──
        AIModel(id: "qwen/qwen3-coder-480b-a35b-instruct", name: "💻 Qwen3 Coder 480B — Rei do Código", contextWindow: 131_072),
        
        // ── Vision / Multimodal ──
        AIModel(id: "qwen/qwen3.5-397b-a17b", name: "🧠 Qwen 3.5 397B — Gigante Multimodal", contextWindow: 131_072, supportsThinking: true, supportsVision: true),
        AIModel(id: "qwen/qwen3.5-122b-a10b", name: "🎥 Qwen 3.5 122B — Visão + Vídeo 262K", contextWindow: 262_144, supportsThinking: true, supportsVision: true),
        AIModel(id: "nvidia/nemotron-nano-12b-v2-vl", name: "👁️ Nemotron VL — Visão rápida", contextWindow: 32_768, supportsVision: true),
        
        // ── Experimental ──
        AIModel(id: "nvidia/nemotron-3-super-120b-a12b", name: "🔥 Nemotron 3 Super 120B", contextWindow: 262_144, supportsThinking: true),
        AIModel(id: "bytedance/seed-oss-36b-instruct", name: "🌱 Seed 36B (ByteDance) — Rápido", contextWindow: 131_072),
        AIModel(id: "z-ai/glm5", name: "⭐ GLM-5 744B — Gigante Chinês", contextWindow: 131_072),
    ]
}
