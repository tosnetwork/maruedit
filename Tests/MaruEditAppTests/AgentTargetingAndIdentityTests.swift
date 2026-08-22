import AppKit
import XCTest
@preconcurrency @testable import MaruEditApp
@testable import MaruEditCore

/// Two things an agent must not have to guess about: which window its command
/// acted on, and whether the file it is about to overwrite is the one it read.
@MainActor
final class AgentTargetingAndIdentityTests: XCTestCase {

    private var home: URL!

    override func setUp() async throws {
        try await super.setUp()
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("maruedit-targeting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        NSApp.windows.filter { $0.windowController is MainWindowController }.forEach { $0.close() }
        try? FileManager.default.removeItem(at: home)
        try await super.tearDown()
    }

    // MARK: - Command targeting

    func testACommandActsOnTheWindowItWasGivenNotTheKeyOne() throws {
        let coordinator = AppCoordinator()
        let first = coordinator.ensureWindowControllerReady(restoreSession: false)
        let second = MainWindowController()
        _ = second.window

        let firstBefore = first.agentTargets().count
        let secondBefore = second.agentTargets().count

        // No target: whatever the coordinator resolves on its own.
        XCTAssertTrue(coordinator.commandRegistry.execute(
            .fileNew, context: CommandContext(coordinator: coordinator)))
        XCTAssertEqual(first.agentTargets().count, firstBefore + 1)
        XCTAssertEqual(second.agentTargets().count, secondBefore)

        // Named target: the command lands there instead, and the untargeted
        // window is untouched.
        XCTAssertTrue(coordinator.commandRegistry.execute(
            .fileNew, context: CommandContext(coordinator: coordinator, target: second)))
        XCTAssertEqual(second.agentTargets().count, secondBefore + 1)
        XCTAssertEqual(first.agentTargets().count, firstBefore + 1)
    }

    func testTargetingIsRestoredAfterTheCommandSoItCannotLeak() throws {
        let coordinator = AppCoordinator()
        let first = coordinator.ensureWindowControllerReady(restoreSession: false)
        let second = MainWindowController()
        _ = second.window

        coordinator.withTargetedWindow(second) {
            XCTAssertTrue(coordinator.ensureWindowControllerReady() === second)
        }
        // A pin that outlived its command would silently redirect every later
        // command, including the human's own menu items.
        XCTAssertTrue(coordinator.ensureWindowControllerReady() === first)
    }

    func testOnlyExplicitlyExposedCommandsAreReachable() throws {
        let coordinator = AppCoordinator()
        _ = coordinator.ensureWindowControllerReady(restoreSession: false)

        let exposed = coordinator.commandRegistry.allDefinitions.filter(\.isAgentExposed)
        XCTAssertFalse(exposed.isEmpty, "the tool would be pointless with nothing exposed")

        // Registering a command must never be what makes it remotely
        // invocable, so the exposed set stays a small, deliberate list.
        XCTAssertLessThan(
            exposed.count, coordinator.commandRegistry.allDefinitions.count / 2,
            "exposure has stopped being the exception")
    }

    // MARK: - File identity

    func testAnAgentOpenedDocumentCarriesTheIdentityOfTheFileItRead() throws {
        let path = home.appendingPathComponent("note.txt")
        try Data("hello\n".utf8).write(to: path)

        let file = try AgentFileAccess.open(path: path.path, underAnyOf: [home.path])
        defer { file.close() }
        let data = try AgentFileAccess.read(file)
        let loaded = try TextFileLoader.load(
            data: data, representing: path,
            metadata: TextFileLoader.SourceMetadata(
                identity: file.identity,
                modificationDate: file.modificationDate,
                posixPermissions: file.permissions))

        let controller = MainWindowController()
        _ = controller.window
        let document = controller.adoptAgentOpenedDocument(url: path, loaded: loaded)

        XCTAssertEqual(document.content, "hello\n")
        XCTAssertEqual(document.fileIdentity, file.identity)
        XCTAssertEqual(document.fileIdentity, FileIdentity.of(path))
        XCTAssertNotNil(document.lastKnownModificationDate)
        XCTAssertEqual(document.posixPermissions, file.permissions)
    }

    func testTheDescriptorsIdentityWinsOverAPathThatMovedUnderneathIt() throws {
        let real = home.appendingPathComponent("real.txt")
        let decoy = home.appendingPathComponent("decoy.txt")
        try Data("real\n".utf8).write(to: real)
        try Data("decoy\n".utf8).write(to: decoy)

        let file = try AgentFileAccess.open(path: real.path, underAnyOf: [home.path])
        defer { file.close() }
        let realIdentity = file.identity

        // The path now names a different file — the classic swap between
        // "which file did I read" and "which file will I write".
        try FileManager.default.removeItem(at: real)
        try FileManager.default.moveItem(at: decoy, to: real)
        XCTAssertNotEqual(FileIdentity.of(real), realIdentity)

        // Metadata handed over explicitly still describes what was read, while
        // letting the loader resolve the path again would describe the decoy.
        let loaded = try TextFileLoader.load(
            data: try AgentFileAccess.read(file), representing: real,
            metadata: TextFileLoader.SourceMetadata(
                identity: file.identity,
                modificationDate: file.modificationDate,
                posixPermissions: file.permissions))
        XCTAssertEqual(loaded.content, "real\n")
        XCTAssertEqual(loaded.fileIdentity, realIdentity)

        let reresolved = try TextFileLoader.load(
            data: try AgentFileAccess.read(file), representing: real)
        XCTAssertEqual(
            reresolved.content, "real\n",
            "the bytes are always the descriptor's")
        XCTAssertNotEqual(
            reresolved.fileIdentity, realIdentity,
            "and this is exactly the mismatch the metadata parameter exists to prevent")
    }

    func testNoBaselineIsReportedAsUnknownRatherThanUnchanged() throws {
        let path = home.appendingPathComponent("nobase.txt")
        try Data("x".utf8).write(to: path)

        // Saying "unchanged" here is an unearned claim about a file nobody
        // read, and a save that believes it overwrites unseen content.
        XCTAssertEqual(
            ExternalChangeDetector.check(
                url: path, knownIdentity: nil, knownModificationDate: nil),
            .unknownBaseline)

        XCTAssertEqual(
            ExternalChangeDetector.check(
                url: path,
                knownIdentity: FileIdentity.of(path),
                knownModificationDate: try FileManager.default
                    .attributesOfItem(atPath: path.path)[.modificationDate] as? Date),
            .unchanged)
    }

    func testAnInPlaceSaveIsRefusedWhenTheFileIsNoLongerTheOneThatWasRead() throws {
        let path = home.appendingPathComponent("target.txt")
        try Data("original\n".utf8).write(to: path)

        let file = try AgentFileAccess.open(path: path.path, underAnyOf: [home.path])
        defer { file.close() }
        let loaded = try TextFileLoader.load(
            data: try AgentFileAccess.read(file), representing: path,
            metadata: TextFileLoader.SourceMetadata(
                identity: file.identity,
                modificationDate: file.modificationDate,
                posixPermissions: file.permissions))

        let controller = MainWindowController()
        _ = controller.window
        let document = controller.adoptAgentOpenedDocument(url: path, loaded: loaded)
        document.content = "edited by an agent\n"

        // Someone replaces the file — a rebuild, a git checkout, another
        // editor writing atomically.
        try FileManager.default.removeItem(at: path)
        try Data("written by someone else\n".utf8).write(to: path)

        let coordinator = SaveCoordinator()
        let outcome = coordinator.saveSynchronously(document: document, requester: .agent)

        guard case .conflicted(let reason) = outcome else {
            return XCTFail("an in-place save over a replaced file must not proceed: \(outcome)")
        }
        XCTAssertEqual(reason, "external_change")
        XCTAssertEqual(
            try String(contentsOf: path, encoding: .utf8), "written by someone else\n",
            "the other writer's content must still be there")
    }
}
