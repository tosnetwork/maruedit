import XCTest
@testable import MaruEditCore

final class TextFileSaverTests: XCTestCase {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextFileSaverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func posixPermissions(of url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    func testSaveWritesExactBytes() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("file.txt")

        try TextFileSaver.save(Data("hello".utf8), to: url, preservingPermissionsFrom: nil)

        XCTAssertEqual(try Data(contentsOf: url), Data("hello".utf8))
    }

    func testSaveReturnsFreshIdentityAndModificationDate() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("file.txt")

        let info = try TextFileSaver.save(Data("hello".utf8), to: url, preservingPermissionsFrom: nil)

        XCTAssertNotNil(info.fileIdentity)
        XCTAssertEqual(info.fileIdentity, FileIdentity.of(url))
        XCTAssertNotNil(info.modificationDate)
    }

    func testPreservesExistingPermissionsInsteadOfDefaultUmask() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("file.txt")

        try Data("original".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(try posixPermissions(of: url), 0o600)

        try TextFileSaver.save(Data("updated".utf8), to: url, preservingPermissionsFrom: 0o600)

        XCTAssertEqual(try posixPermissions(of: url), 0o600, "save must not silently fall back to default (umask-derived) permissions")
        XCTAssertEqual(try Data(contentsOf: url), Data("updated".utf8))
    }

    func testNoPermissionsToPreserveLeavesDefaultPermissions() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("brand-new.txt")

        // Never-saved-before document: nothing to preserve, and the call
        // must not crash or throw just because existingPermissions is nil.
        XCTAssertNoThrow(try TextFileSaver.save(Data("new".utf8), to: url, preservingPermissionsFrom: nil))
        XCTAssertEqual(try Data(contentsOf: url), Data("new".utf8))
    }

    func testWriteFailureLeavesOriginalFileIntact() throws {
        let dir = try tempDir()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let url = dir.appendingPathComponent("file.txt")
        let originalContent = Data("original, must survive".utf8)
        try originalContent.write(to: url)

        // Make the containing directory read-only so atomic save (which
        // needs to create a temporary file alongside the target) fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        XCTAssertThrowsError(try TextFileSaver.save(Data("new content".utf8), to: url, preservingPermissionsFrom: nil)) { error in
            guard case TextFileSaverError.writeFailed = error else {
                return XCTFail("expected writeFailed, got \(error)")
            }
        }

        // Restore write access to read the file back and confirm it's untouched.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        XCTAssertEqual(try Data(contentsOf: url), originalContent, "a failed save must never corrupt or truncate the original file")
    }
}
