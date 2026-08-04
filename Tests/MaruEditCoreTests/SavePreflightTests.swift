import XCTest
@testable import MaruEditCore

final class SavePreflightTests: XCTestCase {

    func testFullyRepresentableTextHasNoProblems() {
        let result = SavePreflight.check("hello world", encoding: .utf8)
        XCTAssertTrue(result.isRepresentable)
        XCTAssertTrue(result.unrepresentableCharacters.isEmpty)
    }

    func testEmojiIsUnrepresentableInLegacyJapaneseEncodings() {
        for encoding in TextEncoding.initialCandidates {
            let result = SavePreflight.check("hello 😀 world", encoding: encoding)
            XCTAssertFalse(result.isRepresentable, "\(encoding.rawValue) should not represent emoji")
            XCTAssertEqual(result.unrepresentableCharacters.first?.character, "😀")
        }
    }

    func testLocatesLineAndColumnOfUnrepresentableCharacter() {
        let text = "line one\nline t😀o\nline three"
        let result = SavePreflight.check(text, encoding: .eucJP)
        XCTAssertFalse(result.isRepresentable)
        guard let problem = result.unrepresentableCharacters.first else {
            return XCTFail("expected at least one unrepresentable character")
        }
        XCTAssertEqual(problem.character, "😀")
        XCTAssertEqual(problem.line, 2)
        XCTAssertEqual(problem.column, 7, "'l','i','n','e',' ','t' precede it: column 7")
    }

    func testLocatesMultipleUnrepresentableCharactersInOrder() {
        let text = "a😀b\nc🗻d"
        let result = SavePreflight.check(text, encoding: .shiftJISClassic)
        XCTAssertEqual(result.unrepresentableCharacters.map { $0.character }, ["😀", "🗻"])
        XCTAssertEqual(result.unrepresentableCharacters.map { $0.line }, [1, 2])
    }

    // MARK: - Japanese edge characters (ROADMAP.md section 10.4)

    func testCommonJapaneseCharactersAreRepresentableInEveryLegacyEncoding() {
        let text = "日本語、漢字、ひらがな、カタカナ"
        for encoding in TextEncoding.initialCandidates {
            let result = SavePreflight.check(text, encoding: encoding)
            XCTAssertTrue(result.isRepresentable, "\(encoding.rawValue) should represent common Japanese text")
        }
    }

    func testWaveDashAndYenSignDoNotSilentlyAlterRepresentability() {
        // These are the classic Shift-JIS/Unicode ambiguous-mapping
        // characters (ROADMAP.md 10.4). This test doesn't assert a
        // specific outcome for each encoding (their exact round-trip
        // behavior is determined by macOS's own ICU tables, per the
        // EncodingDetectorTests precedent) — it asserts the *contract*:
        // whatever SavePreflight decides, it must be a real, checkable
        // answer, not silently treating an ambiguous character as fine
        // when it can't actually be encoded.
        let waveDash = "\u{301C}"   // WAVE DASH
        let fullwidthTilde = "\u{FF5E}" // FULLWIDTH TILDE
        let yen = "\u{00A5}"        // YEN SIGN

        for character in [waveDash, fullwidthTilde, yen] {
            for encoding in TextEncoding.initialCandidates {
                guard let foundationEncoding = encoding.foundationEncoding else { continue }
                let result = SavePreflight.check(character, encoding: encoding)
                let directlyEncodable = character.data(using: foundationEncoding) != nil
                XCTAssertEqual(result.isRepresentable, directlyEncodable, "SavePreflight must agree with direct encodability for \(character.unicodeScalars.first!.debugDescription) in \(encoding.rawValue)")
            }
        }
    }

    func testUTF8RepresentsTheFullSection10_4CharacterSet() {
        let text = "日本語、漢字、ひらがな、カタカナ、半角ｶﾅ\n① ㈱ 髙 﨑 ～ 〜 ¥ \\ — −\nEmoji: 😀 🗻\nCombining: é が"
        let result = SavePreflight.check(text, encoding: .utf8)
        XCTAssertTrue(result.isRepresentable, "UTF-8 must represent every character in the standard fixture set")
    }
}
