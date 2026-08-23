import Foundation

/// The single source of truth for what tools exist and what they accept.
///
/// The bridge needs it to answer `tools/list` before it has even reached the
/// app, the app needs it to validate arguments, and the conformance tests need
/// it to know what to exercise. Three hand-maintained copies of a schema
/// diverge; one value that all three read cannot.
public enum AgentToolCatalog {

    /// Bumped whenever a tool's name, arguments, or result shape changes, so a
    /// bridge from one build talking to an app from another can say so instead
    /// of failing in a confusing way.
    public static let version = 1

    public struct Tool: Sendable, Equatable {
        public let name: String
        public let title: String
        public let summary: String
        /// Phase the tool first ships in, so `tools/list` can present exactly
        /// what is actually wired up rather than advertising the roadmap.
        public let phase: Int
        public let isReadOnly: Bool
        public let isDestructive: Bool
        public let inputSchema: JSONValue
        public let outputSchema: JSONValue
    }

    private static func object(_ pairs: [(String, JSONValue)]) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: pairs))
    }

    private static func schema(
        properties: [(String, JSONValue)],
        required: [String] = [],
        additional: Bool = false
    ) -> JSONValue {
        object([
            ("type", .string("object")),
            ("properties", object(properties)),
            ("required", .array(required.map(JSONValue.string))),
            ("additionalProperties", .bool(additional)),
        ])
    }

    private static func property(_ type: String, _ description: String) -> JSONValue {
        object([("type", .string(type)), ("description", .string(description))])
    }

    private static func array(of type: String, _ description: String) -> JSONValue {
        object([
            ("type", .string("array")),
            ("description", .string(description)),
            ("items", object([("type", .string(type))])),
        ])
    }

    // MARK: - Tools

    public static let documentIDProperty = property("string", "Opaque document handle from list_documents.")
    public static let editorIDProperty = property("string", "Opaque editor-pane handle from list_editors.")

    public static let all: [Tool] = [
        Tool(
            name: "list_documents",
            title: "List open documents",
            summary: """
                Documents open in MaruEdit, with the revisions every write is \
                checked against and whether the buffer differs from disk. Read \
                a document through read_document rather than from its path: \
                while the buffer is dirty the file on disk is out of date, and \
                an untitled document has no path at all.
                """,
            phase: 1, isReadOnly: true, isDestructive: false,
            inputSchema: schema(properties: []),
            outputSchema: schema(properties: [
                ("documents", array(of: "object", "One entry per document inside your grant.")),
            ], required: ["documents"])),

        Tool(
            name: "list_editors",
            title: "List editor panes",
            summary: """
                Editor panes showing your granted documents. A split shows one \
                document in two panes with independent cursors, so selections \
                are addressed by editor, never by document.
                """,
            phase: 1, isReadOnly: true, isDestructive: false,
            inputSchema: schema(properties: []),
            outputSchema: schema(properties: [
                ("editors", array(of: "object", "One entry per visible pane.")),
            ], required: ["editors"])),

        Tool(
            name: "read_document",
            title: "Read document text",
            summary: """
                Authoritative buffer text, never the file on disk, always with \
                LF line endings whatever the document saves as. Returns the \
                revisions you must pass back when writing. Prefer a line range: \
                reading a whole large document is the most expensive thing you \
                can do here.
                """,
            phase: 1, isReadOnly: true, isDestructive: false,
            inputSchema: schema(properties: [
                ("documentId", documentIDProperty),
                ("startLine", property("integer", "One-based, inclusive. Omit to read from the start.")),
                ("endLine", property("integer", "One-based, exclusive. Omit to read to the end.")),
                ("maxBytes", property("integer", "Cap on returned UTF-8 bytes; truncation is reported, never silent.")),
            ], required: ["documentId"]),
            outputSchema: schema(properties: [
                ("documentId", property("string", "")),
                ("revision", property("integer", "")),
                ("metadataRevision", property("integer", "")),
                ("text", property("string", "")),
                ("truncated", property("boolean", "")),
            ], required: ["documentId", "revision", "metadataRevision", "text", "truncated"])),

        Tool(
            name: "get_outline",
            title: "Outline a document",
            summary: """
                Headings and symbols with one-based line numbers — a short map \
                of a long document, far cheaper than reading it to find out \
                what is in it.
                """,
            phase: 1, isReadOnly: true, isDestructive: false,
            inputSchema: schema(properties: [("documentId", documentIDProperty)], required: ["documentId"]),
            outputSchema: schema(properties: [
                ("symbols", array(of: "object", "Heading title, kind, level, and one-based line.")),
            ], required: ["symbols"])),

        Tool(
            name: "search_documents",
            title: "Search open documents",
            summary: """
                Search one document or every granted document, with \
                surrounding context. Use this instead of reading a whole file \
                to find something. Results carry the revisions of the snapshot \
                they were computed against.
                """,
            phase: 1, isReadOnly: true, isDestructive: false,
            inputSchema: schema(properties: [
                ("query", property("string", "Text to find, literal unless regex is true.")),
                ("regex", property("boolean", """
                    Treat query as an ICU regular expression. Defaults to \
                    false. Patterns that can backtrack exponentially — an \
                    unbounded quantifier around another one, or around a \
                    group containing | — are refused with an explanation, \
                    because they cannot be interrupted once started. Bound \
                    the repetition (a{1,64}) or use a character class.
                    """)),
                ("documentId", documentIDProperty),
                ("ignoreCase", property("boolean", "Defaults to false.")),
                ("maxResults", property("integer", "Defaults to 100.")),
            ], required: ["query"]),
            outputSchema: schema(properties: [
                ("matches", array(of: "object", "documentId, revision, line, column, offset, and context.")),
                ("truncated", property("boolean", "")),
            ], required: ["matches", "truncated"])),

        Tool(
            name: "get_selection",
            title: "Read a pane's selection",
            summary: """
                What the human has selected in one pane, as line and column and \
                as offsets, with the selection revision you must pass back to \
                move it.
                """,
            phase: 1, isReadOnly: true, isDestructive: false,
            inputSchema: schema(properties: [("editorId", editorIDProperty)], required: ["editorId"]),
            outputSchema: schema(properties: [
                ("editorId", property("string", "")),
                ("selectionRevision", property("integer", "")),
                ("selections", array(of: "object", "")),
            ], required: ["editorId", "selectionRevision", "selections"])),

        Tool(
            name: "apply_edits",
            title: "Edit a document",
            summary: """
                Apply edits atomically, or not at all. You must pass the \
                revisions you read: if the human typed since, the call is \
                refused and tells you the new state rather than overwriting \
                their work. Text must use LF. One call is one undo entry the \
                human can press ⌘Z on.
                """,
            phase: 2, isReadOnly: false, isDestructive: true,
            inputSchema: schema(properties: [
                ("documentId", documentIDProperty),
                ("baseRevision", property("integer", "The revision the edits were computed against.")),
                ("baseMetadataRevision", property("integer", "Encoding and line-ending revision, from the same read.")),
                ("label", property("string", "Short description; becomes the undo entry's name.")),
                ("edits", array(of: "object", "Each: start, end, replacement, and optionally expectDigest.")),
                ("idempotencyKey", property("string", "Optional; a repeat with the same key returns the first outcome.")),
            ], required: ["documentId", "baseRevision", "baseMetadataRevision", "edits"]),
            outputSchema: schema(properties: [
                ("status", property("string", "applied or pending")),
                ("revision", property("integer", "")),
                ("proposalId", property("string", "Present when the human must review the edit first.")),
            ], required: ["status"])),

        Tool(
            name: "review_status",
            title: "Check a pending edit",
            summary: """
                Whether an edit queued for human review was applied, rejected, \
                conflicted, or is still waiting. Poll this rather than assuming \
                a queued edit landed.
                """,
            phase: 2, isReadOnly: true, isDestructive: false,
            inputSchema: schema(properties: [
                ("proposalId", property("string", "From apply_edits.")),
            ], required: ["proposalId"]),
            outputSchema: schema(properties: [
                ("status", property("string", "pending, applied, rejected, conflicted, or expired")),
                ("revision", property("integer", "Present once applied.")),
            ], required: ["status"])),

        Tool(
            name: "set_selection",
            title: "Move the cursor",
            summary: """
                Put the human's cursor and selection where you have been \
                working. Requires both the document and selection revisions, so \
                it cannot yank a cursor they just moved or aim at coordinates \
                that have shifted.
                """,
            phase: 2, isReadOnly: false, isDestructive: false,
            inputSchema: schema(properties: [
                ("editorId", editorIDProperty),
                ("baseRevision", property("integer", "")),
                ("baseSelectionRevision", property("integer", "")),
                ("selections", array(of: "object", "Each: start and end offsets.")),
            ], required: ["editorId", "baseRevision", "baseSelectionRevision", "selections"]),
            outputSchema: schema(properties: [
                ("selectionRevision", property("integer", "")),
            ], required: ["selectionRevision"])),

        Tool(
            name: "reveal",
            title: "Scroll to a line",
            summary: "Scroll a pane so a line is visible, without moving the cursor.",
            phase: 2, isReadOnly: false, isDestructive: false,
            inputSchema: schema(properties: [
                ("editorId", editorIDProperty),
                ("baseRevision", property("integer", "")),
                ("line", property("integer", "One-based.")),
            ], required: ["editorId", "baseRevision", "line"]),
            outputSchema: schema(properties: [("revealedLine", property("integer", ""))], required: ["revealedLine"])),

        Tool(
            name: "open_document",
            title: "Open a file",
            summary: """
                Open a file into MaruEdit, from a folder the person at the \
                keyboard authorized. Without such a folder this is unavailable \
                rather than unrestricted, and symbolic links out of it are \
                refused.
                """,
            phase: 3, isReadOnly: false, isDestructive: false,
            inputSchema: schema(properties: [
                ("path", property("string", "Absolute path inside an authorized folder.")),
            ], required: ["path"]),
            outputSchema: schema(properties: [
                ("documentId", property("string", "")),
                ("revision", property("integer", "")),
            ], required: ["documentId", "revision"])),

        Tool(
            name: "run_command",
            title: "Run an editor command",
            summary: """
                Run one of MaruEdit's own commands. Default-deny: a command is \
                available only if it was explicitly exposed. Name a document \
                to say which window the command acts on; without one it acts \
                on the first window this client can see.
                """,
            phase: 3, isReadOnly: false, isDestructive: true,
            inputSchema: schema(properties: [
                ("commandId", property("string", "Stable command identifier, e.g. file.new.")),
                ("documentId", property("string", """
                    Optional. The window showing this document is the one the \
                    command acts on, so a person switching tabs mid-call \
                    cannot redirect it.
                    """)),
            ], required: ["commandId"]),
            outputSchema: schema(properties: [
                ("commandId", property("string", "")),
                ("ran", property("boolean", "")),
            ], required: ["commandId", "ran"])),

        Tool(
            name: "save_document",
            title: "Save a document",
            summary: """
                Save, after a non-interactive preflight. Never silently \
                resolves a conflict: if the file changed underneath, the \
                encoding cannot represent the text, or the document needs a \
                Save As, you are told which rather than the human being \
                interrupted by a dialog.
                """,
            phase: 2, isReadOnly: false, isDestructive: true,
            inputSchema: schema(properties: [
                ("documentId", documentIDProperty),
                ("expectRevision", property("integer", "")),
                ("expectMetadataRevision", property("integer", "")),
            ], required: ["documentId", "expectRevision", "expectMetadataRevision"]),
            outputSchema: schema(properties: [
                ("status", property("string", "saved, or the reason it was not")),
            ], required: ["status"])),
    ]

    public static func tools(throughPhase phase: Int) -> [Tool] {
        all.filter { $0.phase <= phase }.sorted { $0.name < $1.name }
    }

    public static func tool(named name: String) -> Tool? {
        all.first { $0.name == name }
    }
}
