import AppKit
import Foundation
import XCTest
@testable import MaruEditApp

final class BinaryDocumentTests: XCTestCase {
    @MainActor
    func testBinaryGutterUsesHexadecimalByteAddresses() {
        let textView = NSTextView()
        let gutter = LineNumberView(textView: textView)
        gutter.isBinaryMode = true
        XCTAssertEqual(gutter.formattedLineLabel(1), "00000000")
        XCTAssertEqual(gutter.formattedLineLabel(17), "00000100")
    }

    func testBinaryDocumentEditsAndSavesExactBytes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-binary-\(UUID().uuidString).bin")
        try Data([0x00, 0x7F, 0xFF]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try Document.openBinary(url: url)
        XCTAssertTrue(document.isBinaryMode)
        XCTAssertEqual(document.content, "00,7F,FF")
        document.content = "CA,FE,BA,BE"
        document.markModified()
        try document.save()

        XCTAssertEqual(try Data(contentsOf: url), Data([0xCA, 0xFE, 0xBA, 0xBE]))
        XCTAssertFalse(document.isModified)
    }

    func testMalformedBinaryTextNeverOverwritesOriginalFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEdit-binary-invalid-\(UUID().uuidString).bin")
        let original = Data([1, 2, 3])
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try Document.openBinary(url: url)
        document.content = "01,NOT-A-BYTE"
        document.markModified()
        XCTAssertThrowsError(try document.save())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
