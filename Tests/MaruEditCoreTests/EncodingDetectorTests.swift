import XCTest
@testable import MaruEditCore

final class EncodingDetectorTests: XCTestCase {

    // MARK: - Empty / ASCII / UTF-8

    func testEmptyDataIsCertainEmptyUTF8() {
        let result = EncodingDetector.detect(Data())
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.confidence, .certain)
        XCTAssertEqual(result.content, "")
    }

    func testPlainUTF8NoBOMIsHighConfidence() {
        let text = "hello, world"
        let result = EncodingDetector.detect(Data(text.utf8))
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.content, text)
        XCTAssertFalse(result.hasByteOrderMark)
    }

    func testJapaneseUTF8NoBOMDecodesExactly() {
        let text = "日本語、漢字、ひらがな、カタカナ、半角ｶﾅ\n① ㈱ 髙 﨑 ～ 〜 ¥ \\ — −\nEmoji: 😀 🗻\nCombining: é が"
        let result = EncodingDetector.detect(Data(text.utf8))
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.content, text)
    }

    // MARK: - BOM detection

    func testUTF8BOMIsStrippedAndCertain() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hello".utf8))
        let result = EncodingDetector.detect(data)
        XCTAssertEqual(result.encoding, .utf8)
        XCTAssertEqual(result.confidence, .certain)
        XCTAssertTrue(result.hasByteOrderMark)
        XCTAssertEqual(result.content, "hello", "the BOM character itself must not appear in the returned content")
    }

    func testUTF16LittleEndianBOMDecodesCorrectly() {
        let text = "日本語 hello"
        guard let body = text.data(using: .utf16LittleEndian) else { return XCTFail("setup") }
        var data = Data([0xFF, 0xFE])
        data.append(body)
        let result = EncodingDetector.detect(data)
        XCTAssertEqual(result.encoding, .utf16LittleEndian)
        XCTAssertEqual(result.confidence, .certain)
        XCTAssertTrue(result.hasByteOrderMark)
        XCTAssertEqual(result.content, text)
    }

    func testUTF16BigEndianBOMDecodesCorrectly() {
        let text = "日本語 hello"
        guard let body = text.data(using: .utf16BigEndian) else { return XCTFail("setup") }
        var data = Data([0xFE, 0xFF])
        data.append(body)
        let result = EncodingDetector.detect(data)
        XCTAssertEqual(result.encoding, .utf16BigEndian)
        XCTAssertEqual(result.confidence, .certain)
        XCTAssertTrue(result.hasByteOrderMark)
        XCTAssertEqual(result.content, text)
    }

    func testUTF32BOMIsRecognizedButNotDecoded() {
        // UTF-32 isn't in the supported candidate set yet (not required by
        // M2-01's acceptance criteria) — must report failure explicitly,
        // never silently misdecode as UTF-16.
        let data = Data([0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00])
        let result = EncodingDetector.detect(data)
        XCTAssertEqual(result.confidence, .failed)
        XCTAssertTrue(result.hasByteOrderMark)
        XCTAssertEqual(result.content, "")
        XCTAssertFalse(result.diagnostics.isEmpty)
    }

    // MARK: - Legacy Japanese candidates (no BOM, not valid UTF-8)

    private let japaneseSample = "日本語のテキストファイルです。漢字とひらがなとカタカナ。"

    func testWindows31JIsDetectedViaRoundTrip() throws {
        guard let encoding = TextEncoding.windows31J.foundationEncoding,
              let data = japaneseSample.data(using: encoding) else {
            throw XCTSkip("Windows-31J encoding unavailable on this system")
        }
        XCTAssertNil(String(data: data, encoding: .utf8), "test setup: must not also be valid UTF-8")

        let result = EncodingDetector.detect(data)
        // Windows-31J is tried first among the legacy candidates, so if
        // these bytes round-trip at all, this is the label that wins.
        XCTAssertEqual(result.encoding, .windows31J)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.content, japaneseSample)
    }

    func testEUCJPIsDetectedAndContentRecoveredExactly() throws {
        guard let data = japaneseSample.data(using: .japaneseEUC) else {
            throw XCTSkip("EUC-JP encoding unavailable on this system")
        }
        XCTAssertNil(String(data: data, encoding: .utf8), "test setup: must not also be valid UTF-8")

        let result = EncodingDetector.detect(data)
        XCTAssertTrue(TextEncoding.initialCandidates.contains(result.encoding), "should match some legacy JP candidate, not fail or silently pick UTF-8")
        XCTAssertEqual(result.confidence, .low)
        XCTAssertEqual(result.content, japaneseSample, "content must be recovered exactly regardless of which byte-compatible candidate label was chosen")
    }

    func testISO2022JPIsDetectedAndContentRecoveredExactly() throws {
        guard let data = japaneseSample.data(using: .iso2022JP) else {
            throw XCTSkip("ISO-2022-JP encoding unavailable on this system")
        }
        // Unlike the other three legacy candidates, ISO-2022-JP bytes are
        // *always* also technically valid UTF-8 (it's a 7-bit-safe,
        // ASCII-range-only encoding) — detection relies on recognizing
        // its ESC-based mode-switch sequence, not on UTF-8 decode failing.
        XCTAssertNotNil(String(data: data, encoding: .utf8), "test setup sanity check: ISO-2022-JP bytes are ASCII-range and thus valid UTF-8 too")

        let result = EncodingDetector.detect(data)
        XCTAssertEqual(result.encoding, .iso2022JP)
        XCTAssertEqual(result.confidence, .high)
        XCTAssertEqual(result.content, japaneseSample)
    }

    // MARK: - Failure case

    func testUndecodableBytesFailExplicitlyRatherThanGuessing() {
        // Neither a recognized BOM, valid UTF-8, nor round-trippable
        // through any legacy candidate.
        let garbage = Data([0x81, 0xFF, 0x00, 0x81, 0xFF, 0x00, 0x81])
        let result = EncodingDetector.detect(garbage)
        XCTAssertEqual(result.confidence, .failed)
        XCTAssertEqual(result.content, "", "must never return partially-decoded or guessed content")
        XCTAssertFalse(result.diagnostics.isEmpty)
    }
}
