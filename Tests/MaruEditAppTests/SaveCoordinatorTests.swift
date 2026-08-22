import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp
@testable import MaruEditCore

/// The save machine, and the bug it exists to kill.
///
/// The old code recorded whatever the buffer held when the write returned, so
/// the moment encoding moved off the main actor a document could be reported
/// clean in a state it was never saved in. Most of these cases are about that
/// one sentence.
@MainActor
final class SaveCoordinatorTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        _ = NSApplication.shared
        directory = URL(fileURLWithPath: "/tmp/msc-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func fileDocument(_ text: String, named name: String = "doc.txt") throws -> (Document, URL) {
        let url = directory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let document = try Document.open(url: url)
        return (document, url)
    }

    private func save(
        _ document: Document, as url: URL? = nil,
        requester: SaveCoordinator.Requester = .human
    ) async -> SaveCoordinator.Outcome {
        await withCheckedContinuation { continuation in
            SaveCoordinator.shared.save(document: document, as: url, requester: requester) {
                continuation.resume(returning: $0)
            }
        }
    }

    /// Holds an outcome that may arrive before or after anyone waits for it.
    ///
    /// Main-actor confined, so no locking: the coordinator's completion and the
    /// test both run there.
    @MainActor
    private final class OutcomeBox {
        private var outcome: SaveCoordinator.Outcome?
        private var waiter: CheckedContinuation<SaveCoordinator.Outcome, Never>?

        func deliver(_ value: SaveCoordinator.Outcome) {
            if let waiter {
                self.waiter = nil
                waiter.resume(returning: value)
            } else {
                outcome = value
            }
        }

        func value() async -> SaveCoordinator.Outcome {
            if let outcome { return outcome }
            return await withCheckedContinuation { waiter = $0 }
        }
    }

    /// Starts a save and returns before it finishes.
    ///
    /// `async let` would not do: it may not run the child task until it is
    /// awaited, so a test that mutates the document "during" the save would
    /// actually mutate it beforehand and prove nothing. Calling the callback
    /// API directly captures the plan synchronously, which is the point — and
    /// the result is then *awaited* rather than waited for on a nested run
    /// loop, which would occupy the main actor the coordinator needs to hop
    /// back onto.
    private func beginSave(
        _ document: Document, as url: URL? = nil,
        requester: SaveCoordinator.Requester = .human
    ) -> OutcomeBox {
        let box = OutcomeBox()
        SaveCoordinator.shared.save(document: document, as: url, requester: requester) {
            box.deliver($0)
        }
        return box
    }

    // MARK: - The bug

    func testTextTypedWhileASaveIsPreparingLeavesTheDocumentDirty() async throws {
        let (document, url) = try fileDocument("original\n")
        document.content = "planned\n"
        document.markModified()

        // Start the save, then type before it commits — the window the old
        // code got wrong.
        let box = beginSave(document)
        document.content = "planned and then some more\n"
        document.markModified()
        let result = await box.value()

        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "planned\n")
        // The newer text is genuinely unsaved, and saying otherwise is how work
        // gets lost.
        XCTAssertTrue(
            document.isModified,
            "text typed during the save must not be reported as saved")
    }

    func testAnUnchangedBufferIsCleanAfterSaving() async throws {
        let (document, _) = try fileDocument("stable\n")
        document.content = "written\n"
        document.markModified()
        let result1 = await save(document)
        XCTAssertEqual(result1, .succeeded)
        XCTAssertFalse(document.isModified)
    }

    func testAMetadataChangeDuringTheSaveLeavesTheDocumentFormatDirty() async throws {
        let (document, _) = try fileDocument("text\n")
        document.content = "text\n"
        document.markModified()

        let box = beginSave(document)
        // Changing the encoding moves no text, but the file was never saved in
        // this form.
        document.encoding = .windows31J
        let result = await box.value()

        XCTAssertEqual(result, .succeeded)
        XCTAssertTrue(document.isModified, "a format change during the save is still unsaved")
    }

    // MARK: - Preconditions

    func testExternalChangesAreNeverSilentlyOverwritten() async throws {
        let (document, url) = try fileDocument("mine\n")
        document.content = "mine edited\n"
        document.markModified()

        // Another editor writes the file after we opened it.
        try "theirs\n".write(to: url, atomically: true, encoding: .utf8)

        let outcome = await save(document)
        XCTAssertEqual(outcome, .conflicted("external_change"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "theirs\n")
    }

    func testAnUntitledDocumentReportsThatItNeedsSaveAs() async {
        let document = Document(content: "unnamed")
        let result2 = await save(document)
        XCTAssertEqual(result2, .failedBeforeIrreversible("save_as_required"))
    }

    func testReadOnlyAndOverwriteProhibitedAreRefusedBeforeAnythingIsWritten() async throws {
        let (document, url) = try fileDocument("locked\n")
        document.content = "changed\n"

        document.isReadOnly = true
        let result3 = await save(document)
        XCTAssertEqual(result3, .failedBeforeIrreversible("read_only"))
        document.isReadOnly = false

        document.isOverwriteProhibited = true
        let result4 = await save(document)
        XCTAssertEqual(result4, .failedBeforeIrreversible("overwrite_prohibited"))
        document.isOverwriteProhibited = false

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "locked\n")
    }

    func testTextTheEncodingCannotHoldIsRefused() async throws {
        let (document, url) = try fileDocument("ascii\n")
        document.encoding = .windows31J
        document.content = "emoji 😀\n"
        let result5 = await save(document)
        XCTAssertEqual(result5, .failedBeforeIrreversible("unrepresentable"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "ascii\n")
    }

    // MARK: - Human priority

    func testAHumanSaveArrivingMidFlightIsQueuedRatherThanDropped() async throws {
        let (document, url) = try fileDocument("start\n")
        document.content = "agent version\n"
        document.markModified()

        // The exact UI sequence: supersede, then call the synchronous path
        // immediately — which is where the first version returned .inProgress
        // and threw the human's ⌘S away.
        let agentBox = beginSave(document, requester: .agent)
        SaveCoordinator.shared.supersede(document)
        document.content = "human version\n"
        let immediate = SaveCoordinator.shared.saveSynchronously(document: document)
        XCTAssertEqual(immediate, .queuedBehindAnotherSave)

        let agentOutcome = await agentBox.value()
        XCTAssertEqual(agentOutcome, .superseded)

        // The queued save ran when the agent's unwound, and it wrote the
        // human's text.
        let deadline = Date().addingTimeInterval(2)
        while document.isModified && Date() < deadline {
            await Task.yield()
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "human version\n")
    }

    func testAnAgentSaveIsSupersededByTheHumanAndTheHumanNeverWaits() async throws {
        let (document, url) = try fileDocument("start\n")
        document.content = "agent version\n"
        document.markModified()

        let agentBox = beginSave(document, requester: .agent)
        // The human presses ⌘S while the agent's save is preparing.
        SaveCoordinator.shared.supersede(document)
        let agentOutcome = await agentBox.value()

        XCTAssertEqual(agentOutcome, .superseded)
        XCTAssertEqual(
            try String(contentsOf: url, encoding: .utf8), "start\n",
            "a superseded save writes nothing")

        // And the human's own save then works normally.
        let result6 = await save(document, requester: .human)
        XCTAssertEqual(result6, .succeeded)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "agent version\n")
    }

    func testASecondAgentSaveIsRefusedRatherThanQueued() async throws {
        let (document, _) = try fileDocument("start\n")
        document.content = "one\n"

        let firstBox = beginSave(document, requester: .agent)
        let secondBox = beginSave(document, requester: .agent)
        let outcomes = [await firstBox.value(), await secondBox.value()]

        // Exactly one wins; a queue would hide the ordering question rather
        // than answer it.
        XCTAssertEqual(outcomes.filter { $0 == .succeeded }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .inProgress }.count, 1)
    }

    // MARK: - Save As

    func testSaveAsWritesElsewhereAndAdoptsTheNewFile() async throws {
        let document = Document(content: "fresh\n")
        let target = directory.appendingPathComponent("new.txt")

        let result7 = await save(document, as: target)
        XCTAssertEqual(result7, .succeeded)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "fresh\n")
        XCTAssertEqual(document.fileURL, target)
        XCTAssertFalse(document.isModified)
    }

    func testSaveAsDoesNotApplyTheExternalChangeCheckToItsNewPath() async throws {
        let (document, _) = try fileDocument("mine\n")
        let target = directory.appendingPathComponent("elsewhere.txt")
        try "someone else's file\n".write(to: target, atomically: true, encoding: .utf8)
        document.content = "mine edited\n"

        // The known baseline describes the old path, not the one being picked,
        // so it must not be used to refuse this write.
        let result8 = await save(document, as: target)
        XCTAssertEqual(result8, .succeeded)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "mine edited\n")
    }

    // MARK: - Encoding fidelity

    func testAJapaneseDocumentKeepsItsEncodingAndLineEndingThroughASave() async throws {
        let url = directory.appendingPathComponent("sjis.txt")
        let original = "日本語\r\nテキスト\r\n"
        try XCTUnwrap(original.data(using: .shiftJIS)).write(to: url)
        let document = try Document.open(url: url)

        XCTAssertEqual(document.encoding, .windows31J)
        XCTAssertEqual(document.lineEnding, .crlf)
        // The buffer is LF internally whatever the file uses.
        XCTAssertFalse(TextCanonicalization.containsCarriageReturn(document.content))

        document.content = document.content.replacingOccurrences(of: "テキスト", with: "文章")
        let result9 = await save(document)
        XCTAssertEqual(result9, .succeeded)

        let written = try Data(contentsOf: url)
        let decoded = try XCTUnwrap(String(data: written, encoding: .shiftJIS))
        XCTAssertEqual(decoded, "日本語\r\n文章\r\n")
    }
}
