import XCTest
@testable import MaruEditCore

final class TagFileGeneratorTests: XCTestCase {
    func testGeneratesSortedPortableTagsThatTagIndexCanResolve() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "struct Zebra {}\nfunc alpha() {}\n".write(to: sources.appendingPathComponent("A.swift"), atomically: true, encoding: .utf8)
        try "class PythonType:\n    pass\nasync def fetch_data():\n    pass\n".write(to: root.appendingPathComponent("tool.py"), atomically: true, encoding: .utf8)

        let summary = try TagFileGenerator().generate(in: root)
        XCTAssertEqual(summary.fileCount, 2)
        XCTAssertEqual(summary.tagCount, 4)
        let contents = try String(contentsOf: summary.outputURL, encoding: .utf8)
        let index = TagIndex(contents: contents)
        XCTAssertEqual(index.matches(named: "alpha").first?.relativePath, "Sources/A.swift")
        XCTAssertEqual(index.matches(named: "fetch_data").first?.line, 3)
        XCTAssertEqual(index.destinations.map(\.name), ["PythonType", "Zebra", "alpha", "fetch_data"])
    }

    func testSkipsDependenciesHiddenFilesSymlinksAndOversizedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dependency = root.appendingPathComponent("node_modules/pkg", isDirectory: true)
        try FileManager.default.createDirectory(at: dependency, withIntermediateDirectories: true)
        try "function dependency() {}".write(to: dependency.appendingPathComponent("x.js"), atomically: true, encoding: .utf8)
        try "func tooLarge() {}".write(to: root.appendingPathComponent("large.swift"), atomically: true, encoding: .utf8)
        let summary = try TagFileGenerator(maximumFileBytes: 4).generate(in: root)
        XCTAssertEqual(summary.fileCount, 1)
        XCTAssertEqual(summary.tagCount, 0)
    }
}
