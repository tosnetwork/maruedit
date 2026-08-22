import AppKit
import MaruEditCore

/// Executes agent tools against the editor.
///
/// Everything here is main-actor because resolving a handle means reading live
/// controller state. What is deliberately *not* here is the expensive part:
/// search, outlining, and serialization run against an immutable snapshot the
/// main actor hands out, so a large document cannot stall typing (R9).
@MainActor
struct AgentToolExecutor {
    let coordinator: AppCoordinator
    let control: AgentControlService

    // MARK: - Limits
    //
    // Bounds are explicit and reported, never silently applied: a truncated
    // answer that does not say it was truncated is a wrong answer.

    static let defaultMaxBytes = 256 * 1024
    static let hardMaxBytes = 4 * 1024 * 1024
    static let maxSearchResults = 500
    static let defaultSearchResults = 100
    static let maxQueryLength = 1_000
    static let contextCharacters = 80

    func run(tool: String, arguments: JSONValue, connection: AgentControlService.Connection) async -> AgentToolOutcome {
        if let refusal = control.authorize(connection, tool: tool) {
            control.record(connection: connection, tool: tool, document: nil, outcome: "refused")
            return refusal
        }
        let outcome: AgentToolOutcome
        switch tool {
        case "control.pair": outcome = pair()
        case "list_documents": outcome = listDocuments(connection)
        case "list_editors": outcome = listEditors(connection)
        case "read_document": outcome = await readDocument(arguments, connection)
        case "get_outline": outcome = await outline(arguments, connection)
        case "search_documents": outcome = await search(arguments, connection)
        case "get_selection": outcome = selection(arguments, connection)
        default:
            outcome = .failure(
                code: "tool.unknown",
                message: "MaruEdit does not implement \(tool) yet.",
                details: nil)
        }
        control.record(
            connection: connection, tool: tool,
            document: arguments["documentId"]?.stringValue,
            outcome: outcome.isFailure ? "error" : "ok")
        return outcome
    }

    // MARK: - Pairing

    private func pair() -> AgentToolOutcome {
        switch control.beginPairing() {
        case .success(let request):
            return .success(.object([
                "verificationCode": .string(request.verificationCode),
                "credentialPath": .string(request.credentialPath),
            ]))
        case .failure(let failure):
            return failure.outcome
        }
    }

    // MARK: - Document resolution

    private struct Target {
        let document: Document
        let editor: EditorViewController
    }

    /// Every open document, paired with a pane that shows it.
    private var visibleTargets: [Target] {
        coordinator.agentVisibleTargets().map { Target(document: $0.document, editor: $0.editor) }
    }

    private func resolve(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) -> Result<Target, AgentToolFailure> {
        guard let raw = arguments["documentId"]?.stringValue else {
            return .failure(AgentToolFailure(
                code: "argument.missing",
                message: "documentId is required. Call list_documents first."))
        }
        let id = AutomationID(rawValue: raw)
        // A document outside the grant is reported as unknown rather than
        // forbidden: "you may not see that" still confirms it exists.
        guard control.mayAccess(connection, document: id),
              let target = visibleTargets.first(where: { $0.document.automationID == id })
        else {
            return .failure(AgentToolFailure(
                code: "document.unknown",
                message: "No document with id \(raw) is available to this client."))
        }
        return .success(target)
    }

    // MARK: - Tools

    private func listDocuments(_ connection: AgentControlService.Connection) -> AgentToolOutcome {
        let entries = visibleTargets
            .filter { control.mayAccess(connection, document: $0.document.automationID) }
            .map { target -> JSONValue in
                let document = target.document
                let service = EditorAutomationService(editor: target.editor)
                let snapshot = service.documentSnapshot()
                return .object([
                    "documentId": .string(document.automationID.rawValue),
                    "displayName": .string(document.localizedDisplayName),
                    "path": document.fileURL.map { .string($0.path) } ?? .null,
                    "revision": .int(Int(document.textRevision)),
                    "metadataRevision": .int(Int(document.metadataRevision)),
                    "bufferState": .string(document.isModified ? "dirty" : "clean"),
                    "backingFileState": .string(Self.backingFileState(document)),
                    "observedAt": .string(ISO8601DateFormatter().string(from: Date())),
                    "lines": .int(Self.lineCount(document.content)),
                    "utf16Length": .int((document.content as NSString).length),
                    "encoding": .string(document.encoding.displayName),
                    "lineEnding": .string(document.lineEnding.displayName),
                    "bom": .bool(document.hasByteOrderMark),
                    "contentKind": .string(snapshot?.contentKind.rawValue ?? "text"),
                    "editable": .bool(!document.isEditingDisabled),
                    "savableInPlace": .bool(!document.isEditingDisabled && !document.isOverwriteProhibited),
                    "saveAsRequired": .bool(document.fileURL == nil),
                ])
            }
        return .success(.object(["documents": .array(entries)]))
    }

    private func listEditors(_ connection: AgentControlService.Connection) -> AgentToolOutcome {
        let entries = visibleTargets
            .filter { control.mayAccess(connection, document: $0.document.automationID) }
            .map { target -> JSONValue in
                .object([
                    "editorId": .string(target.editor.automationID.rawValue),
                    "documentId": .string(target.document.automationID.rawValue),
                    "selectionRevision": .int(Int(target.editor.selectionRevision)),
                    "isPrimaryPane": .bool(target.editor.reusesDocumentTextStorage),
                ])
            }
        return .success(.object(["editors": .array(entries)]))
    }

    private func readDocument(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) async -> AgentToolOutcome {
        let resolved = resolve(arguments, connection)
        guard case .success(let target) = resolved else {
            if case .failure(let failure) = resolved { return failure.outcome }
            return .failure(code: "internal", message: "unreachable", details: nil)
        }
        // Snapshot on the main actor, then leave it: everything below is pure
        // string work against an immutable value.
        let document = target.document
        let text = document.content
        let revision = document.textRevision
        let metadataRevision = document.metadataRevision
        let startLine = arguments["startLine"]?.intValue
        let endLine = arguments["endLine"]?.intValue
        let maxBytes = min(arguments["maxBytes"]?.intValue ?? Self.defaultMaxBytes, Self.hardMaxBytes)

        let slice = await Task.detached(priority: .userInitiated) {
            AgentTextSlicer.slice(
                text: text, startLine: startLine, endLine: endLine, maxBytes: maxBytes)
        }.value

        return .success(.object([
            "documentId": .string(document.automationID.rawValue),
            "revision": .int(Int(revision)),
            "metadataRevision": .int(Int(metadataRevision)),
            "startLine": .int(slice.startLine),
            "endLine": .int(slice.endLine),
            "totalLines": .int(slice.totalLines),
            "startOffset": .int(slice.startOffset),
            "endOffset": .int(slice.endOffset),
            "text": .string(slice.text),
            "truncated": .bool(slice.truncated),
        ]))
    }

    private func outline(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) async -> AgentToolOutcome {
        let resolved = resolve(arguments, connection)
        guard case .success(let target) = resolved else {
            if case .failure(let failure) = resolved { return failure.outcome }
            return .failure(code: "internal", message: "unreachable", details: nil)
        }
        let text = target.document.content
        let language = target.document.language

        let symbols = await Task.detached(priority: .userInitiated) {
            OutlineModel(text: text, language: language).symbols.map { symbol -> JSONValue in
                .object([
                    "title": .string(symbol.title),
                    "kind": .string(symbol.kind.rawValue),
                    "level": .int(symbol.level),
                    // OutlineSymbol.line is zero-based internally; the protocol
                    // is one-based, so the mapping is explicit here rather than
                    // left to a caller to guess.
                    "line": .int(symbol.line + 1),
                ])
            }
        }.value

        return .success(.object(["symbols": .array(symbols)]))
    }

    private func search(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) async -> AgentToolOutcome {
        guard let query = arguments["query"]?.stringValue, !query.isEmpty else {
            return .failure(code: "argument.missing", message: "query is required.", details: nil)
        }
        guard query.count <= Self.maxQueryLength else {
            return .failure(
                code: "limit.query_length",
                message: "Query longer than \(Self.maxQueryLength) characters.",
                details: nil)
        }
        let ignoreCase = arguments["ignoreCase"]?.boolValue ?? false
        let limit = min(arguments["maxResults"]?.intValue ?? Self.defaultSearchResults, Self.maxSearchResults)

        var scope: [(id: String, revision: UInt64, metadataRevision: UInt64, text: String)] = []
        if arguments["documentId"] != nil {
            let resolved = resolve(arguments, connection)
            guard case .success(let target) = resolved else {
                if case .failure(let failure) = resolved { return failure.outcome }
                return .failure(code: "internal", message: "unreachable", details: nil)
            }
            scope = [(target.document.automationID.rawValue, target.document.textRevision,
                      target.document.metadataRevision, target.document.content)]
        } else {
            scope = visibleTargets
                .filter { control.mayAccess(connection, document: $0.document.automationID) }
                .map { ($0.document.automationID.rawValue, $0.document.textRevision,
                        $0.document.metadataRevision, $0.document.content) }
        }

        let snapshot = scope
        let results = await Task.detached(priority: .userInitiated) {
            AgentTextSlicer.searchLiteral(
                in: snapshot, query: query, ignoreCase: ignoreCase, limit: limit)
        }.value

        return .success(.object([
            "matches": .array(results.matches),
            "truncated": .bool(results.truncated),
        ]))
    }

    private func selection(
        _ arguments: JSONValue, _ connection: AgentControlService.Connection
    ) -> AgentToolOutcome {
        guard let raw = arguments["editorId"]?.stringValue else {
            return .failure(code: "argument.missing", message: "editorId is required.", details: nil)
        }
        let id = AutomationID(rawValue: raw)
        guard let target = visibleTargets.first(where: { $0.editor.automationID == id }),
              control.mayAccess(connection, document: target.document.automationID)
        else {
            return .failure(
                code: "editor.unknown",
                message: "No editor pane with id \(raw) is available to this client.",
                details: nil)
        }
        let text = target.document.content as NSString
        let selections = target.editor.selectionSet.ranges.map { range -> JSONValue in
            let position = AgentTextSlicer.position(ofOffset: range.location, in: text)
            return .object([
                "start": .int(range.location),
                "end": .int(NSMaxRange(range)),
                "line": .int(position.line),
                "column": .int(position.column),
                "text": .string(AgentTextSlicer.bounded(text.substring(with: range))),
            ])
        }
        return .success(.object([
            "editorId": .string(raw),
            "documentId": .string(target.document.automationID.rawValue),
            "revision": .int(Int(target.document.textRevision)),
            "selectionRevision": .int(Int(target.editor.selectionRevision)),
            "selections": .array(selections),
        ]))
    }

    // MARK: - Helpers

    private static func lineCount(_ text: String) -> Int {
        text.isEmpty ? 1 : text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    /// Deliberately conservative. The existing detector runs on focus and
    /// before save and presents its answer to the human immediately rather than
    /// storing it, so the model has no continuously accurate value to report;
    /// `unknown` is the honest answer rather than a stale one.
    private static func backingFileState(_ document: Document) -> String {
        guard let url = document.fileURL else { return "unknown" }
        guard FileManager.default.fileExists(atPath: url.path) else { return "missing" }
        return "unknown"
    }
}
