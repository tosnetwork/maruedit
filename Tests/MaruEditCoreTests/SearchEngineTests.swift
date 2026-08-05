import XCTest
@testable import MaruEditCore

final class SearchEngineTests: XCTestCase {
    func testFuzzySearchMatchesWidthAndCompatibilityFormsWithOriginalRanges() throws {
        let text = "前 ﾊﾞｰｼﾞｮﾝ 後 バージョン ＡBC"
        let kana = SearchQuery(pattern: "バージョン", isFuzzy: true)
        let matches = try SearchEngine.matches(for: kana, in: text)
        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map { (text as NSString).substring(with: $0.range) },
                       ["ﾊﾞｰｼﾞｮﾝ", "バージョン"])

        let latin = SearchQuery(pattern: "ABC", isCaseSensitive: true, isFuzzy: true)
        XCTAssertEqual(try SearchEngine.matches(for: latin, in: text).count, 1)
    }

    func testFuzzyRegexCapturesAndReplacementMapBackToOriginalText() throws {
        let text = "x Ａ１２ y"
        let query = SearchQuery(
            pattern: "(A)([0-9]+)", replacement: "$2-$1",
            mode: .regularExpression, isCaseSensitive: true, isFuzzy: true)
        let matches = try SearchEngine.matches(for: query, in: text)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual((text as NSString).substring(with: matches[0].range), "Ａ１２")
        XCTAssertEqual(SearchEngine.replacement(for: matches[0], in: text, query: query), "１２-Ａ")
        let replaced = try SearchEngine.replacingAllMatches(of: query, in: text)
        XCTAssertEqual(replaced.text, "x １２-Ａ y")
    }

    // MARK: - Literal mode

    func testLiteralMatchesAreCaseInsensitiveByDefault() throws {
        let query = SearchQuery(pattern: "cat")
        let found = try SearchEngine.matches(for: query, in: "Cat cat CAT")
        XCTAssertEqual(found.map { $0.range }, [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 3),
            NSRange(location: 8, length: 3),
        ])
    }

    func testCaseSensitiveLiteralMatchesOnlyExactCase() throws {
        let query = SearchQuery(pattern: "cat", isCaseSensitive: true)
        let found = try SearchEngine.matches(for: query, in: "Cat cat CAT")
        XCTAssertEqual(found.map { $0.range }, [NSRange(location: 4, length: 3)])
    }

    func testLiteralPatternTreatsRegexMetacharactersAsText() throws {
        let query = SearchQuery(pattern: "a.c")
        let found = try SearchEngine.matches(for: query, in: "abc a.c")
        XCTAssertEqual(found.map { $0.range }, [NSRange(location: 4, length: 3)],
                       "a literal '.' must not match an arbitrary character")
    }

    func testEmptyPatternFindsNothingRatherThanErroring() throws {
        XCTAssertEqual(try SearchEngine.matches(for: SearchQuery(pattern: ""), in: "abc").count, 0)
    }

    // MARK: - Whole word

    func testWholeWordExcludesSubstringMatches() throws {
        let query = SearchQuery(pattern: "cat", wholeWord: true)
        let found = try SearchEngine.matches(for: query, in: "cat category concat cat.")
        XCTAssertEqual(found.map { $0.range }, [
            NSRange(location: 0, length: 3),
            NSRange(location: 20, length: 3),
        ])
    }

    func testWholeWordTreatsUnderscoreAsWordCharacter() throws {
        let query = SearchQuery(pattern: "cat", wholeWord: true)
        XCTAssertTrue(try SearchEngine.matches(for: query, in: "my_cat").isEmpty)
    }

    func testWholeWordWorksForPatternsStartingWithPunctuation() throws {
        // A `\b…\b` implementation would find nothing here, since there is
        // no word boundary immediately before "(".
        let query = SearchQuery(pattern: "(x)", wholeWord: true)
        XCTAssertEqual(try SearchEngine.matches(for: query, in: "f(x)").map { $0.range },
                       [NSRange(location: 1, length: 3)])
    }

    // MARK: - Regex mode

    func testRegexCaptureGroupsAreReported() throws {
        let query = SearchQuery(pattern: "(\\w+)=(\\d+)", mode: .regularExpression)
        let found = try SearchEngine.matches(for: query, in: "width=100")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].captureGroups.count, 3)
        XCTAssertEqual(found[0].captureGroups[1], NSRange(location: 0, length: 5))
        XCTAssertEqual(found[0].captureGroups[2], NSRange(location: 6, length: 3))
    }

    func testRegexAnchorsMatchLineBoundaries() throws {
        let query = SearchQuery(pattern: "^b", mode: .regularExpression)
        let found = try SearchEngine.matches(for: query, in: "a\nb\nc")
        XCTAssertEqual(found.map { $0.range }, [NSRange(location: 2, length: 1)])
    }

    func testInvalidRegexThrowsDiagnosticWithoutCrashing() {
        let query = SearchQuery(pattern: "([unclosed", mode: .regularExpression)
        XCTAssertThrowsError(try SearchEngine.matches(for: query, in: "abc")) { error in
            guard case SearchError.invalidPattern(let pattern, let reason)? = error as? SearchError else {
                return XCTFail("expected .invalidPattern, got \(error)")
            }
            XCTAssertEqual(pattern, "([unclosed")
            XCTAssertFalse(reason.isEmpty, "the user needs to see why the pattern was rejected")
        }
    }

    func testValidateAcceptsEmptyAndGoodPatternsAndRejectsBadOnes() {
        XCTAssertNoThrow(try SearchEngine.validate(SearchQuery(pattern: "")))
        XCTAssertNoThrow(try SearchEngine.validate(SearchQuery(pattern: "a(b)c", mode: .regularExpression)))
        XCTAssertThrowsError(try SearchEngine.validate(SearchQuery(pattern: "a(bc", mode: .regularExpression)))
        // An invalid *regex* is a perfectly ordinary literal pattern.
        XCTAssertNoThrow(try SearchEngine.validate(SearchQuery(pattern: "a(bc", mode: .literal)))
    }

    // MARK: - Zero-length matches

    func testZeroLengthRegexTerminatesAndMatchesEachPosition() throws {
        let query = SearchQuery(pattern: "x*", mode: .regularExpression)
        let found = try SearchEngine.matches(for: query, in: "axb")
        // One match per position (all zero-length except at "x"), and,
        // critically, the call returns instead of looping forever.
        XCTAssertEqual(found.map { $0.range }, [
            NSRange(location: 0, length: 0),
            NSRange(location: 1, length: 1),
            NSRange(location: 2, length: 0),
            NSRange(location: 3, length: 0),
        ])
    }

    func testZeroLengthAnchorRegexTerminates() throws {
        let query = SearchQuery(pattern: "^", mode: .regularExpression)
        let found = try SearchEngine.matches(for: query, in: "a\nb\nc")
        XCTAssertEqual(found.count, 3)
    }

    func testReplaceAllWithZeroLengthPatternTerminates() throws {
        let query = SearchQuery(pattern: "^", replacement: "> ", mode: .regularExpression)
        let result = try SearchEngine.replacingAllMatches(of: query, in: "a\nb")
        XCTAssertEqual(result.text, "> a\n> b")
        XCTAssertEqual(result.replacementCount, 2)
    }

    // MARK: - Unicode

    func testMatchesJapaneseText() throws {
        let text = "日本語のテキスト、日本語の検索"
        let found = try SearchEngine.matches(for: SearchQuery(pattern: "日本語"), in: text)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual((text as NSString).substring(with: found[1].range), "日本語")
    }

    func testMatchRangesAreUTF16OffsetsAcrossAstralCharacters() throws {
        // "👍" is two UTF-16 units; the match after it must account for that.
        let text = "👍end"
        let found = try SearchEngine.matches(for: SearchQuery(pattern: "end"), in: text)
        XCTAssertEqual(found.map { $0.range }, [NSRange(location: 2, length: 3)])
        XCTAssertEqual((text as NSString).substring(with: found[0].range), "end")
    }

    /// Documents (rather than fights) ICU's full case folding: a
    /// case-insensitive search for "straße" also matches "STRASSE". This
    /// is the behavior ROADMAP.md 11.2 commits to by choosing ICU/Apple
    /// regex semantics; a case-sensitive search is unaffected.
    func testCaseInsensitiveMatchingUsesFullUnicodeCaseFolding() throws {
        let insensitive = try SearchEngine.matches(for: SearchQuery(pattern: "straße"), in: "STRASSE Straße")
        XCTAssertEqual(insensitive.count, 2)
        let sensitive = try SearchEngine.matches(
            for: SearchQuery(pattern: "straße", isCaseSensitive: true), in: "STRASSE Straße")
        XCTAssertEqual(sensitive.count, 0)
    }

    // MARK: - Scope

    func testSelectionScopeRestrictsMatches() throws {
        let query = SearchQuery(pattern: "a", scope: .selection(NSRange(location: 2, length: 3)))
        let found = try SearchEngine.matches(for: query, in: "aa aaa aa")
        XCTAssertEqual(found.map { $0.range }, [
            NSRange(location: 3, length: 1),
            NSRange(location: 4, length: 1),
        ])
    }

    func testSelectionScopeIsClampedToTextLength() throws {
        let query = SearchQuery(pattern: "a", scope: .selection(NSRange(location: 1, length: 999)))
        XCTAssertEqual(try SearchEngine.matches(for: query, in: "aaa").count, 2)
    }

    // MARK: - Next / previous

    func testNextMatchSkipsTheCurrentlySelectedMatch() throws {
        let query = SearchQuery(pattern: "ab")
        let text = "ab ab ab"
        let next = try SearchEngine.nextMatch(for: query, in: text, from: 2)
        XCTAssertEqual(next?.range, NSRange(location: 3, length: 2))
    }

    func testNextMatchWrapsWhenEnabled() throws {
        let query = SearchQuery(pattern: "ab", wraps: true)
        let next = try SearchEngine.nextMatch(for: query, in: "ab ab", from: 5)
        XCTAssertEqual(next?.range, NSRange(location: 0, length: 2))
    }

    func testNextMatchDoesNotWrapWhenDisabled() throws {
        let query = SearchQuery(pattern: "ab", wraps: false)
        XCTAssertNil(try SearchEngine.nextMatch(for: query, in: "ab ab", from: 5))
    }

    func testPreviousMatchFindsTheMatchBeforeTheSelection() throws {
        let query = SearchQuery(pattern: "ab")
        let previous = try SearchEngine.previousMatch(for: query, in: "ab ab ab", from: 6)
        XCTAssertEqual(previous?.range, NSRange(location: 3, length: 2))
    }

    func testPreviousMatchWrapsToTheLastMatch() throws {
        let query = SearchQuery(pattern: "ab", wraps: true)
        let previous = try SearchEngine.previousMatch(for: query, in: "ab ab", from: 0)
        XCTAssertEqual(previous?.range, NSRange(location: 3, length: 2))
    }

    func testNextAndPreviousReturnNilWhenNothingMatches() throws {
        let query = SearchQuery(pattern: "zz")
        XCTAssertNil(try SearchEngine.nextMatch(for: query, in: "ab", from: 0))
        XCTAssertNil(try SearchEngine.previousMatch(for: query, in: "ab", from: 2))
    }

    // MARK: - Acceptance: one match set shared by Find, Select All, and Replace

    func testFindSelectAllAndReplaceAgreeOnTheSameMatchSet() throws {
        let text = "one two one two one"
        let query = SearchQuery(pattern: "one", replacement: "X", wholeWord: true)

        let all = try SearchEngine.matches(for: query, in: text)
        var walked: [NSRange] = []
        var cursor = 0
        while let next = try SearchEngine.nextMatch(
            for: SearchQuery(pattern: query.pattern, wholeWord: true, wraps: false),
            in: text, from: cursor
        ) {
            walked.append(next.range)
            cursor = NSMaxRange(next.range)
        }
        let replaced = try SearchEngine.replacingAllMatches(of: query, in: text)

        XCTAssertEqual(walked, all.map { $0.range })
        XCTAssertEqual(replaced.replacementCount, all.count)
    }
}
