import XCTest
@testable import MaruEditCore

final class FileTypeProfileTests: XCTestCase {
    func testEveryRequiredBuiltInProfileExistsAndResolves() {
        let names = Set(BuiltInFileTypeProfiles.all.map(\.name))
        XCTAssertTrue(Set(["Plain Text", "Swift", "C/C++", "Go", "Rust", "JavaScript", "JSON", "Markdown", "Shell"]).isSubset(of: names))
        let resolver = FileTypeProfileStore(directory: temporaryDirectory()).resolver()
        XCTAssertEqual(resolver.resolve(for: URL(fileURLWithPath: "/tmp/a.swift"))?.settings.syntax, .swift)
        XCTAssertEqual(resolver.resolve(for: URL(fileURLWithPath: "/tmp/a.hpp"))?.name, "C/C++")
        XCTAssertEqual(resolver.resolve(for: URL(fileURLWithPath: "/tmp/Makefile"))?.settings.syntax, .shell)
        XCTAssertEqual(resolver.resolve(for: URL(fileURLWithPath: "/tmp/README.unknown"))?.name, "Plain Text")
    }

    func testExactFilenameBeatsExtensionThenUserBeatsBuiltInThenPriorityAndID() {
        func profile(_ id: String, filename: [String] = [], ext: [String] = [], priority: Int = 0) -> FileTypeProfile {
            FileTypeProfile(id: id, name: id, filenamePatterns: filename, extensions: ext,
                            priority: priority, settings: FileTypeSettings())
        }
        let resolver = FileTypeProfileResolver(profiles: [
            SourcedFileTypeProfile(profile("builtin", ext: ["conf"], priority: 99), source: .builtIn),
            SourcedFileTypeProfile(profile("user-z", ext: ["conf"]), source: .user),
            SourcedFileTypeProfile(profile("user-a", ext: ["conf"]), source: .user),
            SourcedFileTypeProfile(profile("exact", filename: ["special.conf"]), source: .builtIn),
        ])
        XCTAssertEqual(resolver.resolve(for: URL(fileURLWithPath: "/tmp/normal.conf"))?.id, "user-a")
        XCTAssertEqual(resolver.resolve(for: URL(fileURLWithPath: "/tmp/special.conf"))?.id, "exact")
    }

    func testSchemaRoundTripIncludesAllEditorSettings() throws {
        let profile = FileTypeProfile(
            id: "user.test", name: "Test", filenamePatterns: ["Testfile"], extensions: ["test"],
            priority: 4, settings: FileTypeSettings(
                tabWidth: 8, indentWidth: 2, indentStyle: .tabs, wrapLines: true,
                encoding: .windows31J, syntax: .shell, lineComment: "#",
                blockCommentStart: "<#", blockCommentEnd: "#>"))
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileTypeProfileStore(directory: directory)
        try store.saveUserProfile(profile)
        XCTAssertEqual(store.loadUserProfiles(), [profile])
    }

    func testImportExportDoesNotOverwriteBuiltIns() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("import.json")
        let store = FileTypeProfileStore(directory: directory.appendingPathComponent("users"))
        var custom = BuiltInFileTypeProfiles.all.first { $0.name == "Swift" }!
        custom.settings.tabWidth = 7
        try store.export(custom, to: source)
        _ = try store.importProfile(from: source)
        XCTAssertEqual(store.resolver().resolve(for: URL(fileURLWithPath: "/tmp/a.swift"))?.settings.tabWidth, 7)
        XCTAssertEqual(BuiltInFileTypeProfiles.all.first { $0.name == "Swift" }?.settings.tabWidth, 4)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
