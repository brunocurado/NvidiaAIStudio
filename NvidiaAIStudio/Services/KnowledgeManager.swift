import Foundation
import PDFKit
import AppKit

/// Manages the Knowledge Base — file ingestion, AI digestion, and context building.
@Observable
final class KnowledgeManager {
    
    var files: [KnowledgeFile] = []
    var collections: [KnowledgeCollection] = []
    var activeCollectionID: UUID? = nil    // nil = Default collection
    var isDigesting = false
    var digestProgress: (current: Int, total: Int) = (0, 0)
    
    static let maxFiles = 100
    private static let chunkSize = 2000   // chars per chunk
    
    private let storageURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NvidiaAIStudio/knowledge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    
    private var metadataURL: URL { storageURL.appendingPathComponent("metadata.json") }
    private var collectionsURL: URL { storageURL.appendingPathComponent("collections.json") }
    private var pagesDir: URL {
        let dir = storageURL.appendingPathComponent("pages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    init() {
        loadMetadata()
    }
    
    // MARK: - Active Collection
    
    /// The currently active collection (Default if none selected).
    var activeCollection: KnowledgeCollection {
        collections.first { $0.id == activeCollectionID } ?? .default
    }
    
    /// All collections including Default.
    var allCollections: [KnowledgeCollection] {
        [.default] + collections
    }
    
    /// Files belonging to the active collection.
    var activeFiles: [KnowledgeFile] {
        files.filter { ($0.collectionID ?? KnowledgeCollection.default.id) == (activeCollectionID ?? KnowledgeCollection.default.id) }
    }
    
    // MARK: - Collection Management
    
    @MainActor
    func createCollection(name: String, icon: String = "folder.fill") -> KnowledgeCollection {
        let collection = KnowledgeCollection(name: name, icon: icon)
        collections.append(collection)
        activeCollectionID = collection.id
        saveMetadata()
        return collection
    }
    
    @MainActor
    func renameCollection(id: UUID, name: String) {
        if let idx = collections.firstIndex(where: { $0.id == id }) {
            collections[idx].name = name
            saveMetadata()
        }
    }
    
    @MainActor
    func deleteCollection(id: UUID) {
        // Remove all files in this collection
        let fileIDs = files.filter { $0.collectionID == id }.map(\.id)
        for fid in fileIDs { removeFile(id: fid) }
        collections.removeAll { $0.id == id }
        if activeCollectionID == id { activeCollectionID = nil }
        saveMetadata()
    }
    
    @MainActor
    func switchCollection(id: UUID?) {
        activeCollectionID = id
    }
    
    // MARK: - File Management
    
    /// Add files to the knowledge base. Reads and chunks content.
    @MainActor
    func addFiles(_ urls: [URL]) -> [KnowledgeFile] {
        var added: [KnowledgeFile] = []
        
        for url in urls {
            guard files.count < Self.maxFiles else { break }
            // Skip duplicates
            guard !files.contains(where: { $0.originalPath == url.path }) else { continue }
            
            let mimeType = Self.mimeType(for: url)
            var file = KnowledgeFile(
                collectionID: activeCollectionID,
                filename: url.lastPathComponent,
                originalPath: url.path,
                mimeType: mimeType
            )
            
            // Extract content based on type
            if mimeType.contains("pdf") {
                extractPDF(url: url, into: &file)
            } else if mimeType.starts(with: "image/") {
                // Store image path — will be sent to vision during digest
                file.chunks = [KnowledgeFile.TextChunk(pageNumber: 1, content: "[Image: \(url.lastPathComponent)]")]
                file.pageCount = 1
                // Copy image to pages directory
                copyImageToPages(url: url, fileID: file.id, page: 0)
            } else {
                extractText(url: url, into: &file)
            }
            
            files.append(file)
            added.append(file)
        }
        
        saveMetadata()
        return added
    }
    
    /// Remove a file from the knowledge base.
    @MainActor
    func removeFile(id: UUID) {
        files.removeAll { $0.id == id }
        // Clean up page images
        let pattern = "\(id.uuidString)"
        if let contents = try? FileManager.default.contentsOfDirectory(at: pagesDir, includingPropertiesForKeys: nil) {
            for file in contents where file.lastPathComponent.hasPrefix(pattern) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        saveMetadata()
    }
    
    /// Toggle a file enabled/disabled.
    @MainActor
    func toggleFile(id: UUID) {
        if let idx = files.firstIndex(where: { $0.id == id }) {
            files[idx].isEnabled.toggle()
            saveMetadata()
        }
    }
    
    /// Clear all files.
    @MainActor
    func clearAll() {
        files.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: pagesDir, withIntermediateDirectories: true)
        saveMetadata()
    }
    
    // MARK: - Digest (AI Processing)
    
    /// Digest all pending files using the AI API.
    func digestAll(
        service: any AIProvider,
        model: AIModel,
        visionModel: AIModel?
    ) async {
        let pending = await MainActor.run {
            isDigesting = true
            let pendingFiles = files.enumerated().filter { $0.element.digestStatus == .pending || $0.element.digestStatus == .failed }
            digestProgress = (0, pendingFiles.count)
            return pendingFiles.map { (index: $0.offset, file: $0.element) }
        }
        
        for item in pending {
            await MainActor.run {
                digestProgress.current = pending.firstIndex(where: { $0.index == item.index }).map { $0 + 1 } ?? 0
                if item.index < files.count {
                    files[item.index].digestStatus = .processing
                }
            }
            
            let digest = await digestSingleFile(
                file: item.file,
                service: service,
                model: model,
                visionModel: visionModel
            )
            
            await MainActor.run {
                guard item.index < files.count else { return }
                if let digest {
                    files[item.index].digest = digest
                    files[item.index].digestStatus = .completed
                } else {
                    files[item.index].digestStatus = .failed
                }
                saveMetadata()
            }
        }
        
        await MainActor.run {
            isDigesting = false
        }
    }
    
    /// Digest a single file — sends content to the AI for summarization.
    private func digestSingleFile(
        file: KnowledgeFile,
        service: any AIProvider,
        model: AIModel,
        visionModel: AIModel?
    ) async -> String? {
        // Build the digest prompt
        let textContent = file.chunks.map { chunk in
            if let page = chunk.pageNumber {
                return "--- Page \(page) ---\n\(chunk.content)"
            }
            return chunk.content
        }.joined(separator: "\n\n")
        
        let systemPrompt = """
        You are a document analyzer. Your task is to create a comprehensive, structured summary of the provided document.
        
        Create a detailed summary that covers:
        1. ALL procedures, workflows, and step-by-step processes
        2. ALL rules, policies, and conditions
        3. ALL exceptions and edge cases
        4. Key terms and definitions
        5. Decision trees and if/then conditions
        6. Any tables, lists, or reference data
        
        Format the summary as structured markdown with clear headers and bullet points.
        Be thorough — the summary will be used as a reference to answer questions about this document.
        Preserve specific details like numbers, dates, percentages, and exact conditions.
        
        IMPORTANT: Write the summary in the SAME LANGUAGE as the original document.
        """
        
        let userPrompt = """
        Analyze and summarize this document: "\(file.filename)"
        
        Document content:
        \(textContent.prefix(150_000))
        """

        var messages: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: userPrompt)
        ]
        
        // If PDF has images and we have a vision model, include page images
        if file.mimeType.contains("pdf"), let vm = visionModel, vm.supportsVision {
            let imageAttachments = loadPageImages(fileID: file.id, maxPages: 8)
            if !imageAttachments.isEmpty {
                // Add images to the user message
                messages[1] = Message(
                    role: .user,
                    content: userPrompt,
                    attachments: imageAttachments
                )
            }
        }
        
        // Call the API and collect the full response
        let stream = service.chat(messages: messages, model: model, tools: nil, reasoningLevel: .off)
        
        var result = ""
        do {
            for try await chunk in stream {
                if let content = chunk.content {
                    result += content
                }
            }
        } catch {
            print("[KnowledgeManager] Digest error for \(file.filename): \(error)")
            return nil
        }
        
        return result.isEmpty ? nil : result
    }
    
    // MARK: - Context Building
    
    /// Build context string from digests for injection into the system prompt.
    func buildContext(query: String) -> String {
        let enabledFiles = activeFiles.filter { $0.isEnabled && $0.digestStatus == .completed }
        guard !enabledFiles.isEmpty else { return "" }
        
        var context = "\n\n## Knowledge Base Context\nThe user has a knowledge base with the following documents. Use this context to answer their questions accurately.\n\n"
        
        // Inject all digests — they're compressed summaries, so they fit easily
        for file in enabledFiles {
            context += "### 📄 \(file.filename)\n"
            context += file.digest
            context += "\n\n---\n\n"
        }
        
        // If the query matches specific chunks, add those too (for precision)
        let queryWords = Set(query.lowercased().split(separator: " ").filter { $0.count > 3 }.map(String.init))
        if !queryWords.isEmpty {
            var relevantChunks: [(file: String, chunk: KnowledgeFile.TextChunk, score: Int)] = []
            
            for file in enabledFiles {
                for chunk in file.chunks {
                    let chunkLower = chunk.content.lowercased()
                    let score = queryWords.filter { chunkLower.contains($0) }.count
                    if score > 0 {
                        relevantChunks.append((file.filename, chunk, score))
                    }
                }
            }
            
            // Top 10 most relevant chunks
            let topChunks = relevantChunks.sorted { $0.score > $1.score }.prefix(10)
            if !topChunks.isEmpty {
                context += "### Relevant Source Excerpts\n"
                for item in topChunks {
                    let pageInfo = item.chunk.pageNumber.map { " (Page \($0))" } ?? ""
                    context += "**\(item.file)\(pageInfo):**\n\(item.chunk.content)\n\n"
                }
            }
        }
        
        return context
    }
    
    /// Build image attachments for pages relevant to the query.
    func buildImageAttachments(query: String, maxImages: Int = 5) -> [Message.Attachment] {
        let enabledFiles = activeFiles.filter { $0.isEnabled && $0.mimeType.contains("pdf") }
        guard !enabledFiles.isEmpty else { return [] }
        
        let queryWords = Set(query.lowercased().split(separator: " ").filter { $0.count > 3 }.map(String.init))
        guard !queryWords.isEmpty else { return [] }
        
        // Find pages with relevant text
        var relevantPages: [(fileID: UUID, filename: String, page: Int, score: Int)] = []
        
        for file in enabledFiles {
            for chunk in file.chunks {
                guard let page = chunk.pageNumber else { continue }
                let chunkLower = chunk.content.lowercased()
                let score = queryWords.filter { chunkLower.contains($0) }.count
                if score > 0 {
                    relevantPages.append((file.id, file.filename, page, score))
                }
            }
        }
        
        let topPages = relevantPages
            .sorted { $0.score > $1.score }
            .prefix(maxImages)
        
        var attachments: [Message.Attachment] = []
        for pageInfo in topPages {
            let imageURL = pagesDir.appendingPathComponent("\(pageInfo.fileID.uuidString)_page\(pageInfo.page).png")
            if let data = try? Data(contentsOf: imageURL) {
                let base64 = data.base64EncodedString()
                attachments.append(Message.Attachment(
                    filename: "\(pageInfo.filename)_page\(pageInfo.page).png",
                    mimeType: "image/png",
                    data: base64
                ))
            }
        }
        
        return attachments
    }
    
    // MARK: - File Extraction
    
    private func extractPDF(url: URL, into file: inout KnowledgeFile) {
        guard let doc = PDFDocument(url: url) else { return }
        file.pageCount = doc.pageCount
        
        var allText = ""
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let pageText = page.string ?? ""
            allText += pageText
            
            // Chunk per page
            if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let pageChunks = Self.chunkText(pageText, pageNumber: i + 1)
                file.chunks.append(contentsOf: pageChunks)
            }
            
            // Render page as image for vision
            renderPageToImage(page: page, fileID: file.id, pageNumber: i)
        }
        
        file.totalCharacters = allText.count
    }
    
    private func extractText(url: URL, into file: inout KnowledgeFile) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            // Try other encodings
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .ascii)
            else { return }
            file.chunks = Self.chunkText(text)
            file.totalCharacters = text.count
            return
        }
        file.chunks = Self.chunkText(text)
        file.totalCharacters = text.count
    }
    
    private func renderPageToImage(page: PDFPage, fileID: UUID, pageNumber: Int) {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 1.5  // ~108 DPI — good balance of quality vs size
        let imageSize = NSSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let image = NSImage(size: imageSize)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: imageSize))
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
        }
        image.unlockFocus()
        
        // Save as PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.7])
        else { return }
        
        let outputURL = pagesDir.appendingPathComponent("\(fileID.uuidString)_page\(pageNumber).png")
        try? pngData.write(to: outputURL)
    }
    
    private func copyImageToPages(url: URL, fileID: UUID, page: Int) {
        let dest = pagesDir.appendingPathComponent("\(fileID.uuidString)_page\(page).png")
        try? FileManager.default.copyItem(at: url, to: dest)
    }
    
    private func loadPageImages(fileID: UUID, maxPages: Int) -> [Message.Attachment] {
        var attachments: [Message.Attachment] = []
        for i in 0..<maxPages {
            let imageURL = pagesDir.appendingPathComponent("\(fileID.uuidString)_page\(i).png")
            guard let data = try? Data(contentsOf: imageURL) else { continue }
            let base64 = data.base64EncodedString()
            attachments.append(Message.Attachment(
                filename: "page_\(i + 1).png",
                mimeType: "image/png",
                data: base64
            ))
        }
        return attachments
    }
    
    // MARK: - Text Chunking
    
    private static func chunkText(_ text: String, pageNumber: Int? = nil) -> [KnowledgeFile.TextChunk] {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        
        if clean.count <= chunkSize {
            return [KnowledgeFile.TextChunk(pageNumber: pageNumber, content: clean)]
        }
        
        var chunks: [KnowledgeFile.TextChunk] = []
        var startIndex = clean.startIndex
        
        while startIndex < clean.endIndex {
            let endOffset = clean.index(startIndex, offsetBy: chunkSize, limitedBy: clean.endIndex) ?? clean.endIndex
            var endIndex = endOffset
            
            // Try to break at a paragraph or sentence boundary
            if endIndex < clean.endIndex {
                let searchRange = startIndex..<endIndex
                if let paraBreak = clean[searchRange].range(of: "\n\n", options: .backwards) {
                    endIndex = paraBreak.upperBound
                } else if let sentenceBreak = clean[searchRange].range(of: ". ", options: .backwards) {
                    endIndex = sentenceBreak.upperBound
                }
            }
            
            let chunk = String(clean[startIndex..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty {
                chunks.append(KnowledgeFile.TextChunk(pageNumber: pageNumber, content: chunk))
            }
            startIndex = endIndex
        }
        
        return chunks
    }
    
    // MARK: - Persistence
    
    private func saveMetadata() {
        if let data = try? JSONEncoder().encode(files) {
            try? data.write(to: metadataURL)
        }
        if let data = try? JSONEncoder().encode(collections) {
            try? data.write(to: collectionsURL)
        }
    }
    
    private func loadMetadata() {
        if let data = try? Data(contentsOf: metadataURL),
           let loaded = try? JSONDecoder().decode([KnowledgeFile].self, from: data) {
            files = loaded
        }
        if let data = try? Data(contentsOf: collectionsURL),
           let loaded = try? JSONDecoder().decode([KnowledgeCollection].self, from: data) {
            collections = loaded
        }
    }
    
    // MARK: - MIME Type Detection
    
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":                          return "application/pdf"
        case "txt", "text":                  return "text/plain"
        case "md", "markdown":               return "text/markdown"
        case "swift":                        return "text/x-swift"
        case "py":                           return "text/x-python"
        case "js", "jsx", "ts", "tsx":       return "text/javascript"
        case "json":                         return "application/json"
        case "csv":                          return "text/csv"
        case "html", "htm":                  return "text/html"
        case "xml":                          return "text/xml"
        case "yaml", "yml":                  return "text/yaml"
        case "sh", "bash", "zsh":            return "text/x-shellscript"
        case "c", "h":                       return "text/x-c"
        case "cpp", "hpp", "cc":             return "text/x-c++"
        case "java":                         return "text/x-java"
        case "rb":                           return "text/x-ruby"
        case "go":                           return "text/x-go"
        case "rs":                           return "text/x-rust"
        case "png":                          return "image/png"
        case "jpg", "jpeg":                  return "image/jpeg"
        case "gif":                          return "image/gif"
        case "webp":                         return "image/webp"
        case "rtf":                          return "text/rtf"
        case "doc", "docx":                  return "application/msword"
        default:                             return "text/plain"
        }
    }
    
    // MARK: - Stats
    
    var totalCharacters: Int { activeFiles.filter(\.isEnabled).reduce(0) { $0 + $1.totalCharacters } }
    var totalDigestCharacters: Int { activeFiles.filter { $0.isEnabled && $0.digestStatus == .completed }.reduce(0) { $0 + $1.digest.count } }
    var estimatedTokens: Int { totalDigestCharacters / 4 }
    var pendingCount: Int { activeFiles.filter { $0.digestStatus == .pending || $0.digestStatus == .failed }.count }
    var completedCount: Int { activeFiles.filter { $0.digestStatus == .completed }.count }
    var activeFileCount: Int { activeFiles.count }
}
