import AppKit
import MaruEditCore

/// Phase 3: the two tools that reach past the documents already open.
///
/// Both are gated on something the human authorized out of band — a directory
/// root for opening, an explicit per-command flag for running commands —
/// because "the agent asked" is not authorization.
extension AgentToolExecutor {

    // MARK: - open_document

    func openDocument(
        _ arguments: JSONValue,
        _ connection: AgentControlService.Connection,
        _ grant: AgentControlService.GrantStamp
    ) -> AgentToolOutcome {
        guard let path = arguments["path"]?.stringValue else {
            return .failure(code: "argument.missing", message: "path is required.", details: nil)
        }
        // The connection's own roots, not the process-wide list: a folder
        // authorized for one configuration must not silently authorize every
        // other connection.
        let roots = connection.authorizedRoots
        guard !roots.isEmpty else {
            return .failure(
                code: "authorization.no_root",
                message: """
                    No folder has been authorized for this client. Ask the person \
                    at the keyboard to grant one in MaruEdit's agent window; \
                    without one this tool is unavailable rather than permissive.
                    """,
                details: nil)
        }

        let file: AgentFileAccess.VerifiedFile
        do {
            file = try AgentFileAccess.open(path: path, underAnyOf: roots)
        } catch let error as AgentFileAccess.AccessError {
            return .failure(
                code: Self.code(for: error),
                message: Self.message(for: error, path: path),
                details: nil)
        } catch {
            return .failure(code: "file.unreadable", message: "\(error)", details: nil)
        }
        defer { file.close() }

        // The descriptor is the authority. Reopening the path here would hand
        // back the symlink race the walk just closed.
        guard let data = try? AgentFileAccess.read(file),
              let loaded = try? TextFileLoader.load(
                  data: data,
                  representing: URL(fileURLWithPath: path),
                  // From `fstat` on the descriptor the bytes came from. Letting
                  // the loader resolve the path again would hand back the race
                  // the walk just closed, one step later.
                  metadata: TextFileLoader.SourceMetadata(
                      identity: file.identity,
                      modificationDate: file.modificationDate,
                      posixPermissions: file.permissions))
        else {
            return .failure(
                code: "file.unreadable",
                message: "That file could not be decoded as text.",
                details: nil)
        }

        guard control.isStillValid(grant) else {
            return .failure(
                code: "authorization.denied",
                message: "This client's access was revoked while the file was being read.",
                details: nil)
        }
        guard let controller = coordinator.agentWindowControllers().first else {
            return .failure(code: "internal", message: "No window is available.", details: nil)
        }
        let document = controller.adoptAgentOpenedDocument(
            url: URL(fileURLWithPath: path), loaded: loaded)

        // This is the one sanctioned way a frozen grant grows, and it grows by
        // an object the human's own root authorization already covered.
        control.extendGrant(connection, with: document.automationID)

        return .success(.object([
            "documentId": .string(document.automationID.rawValue),
            "revision": .int(Int(document.textRevision)),
            "metadataRevision": .int(Int(document.metadataRevision)),
            "encoding": .string(document.encoding.displayName),
            "lineEnding": .string(document.lineEnding.displayName),
        ]))
    }

    private static func code(for error: AgentFileAccess.AccessError) -> String {
        switch error {
        case .noAuthorizedRoot: "authorization.no_root"
        case .escapesRoot: "path.outside_root"
        case .symlinkComponent: "path.symlink"
        case .notAFile: "path.not_a_file"
        case .tooLarge: "limit.file_bytes"
        case .unreadable: "file.unreadable"
        }
    }

    private static func message(for error: AgentFileAccess.AccessError, path: String) -> String {
        switch error {
        case .noAuthorizedRoot:
            "No authorized folder."
        case .escapesRoot:
            "\(path) is outside every folder authorized for this client."
        case .symlinkComponent(let component):
            "\(component) is a symbolic link; MaruEdit will not follow one out of an authorized folder."
        case .notAFile:
            "\(path) is not a regular file."
        case .tooLarge(let size):
            "\(path) is \(size) bytes, past the \(AgentFileAccess.maximumFileBytes)-byte limit for this tool."
        case .unreadable:
            "\(path) could not be opened."
        }
    }

    // MARK: - run_command

    func runCommand(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) -> AgentToolOutcome {
        guard let raw = arguments["commandId"]?.stringValue else {
            return .failure(code: "argument.missing", message: "commandId is required.", details: nil)
        }
        let registry = coordinator.commandRegistry
        guard let definition = registry.definition(for: CommandID(raw)) else {
            return .failure(
                code: "command.unknown",
                message: "No command with id \(raw).",
                details: nil)
        }
        guard definition.isAgentExposed else {
            // Registering a command must never be what makes it remotely
            // invocable.
            return .failure(
                code: "command.not_exposed",
                message: """
                    \(raw) is not exposed to agents. A command must act \
                    synchronously to be exposed, because one that defers its \
                    work would resolve a window again after the caller's target \
                    stops applying.
                    """,
                details: nil)
        }

        // The window this command acts on is named, not inherited from whatever
        // happens to be focused when it runs — otherwise a human switching tabs
        // mid-call could redirect it, and no authorization check could be made
        // about a target nobody stated.
        let target: MainWindowController?
        if let rawDocument = arguments["documentId"]?.stringValue {
            let id = AutomationID(rawValue: rawDocument)
            guard control.mayAccess(connection, document: id),
                  let controller = coordinator.agentWindowControllers().first(where: { controller in
                      controller.agentTargets().contains { $0.document.automationID == id }
                  })
            else {
                return .failure(
                    code: "document.unknown",
                    message: "No document with id \(rawDocument) is available to this client.",
                    details: nil)
            }
            target = controller
        } else {
            target = coordinator.agentWindowControllers().first
        }

        control.record(
            connection: connection, tool: "run_command", document: nil, outcome: raw)
        let ran = registry.execute(
            CommandID(raw),
            context: CommandContext(coordinator: coordinator, target: target))
        return .success(.object([
            "commandId": .string(raw),
            "ran": .bool(ran),
        ]))
    }
}
