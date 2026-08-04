import AppKit
import MaruEditCore

final class Document {
    var fileURL: URL?
    var content: String
    var isModified: Bool = false
    var language: Language
    /// The encoding this document was loaded with (or `.utf8` for a new,
    /// never-saved document). `save()`/`save(to:)` re-encode using this
    /// same value, not a hardcoded UTF-8 — see ROADMAP.md M2-02's note on
    /// why M2-01's TextFileLoader wasn't wired in without this.
    var encoding: TextEncoding = .utf8
    var hasByteOrderMark: Bool = false
    var cursorPosition: Int = 0
    var scrollOffset: NSPoint = .zero
    var cachedTextStorage: NSTextStorage?
    private var savedContent: String

    init(fileURL: URL? = nil, content: String = "", language: Language = .plainText) {
        self.fileURL = fileURL
        self.content = content
        self.language = language
        self.savedContent = content
    }

    var displayName: String { fileURL?.lastPathComponent ?? "Untitled" }
    var title: String { isModified ? "\(displayName) •" : displayName }

    func markModified() {
        isModified = content != savedContent
    }

    func markSaved() {
        savedContent = content
        isModified = false
    }

    static func open(url: URL) throws -> Document {
        let loaded = try TextFileLoader.load(contentsOf: url)
        let doc = Document(fileURL: url, content: loaded.content, language: Language.detect(for: url))
        doc.encoding = loaded.encoding
        doc.hasByteOrderMark = loaded.hasByteOrderMark
        return doc
    }

    /// Re-reads this document's file from disk using an explicitly chosen
    /// encoding, bypassing auto-detection (ROADMAP.md M2-02, "Reopen with
    /// Encoding…"). Callers are responsible for resolving unsaved changes
    /// first — this discards in-memory content unconditionally.
    func reopen(forcing encoding: TextEncoding) throws {
        guard let url = fileURL else { return }
        let loaded = try TextFileLoader.load(contentsOf: url, forcing: encoding)
        content = loaded.content
        self.encoding = loaded.encoding
        hasByteOrderMark = loaded.hasByteOrderMark
        cursorPosition = 0
        scrollOffset = .zero
        cachedTextStorage = nil
        markSaved()
    }

    func save() throws {
        guard let url = fileURL else { return }
        guard let foundationEncoding = encoding.foundationEncoding,
              let encoded = content.data(using: foundationEncoding)
        else {
            throw DocumentSaveError.unrepresentable(encoding: encoding)
        }
        let data = (hasByteOrderMark ? (encoding.byteOrderMark ?? Data()) : Data()) + encoded
        try data.write(to: url, options: .atomic)
        markSaved()
    }

    func save(to url: URL) throws {
        fileURL = url
        language = Language.detect(for: url)
        try save()
    }
}

enum DocumentSaveError: Error {
    case unrepresentable(encoding: TextEncoding)
}

extension DocumentSaveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unrepresentable(let encoding):
            return "This document contains characters that cannot be represented in \(encoding.displayName). Save As UTF-8 or another encoding instead."
        }
    }
}
