import XCTest
@testable import MaruEdit

final class DocumentTests: XCTestCase {

    func testNewDocumentDefaults() {
        let doc = Document()
        XCTAssertNil(doc.fileURL)
        XCTAssertEqual(doc.content, "")
        XCTAssertFalse(doc.isModified)
        XCTAssertEqual(doc.displayName, "Untitled")
        XCTAssertEqual(doc.language, .plainText)
    }

    func testMarkModifiedAndSaved() {
        let doc = Document(content: "hello")
        XCTAssertFalse(doc.isModified)

        doc.content = "hello world"
        doc.markModified()
        XCTAssertTrue(doc.isModified)

        doc.markSaved()
        XCTAssertFalse(doc.isModified)
    }

    func testDetectLanguageFromExtension() {
        XCTAssertEqual(Document.detectLanguage(for: URL(fileURLWithPath: "main.swift")), .swift)
        XCTAssertEqual(Document.detectLanguage(for: URL(fileURLWithPath: "script.py")), .python)
        XCTAssertEqual(Document.detectLanguage(for: URL(fileURLWithPath: "notes.txt")), .plainText)
        XCTAssertEqual(Document.detectLanguage(for: URL(fileURLWithPath: "no-extension")), .plainText)
    }

    func testSaveAndReopenRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("MaruEditDocumentTests-\(UUID().uuidString).swift")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = Document(content: "let x = 1\n")
        try original.save(to: url)
        XCTAssertFalse(original.isModified)

        let reopened = try Document.open(url: url)
        XCTAssertEqual(reopened.content, "let x = 1\n")
        XCTAssertEqual(reopened.language, .swift)
        XCTAssertEqual(reopened.displayName, url.lastPathComponent)
    }
}
