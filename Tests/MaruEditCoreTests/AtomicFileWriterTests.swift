import XCTest
@testable import MaruEditCore

final class AtomicFileWriterTests: XCTestCase {

    func testWriteCreatesFileAndContainingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/file.json")

        try AtomicFileWriter.write(Data("hello".utf8), to: url)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "hello")
    }

    func testWriteOverwritesExistingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("file.json")

        try AtomicFileWriter.write(Data("first".utf8), to: url)
        try AtomicFileWriter.write(Data("second".utf8), to: url)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "second")
    }
}
