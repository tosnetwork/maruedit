import XCTest
@testable import MaruEditCore

final class TextEncodingTests: XCTestCase {

    func testByteOrderMarkBytesMatchWhatEncodingDetectorRecognizes() {
        XCTAssertEqual(TextEncoding.utf8.byteOrderMark, Data([0xEF, 0xBB, 0xBF]))
        XCTAssertEqual(TextEncoding.utf16LittleEndian.byteOrderMark, Data([0xFF, 0xFE]))
        XCTAssertEqual(TextEncoding.utf16BigEndian.byteOrderMark, Data([0xFE, 0xFF]))
    }

    func testLegacyEncodingsHaveNoByteOrderMark() {
        for encoding in TextEncoding.initialCandidates {
            XCTAssertNil(encoding.byteOrderMark, "\(encoding.rawValue) should have no BOM convention")
        }
    }

    func testEveryUserSelectableEncodingHasADisplayNameAndFoundationMapping() {
        for encoding in TextEncoding.userSelectable {
            XCTAssertFalse(encoding.displayName.isEmpty, "\(encoding.rawValue) has no display name")
            XCTAssertNotNil(encoding.foundationEncoding, "\(encoding.rawValue) has no Foundation encoding mapping")
        }
    }

    func testPrependingByteOrderMarkThenDecodingRoundTrips() throws {
        for encoding in [TextEncoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            guard let foundationEncoding = encoding.foundationEncoding,
                  let bom = encoding.byteOrderMark,
                  let body = "hello".data(using: foundationEncoding) else {
                return XCTFail("setup for \(encoding.rawValue)")
            }
            let withBOM = bom + body
            let result = EncodingDetector.detect(withBOM)
            XCTAssertEqual(result.encoding, encoding)
            XCTAssertTrue(result.hasByteOrderMark)
            XCTAssertEqual(result.content, "hello")
        }
    }
}
