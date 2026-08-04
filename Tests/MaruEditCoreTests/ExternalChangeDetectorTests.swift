import XCTest
@testable import MaruEditCore

final class ExternalChangeDetectorTests: XCTestCase {

    private func tempFile(contents: String = "hello") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalChangeDetectorTests-\(UUID().uuidString).txt")
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func modificationDate(of url: URL) throws -> Date {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attrs[.modificationDate] as? Date else {
            throw NSError(domain: "test", code: 1)
        }
        return date
    }

    func testUnchangedFileMatchingKnownBaseline() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let knownDate = try modificationDate(of: url)
        let knownIdentity = FileIdentity.of(url)

        let status = ExternalChangeDetector.check(url: url, knownIdentity: knownIdentity, knownModificationDate: knownDate)
        XCTAssertEqual(status, .unchanged)
    }

    func testModifiedFileIsDetected() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let knownDate = try modificationDate(of: url)
        let knownIdentity = FileIdentity.of(url)

        // Simulate an external editor writing to the file: set the
        // modification date explicitly rather than relying on real-time
        // write timing, which can be too close together to register as a
        // different mtime on some filesystems.
        try Data("changed externally".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: knownDate.addingTimeInterval(60)],
            ofItemAtPath: url.path
        )

        let status = ExternalChangeDetector.check(url: url, knownIdentity: knownIdentity, knownModificationDate: knownDate)
        XCTAssertEqual(status, .modified)
    }

    func testDeletedFileIsDetected() throws {
        let url = try tempFile()
        let knownDate = try modificationDate(of: url)
        let knownIdentity = FileIdentity.of(url)
        try FileManager.default.removeItem(at: url)

        let status = ExternalChangeDetector.check(url: url, knownIdentity: knownIdentity, knownModificationDate: knownDate)
        XCTAssertEqual(status, .deletedOrMoved)
    }

    func testMovedAwayFileIsReportedAsDeletedOrMoved() throws {
        // From the perspective of the *original* path, a rename/move away
        // looks identical to a deletion — there's nothing at that path
        // anymore. This checker doesn't do live FSEvents rename tracking
        // (out of scope), so both are reported the same way.
        let url = try tempFile()
        let knownDate = try modificationDate(of: url)
        let knownIdentity = FileIdentity.of(url)
        let newLocation = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExternalChangeDetectorTests-moved-\(UUID().uuidString).txt")
        try FileManager.default.moveItem(at: url, to: newLocation)
        defer { try? FileManager.default.removeItem(at: newLocation) }

        let status = ExternalChangeDetector.check(url: url, knownIdentity: knownIdentity, knownModificationDate: knownDate)
        XCTAssertEqual(status, .deletedOrMoved)
    }

    func testNoBaselineIsTreatedAsUnchanged() throws {
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let status = ExternalChangeDetector.check(url: url, knownIdentity: nil, knownModificationDate: nil)
        XCTAssertEqual(status, .unchanged, "nothing to compare against must not be treated as a conflict")
    }

    func testOwnSaveUpdatingTheBaselineIsNotFlaggedAsExternal() throws {
        // Mirrors what Document does in practice: after a successful
        // save, the known baseline is refreshed to the just-written
        // file's state, so an immediate re-check must not see a "change."
        let url = try tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("our own new content".utf8).write(to: url)
        let refreshedDate = try modificationDate(of: url)
        let refreshedIdentity = FileIdentity.of(url)

        let status = ExternalChangeDetector.check(url: url, knownIdentity: refreshedIdentity, knownModificationDate: refreshedDate)
        XCTAssertEqual(status, .unchanged)
    }
}
