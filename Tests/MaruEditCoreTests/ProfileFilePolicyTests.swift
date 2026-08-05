import XCTest
@testable import MaruEditCore

final class ProfileFilePolicyTests: XCTestCase {
    func testTemplateIsUTF8AndBounded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try "// template\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ProfileFilePolicy.loadTemplate(path: url.path), "// template\n")
    }

    func testSaveTransformIsDeterministic() {
        let policy = ProfileSavePolicy(ensuresFinalNewline: true, trimsTrailingWhitespace: true)
        XCTAssertEqual(ProfileFilePolicy.transformedForSave("a  \n b\t", policy: policy), "a\n b\n")
        XCTAssertEqual(ProfileFilePolicy.transformedForSave("a", policy: nil), "a")
    }

    func testBackupsAreCreatedAndRetentionIsBounded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditBackup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("file.txt")
        try "old".write(to: source, atomically: true, encoding: .utf8)
        let settings = BackupSettings(enabled: true, suffix: ".bak", maximumCopies: 2)
        for _ in 0..<3 {
            _ = try ProfileFilePolicy.createBackup(of: source, settings: settings)
            Thread.sleep(forTimeInterval: 0.002)
        }
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".bak") }
        XCTAssertEqual(backups.count, 2)
    }
}
