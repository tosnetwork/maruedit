import Foundation
import XCTest
@testable import MaruEditCore

final class BinaryDocumentCodecTests: XCTestCase {
    func testFormattingUsesSixteenCommaSeparatedBytesPerLineAndRoundTrips() throws {
        let data = Data(0...32)
        let text = BinaryDocumentCodec.format(data)
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].split(separator: ",").count, 16)
        XCTAssertEqual(lines[1].split(separator: ",").count, 16)
        XCTAssertEqual(lines[2], "20")
        XCTAssertEqual(try BinaryDocumentCodec.parse(text), data)
    }

    func testParserAcceptsWhitespaceButRejectsMalformedBytes() throws {
        XCTAssertEqual(try BinaryDocumentCodec.parse("00, ff\n7A"), Data([0, 255, 122]))
        XCTAssertThrowsError(try BinaryDocumentCodec.parse("0,GG"))
    }
}
