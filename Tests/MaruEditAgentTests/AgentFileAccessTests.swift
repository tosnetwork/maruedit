import XCTest
@testable import MaruEditCore

/// Containment for the one place this profile touches the filesystem.
///
/// The interesting cases are all about the gap between checking a path and
/// using it, which is where string comparison quietly fails.
final class AgentFileAccessTests: XCTestCase {

    private var root: URL!
    private var outside: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = URL(fileURLWithPath: "/tmp/mfa-\(UUID().uuidString.prefix(8))")
        root = base.appendingPathComponent("root")
        outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "inside".write(to: root.appendingPathComponent("ok.txt"), atomically: true, encoding: .utf8)
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    func testAFileInsideTheRootOpensAndReads() throws {
        let file = try AgentFileAccess.open(
            path: root.appendingPathComponent("ok.txt").path, underAnyOf: [root.path])
        defer { file.close() }
        XCTAssertEqual(String(decoding: try AgentFileAccess.read(file), as: UTF8.self), "inside")
    }

    func testWithoutAnAuthorizedRootNothingOpens() {
        XCTAssertThrowsError(
            try AgentFileAccess.open(path: root.appendingPathComponent("ok.txt").path, underAnyOf: [])
        ) { error in
            XCTAssertEqual(error as? AgentFileAccess.AccessError, .noAuthorizedRoot)
        }
    }

    func testAPathOutsideTheRootIsRefused() {
        let path = outside.appendingPathComponent("secret.txt").path
        XCTAssertThrowsError(try AgentFileAccess.open(path: path, underAnyOf: [root.path])) { error in
            XCTAssertEqual(error as? AgentFileAccess.AccessError, .escapesRoot(path))
        }
    }

    func testTraversalOutOfTheRootIsRefused() {
        // Standardization resolves this to the outside file; the containment
        // check must catch it rather than the filesystem.
        let path = root.appendingPathComponent("../outside/secret.txt").path
        XCTAssertThrowsError(try AgentFileAccess.open(path: path, underAnyOf: [root.path]))
    }

    func testASymlinkedFileInsideTheRootIsNotFollowed() throws {
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: outside.appendingPathComponent("secret.txt"))

        // The path is inside the root by string comparison, which is exactly
        // why string comparison is not the boundary.
        XCTAssertThrowsError(
            try AgentFileAccess.open(path: link.path, underAnyOf: [root.path])
        ) { error in
            XCTAssertEqual(error as? AgentFileAccess.AccessError, .symlinkComponent("link.txt"))
        }
    }

    func testASymlinkedDirectoryComponentIsNotFollowed() throws {
        let link = root.appendingPathComponent("sub")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let path = link.appendingPathComponent("secret.txt").path
        XCTAssertThrowsError(try AgentFileAccess.open(path: path, underAnyOf: [root.path])) { error in
            XCTAssertEqual(error as? AgentFileAccess.AccessError, .symlinkComponent("sub"))
        }
    }

    func testADirectoryIsNotAFile() {
        XCTAssertThrowsError(
            try AgentFileAccess.open(path: root.path, underAnyOf: [root.path])
        ) { error in
            XCTAssertEqual(error as? AgentFileAccess.AccessError, .notAFile(root.path))
        }
    }

    func testAnOversizedFileIsRefusedBeforeItIsRead() throws {
        let big = root.appendingPathComponent("big.bin")
        let data = Data(repeating: 0x41, count: AgentFileAccess.maximumFileBytes + 1)
        try data.write(to: big)
        XCTAssertThrowsError(try AgentFileAccess.open(path: big.path, underAnyOf: [root.path])) { error in
            guard case .tooLarge = error as? AgentFileAccess.AccessError else {
                return XCTFail("expected tooLarge, got \(error)")
            }
        }
    }

    func testRelativeComponentsSplitsOnlyInsideTheRoot() {
        XCTAssertEqual(
            AgentFileAccess.relativeComponents(of: "/tmp/a/b/c.txt", under: "/tmp/a"),
            ["b", "c.txt"])
        XCTAssertNil(AgentFileAccess.relativeComponents(of: "/tmp/other/c.txt", under: "/tmp/a"))
        // A prefix match is not a containment check: /tmp/ab is not inside
        // /tmp/a.
        XCTAssertNil(AgentFileAccess.relativeComponents(of: "/tmp/ab/c.txt", under: "/tmp/a"))
    }
}
