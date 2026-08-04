import AppKit
import MaruEditCore
import XCTest
@testable import MaruEditApp

final class LargeFileModeTests: XCTestCase {
    private func sparseFile(size: UInt64) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditLargeFile-\(UUID().uuidString).txt")
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size)
        try handle.close()
        return url
    }

    func testFileAboveSafetyCeilingIsRejectedBeforeMaterialization() throws {
        let url = try sparseFile(size: UInt64(LargeFilePolicy.maximumMaterializedSize + 1))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try Document.open(url: url)) { error in
            guard case let DocumentOpenError.fileTooLarge(size, maximum) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(size, LargeFilePolicy.maximumMaterializedSize + 1)
            XCTAssertEqual(maximum, LargeFilePolicy.maximumMaterializedSize)
        }
    }

    func testThresholdFileAutomaticallyOpensReducedWithoutUIPrompt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaruEditReduced-\(UUID().uuidString).txt")
        try Data(
            repeating: 0x61,
            count: Int(LargeFilePolicy.reducedFeaturesThreshold)
        ).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try Document.open(url: url)
        XCTAssertEqual(document.largeFileMode, .reducedFeatures)
        XCTAssertFalse(document.isReadOnly)
    }

    func testReducedAndReadOnlyModesApplyEditorSafetyFeatures() {
        let reduced = Document(content: "let value = 1")
        reduced.largeFileMode = .reducedFeatures
        let editor = EditorViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = editor.view
        editor.document = reduced

        XCTAssertFalse(editor.effectiveWrapLines)
        XCTAssertEqual(
            (editor.textView as? MaruTextView)?.invisibleCharacters,
            InvisibleCharacterOptions.none)
        XCTAssertEqual(editor.textView.undoManager?.levelsOfUndo, 20)
        XCTAssertTrue(editor.textView.isEditable)

        editor.enableAllLargeFileFeatures()
        XCTAssertEqual(reduced.largeFileMode, .normal)
        XCTAssertTrue(reduced.hasExplicitlyEnabledLargeFileFeatures)
        XCTAssertEqual(editor.textView.undoManager?.levelsOfUndo, 0)

        let readOnly = Document(content: "large")
        readOnly.largeFileMode = .readOnly
        readOnly.isReadOnly = true
        editor.document = readOnly
        XCTAssertFalse(editor.textView.isEditable)
    }
}
