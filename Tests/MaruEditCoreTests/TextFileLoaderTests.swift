import XCTest
@testable import MaruEditCore

final class TextFileLoaderTests: XCTestCase {

    private func tempFile(named name: String, contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextFileLoaderTests-\(UUID().uuidString)-\(name)")
        try contents.write(to: url)
        return url
    }

    func testLoadingMissingFileThrows() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString).txt")
        XCTAssertThrowsError(try TextFileLoader.load(contentsOf: url)) { error in
            guard case TextFileLoaderError.fileNotReadable = error else {
                return XCTFail("expected fileNotReadable, got \(error)")
            }
        }
    }

    func testLoadingUndecodableFileThrows() throws {
        let url = try tempFile(named: "garbage.bin", contents: Data([0x81, 0xFF, 0x00, 0x81, 0xFF, 0x00, 0x81]))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try TextFileLoader.load(contentsOf: url)) { error in
            guard case TextFileLoaderError.couldNotDecode = error else {
                return XCTFail("expected couldNotDecode, got \(error)")
            }
        }
    }

    // MARK: - Acceptance: each initial-target encoding "opens as expected"

    func testUTF8SampleOpensAsExpected() throws {
        try assertSampleOpens(encoding: .utf8, using: nil) // nil = write raw UTF-8 bytes directly
    }

    func testUTF16SampleOpensAsExpected() throws {
        let text = japaneseSample
        guard let body = text.data(using: .utf16LittleEndian) else { return XCTFail("setup") }
        var data = Data([0xFF, 0xFE])
        data.append(body)
        let url = try tempFile(named: "utf16.txt", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try TextFileLoader.load(contentsOf: url)
        XCTAssertEqual(loaded.content, text)
        XCTAssertEqual(loaded.encoding, .utf16LittleEndian)
        XCTAssertTrue(loaded.hasByteOrderMark)
    }

    func testWindows31JSampleOpensAsExpected() throws {
        try assertSampleOpens(encoding: .windows31J, using: TextEncoding.windows31J.foundationEncoding)
    }

    func testShiftJISClassicSampleOpensAsExpected() throws {
        try assertSampleOpens(encoding: .shiftJISClassic, using: .shiftJIS)
    }

    func testEUCJPSampleOpensAsExpected() throws {
        try assertSampleOpens(encoding: .eucJP, using: .japaneseEUC)
    }

    func testISO2022JPSampleOpensAsExpected() throws {
        try assertSampleOpens(encoding: .iso2022JP, using: .iso2022JP)
    }

    private let japaneseSample = "日本語のテキストファイルです。漢字とひらがなとカタカナ。"

    private func assertSampleOpens(encoding: TextEncoding, using foundationEncoding: String.Encoding?) throws {
        let data: Data
        if let foundationEncoding {
            guard let encoded = japaneseSample.data(using: foundationEncoding) else {
                throw XCTSkip("\(encoding.displayName) unavailable on this system")
            }
            data = encoded
        } else {
            data = Data(japaneseSample.utf8)
        }

        let url = try tempFile(named: "sample.txt", contents: data)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try TextFileLoader.load(contentsOf: url)
        XCTAssertEqual(loaded.content, japaneseSample)
        XCTAssertNotEqual(loaded.confidence, .failed)
    }

    // MARK: - File metadata capture

    func testLoadCapturesSizePermissionsAndIdentity() throws {
        let url = try tempFile(named: "meta.txt", contents: Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try TextFileLoader.load(contentsOf: url)
        XCTAssertEqual(loaded.fileSize, 5)
        XCTAssertNotNil(loaded.modificationDate)
        XCTAssertNotNil(loaded.fileIdentity)
        XCTAssertEqual(loaded.fileIdentity, FileIdentity.of(url))
    }
}
