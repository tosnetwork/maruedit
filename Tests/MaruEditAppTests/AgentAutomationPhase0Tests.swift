import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp
@testable import MaruEditCore

/// Phase 0 of ADR-012: the shared automation core, before any socket, bridge,
/// or protocol exists. Everything here is an invariant the later phases assume
/// and none of them can restore if it is wrong.
@MainActor
final class AgentAutomationPhase0Tests: XCTestCase {

    private func makeEditor(_ content: String = "") -> (EditorViewController, Document) {
        let editor = EditorViewController()
        _ = editor.view
        let document = Document(content: content)
        editor.document = document
        editor.textView.string = document.content
        editor.lineIndex = LineIndex(document.content)
        return (editor, document)
    }

    // MARK: - 0.1 Canonical text

    func testCanonicalizationCoversEveryDocumentIngress() throws {
        // Initializer.
        XCTAssertEqual(Document(content: "a\r\nb\rc").content, "a\nb\nc")

        // Crash-recovery restore.
        let record = RecoveryRecord(
            recoveryID: RecoveryID(), content: "x\r\ny", encoding: .utf8,
            selectionLocation: 0, selectionLength: 0)
        XCTAssertEqual(Document.recovered(from: record).content, "x\ny")

        // Direct assignment — the backstop for paths nobody audited, such as
        // the generated grep-result document.
        let document = Document(content: "")
        document.content = "one\r\ntwo\rthree"
        XCTAssertEqual(document.content, "one\ntwo\nthree")
    }

    func testCanonicalizationCoversEveryEditorIngress() {
        let (editor, document) = makeEditor("")

        // Typing, paste, drop, and IME commit all funnel through insertText.
        editor.textView.insertText("a\r\nb", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertFalse(TextCanonicalization.containsCarriageReturn(editor.textView.string))
        XCTAssertFalse(TextCanonicalization.containsCarriageReturn(document.content))

        // The transaction primitive, which macros, multi-cursor paste, box
        // paste, the conversion pipeline, and external-command output share.
        let length = (editor.textView.string as NSString).length
        _ = editor.applyTransaction(
            [AutomationEdit(range: NSRange(location: 0, length: length), replacement: "x\r\ny\rz")],
            actionName: "test")
        XCTAssertEqual(editor.textView.string, "x\ny\nz")
        XCTAssertEqual(document.content, "x\ny\nz")
    }

    func testAutomationEditCanonicalizesItsReplacementAtConstruction() {
        XCTAssertEqual(
            AutomationEdit(range: NSRange(location: 0, length: 0), replacement: "p\r\nq").replacement,
            "p\nq")
    }

    func testControlCodePickerIsValueBackedAndOffersNoCarriageReturn() {
        let choices = MainWindowController.controlCodeChoices
        XCTAssertFalse(choices.contains { $0.value == 0x0D })
        XCTAssertNil(choices.first { $0.title.hasPrefix("CR") })

        // Removing a row must not shift the codes after it: these three used to
        // be derived from the row index.
        XCTAssertEqual(choices.first { $0.title.hasPrefix("SO ") }?.value, 0x0E)
        XCTAssertEqual(choices.first { $0.title.hasPrefix("SOH") }?.value, 0x01)
        XCTAssertEqual(choices.first { $0.title.hasPrefix("US") }?.value, 0x1F)
        XCTAssertEqual(choices.first { $0.title.hasPrefix("DEL") }?.value, 0x7F)
        XCTAssertEqual(choices.last?.value, 0x7F)

        // Every title still maps to the byte it names.
        for choice in choices {
            let hex = choice.title.split(separator: " ").last.map(String.init) ?? ""
            XCTAssertEqual(UInt8(hex, radix: 16), choice.value, "mismatch for \(choice.title)")
        }
    }

    func testInsertControlCodeRefusesCarriageReturnFromAnyCaller() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "", selections: [])
        XCTAssertFalse(controller.insertControlCode(0x0D))
        XCTAssertTrue(controller.insertControlCode(0x09))
    }

    // MARK: - 0.2 Revisions

    func testTextRevisionCoversEveryMutationPathAndIgnoresNoOps() {
        let (editor, document) = makeEditor("abc")
        let start = document.textRevision

        editor.textView.insertText("d", replacementRange: NSRange(location: 3, length: 0))
        let afterTyping = document.textRevision
        XCTAssertGreaterThan(afterTyping, start)

        _ = editor.applyTransaction(
            [AutomationEdit(range: NSRange(location: 0, length: 1), replacement: "z")],
            actionName: "test")
        let afterTransaction = document.textRevision
        XCTAssertGreaterThan(afterTransaction, afterTyping)

        // Assigning the same text again is not a change.
        let sameText = document.content
        document.content = sameText
        XCTAssertEqual(document.textRevision, afterTransaction)
    }

    func testMetadataRevisionCoversItsEnumeratedDomainAndIgnoresNoOps() {
        let document = Document(content: "x")
        var revision = document.metadataRevision

        func assertBumps(_ label: String, _ mutate: () -> Void) {
            mutate()
            XCTAssertGreaterThan(document.metadataRevision, revision, label)
            revision = document.metadataRevision
        }

        assertBumps("encoding") { document.encoding = .windows31J }
        assertBumps("bom") { document.hasByteOrderMark = true }
        assertBumps("lineEnding") { document.lineEnding = .crlf }
        assertBumps("url") { document.fileURL = URL(fileURLWithPath: "/tmp/x.txt") }
        assertBumps("permissions") { document.posixPermissions = 0o644 }
        assertBumps("readOnly") { document.isReadOnly = true }
        assertBumps("viewMode") { document.isViewMode = true }
        assertBumps("overwriteProhibited") { document.isOverwriteProhibited = true }
        assertBumps("binaryMode") { document.isBinaryMode = true }
        assertBumps("profileReadOnly") { document.profileForcesReadOnly = true }

        // Re-assigning identical values changes nothing.
        document.encoding = .windows31J
        document.isReadOnly = true
        XCTAssertEqual(document.metadataRevision, revision)

        // Text and metadata counters are independent.
        let textRevision = document.textRevision
        document.encoding = .utf8
        XCTAssertEqual(document.textRevision, textRevision)
    }

    func testSelectionRevisionCoversProgrammaticAndDelegatePathsWithoutDoubleCounting() {
        let (editor, _) = makeEditor("hello world")
        let start = editor.selectionRevision

        editor.setSelections([NSRange(location: 0, length: 5)])
        let afterProgrammatic = editor.selectionRevision
        XCTAssertGreaterThan(afterProgrammatic, start)

        // The multi-cursor path deliberately re-applies the same selections
        // after rehighlighting; that must not count as a change.
        editor.setSelections([NSRange(location: 0, length: 5)])
        XCTAssertEqual(editor.selectionRevision, afterProgrammatic)

        // A user selection change arrives through the AppKit delegate.
        editor.textView.setSelectedRange(NSRange(location: 6, length: 5))
        editor.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification))
        XCTAssertGreaterThan(editor.selectionRevision, afterProgrammatic)
    }

    func testCrossPaneSynchronizationRoutesThroughTheSelectionBoundary() {
        let (editor, document) = makeEditor("one two three")
        editor.setSelections([NSRange(location: 0, length: 3)])
        let before = editor.selectionRevision

        // The other pane shortened the document; clamping used to assign
        // selectedRanges directly, leaving SelectionSet stale and bumping
        // nothing.
        document.content = "on"
        editor.synchronizeSharedDocumentState()

        XCTAssertGreaterThan(editor.selectionRevision, before)
        XCTAssertEqual(editor.selectionSet.ranges.map(\.location), editor.textView.selectedRanges.map(\.rangeValue.location))
        for range in editor.selectionSet.ranges {
            XCTAssertLessThanOrEqual(NSMaxRange(range), (document.content as NSString).length)
        }
    }

    // MARK: - 0.3 Effective writability

    func testEveryReadOnlySourceSurvivesRecomputation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("writable.txt")
        try "content".write(to: url, atomically: true, encoding: .utf8)

        let document = Document(fileURL: url, content: "content")

        // Profile policy: the source a focus refresh used to drop.
        document.profileForcesReadOnly = true
        XCTAssertTrue(document.effectiveReadOnlyState(for: url))
        document.isReadOnly = document.effectiveReadOnlyState(for: url)
        document.refreshReadOnlyState()
        XCTAssertTrue(document.isReadOnly, "profile read-only must survive a refresh")

        document.profileForcesReadOnly = false
        document.refreshReadOnlyState()
        XCTAssertFalse(document.isReadOnly)

        // Large-file read-only mode.
        document.largeFileMode = .readOnly
        document.refreshReadOnlyState()
        XCTAssertTrue(document.isReadOnly)
        document.largeFileMode = .normal
        document.refreshReadOnlyState()
        XCTAssertFalse(document.isReadOnly)

        // Filesystem permissions.
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        document.refreshReadOnlyState()
        XCTAssertTrue(document.isReadOnly)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        document.refreshReadOnlyState()
        XCTAssertFalse(document.isReadOnly)
    }

    func testSplitPaneDoesNotMakeAReadOnlyDocumentEditable() {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "protected", selections: [])
        controller.macroEditor.document?.isReadOnly = true

        controller.showEditorSplit(.vertical)

        XCTAssertEqual(controller.secondaryEditorForTesting?.textView.isEditable, false)

        controller.macroEditor.document?.isReadOnly = false
        controller.closeEditorSplit()
        controller.showEditorSplit(.vertical)
        XCTAssertEqual(controller.secondaryEditorForTesting?.textView.isEditable, true)
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
    }

    // MARK: - 0.4 Transaction primitive

    func testTransactionRejectsOutOfBoundsBatchWithoutMutatingAnything() {
        let (editor, document) = makeEditor("abcdef")
        _ = document.bookmarks.toggle(lineAt: 3, in: document.content as NSString)
        let revision = document.textRevision
        let bookmarks = document.bookmarks.offsets

        let result = editor.applyTransaction([
            AutomationEdit(range: NSRange(location: 0, length: 1), replacement: "Z"),
            AutomationEdit(range: NSRange(location: 99, length: 1), replacement: "!"),
        ], actionName: "test")

        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.identifier, "transaction.range_out_of_bounds")
        XCTAssertEqual(editor.textView.string, "abcdef")
        XCTAssertEqual(document.content, "abcdef")
        XCTAssertEqual(document.textRevision, revision)
        XCTAssertEqual(document.bookmarks.offsets, bookmarks)
    }

    func testTransactionRejectsOverlappingEditsRatherThanMergingThem() {
        let (editor, document) = makeEditor("abcdef")
        let result = editor.applyTransaction([
            AutomationEdit(range: NSRange(location: 0, length: 3), replacement: "X"),
            AutomationEdit(range: NSRange(location: 2, length: 2), replacement: "Y"),
        ], actionName: "test")

        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.identifier, "transaction.overlapping_edits")
        XCTAssertEqual(document.content, "abcdef")
    }

    func testTransactionAppliesEveryEditAtomicallyAndReportsWhatItDid() throws {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "aaa bbb ccc", selections: [])
        let editor = controller.macroEditor
        let document = try XCTUnwrap(editor.document)

        let result = editor.applyTransaction([
            AutomationEdit(range: NSRange(location: 0, length: 3), replacement: "111"),
            AutomationEdit(range: NSRange(location: 8, length: 3), replacement: "333"),
        ], actionName: "agent: rename")

        guard case .success(let outcome) = result else { return XCTFail("expected success") }
        XCTAssertEqual(document.content, "111 bbb 333")
        XCTAssertEqual(outcome.appliedEdits.count, 2)
        XCTAssertEqual(outcome.revisions.text, document.textRevision)
        // One tool call is one undo entry, named by its caller.
        XCTAssertEqual(editor.textView.undoManager?.undoActionName, "agent: rename")
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
    }

    func testTransactionRefusesEmptyBatchAndNonEditableDocument() {
        let (editor, document) = makeEditor("abc")
        guard case .failure(let empty) = editor.applyTransaction([], actionName: "t") else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(empty.identifier, "transaction.empty")

        document.isViewMode = true
        let result = editor.applyTransaction(
            [AutomationEdit(range: NSRange(location: 0, length: 1), replacement: "z")],
            actionName: "t")
        guard case .failure(let blocked) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(blocked.identifier, "document.not_editable")
        XCTAssertEqual(document.content, "abc")
    }

    func testUndoRestoresTextSelectionsAndPositionalStateTogether() throws {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "alpha beta", selections: [])
        let editor = controller.macroEditor
        let document = try XCTUnwrap(editor.document)
        _ = document.bookmarks.toggle(lineAt: 0, in: document.content as NSString)
        _ = document.colorMarkers.toggle(
            lineAt: 0, color: .yellow, in: document.content as NSString)
        editor.setSelections([NSRange(location: 0, length: 5)])
        let bookmarksBefore = document.bookmarks.offsets
        let markersBefore = document.colorMarkers.markers
        let editMarksBefore = document.editMarks.offsets
        document.searchColorLayers = [SearchColorLayer(
            query: "alpha", ranges: [NSRange(location: 0, length: 5)], color: .systemYellow)]
        let searchLayersBefore = document.searchColorLayers.count
        let temporaryMarkersBefore = editor.temporaryColorMarkers.count

        _ = editor.applyTransaction(
            [AutomationEdit(range: NSRange(location: 0, length: 5), replacement: "OMEGA-LONGER")],
            actionName: "agent: edit")
        XCTAssertNotEqual(document.content, "alpha beta")

        editor.textView.undoManager?.undo()

        XCTAssertEqual(document.content, "alpha beta")
        XCTAssertEqual(document.bookmarks.offsets, bookmarksBefore)
        XCTAssertEqual(document.colorMarkers.markers, markersBefore)
        // Everything the transaction touches, not just the two sets the first
        // version of this test happened to check.
        XCTAssertEqual(document.editMarks.offsets, editMarksBefore)
        XCTAssertEqual(document.searchColorLayers.count, searchLayersBefore)
        XCTAssertEqual(editor.temporaryColorMarkers.count, temporaryMarkersBefore)
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 0, length: 5)])
        XCTAssertEqual(editor.lineIndex.utf16Length, (document.content as NSString).length)
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
    }

    func testLenientBatchReplaceKeepsItsMultiCursorContract() {
        let (editor, document) = makeEditor("abcdef")

        // Out-of-bounds ranges are dropped, not fatal, for multi-cursor use.
        editor.batchReplace(
            [NSRange(location: 0, length: 1), NSRange(location: 99, length: 1)],
            with: ["Z", "!"])
        XCTAssertEqual(document.content, "Zbcdef")

        // Overlapping ranges merge, with the earliest supplying the text.
        editor.batchReplace(
            [NSRange(location: 0, length: 3), NSRange(location: 2, length: 2)],
            with: ["Q", "R"])
        XCTAssertEqual(document.content, "Qef")
    }

    // MARK: - 0.5 Shared automation service

    func testAutomationIdentifiersAreOpaqueAndUnique() {
        let (firstEditor, firstDocument) = makeEditor("a")
        let (secondEditor, secondDocument) = makeEditor("b")
        XCTAssertNotEqual(firstDocument.automationID, secondDocument.automationID)
        XCTAssertNotEqual(firstEditor.automationID, secondEditor.automationID)
        XCTAssertTrue(firstDocument.automationID.rawValue.hasPrefix("doc_"))
        XCTAssertTrue(firstEditor.automationID.rawValue.hasPrefix("ed_"))

        // Opaque means it carries nothing about the document: not its name, not
        // its path, not its contents. (Checking that a hex id lacks the letter
        // "a" — the first version of this assertion — tested nothing and failed
        // as soon as the counter reached 0xa.)
        let named = Document(fileURL: URL(fileURLWithPath: "/tmp/secret-name.txt"), content: "body")
        let raw = named.automationID.rawValue
        XCTAssertFalse(raw.contains("secret"))
        XCTAssertFalse(raw.contains("tmp"))
        XCTAssertFalse(raw.contains("body"))
        XCTAssertEqual(raw.dropFirst(4).allSatisfy(\.isHexDigit), true)
    }

    func testAutomationServiceExposesValuesOnly() {
        let (editor, document) = makeEditor("hello")
        let service = EditorAutomationService(editor: editor)

        let snapshot = service.documentSnapshot()
        XCTAssertEqual(snapshot?.text, "hello")
        XCTAssertEqual(snapshot?.documentID, document.automationID)
        XCTAssertEqual(snapshot?.contentKind, .text)
        XCTAssertEqual(snapshot?.isEditable, true)

        document.isBinaryMode = true
        XCTAssertEqual(service.documentSnapshot()?.contentKind, .hex)

        XCTAssertEqual(service.editorSnapshot().editorID, editor.automationID)
    }

    func testAutomationServiceSelectionValidationMatchesTheMacroContract() {
        let (editor, _) = makeEditor("hello")
        let service = EditorAutomationService(editor: editor)

        XCTAssertFalse(service.setSelections([]), "an empty set is rejected")
        XCTAssertFalse(
            service.setSelections([NSRange(location: 4, length: 99)]),
            "a range past the end is rejected")
        XCTAssertTrue(service.setSelections([NSRange(location: 1, length: 2)]))
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 1, length: 2)])
    }

    func testAutomationServiceReplaceSelectionsUsesOneUndoStep() throws {
        let controller = MainWindowController()
        controller.prepareUITestDocument(content: "aa bb", selections: [])
        let editor = controller.macroEditor
        let document = try XCTUnwrap(editor.document)
        let service = EditorAutomationService(editor: editor)
        editor.setSelections([NSRange(location: 0, length: 2), NSRange(location: 3, length: 2)])

        _ = service.replaceSelections(with: "X", actionName: "Macro")
        XCTAssertEqual(document.content, "X X")

        editor.textView.undoManager?.undo()
        XCTAssertEqual(document.content, "aa bb")
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
    }
}
