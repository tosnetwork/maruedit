import XCTest
@testable import MaruEditCore

final class GlobPatternTests: XCTestCase {

    func testExtensionPatternMatchesAtAnyDepth() {
        let glob = GlobPattern("*.swift")
        XCTAssertTrue(glob.matches(relativePath: "main.swift"))
        XCTAssertTrue(glob.matches(relativePath: "Sources/App/main.swift"))
        XCTAssertFalse(glob.matches(relativePath: "main.swift.bak"))
    }

    func testBareNamePatternMatchesADirectoryName() {
        let glob = GlobPattern("node_modules")
        XCTAssertTrue(glob.matches(relativePath: "web/node_modules"))
        XCTAssertFalse(glob.matches(relativePath: "web/node_modules_old"))
    }

    func testPatternWithASlashIsMatchedAgainstTheWholeRelativePath() {
        let glob = GlobPattern("src/*.js")
        XCTAssertTrue(glob.matches(relativePath: "src/app.js"))
        XCTAssertFalse(glob.matches(relativePath: "lib/src/app.js"),
                       "a single * must not cross a path separator")
        XCTAssertFalse(glob.matches(relativePath: "src/nested/app.js"))
    }

    func testDoubleStarCrossesDirectories() {
        let glob = GlobPattern("src/**/*.js")
        XCTAssertTrue(glob.matches(relativePath: "src/app.js"))
        XCTAssertTrue(glob.matches(relativePath: "src/a/b/app.js"))
        XCTAssertFalse(glob.matches(relativePath: "lib/app.js"))
    }

    func testQuestionMarkMatchesExactlyOneCharacter() {
        let glob = GlobPattern("log?.txt")
        XCTAssertTrue(glob.matches(relativePath: "log1.txt"))
        XCTAssertFalse(glob.matches(relativePath: "log.txt"))
        XCTAssertFalse(glob.matches(relativePath: "log12.txt"))
    }

    func testCharacterClasses() {
        XCTAssertTrue(GlobPattern("[abc]*.txt").matches(relativePath: "b1.txt"))
        XCTAssertFalse(GlobPattern("[abc]*.txt").matches(relativePath: "d1.txt"))
        XCTAssertTrue(GlobPattern("[a-z].log").matches(relativePath: "q.log"))
        XCTAssertTrue(GlobPattern("[!x]*.log").matches(relativePath: "a1.log"))
        XCTAssertFalse(GlobPattern("[!x]*.log").matches(relativePath: "x1.log"))
    }

    func testRegexMetacharactersInAPatternAreLiteral() {
        let glob = GlobPattern("a+b.txt")
        XCTAssertTrue(glob.matches(relativePath: "a+b.txt"))
        XCTAssertFalse(glob.matches(relativePath: "aab.txt"))
    }

    func testUnterminatedCharacterClassIsALiteralBracket() {
        XCTAssertTrue(GlobPattern("[abc.txt").matches(relativePath: "[abc.txt"))
    }

    func testFirstMatchReportsWhichPatternMatched() {
        let globs = [GlobPattern("*.o"), GlobPattern("build")].firstMatch(relativePath: "x/build")
        XCTAssertEqual(globs?.pattern, "build")
    }
}
