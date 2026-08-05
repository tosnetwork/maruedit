import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class StatusBarViewTests: XCTestCase {
    func testClassicInputModeSegmentIsExplicit() async {
        let bar = StatusBarView()
        XCTAssertEqual(bar.displayedInputModeText, "INS")
        bar.updateInputMode(.overwrite)
        XCTAssertEqual(bar.displayedInputModeText, "OVR")
    }
    func testAccessModeDistinguishesViewModeFromDiskReadOnly() async {
        let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 900, height: 24))
        bar.updateAccessMode(isReadOnly: false, isViewMode: true)
        bar.layoutSubtreeIfNeeded()
        XCTAssertTrue(bar.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains("View Mode"))
        bar.updateAccessMode(isReadOnly: true, isViewMode: false)
        XCTAssertTrue(bar.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.contains("Read-Only"))
    }
    private final class Delegate: StatusBarViewDelegate {
        var controls: [StatusBarControl] = []
        func statusBar(
            _ statusBar: StatusBarView, didClick control: StatusBarControl, at point: NSPoint
        ) {
            controls.append(control)
        }
    }

    func testTransientMessageRestoresCursorText() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 24))
        status.updateCursor(EditorCursorState(
            lineNumber: 4, displayColumn: 9, utf16Offset: 42,
            selectedCharacterCount: 0, selectedUTF16Length: 0, selectionRangeCount: 1))
        status.showTransientMessage("Chord: ctrl+k …", duration: 0.01)
        XCTAssertEqual(status.displayedLeadingText, "Chord: ctrl+k …")

        let restored = expectation(description: "cursor text restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            XCTAssertEqual(status.displayedLeadingText, "Ln 4, Col 9")
            restored.fulfill()
        }
        await fulfillment(of: [restored], timeout: 1)
    }

    func testCursorSelectionAndFormatFieldsAreExplicit() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 900, height: 24))
        status.updateCursor(EditorCursorState(
            lineNumber: 2, displayColumn: 7, utf16Offset: 4,
            selectedCharacterCount: 9, selectedUTF16Length: 11, selectionRangeCount: 3))
        status.updateEncoding(.windows31J)
        status.updateByteOrderMark(false)
        status.updateLineEnding(.crlf)
        status.updateLanguage(.swift, profileName: "Swift")

        XCTAssertEqual(status.displayedLeadingText, "Ln 2, Col 7")
        XCTAssertEqual(status.displayedSelectionText, "Sel 9 (3 ranges)")
        XCTAssertEqual(status.displayedEncodingText, "Windows-31J (Shift-JIS)")
        XCTAssertEqual(status.displayedBOMText, "No BOM")
        XCTAssertEqual(status.displayedLineEndingText, "CRLF")
        XCTAssertEqual(status.displayedLanguageProfileText, "Swift · Swift")
    }

    func testHidemaruMetricsCharacterCodeAndInteractiveSegments() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        let delegate = Delegate(); status.delegate = delegate
        status.updateDocumentMetrics(text: "A日\nthird", fontSize: 15)
        status.updateCursor(EditorCursorState(
            lineNumber: 1, displayColumn: 2, utf16Offset: 1,
            selectedCharacterCount: 2, selectedUTF16Length: 2,
            selectionRangeCount: 1, selectedLineCount: 2))
        status.layoutSubtreeIfNeeded()

        XCTAssertEqual(status.displayedTotalsText, "2 lines · 8 chars")
        XCTAssertEqual(status.displayedCharacterCodeText, "U+65E5")
        XCTAssertEqual(status.displayedFontSizeText, "15 pt")
        XCTAssertTrue(status.displayedSelectionText.contains("2 lines"))
        for control: StatusBarControl in [.cursorPosition, .characterCode, .inputMode, .fontSize] {
            XCTAssertNotNil(status.frame(for: control)); status.activate(control)
        }
        XCTAssertEqual(delegate.controls, [.cursorPosition, .characterCode, .inputMode, .fontSize])
    }

    func testBoxSelectionDimensionsAreDisplayed() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        status.updateCursor(EditorCursorState(
            lineNumber: 2, displayColumn: 8, utf16Offset: 12,
            selectedCharacterCount: 12, selectedUTF16Length: 12,
            selectionRangeCount: 3, selectedLineCount: 3,
            boxWidth: 4, boxHeight: 3))
        XCTAssertTrue(status.displayedSelectionText.contains("BOX 4×3"))
    }

    func testEveryFormatFieldRoutesAsAClickableControl() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 900, height: 24))
        let delegate = Delegate()
        status.delegate = delegate
        status.layoutSubtreeIfNeeded()

        let formatControls: [StatusBarControl] = [
            .encoding, .byteOrderMark, .lineEnding, .languageProfile,
        ]
        for control in formatControls {
            XCTAssertNotNil(status.frame(for: control))
            status.activate(control)
        }

        XCTAssertEqual(delegate.controls.count, formatControls.count)
    }

    func testLargeFileModeIsVisibleExplicitAndClickable() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 900, height: 24))
        let delegate = Delegate()
        status.delegate = delegate
        status.updateLargeFileMode(.reducedFeatures)
        status.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            status.displayedLargeFileModeText,
            SettingsLocalization.text("reducedFeatures"))
        XCTAssertNotNil(status.frame(for: .largeFileMode))
        status.activate(.largeFileMode)
        XCTAssertEqual(delegate.controls, [.largeFileMode])

        status.updateLargeFileMode(.normal)
        XCTAssertNil(status.displayedLargeFileModeText)
        XCTAssertNil(status.frame(for: .largeFileMode))
    }

    func testFieldsAreConfigurableAndCursorPositionIsAlwaysRetained() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        status.setConfiguredFieldsForTesting([.encoding, .fontSize])
        status.layoutSubtreeIfNeeded()
        XCTAssertEqual(status.configuredFieldIDs, ["cursorPosition", "encoding", "fontSize"])
        XCTAssertNotNil(status.frame(for: .cursorPosition))
        XCTAssertNotNil(status.frame(for: .encoding))
        XCTAssertNotNil(status.frame(for: .fontSize))
        XCTAssertNil(status.frame(for: .lineEnding))
        XCTAssertNil(status.frame(for: .languageProfile))
    }

    func testNarrowStatusBarHidesLowerPriorityFieldsWithoutOverlap() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        status.layoutSubtreeIfNeeded()
        let visible = StatusBarControl.allCases.compactMap { status.frame(for: $0) }
        for left in visible.indices {
            for right in visible.indices where left < right {
                XCTAssertFalse(visible[left].intersects(visible[right]))
            }
        }
    }

    func testCapsLockAppearsOnlyWhileEnabledAndConfigured() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        status.updateCapsLock(true)
        status.layoutSubtreeIfNeeded()
        XCTAssertEqual(status.displayedCapsLockText, "CAPS")
        status.updateCapsLock(false)
        XCTAssertNil(status.displayedCapsLockText)

        status.setConfiguredFieldsForTesting([.cursorPosition])
        status.updateCapsLock(true)
        XCTAssertNil(status.displayedCapsLockText)
    }

    func testMacroActivityReflectsRealExecutionLifecycleAndConfiguration() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        status.updateMacroActivity(isRunning: true)
        status.layoutSubtreeIfNeeded()
        XCTAssertEqual(status.displayedMacroActivityText, "MACRO")
        status.updateMacroActivity(isRunning: false)
        XCTAssertNil(status.displayedMacroActivityText)

        status.setConfiguredFieldsForTesting([.cursorPosition])
        status.updateMacroActivity(isRunning: true)
        XCTAssertNil(status.displayedMacroActivityText)
    }

    func testMacroRecordingUsesDistinctStatus() async {
        let status = StatusBarView()
        status.updateMacroRecording(isRecording: true)
        XCTAssertEqual(status.displayedMacroActivityText, "REC")
        status.updateMacroRecording(isRecording: false)
        XCTAssertNil(status.displayedMacroActivityText)
    }
}


@preconcurrency @MainActor
final class EditorCursorStateTests: XCTestCase {
    private final class Delegate: EditorViewControllerDelegate {
        var state: EditorCursorState?
        func editorTextDidChange(_ vc: EditorViewController) {}
        func editorCursorMoved(_ vc: EditorViewController, state: EditorCursorState) {
            self.state = state
        }
    }

    func testDisplayColumnIsNotUTF16OffsetAndSelectionCountsAllRanges() async {
        let editor = EditorViewController()
        _ = editor.view
        editor.document = Document(content: "\t日e\u{301}\nnext")
        let delegate = Delegate()
        editor.delegate = delegate
        editor.setSelections([
            NSRange(location: 2, length: 2),
            NSRange(location: 7, length: 1),
        ], primaryRange: NSRange(location: 2, length: 2))
        editor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))

        XCTAssertEqual(delegate.state, EditorCursorState(
            lineNumber: 1, displayColumn: 7, utf16Offset: 2,
            selectedCharacterCount: 2, selectedUTF16Length: 3,
            selectionRangeCount: 2, selectedLineCount: 2))
    }
}
