import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp
@testable import MaruEditCore

/// Phase 2: revision-gated writes.
///
/// Every case here corresponds to a way agent editing goes wrong against a real
/// filesystem — a stale snapshot overwriting newer work, a half-applied batch,
/// an edit aimed at coordinates that moved, text the encoding cannot hold.
@MainActor
final class AgentWriteTests: XCTestCase {

    private var home: URL!
    private var coordinator: AppCoordinator!
    private var server: AgentServer!
    private var connection: AgentControlService.Connection!
    private var executor: AgentToolExecutor!
    private var controller: MainWindowController!

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        home = URL(fileURLWithPath: "/tmp/mw-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        coordinator = AppCoordinator()
        controller = coordinator.ensureWindowControllerReady(restoreSession: false)
        server = AgentServer(coordinator: coordinator, home: home)
        connection = AgentControlService.Connection(
            id: AutomationID.next(prefix: "conn"),
            credentialID: nil, claimedName: "test-agent", bridgePID: getpid())
        // States what this suite is testing: editing, cursor movement, and
        // saving, applied directly rather than queued for review.
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments, .writeSelection, .saveDocuments],
            writeMode: .auto)
        executor = AgentToolExecutor(coordinator: coordinator, control: server.control)
    }

    override func tearDown() async throws {
        server?.stop()
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
        try? FileManager.default.removeItem(at: home)
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func document(_ text: String) -> Document {
        controller.prepareUITestDocument(content: text, selections: [])
        return controller.macroEditor.document!
    }

    private func run(_ tool: String, _ arguments: [String: JSONValue]) async -> AgentToolOutcome {
        await executor.run(tool: tool, arguments: .object(arguments), connection: connection)
    }

    private func value(_ outcome: AgentToolOutcome) -> JSONValue? {
        if case .success(let value) = outcome { return value }
        return nil
    }

    private func failureCode(_ outcome: AgentToolOutcome) -> String? {
        if case .failure(let code, _, _) = outcome { return code }
        return nil
    }

    private func edit(_ start: Int, _ end: Int, _ text: String, digest: String? = nil) -> JSONValue {
        var members: [String: JSONValue] = [
            "start": .int(start), "end": .int(end), "text": .string(text),
        ]
        if let digest { members["expectDigest"] = .string(digest) }
        return .object(members)
    }

    // MARK: - Preconditions

    func testAStaleWriteIsRefusedAndSaysWhatChanged() async {
        let doc = document("hello world")
        let stale = doc.textRevision
        // The human types after the agent read.
        controller.macroEditor.textView.insertText(
            "!", replacementRange: NSRange(location: 0, length: 0))

        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(stale)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 5, "HELLO")]),
        ])
        XCTAssertEqual(failureCode(outcome), "state.text_revision_conflict")
        XCTAssertEqual(doc.content, "!hello world", "nothing may be written on a stale base")
    }

    func testAMetadataOnlyChangeIsItsOwnConflictAndDoesNotForceAReRead() async {
        let doc = document("hello")
        let revision = doc.textRevision
        let metadata = doc.metadataRevision
        // Changing the encoding moves no text, but it does change what an edit
        // is allowed to contain.
        doc.encoding = .windows31J

        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(revision)),
            "baseMetadataRevision": .int(Int(metadata)),
            "edits": .array([edit(0, 5, "HELLO")]),
        ])
        XCTAssertEqual(failureCode(outcome), "state.metadata_conflict")

        // The offsets were never invalid, so resubmitting with the new metadata
        // revision succeeds without re-reading.
        let retry = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 5, "HELLO")]),
        ])
        XCTAssertEqual(value(retry)?["status"], .string("applied"))
        XCTAssertEqual(doc.content, "HELLO")
    }

    func testADigestMismatchIsDistinguishedAndCarriesTheCurrentText() async {
        let doc = document("alpha beta")
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 5, "OMEGA", digest: AgentDigest.of("wrong"))]),
        ])
        XCTAssertEqual(failureCode(outcome), "state.digest_mismatch")
        XCTAssertEqual(doc.content, "alpha beta")
    }

    // MARK: - Application

    func testEditsApplyAtomicallyAsOneUndoEntry() async {
        let doc = document("aaa bbb ccc")
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "label": .string("rename"),
            "edits": .array([edit(0, 3, "111"), edit(8, 11, "333")]),
        ])
        XCTAssertEqual(value(outcome)?["status"], .string("applied"))
        XCTAssertEqual(doc.content, "111 bbb 333")
        XCTAssertEqual(
            controller.macroEditor.textView.undoManager?.undoActionName, "test-agent: rename")

        controller.macroEditor.textView.undoManager?.undo()
        XCTAssertEqual(doc.content, "aaa bbb ccc", "one call is one undo")
    }

    func testAnInvalidEditInABatchLeavesTheDocumentUntouched() async {
        let doc = document("abcdef")
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 1, "Z"), edit(99, 100, "!")]),
        ])
        XCTAssertEqual(failureCode(outcome), "edit.range_invalid")
        XCTAssertEqual(doc.content, "abcdef")
    }

    func testOverlappingEditsAreRefusedRatherThanMerged() async {
        let doc = document("abcdef")
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 3, "X"), edit(2, 4, "Y")]),
        ])
        XCTAssertEqual(failureCode(outcome), "transaction.overlapping_edits")
        XCTAssertEqual(doc.content, "abcdef")
    }

    func testCarriageReturnIsRefusedNotNormalized() async {
        let doc = document("line")
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 4, "a\r\nb")]),
        ])
        // The agent is told its payload was wrong rather than having it
        // silently rewritten.
        XCTAssertEqual(failureCode(outcome), "text.carriage_return")
        XCTAssertEqual(doc.content, "line")
    }

    func testTextTheEncodingCannotHoldIsRefusedBeforeAnythingIsWritten() async {
        let doc = document("hello")
        doc.encoding = .windows31J
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 5, "emoji 😀")]),
        ])
        // Otherwise the document could not be saved without a human conversion
        // decision the agent never asked for.
        XCTAssertEqual(failureCode(outcome), "encoding.unrepresentable")
        XCTAssertEqual(doc.content, "hello")
    }

    func testJapaneseTextIsFineInAJapaneseEncoding() async {
        let doc = document("hello")
        doc.encoding = .windows31J
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 5, "日本語テキスト")]),
        ])
        XCTAssertEqual(value(outcome)?["status"], .string("applied"))
        XCTAssertEqual(doc.content, "日本語テキスト")
        XCTAssertEqual(doc.encoding, .windows31J, "an edit never changes the encoding")
    }

    // MARK: - Anchors

    func testAnchorsAreMintedBoundedAndDieWithTheirRevision() async throws {
        let doc = document("alpha\nbeta\ngamma\n")
        let readOutcome = await run("read_document", [
            "documentId": .string(doc.automationID.rawValue),
            "startLine": .int(2), "endLine": .int(3),
            "withAnchors": .bool(true),
        ])
        let read = try XCTUnwrap(value(readOutcome))
        let anchors = try XCTUnwrap(read["anchors"]?.arrayValue)
        XCTAssertEqual(anchors.count, 1, "withAnchors mints exactly one, for the returned range")
        let anchorID = try XCTUnwrap(anchors.first?["anchorId"]?.stringValue)

        // Editing through the anchor works while its revision stands.
        let applied = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([.object([
                "anchorId": .string(anchorID),
                "expectDigest": .string(try XCTUnwrap(anchors.first?["digest"]?.stringValue)),
                "text": .string("BETA\n"),
            ])]),
        ])
        XCTAssertEqual(value(applied)?["status"], .string("applied"))
        XCTAssertEqual(doc.content, "alpha\nBETA\ngamma\n")

        // That same anchor is now stale: it is a snapshot handle, not a
        // tracked range.
        let reused = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([.object([
                "anchorId": .string(anchorID), "text": .string("x"),
            ])]),
        ])
        XCTAssertEqual(failureCode(reused), "anchor.stale")
    }

    func testAnchorRequestFormsAreMutuallyExclusiveAndCapped() async {
        let doc = document("abcdefghij")
        let both = await run("read_document", [
            "documentId": .string(doc.automationID.rawValue),
            "withAnchors": .bool(true),
            "anchorRanges": .array([.object(["start": .int(0), "end": .int(1)])]),
        ])
        XCTAssertEqual(failureCode(both), "argument.conflict")

        let tooMany = await run("read_document", [
            "documentId": .string(doc.automationID.rawValue),
            "anchorRanges": .array((0..<40).map { _ in
                .object(["start": .int(0), "end": .int(1)])
            }),
        ])
        XCTAssertEqual(failureCode(tooMany), "limit.anchors")
    }

    func testAnEditCannotCarryBothAnAnchorAndOffsets() async {
        let doc = document("abcdef")
        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([.object([
                "anchorId": .string("a_1"), "start": .int(0), "end": .int(1),
                "text": .string("x"),
            ])]),
        ])
        XCTAssertEqual(failureCode(outcome), "edit.ambiguous_address")
    }

    // MARK: - Documents this profile will not write

    func testReadOnlyViewModeAndBinaryDocumentsAreRefused() async {
        let doc = document("protected")
        let arguments: [String: JSONValue] = [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 1, "X")]),
        ]

        doc.isReadOnly = true
        let readOnly = failureCode(await run("apply_edits", arguments))
        XCTAssertEqual(readOnly, "document.not_editable")
        doc.isReadOnly = false

        doc.isViewMode = true
        let viewMode = failureCode(await run("apply_edits", arguments))
        XCTAssertEqual(viewMode, "document.not_editable")
        doc.isViewMode = false

        doc.isBinaryMode = true
        // The buffer is a hex rendering; editing it as text is a corruption
        // engine.
        let binary = failureCode(await run("apply_edits", arguments))
        XCTAssertEqual(binary, "document.unsupported_kind")
        doc.isBinaryMode = false

        XCTAssertEqual(doc.content, "protected")
    }

    func testASplitDocumentRefusesWritesBecauseUndoWouldBeAmbiguous() async {
        let doc = document("split me")
        controller.showEditorSplit(.vertical)
        defer { controller.closeEditorSplit() }
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments], writeMode: .auto)

        let outcome = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 5, "SPLIT")]),
        ])
        XCTAssertEqual(failureCode(outcome), "document.multiple_panes")
        XCTAssertEqual(doc.content, "split me")
    }

    // MARK: - Review mode

    func testReviewModeQueuesRatherThanApplyingAndNeverBlocks() async throws {
        let doc = document("review me")
        let outcome1 = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "mode": .string("review"),
            "label": .string("tidy"),
            "edits": .array([edit(0, 6, "REVIEW")]),
        ])
        let queued = try XCTUnwrap(value(outcome1))
        XCTAssertEqual(queued["status"], .string("pending"))
        let proposalID = try XCTUnwrap(queued["proposalId"]?.stringValue)
        XCTAssertEqual(doc.content, "review me", "a queued edit is not applied")

        let outcome2 = await run("review_status", [
            "proposalId": .string(proposalID),
        ])
        let status = try XCTUnwrap(value(outcome2))
        XCTAssertEqual(status["status"], .string("pending"))

        let proposal = try XCTUnwrap(server.control.proposals.proposal(proposalID))
        let target = try XCTUnwrap(coordinator.agentVisibleTargets().first {
            $0.document.automationID == doc.automationID
        })
        XCTAssertTrue(AgentToolExecutor.applyProposal(
            proposal,
            target: AgentToolExecutor.Target(document: target.document, editor: target.editor),
            store: server.control.proposals))
        XCTAssertEqual(doc.content, "REVIEW me")

        let outcome3 = await run("review_status", [
            "proposalId": .string(proposalID),
        ])
        let after = try XCTUnwrap(value(outcome3))
        XCTAssertEqual(after["status"], .string("applied"))
    }

    func testAProposalAcceptedAfterTheHumanTypedConflictsRatherThanApplying() async throws {
        let doc = document("review me")
        let outcome4 = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "mode": .string("review"),
            "edits": .array([edit(0, 6, "REVIEW")]),
        ])
        let queued = try XCTUnwrap(value(outcome4))
        let proposalID = try XCTUnwrap(queued["proposalId"]?.stringValue)

        // The human keeps typing, which they are explicitly allowed to do.
        controller.macroEditor.textView.insertText(
            "!", replacementRange: NSRange(location: 0, length: 0))

        let proposal = try XCTUnwrap(server.control.proposals.proposal(proposalID))
        let target = try XCTUnwrap(coordinator.agentVisibleTargets().first {
            $0.document.automationID == doc.automationID
        })
        XCTAssertFalse(AgentToolExecutor.applyProposal(
            proposal,
            target: AgentToolExecutor.Target(document: target.document, editor: target.editor),
            store: server.control.proposals))
        XCTAssertEqual(doc.content, "!review me", "stored ranges are never relocated to fit")
        XCTAssertEqual(
            server.control.proposals.proposal(proposalID)?.status, .conflicted)
    }

    func testProposalBudgetsAreEnforced() async {
        let doc = document(String(repeating: "x", count: 100))
        for index in 0..<AgentProposalStore.maximumPendingPerDocument {
            let outcome = await run("apply_edits", [
                "documentId": .string(doc.automationID.rawValue),
                "baseRevision": .int(Int(doc.textRevision)),
                "baseMetadataRevision": .int(Int(doc.metadataRevision)),
                "mode": .string("review"),
                "edits": .array([edit(index, index + 1, "y")]),
            ])
            XCTAssertEqual(value(outcome)?["status"], .string("pending"))
        }
        // Rate limiting bounds requests; it does not bound retained state, so
        // proposals need their own budget.
        let overflow = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "mode": .string("review"),
            "edits": .array([edit(50, 51, "z")]),
        ])
        XCTAssertEqual(failureCode(overflow), "limit.pending_proposals")
    }

    // MARK: - Selection and save

    func testSelectionWritesNeedBothPreconditions() async {
        let doc = document("hello world")
        let editor = controller.macroEditor
        let arguments: [String: JSONValue] = [
            "editorId": .string(editor.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseSelectionRevision": .int(Int(editor.selectionRevision)),
            "selections": .array([.object(["start": .int(0), "end": .int(5)])]),
        ]
        let firstMove = await run("set_selection", arguments)
        XCTAssertNotNil(value(firstMove))
        XCTAssertEqual(editor.selectionSet.ranges, [NSRange(location: 0, length: 5)])

        // The human moves the cursor; the agent's stale target is refused.
        editor.setSelections([NSRange(location: 6, length: 5)])
        let hoisted1 = await run("set_selection", arguments)
        XCTAssertEqual(failureCode(hoisted1), "state.selection_conflict")
    }

    func testSelectionIsRefusedWhenTheTextMovedEvenIfTheCursorDidNot() async {
        let doc = document("hello world")
        let editor = controller.macroEditor
        let staleRevision = doc.textRevision
        editor.setSelections([NSRange(location: 0, length: 1)])
        let selectionRevision = editor.selectionRevision

        // An edit elsewhere shifts the coordinates without moving the cursor,
        // which is exactly why the selection revision alone is not enough.
        doc.content = "hello there world"

        let outcome = await run("set_selection", [
            "editorId": .string(editor.automationID.rawValue),
            "baseRevision": .int(Int(staleRevision)),
            "baseSelectionRevision": .int(Int(selectionRevision)),
            "selections": .array([.object(["start": .int(0), "end": .int(5)])]),
        ])
        XCTAssertEqual(failureCode(outcome), "state.text_revision_conflict")
    }

    func testSavingAnUntitledDocumentIsRefusedRatherThanGuessingAPath() async {
        let doc = document("unsaved")
        let outcome = await run("save_document", [
            "documentId": .string(doc.automationID.rawValue),
            "expectRevision": .int(Int(doc.textRevision)),
            "expectMetadataRevision": .int(Int(doc.metadataRevision)),
        ])
        // Picking a filename on the human's behalf is not this tool's job.
        XCTAssertEqual(failureCode(outcome), "save.save_as_required")
    }

    func testAnAgentSaveWritesTheFileAndReportsTheResultingState() async throws {
        let directory = URL(fileURLWithPath: "/tmp/mas-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("agent.txt")
        try "before\n".write(to: url, atomically: true, encoding: .utf8)

        controller.adoptAgentOpenedDocument(url: url, loaded: try TextFileLoader.load(contentsOf: url))
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments, .saveDocuments], writeMode: .auto)
        let doc = try XCTUnwrap(controller.macroEditor.document)

        let edited = await run("apply_edits", [
            "documentId": .string(doc.automationID.rawValue),
            "baseRevision": .int(Int(doc.textRevision)),
            "baseMetadataRevision": .int(Int(doc.metadataRevision)),
            "edits": .array([edit(0, 6, "after")]),
        ])
        XCTAssertEqual(value(edited)?["status"], .string("applied"))

        let saveOutcome = await run("save_document", [
            "documentId": .string(doc.automationID.rawValue),
            "expectRevision": .int(Int(doc.textRevision)),
            "expectMetadataRevision": .int(Int(doc.metadataRevision)),
        ])
        let saved = try XCTUnwrap(value(saveOutcome))
        XCTAssertEqual(saved["status"], .string("saved"))
        XCTAssertEqual(saved["stillDirty"], .bool(false))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "after\n")
    }

    func testAnAgentSaveOnAStaleRevisionWritesNothing() async throws {
        let directory = URL(fileURLWithPath: "/tmp/mas-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("stale.txt")
        try "before\n".write(to: url, atomically: true, encoding: .utf8)
        controller.adoptAgentOpenedDocument(url: url, loaded: try TextFileLoader.load(contentsOf: url))
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .writeDocuments, .saveDocuments], writeMode: .auto)
        let doc = try XCTUnwrap(controller.macroEditor.document)

        let stale = doc.textRevision
        controller.macroEditor.textView.insertText(
            "!", replacementRange: NSRange(location: 0, length: 0))

        let outcome = await run("save_document", [
            "documentId": .string(doc.automationID.rawValue),
            "expectRevision": .int(Int(stale)),
            "expectMetadataRevision": .int(Int(doc.metadataRevision)),
        ])
        XCTAssertEqual(failureCode(outcome), "state.text_revision_conflict")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "before\n")
    }
}

/// Phase 3: the two tools that reach past the documents already open.
@MainActor
final class AgentAppControlTests: XCTestCase {

    private var home: URL!
    private var workspace: URL!
    private var coordinator: AppCoordinator!
    private var server: AgentServer!
    private var connection: AgentControlService.Connection!
    private var executor: AgentToolExecutor!

    override func setUp() async throws {
        try await super.setUp()
        _ = NSApplication.shared
        home = URL(fileURLWithPath: "/tmp/mac-\(UUID().uuidString.prefix(8))")
        workspace = home.appendingPathComponent("workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        coordinator = AppCoordinator()
        _ = coordinator.ensureWindowControllerReady(restoreSession: false)
        server = AgentServer(coordinator: coordinator, home: home)
        connection = AgentControlService.Connection(
            id: AutomationID.next(prefix: "conn"),
            credentialID: nil, claimedName: "test-agent", bridgePID: getpid())
        // Opening files and running commands, but no folder yet — the point of
        // the first test is that the capability alone is not enough.
        server.control.approveForTesting(
            connection, coordinator: coordinator,
            capabilities: [.readOnly, .openDocuments, .runCommands])
        executor = AgentToolExecutor(coordinator: coordinator, control: server.control)
    }

    override func tearDown() async throws {
        server?.stop()
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
        try? FileManager.default.removeItem(at: home)
        try await super.tearDown()
    }

    private func run(_ tool: String, _ arguments: [String: JSONValue]) async -> AgentToolOutcome {
        await executor.run(tool: tool, arguments: .object(arguments), connection: connection)
    }

    private func failureCode(_ outcome: AgentToolOutcome) -> String? {
        if case .failure(let code, _, _) = outcome { return code }
        return nil
    }

    /// Grants the connection the folders the human offered.
    private func grantRoots() {
        server.control.grantRoots(connection, server.control.offeredRoots)
    }

    func testOpeningIsUnavailableUntilAFolderIsAuthorized() async throws {
        let file = workspace.appendingPathComponent("notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        // Unavailable rather than permissive: a capability whose scope nobody
        // chose is not a scoped capability.
        let refused = await run("open_document", ["path": .string(file.path)])
        XCTAssertEqual(failureCode(refused), "authorization.no_root")

        server.control.addAuthorizedRoot(workspace.path)
        grantRoots()
        let opened = await run("open_document", ["path": .string(file.path)])
        guard case .success(let payload) = opened else {
            return XCTFail("expected success, got \(opened)")
        }
        let documentID = try XCTUnwrap(payload["documentId"]?.stringValue)

        // The one sanctioned way a frozen grant grows — and it grew by an
        // object the human's own root authorization already covered.
        let listed = await run("list_documents", [:])
        guard case .success(let documents) = listed else { return XCTFail("list failed") }
        let ids = documents["documents"]?.arrayValue?.compactMap { $0["documentId"]?.stringValue }
        XCTAssertTrue(ids?.contains(documentID) == true)

        let read = await run("read_document", ["documentId": .string(documentID)])
        guard case .success(let text) = read else { return XCTFail("read failed") }
        XCTAssertEqual(text["text"]?.stringValue, "hello")
    }

    func testOpeningOutsideTheRootOrThroughASymlinkIsRefused() async throws {
        let secret = home.appendingPathComponent("secret.txt")
        try "secret".write(to: secret, atomically: true, encoding: .utf8)
        server.control.addAuthorizedRoot(workspace.path)
        grantRoots()

        let outside = await run("open_document", ["path": .string(secret.path)])
        XCTAssertEqual(failureCode(outside), "path.outside_root")

        let link = workspace.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)
        // Inside the root by string comparison, which is exactly why string
        // comparison is not the boundary.
        let symlinked = await run("open_document", ["path": .string(link.path)])
        XCTAssertEqual(failureCode(symlinked), "path.symlink")
    }

    func testAJapaneseEncodedFileKeepsItsEncodingWhenAnAgentOpensIt() async throws {
        let file = workspace.appendingPathComponent("sjis.txt")
        let text = "日本語のテキスト\n"
        try XCTUnwrap(text.data(using: .shiftJIS)).write(to: file)
        server.control.addAuthorizedRoot(workspace.path)
        grantRoots()

        let opened = await run("open_document", ["path": .string(file.path)])
        guard case .success(let payload) = opened else { return XCTFail("open failed: \(opened)") }
        // Routed through the ordinary lifecycle, so detection behaves exactly
        // as it does when a human opens the file.
        XCTAssertTrue(payload["encoding"]?.stringValue?.contains("Shift") == true)

        let documentID = try XCTUnwrap(payload["documentId"]?.stringValue)
        let read = await run("read_document", ["documentId": .string(documentID)])
        guard case .success(let value) = read else { return XCTFail("read failed") }
        XCTAssertEqual(value["text"]?.stringValue, text)
    }

    func testCommandsAreDefaultDenyAndOnlyDocumentIndependentOnesAreExposed() async {
        let unexposed = await run("run_command", ["commandId": .string("app.settings")])
        // Registering a command must never be what makes it remotely invocable.
        XCTAssertEqual(failureCode(unexposed), "command.not_exposed")

        let unknown = await run("run_command", ["commandId": .string("no.such.command")])
        XCTAssertEqual(failureCode(unknown), "command.unknown")

        let exposed = await run("run_command", ["commandId": .string("file.new")])
        guard case .success(let payload) = exposed else { return XCTFail("expected success") }
        XCTAssertEqual(payload["ran"], .bool(true))
    }
}
