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
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
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
                  data: data, representing: URL(fileURLWithPath: path))
        else {
            return .failure(
                code: "file.unreadable",
                message: "That file could not be decoded as text.",
                details: nil)
        }

        guard control.isStillValid(control.stamp(connection)) else {
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
        guard definition.isSafeForAgentsRegardlessOfTarget else {
            // Registering a command must never be what makes it remotely
            // invocable, and `CommandContext` carries no explicit target, so a
            // command whose effect depends on which window is key cannot be
            // exposed at all yet.
            return .failure(
                code: "command.not_exposed",
                message: """
                    \(raw) is not exposed to agents. Commands act on whichever \
                    window is key, so only ones whose effect does not depend on \
                    that are available until targets are explicit.
                    """,
                details: nil)
        }
        control.record(
            connection: connection, tool: "run_command", document: nil, outcome: raw)
        let ran = registry.execute(CommandID(raw), context: CommandContext(coordinator: coordinator))
        return .success(.object([
            "commandId": .string(raw),
            "ran": .bool(ran),
        ]))
    }
}
