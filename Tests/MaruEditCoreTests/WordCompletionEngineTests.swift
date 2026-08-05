import XCTest
@testable import MaruEditCore

final class WordCompletionEngineTests: XCTestCase {
    func testCurrentDocumentFrequencyRankingAndDeduplication() {
        let words = WordCompletionEngine.candidates(
            prefix: "ap", document: "apple apricot apple application").map(\.word)
        XCTAssertEqual(words, ["apple", "application", "apricot"])
    }

    func testDictionaryAndAlphabeticalRankingAreProfileControlled() {
        let settings = CompletionSettings(
            includesCurrentDocument: false, ranking: .alphabetical)
        XCTAssertEqual(WordCompletionEngine.candidates(
            prefix: "東", document: "東京", dictionaries: ["東北 東海道"], settings: settings).map(\.word),
            ["東海道", "東北"])
    }

    func testEmptyPrefixAndExactWordAreExcluded() {
        XCTAssertTrue(WordCompletionEngine.candidates(prefix: "", document: "alpha").isEmpty)
        XCTAssertTrue(WordCompletionEngine.candidates(prefix: "alpha", document: "alpha").isEmpty)
    }

    func testLegacyProfileDecodesWithoutNewSettings() throws {
        let json = #"{"schemaVersion":2,"id":"old","name":"Old","filenamePatterns":[],"extensions":["txt"],"priority":0,"settings":{"tabWidth":4,"indentWidth":4,"indentStyle":"spaces","wrapLines":false,"encoding":null,"syntax":"plainText","lineComment":null,"blockCommentStart":null,"blockCommentEnd":null,"outlineRules":null}}"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(FileTypeProfile.self, from: json)
        XCTAssertNil(profile.settings.completion)
        XCTAssertNil(profile.settings.spelling)
    }
}
