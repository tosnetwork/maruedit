import AppKit
import MaruEditCore
import XCTest
@preconcurrency @testable import MaruEditApp


@preconcurrency @MainActor
final class StatusBarViewTests: XCTestCase {
    func testWritingAndColumnLayoutFieldIsExplicitAndAccessible() {
        let bar = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1_200, height: 24))
        bar.updateLayoutMode(isVertical: false, isColumn: false, columnCount: 1)
        XCTAssertEqual(bar.displayedLayoutModeText, "HORZ")
        bar.updateLayoutMode(isVertical: true, isColumn: false, columnCount: 1)
        XCTAssertEqual(bar.displayedLayoutModeText, "VERT")
        bar.updateLayoutMode(isVertical: false, isColumn: true, columnCount: 3)
        XCTAssertEqual(bar.displayedLayoutModeText, "COL×3")
        bar.layoutSubtreeIfNeeded()
        XCTAssertNotNil(bar.frame(for: .layoutMode))
    }
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
        for control: StatusBarControl in [.cursorPosition, .totals, .characterCode, .inputMode, .fontSize] {
            XCTAssertNotNil(status.frame(for: control)); status.activate(control)
        }
        XCTAssertEqual(delegate.controls, [.cursorPosition, .totals, .characterCode, .inputMode, .fontSize])
    }

    func testCharacterCountUsesConfigurableHidemaruCategoryWeightsAndRoundsUp() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        defer { status.setCharacterCountConfiguration(.standard) }
        status.setCharacterCountConfiguration(CharacterCountConfiguration(
            fullWidth: 1, halfWidth: 0.5, fullWidthSpace: 2,
            halfWidthSpace: 0.25, tab: 4, lineBreak: 0))
        status.updateDocumentMetrics(text: "日A　 \t\n", fontSize: 13)
        XCTAssertEqual(status.displayedTotalsText, "2 lines · 8 chars")
        XCTAssertEqual(status.characterCountConfiguration.halfWidth, 0.5)
    }

    func testCharacterCodeDetailsIncludeUnicodeUTF8AndShiftJIS() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        status.updateDocumentMetrics(text: "日", fontSize: 13)
        status.updateEncoding(.windows31J)
        status.updateCursor(EditorCursorState(
            lineNumber: 1, displayColumn: 1, utf16Offset: 0,
            selectedCharacterCount: 0, selectedUTF16Length: 0, selectionRangeCount: 1))
        XCTAssertEqual(status.displayedCharacterCodeText, "93 FA")
        XCTAssertTrue(status.characterCodeDetail.contains("Unicode: U+65E5"))
        XCTAssertTrue(status.characterCodeDetail.contains("UTF-8: E6 97 A5"))
        XCTAssertTrue(status.characterCodeDetail.contains("Shift-JIS): 93 FA"))
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
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        let delegate = Delegate(); status.delegate = delegate
        status.updateMacroRecording(isRecording: true)
        status.layoutSubtreeIfNeeded()
        XCTAssertEqual(status.displayedMacroActivityText, "REC")
        XCTAssertNotNil(status.frame(for: .macroActivity))
        status.activate(.macroActivity)
        XCTAssertEqual(delegate.controls, [.macroActivity])
        status.updateMacroRecording(isRecording: false)
        XCTAssertNil(status.displayedMacroActivityText)
    }

    func testStatusBarClickActionsCanBeDisabledGlobally() async {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1100, height: 24))
        let delegate = Delegate(); status.delegate = delegate
        status.layoutSubtreeIfNeeded()
        status.setClickActionsEnabled(false)
        status.activate(.cursorPosition)
        status.activate(.encoding)
        XCTAssertTrue(delegate.controls.isEmpty)
        XCTAssertFalse(status.areClicksEnabled)

        status.setClickActionsEnabled(true)
        status.activate(.cursorPosition)
        XCTAssertEqual(delegate.controls, [.cursorPosition])
    }

    func testVoiceOverPressInvokesEveryInteractiveStatusField() {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1_600, height: 24))
        let delegate = Delegate(); status.delegate = delegate
        status.updateDocumentMetrics(text: "A", fontSize: 13)
        status.updateCursor(EditorCursorState(
            lineNumber: 1, displayColumn: 1, utf16Offset: 0,
            selectedCharacterCount: 0, selectedUTF16Length: 0, selectionRangeCount: 1))
        status.updateMacroActivity(isRunning: true)
        status.updateLargeFileMode(.reducedFeatures)
        status.layoutSubtreeIfNeeded()

        let expected: [StatusBarControl] = [
            .cursorPosition, .totals, .characterCode, .inputMode, .layoutMode, .fontSize,
            .macroActivity, .largeFileMode, .encoding, .byteOrderMark, .lineEnding,
            .languageProfile,
        ]
        for control in expected {
            let field = try! XCTUnwrap(status.accessibilityElement(for: control))
            XCTAssertEqual(field.accessibilityRole(), .button)
            XCTAssertFalse(field.accessibilityLabel()?.isEmpty ?? true)
            XCTAssertTrue(field.accessibilityPerformPress(), "VoiceOver cannot press \(control)")
        }
        XCTAssertEqual(delegate.controls, expected)

        status.setClickActionsEnabled(false)
        let cursor = try! XCTUnwrap(status.accessibilityElement(for: .cursorPosition))
        XCTAssertFalse(cursor.accessibilityPerformPress())
        XCTAssertEqual(delegate.controls, expected)
    }

    func testStatusFontSizeAdjustmentClampsAndUpdatesEditorImmediately() async {
        let controller = MainWindowController()
        controller.adjustStatusFontSizeForTesting(21)
        XCTAssertEqual(controller.currentStatusFontSizeForTesting, 21)
        controller.adjustStatusFontSizeForTesting(100)
        XCTAssertEqual(controller.currentStatusFontSizeForTesting, 72)
        controller.adjustStatusFontSizeForTesting(2)
        XCTAssertEqual(controller.currentStatusFontSizeForTesting, 8)
    }

    func testCrossStateMatrixDoesNotLeakStatusBetweenDocumentsOrEditingModes() {
        let status = StatusBarView(frame: NSRect(x: 0, y: 0, width: 1_400, height: 24))

        struct State {
            let text: String
            let cursor: EditorCursorState
            let encoding: TextEncoding
            let bom: Bool
            let lineEnding: LineEndingState
            let language: Language
            let profile: String?
            let inputMode: EditorInputMode
            let largeFileMode: LargeFileMode
        }
        let states = [
            State(
                text: "ASCII\nsecond", cursor: EditorCursorState(
                    lineNumber: 1, displayColumn: 1, utf16Offset: 0,
                    selectedCharacterCount: 0, selectedUTF16Length: 0,
                    selectionRangeCount: 1),
                encoding: .utf8, bom: true, lineEnding: .lf,
                language: .plainText, profile: nil, inputMode: .insert,
                largeFileMode: .normal),
            State(
                text: "日本語\r\n二行目", cursor: EditorCursorState(
                    lineNumber: 1, displayColumn: 2, utf16Offset: 1,
                    selectedCharacterCount: 6, selectedUTF16Length: 6,
                    selectionRangeCount: 3, selectedLineCount: 2,
                    boxWidth: 2, boxHeight: 3),
                encoding: .windows31J, bom: false, lineEnding: .crlf,
                language: .markdown, profile: "Japanese Notes", inputMode: .overwrite,
                largeFileMode: .reducedFeatures),
            State(
                text: "e\u{301} emoji 👨‍👩‍👧", cursor: EditorCursorState(
                    lineNumber: 1, displayColumn: 3, utf16Offset: 2,
                    selectedCharacterCount: 0, selectedUTF16Length: 0,
                    selectionRangeCount: 4),
                encoding: .utf16LittleEndian, bom: true, lineEnding: .cr,
                language: .swift, profile: "Swift Strict", inputMode: .insert,
                largeFileMode: .readOnly),
        ]

        for (index, state) in states.enumerated() {
            status.updateDocumentMetrics(text: state.text, fontSize: CGFloat(13 + index))
            status.updateEncoding(state.encoding)
            status.updateByteOrderMark(state.bom)
            status.updateLineEnding(state.lineEnding)
            status.updateLanguage(state.language, profileName: state.profile)
            status.updateInputMode(state.inputMode)
            status.updateLargeFileMode(state.largeFileMode)
            status.updateCursor(state.cursor)
            status.layoutSubtreeIfNeeded()

            XCTAssertEqual(status.displayedEncodingText, state.encoding.displayName)
            XCTAssertEqual(status.displayedBOMText, state.bom ? "BOM" : "No BOM")
            XCTAssertEqual(status.displayedLineEndingText, state.lineEnding.displayName)
            XCTAssertEqual(status.displayedInputModeText, state.inputMode == .insert ? "INS" : "OVR")
            XCTAssertEqual(
                status.displayedLanguageProfileText,
                state.profile.map { "\(state.language.displayName) · \($0)" }
                    ?? state.language.displayName)
            XCTAssertEqual(status.displayedLargeFileModeText == nil, state.largeFileMode == .normal)
        }

        // Returning to the ordinary tab must clear every conditional value
        // produced by BOX/multi-selection and large-file tabs.
        let ordinary = states[0]
        status.updateDocumentMetrics(text: ordinary.text, fontSize: 13)
        status.updateEncoding(ordinary.encoding)
        status.updateByteOrderMark(ordinary.bom)
        status.updateLineEnding(ordinary.lineEnding)
        status.updateLanguage(ordinary.language, profileName: ordinary.profile)
        status.updateInputMode(ordinary.inputMode)
        status.updateLargeFileMode(ordinary.largeFileMode)
        status.updateCursor(ordinary.cursor)
        XCTAssertEqual(status.displayedSelectionText, "")
        XCTAssertNil(status.displayedLargeFileModeText)
        XCTAssertEqual(status.displayedCharacterCodeText, "U+0041")
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
