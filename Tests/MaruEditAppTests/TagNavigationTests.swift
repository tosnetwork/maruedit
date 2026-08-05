import XCTest
@preconcurrency @testable import MaruEditApp

@preconcurrency @MainActor
final class TagNavigationTests: XCTestCase {
    func testNamedAndDirectJumpThenBackRestoreOrigin() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditTagTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let origin = root.appendingPathComponent("origin.swift")
        let target = root.appendingPathComponent("target.swift")
        try "let use = targetSymbol\n".write(to: origin, atomically: true, encoding: .utf8)
        try "header\nfunc targetSymbol() {}\n".write(to: target, atomically: true, encoding: .utf8)
        try "targetSymbol\ttarget.swift\t2;\"\tf\n".write(
            to: root.appendingPathComponent("tags"), atomically: true, encoding: .utf8)

        let controller = MainWindowController()
        controller.openFile(origin)
        controller.macroEditor.setSelections(
            [NSRange(location: 10, length: 0)], primaryRange: NSRange(location: 10, length: 0))
        controller.directTagJump()
        XCTAssertEqual(controller.macroEditor.document?.fileURL, target)
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange.location, 7)

        controller.backTagJump()
        XCTAssertEqual(controller.macroEditor.document?.fileURL, origin)
        XCTAssertEqual(controller.macroEditor.selectionSet.primaryRange.location, 10)
    }
}
