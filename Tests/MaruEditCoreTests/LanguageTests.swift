import XCTest
@testable import MaruEditCore

final class LanguageTests: XCTestCase {

    func testDetectFromExtension() {
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "main.swift")), .swift)
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "script.py")), .python)
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "notes.txt")), .plainText)
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "no-extension")), .plainText)
        XCTAssertEqual(Language.detect(for: URL(fileURLWithPath: "README.MD")), .markdown, "extension matching should be case-insensitive")
    }

    func testDisplayNameCoversEveryCase() {
        for lang in Language.allCases {
            XCTAssertFalse(lang.displayName.isEmpty, "\(lang) has no display name")
        }
    }
}
