import Foundation

/// Opaque, process-lifetime identifiers for the objects automation addresses.
///
/// They are deliberately not derived from paths, titles, or pointers: a handle
/// that encodes structure invites guessing, and a handle that outlives the
/// process invites a client assuming state MaruEdit no longer has.
public struct AutomationID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }

    private static let counter = Counter()

    public static func next(prefix: String) -> AutomationID {
        AutomationID(rawValue: "\(prefix)_\(String(counter.next(), radix: 16))")
    }

    /// Monotonic source shared by every identifier kind, so two handles are
    /// never confusable even if their prefixes are dropped somewhere.
    private final class Counter: @unchecked Sendable {
        private var value: UInt64 = 0
        private let lock = NSLock()
        func next() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            value &+= 1
            return value
        }
    }
}

/// The three revision counters a document and its panes carry.
///
/// They answer different questions and are deliberately not collapsed: text
/// moves on every keystroke, selection moves without text, and the metadata
/// that decides whether an edit is admissible moves without either.
public struct DocumentRevisions: Equatable, Sendable {
    public var text: UInt64
    public var metadata: UInt64

    public init(text: UInt64 = 0, metadata: UInt64 = 0) {
        self.text = text
        self.metadata = metadata
    }
}

/// One replacement in a transaction. `range` is in UTF-16 code units against
/// the document as it stands when the transaction is validated.
public struct AutomationEdit: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        // Canonical at construction, so no caller can smuggle a CR past the
        // ingress rules by building an edit directly.
        self.replacement = TextCanonicalization.canonical(replacement)
    }
}

/// Why a transaction was refused. Every case is refused *before* any mutation,
/// so a failed transaction leaves the document byte-identical.
public enum AutomationTransactionError: Error, Equatable, Sendable {
    /// No edits were supplied.
    case empty
    /// A range was `NSNotFound`, negative, or extended past the document.
    case rangeOutOfBounds(NSRange)
    /// Two edits touch the same text. Merging them would silently pick a
    /// winner; refusing tells the caller what it actually asked for.
    case overlappingEdits(NSRange, NSRange)
    /// The document cannot be edited at all — read-only, view mode, or a
    /// missing text storage.
    case notEditable

    public var identifier: String {
        switch self {
        case .empty: "transaction.empty"
        case .rangeOutOfBounds: "transaction.range_out_of_bounds"
        case .overlappingEdits: "transaction.overlapping_edits"
        case .notEditable: "document.not_editable"
        }
    }
}

/// What a successful transaction did, as values only.
public struct AutomationTransactionOutcome: Equatable, Sendable {
    /// Applied edits, in ascending document order after normalization.
    public let appliedEdits: [AutomationEdit]
    /// Caret positions after each applied replacement, ascending and unique.
    public let resultingCursors: [NSRange]
    /// The document's revisions after the transaction committed.
    public let revisions: DocumentRevisions

    public init(
        appliedEdits: [AutomationEdit],
        resultingCursors: [NSRange],
        revisions: DocumentRevisions
    ) {
        self.appliedEdits = appliedEdits
        self.resultingCursors = resultingCursors
        self.revisions = revisions
    }
}

/// Immutable description of a document, safe to hand to an off-main worker.
///
/// Nothing here references `Document`, a view controller, or an AppKit object:
/// `Document` is a mutable `@unchecked Sendable` class holding an
/// `NSTextStorage`, so only a rule and a value type keep it on the main actor.
public struct DocumentSnapshot: Equatable, Sendable {
    public let documentID: AutomationID
    public let displayName: String
    public let path: String?
    public let text: String
    public let revisions: DocumentRevisions
    public let isDirty: Bool
    public let isEditable: Bool
    public let isSavableInPlace: Bool
    public let contentKind: ContentKind
    public let encodingName: String
    public let lineEndingName: String
    public let hasByteOrderMark: Bool

    public enum ContentKind: String, Sendable {
        /// The buffer is the document's text.
        case text
        /// The buffer is a hex rendering of a binary file, not its text.
        case hex
    }

    public init(
        documentID: AutomationID,
        displayName: String,
        path: String?,
        text: String,
        revisions: DocumentRevisions,
        isDirty: Bool,
        isEditable: Bool,
        isSavableInPlace: Bool,
        contentKind: ContentKind,
        encodingName: String,
        lineEndingName: String,
        hasByteOrderMark: Bool
    ) {
        self.documentID = documentID
        self.displayName = displayName
        self.path = path
        self.text = text
        self.revisions = revisions
        self.isDirty = isDirty
        self.isEditable = isEditable
        self.isSavableInPlace = isSavableInPlace
        self.contentKind = contentKind
        self.encodingName = encodingName
        self.lineEndingName = lineEndingName
        self.hasByteOrderMark = hasByteOrderMark
    }
}

/// Immutable description of one editor pane.
public struct EditorSnapshot: Equatable, Sendable {
    public let editorID: AutomationID
    public let documentID: AutomationID?
    public let selections: [NSRange]
    public let primarySelection: NSRange
    public let selectionRevision: UInt64
    public let isPrimaryPane: Bool

    public init(
        editorID: AutomationID,
        documentID: AutomationID?,
        selections: [NSRange],
        primarySelection: NSRange,
        selectionRevision: UInt64,
        isPrimaryPane: Bool
    ) {
        self.editorID = editorID
        self.documentID = documentID
        self.selections = selections
        self.primarySelection = primarySelection
        self.selectionRevision = selectionRevision
        self.isPrimaryPane = isPrimaryPane
    }
}
