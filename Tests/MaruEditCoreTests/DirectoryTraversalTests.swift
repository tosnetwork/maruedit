import XCTest
@testable import MaruEditCore

/// Builds a real fixture tree on disk — including the hostile cases from
/// M3-04's acceptance criterion: an unreadable directory, a symlink loop,
/// and a binary file.
final class DirectoryTraversalTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maruedit-traversal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions first, or the unreadable fixture directory
        // makes cleanup fail.
        let denied = root.appendingPathComponent("denied")
        if FileManager.default.fileExists(atPath: denied.path) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path)
        }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixture helpers

    @discardableResult
    private func write(_ contents: String, to relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func request(
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        includesHiddenFiles: Bool = false,
        followsSymbolicLinks: Bool = false,
        isRecursive: Bool = true,
        maximumFileSize: Int64 = GrepRequest.defaultMaximumFileSize
    ) -> GrepRequest {
        GrepRequest(
            query: SearchQuery(pattern: "x"),
            roots: [root],
            includeGlobs: includeGlobs,
            excludeGlobs: excludeGlobs,
            includesHiddenFiles: includesHiddenFiles,
            followsSymbolicLinks: followsSymbolicLinks,
            isRecursive: isRecursive,
            maximumFileSize: maximumFileSize
        )
    }

    private func run(_ request: GrepRequest, isCancelled: () -> Bool = { false })
        -> (files: [String], skips: [(String, SkipReason)]) {
        var files: [String] = []
        var skips: [(String, SkipReason)] = []
        DirectoryTraversal.traverse(
            request,
            isCancelled: isCancelled,
            onFile: { files.append(DirectoryTraversal.relativePath(of: $0, from: self.root)) },
            onSkip: { skips.append((DirectoryTraversal.relativePath(of: $0, from: self.root), $1)) }
        )
        return (files.sorted(), skips)
    }

    // MARK: - Basics

    func testFindsFilesRecursively() throws {
        try write("a", to: "a.txt")
        try write("b", to: "sub/b.txt")
        try write("c", to: "sub/deeper/c.txt")

        XCTAssertEqual(run(request()).files, ["a.txt", "sub/b.txt", "sub/deeper/c.txt"])
    }

    func testNonRecursiveScanStaysAtTheTopLevel() throws {
        try write("a", to: "a.txt")
        try write("b", to: "sub/b.txt")

        XCTAssertEqual(run(request(isRecursive: false)).files, ["a.txt"])
    }

    func testASingleFileRootIsSearched() throws {
        let file = try write("a", to: "a.txt")
        var found: [URL] = []
        DirectoryTraversal.traverse(
            GrepRequest(query: SearchQuery(pattern: "a"), roots: [file]),
            onFile: { found.append($0) }
        )
        XCTAssertEqual(found, [file])
    }

    func testMissingRootIsReportedAndDoesNotStopTheScan() throws {
        try write("a", to: "a.txt")
        var request = self.request()
        request.roots = [root.appendingPathComponent("nope"), root]

        let result = run(request)
        XCTAssertEqual(result.files, ["a.txt"])
        XCTAssertTrue(result.skips.contains { $0.0.hasSuffix("nope") })
    }

    // MARK: - Filters

    func testIncludeGlobsRestrictTheScan() throws {
        try write("a", to: "a.swift")
        try write("b", to: "b.txt")

        let result = run(request(includeGlobs: ["*.swift"]))
        XCTAssertEqual(result.files, ["a.swift"])
        XCTAssertTrue(result.skips.contains { $0.0 == "b.txt" && $0.1 == .notIncludedByGlob })
    }

    func testExcludeGlobsPruneWholeDirectories() throws {
        try write("a", to: "keep/a.txt")
        try write("b", to: "node_modules/b.txt")
        try write("c", to: "node_modules/deep/c.txt")

        let result = run(request(excludeGlobs: ["node_modules"]))
        XCTAssertEqual(result.files, ["keep/a.txt"])
        XCTAssertTrue(result.skips.contains { $0.0 == "node_modules" && $0.1 == .excludedByGlob("node_modules") },
                      "the directory should be skipped once, not filtered file by file")
    }

    func testHiddenFilesAreSkippedUnlessRequested() throws {
        try write("a", to: "a.txt")
        try write("secret", to: ".hidden.txt")
        try write("deep", to: ".git/config.txt")

        XCTAssertEqual(run(request()).files, ["a.txt"])
        XCTAssertEqual(run(request(includesHiddenFiles: true)).files, [".git/config.txt", ".hidden.txt", "a.txt"])
    }

    func testFilesOverTheSizeLimitAreSkippedWithTheirSize() throws {
        try write(String(repeating: "x", count: 100), to: "big.txt")
        try write("x", to: "small.txt")

        let result = run(request(maximumFileSize: 50))
        XCTAssertEqual(result.files, ["small.txt"])
        XCTAssertEqual(result.skips.first { $0.0 == "big.txt" }?.1, .tooLarge(size: 100, limit: 50))
    }

    // MARK: - Hostile cases (M3-04 acceptance)

    func testBinaryFilesAreSkipped() throws {
        try write("text", to: "text.txt")
        let binary = root.appendingPathComponent("blob.bin")
        try Data([0x7F, 0x45, 0x4C, 0x46, 0x00, 0x01, 0x02]).write(to: binary)

        let result = run(request())
        XCTAssertEqual(result.files, ["text.txt"])
        XCTAssertEqual(result.skips.first { $0.0 == "blob.bin" }?.1, .binary)
    }

    func testUnreadableDirectoryIsReportedAndTheScanContinues() throws {
        try write("a", to: "a.txt")
        let denied = root.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try "hidden".write(to: denied.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)

        let result = run(request())
        XCTAssertEqual(result.files, ["a.txt"], "the rest of the tree must still be scanned")
        let skip = result.skips.first { $0.0 == "denied" }?.1
        guard case .unreadable? = skip else {
            return XCTFail("expected an unreadable skip for the denied directory, got \(String(describing: skip))")
        }
    }

    func testSymbolicLinksAreSkippedByDefault() throws {
        try write("a", to: "real/a.txt")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: root.appendingPathComponent("real")
        )

        let result = run(request())
        XCTAssertEqual(result.files, ["real/a.txt"])
        XCTAssertEqual(result.skips.first { $0.0 == "link" }?.1, .symbolicLink)
    }

    func testSymlinkLoopTerminatesWhenLinksAreFollowed() throws {
        try write("a", to: "real/a.txt")
        // A link inside the tree pointing back at the root: following it
        // naively recurses forever.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("real/loop"),
            withDestinationURL: root
        )

        let result = run(request(followsSymbolicLinks: true))
        XCTAssertEqual(result.files, ["real/a.txt"], "each real file is reported exactly once")
        XCTAssertTrue(result.skips.contains { $0.1 == .alreadyVisited },
                      "the loop must be reported, not silently pruned")
    }

    // MARK: - Cancellation

    func testCancellationStopsTheScanEarly() throws {
        for index in 0..<50 { try write("x", to: "file\(index).txt") }

        var seen = 0
        let token = CancellationToken()
        DirectoryTraversal.traverse(
            request(),
            isCancelled: { token.isCancelled },
            onFile: { _ in
                seen += 1
                if seen == 3 { token.cancel() }
            }
        )
        XCTAssertEqual(seen, 3, "traversal must stop at the first check after cancellation")
    }
}
