import XCTest
@testable import MaruEditCore

final class LineEndingDetectorTests: XCTestCase {

    func testUniformLF() {
        XCTAssertEqual(LineEndingDetector.detect("a\nb\nc\n"), .lf)
    }

    func testUniformCRLF() {
        XCTAssertEqual(LineEndingDetector.detect("a\r\nb\r\nc\r\n"), .crlf)
    }

    func testUniformCR() {
        XCTAssertEqual(LineEndingDetector.detect("a\rb\rc\r"), .cr)
    }

    func testNoLineBreaksIsNone() {
        XCTAssertEqual(LineEndingDetector.detect("just one line, no breaks"), .none)
        XCTAssertEqual(LineEndingDetector.detect(""), .none)
    }

    func testMixedReportsAccurateCounts() {
        let result = LineEndingDetector.detect("a\nb\r\nc\rd\n")
        guard case .mixed(let summary) = result else {
            return XCTFail("expected .mixed, got \(result)")
        }
        XCTAssertEqual(summary.lfCount, 2)
        XCTAssertEqual(summary.crlfCount, 1)
        XCTAssertEqual(summary.crCount, 1)
    }

    func testCRLFIsNotDoubleCountedAsCRAndLF() {
        // A naive scanner that checks \r and \n independently would see
        // this as both a CR and an LF; it must be recognized as one CRLF.
        let result = LineEndingDetector.detect("a\r\nb")
        XCTAssertEqual(result, .crlf)
    }

    // MARK: - Normalize

    func testNormalizeConvertsEverythingToLF() {
        XCTAssertEqual(LineEndingDetector.normalize("a\r\nb\rc\nd"), "a\nb\nc\nd")
    }

    func testNormalizeIsIdempotentOnAlreadyLFText() {
        let text = "a\nb\nc\n"
        XCTAssertEqual(LineEndingDetector.normalize(text), text)
    }

    // MARK: - Applying (denormalize for save)

    func testApplyingLFIsANoOp() {
        XCTAssertEqual(LineEndingDetector.applying(.lf, to: "a\nb\n"), "a\nb\n")
    }

    func testApplyingCRLFConvertsEveryNewline() {
        XCTAssertEqual(LineEndingDetector.applying(.crlf, to: "a\nb\nc"), "a\r\nb\r\nc")
    }

    func testApplyingCRConvertsEveryNewline() {
        XCTAssertEqual(LineEndingDetector.applying(.cr, to: "a\nb\nc"), "a\rb\rc")
    }

    func testApplyingDoesNotAddATrailingNewlineThatWasNotThere() {
        XCTAssertEqual(LineEndingDetector.applying(.crlf, to: "no trailing newline"), "no trailing newline")
    }

    // MARK: - Round trip

    func testDetectNormalizeApplyRoundTripsForEachUniformStyle() {
        for (original, kind): (String, LineEndingKind) in [
            ("line1\nline2\nline3\n", .lf),
            ("line1\r\nline2\r\nline3\r\n", .crlf),
            ("line1\rline2\rline3\r", .cr),
        ] {
            let detected = LineEndingDetector.detect(original)
            let normalized = LineEndingDetector.normalize(original)
            let restored = LineEndingDetector.applying(kind, to: normalized)
            XCTAssertEqual(restored, original, "round trip failed for \(kind)")
            switch (detected, kind) {
            case (.lf, .lf), (.crlf, .crlf), (.cr, .cr): break
            default: XCTFail("detected \(detected) did not match expected \(kind)")
            }
        }
    }
}
