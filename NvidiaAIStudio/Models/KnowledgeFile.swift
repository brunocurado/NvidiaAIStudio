import Foundation

/// A named collection of knowledge files (e.g., "Holidu", "Client X").
struct KnowledgeCollection: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var icon: String
    
    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), icon: String = "folder.fill") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.icon = icon
    }
    
    /// The built-in default collection.
    static let `default` = KnowledgeCollection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "Default", icon: "tray.fill")
}

/// A file added to the Knowledge Base for RAG-style context injection.
struct KnowledgeFile: Identifiable, Codable, Equatable {
    let id: UUID
    var collectionID: UUID?              // nil → belongs to Default collection
    let filename: String
    let originalPath: String
    let addedAt: Date
    let mimeType: String
    var totalCharacters: Int
    var pageCount: Int
    var isEnabled: Bool
    var digestStatus: DigestStatus
    var digest: String                   // AI-generated structured summary
    var chunks: [TextChunk]              // Original text split into chunks
    
    init(
        id: UUID = UUID(),
        collectionID: UUID? = nil,
        filename: String,
        originalPath: String,
        addedAt: Date = Date(),
        mimeType: String,
        totalCharacters: Int = 0,
        pageCount: Int = 0,
        isEnabled: Bool = true,
        digestStatus: DigestStatus = .pending,
        digest: String = "",
        chunks: [TextChunk] = []
    ) {
        self.id = id
        self.collectionID = collectionID
        self.filename = filename
        self.originalPath = originalPath
        self.addedAt = addedAt
        self.mimeType = mimeType
        self.totalCharacters = totalCharacters
        self.pageCount = pageCount
        self.isEnabled = isEnabled
        self.digestStatus = digestStatus
        self.digest = digest
        self.chunks = chunks
    }
    
    enum DigestStatus: String, Codable {
        case pending
        case processing
        case completed
        case failed
    }
    
    struct TextChunk: Codable, Identifiable, Equatable {
        let id: UUID
        let pageNumber: Int?
        let content: String
        
        init(id: UUID = UUID(), pageNumber: Int? = nil, content: String) {
            self.id = id
            self.pageNumber = pageNumber
            self.content = content
        }
    }
    
    /// Estimated token count (~4 chars per token)
    var estimatedTokens: Int { totalCharacters / 4 }
    
    /// Estimated digest token count
    var digestTokens: Int { digest.count / 4 }
    
    /// Human-readable file size
    var sizeDescription: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalCharacters))
    }
    
    /// Icon for the file type
    var icon: String {
        switch mimeType {
        case let m where m.contains("pdf"):   return "doc.richtext.fill"
        case let m where m.contains("image"): return "photo.fill"
        case let m where m.hasSuffix("csv"):  return "tablecells.fill"
        case let m where m.hasSuffix("html"): return "globe"
        default:                              return "doc.text.fill"
        }
    }
}
