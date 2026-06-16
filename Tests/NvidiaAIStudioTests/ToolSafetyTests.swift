import XCTest
@testable import NvidiaAIStudio

final class ToolSafetyTests: XCTestCase {
    func testSandboxRejectsSiblingPathWithSamePrefix() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NvidiaAIStudioTests-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        let sibling = root.appendingPathComponent("workspace-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        
        let outsideFile = sibling.appendingPathComponent("secret.txt")
        try "outside".write(to: outsideFile, atomically: true, encoding: .utf8)
        
        let args = #"{"path":"\#(outsideFile.path)"}"#
        
        do {
            _ = try await SkillRegistry.shared.execute(
                name: "read_file",
                arguments: args,
                accessLevel: .sandboxed,
                workspacePath: workspace.path
            )
            XCTFail("Sandbox must reject sibling paths that merely share the same prefix.")
        } catch SkillError.permissionDenied {
            // Expected.
        }
    }
    
    func testTextAttachmentsAreIncludedInProviderContent() {
        let data = Data("attached body".utf8).base64EncodedString()
        let message = Message(
            role: .user,
            content: "question",
            attachments: [Message.Attachment(filename: "note.txt", mimeType: "text/plain", data: data)]
        )
        
        let content = message.contentIncludingTextAttachments()
        
        XCTAssertTrue(content.contains("question"))
        XCTAssertTrue(content.contains("note.txt"))
        XCTAssertTrue(content.contains("attached body"))
    }
}
