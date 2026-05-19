import Foundation
import NaturalLanguage

/// Core service for Local RAG using Apple's Native Machine Learning.
/// Generates vectors and calculates semantic similarity distances offline.
final class EmbeddingService {
    static let shared = EmbeddingService()
    
    // The English sentence embedding model is highly effective for code and tech documentation, 
    // regardless of the user's UI language.
    private let embeddingModel: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .english)
    
    /// Generates a multidimensional vector for a block of text using macOS Neural Engine.
    func vectorize(_ text: String) -> [Double]? {
        guard let model = embeddingModel else { return nil }
        // Clean text slightly before embedding to improve vector quality
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.vector(for: cleanText)
    }
    
    /// Calculates Cosine Similarity between two text vectors.
    /// Returns a value between -1.0 (opposite) and 1.0 (identical/perfect match).
    func cosineSimilarity(a: [Double], b: [Double]) -> Double {
        guard a.count == b.count, a.count > 0 else { return 0.0 }
        var dotProduct: Double = 0.0
        var normA: Double = 0.0
        var normB: Double = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        if normA == 0.0 || normB == 0.0 { return 0.0 }
        return dotProduct / (sqrt(normA) * sqrt(normB))
    }
}
