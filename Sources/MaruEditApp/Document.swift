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
    /// The line-ending style this document was loaded with. `content`
    /// itself always uses `\n` only internally (ROADMAP.md section 10.3)
    /// regardless of this value — `save()` re-applies it on write. A new,
    /// never-saved document defaults to `.lf`, matching this app's
    /// existing native behavior.
    var lineEnding: LineEndingState = .lf
    /// File metadata captured on open/reopen and refreshed after every
    /// successful save (ROADMAP.md M2-05), so later work (M2-06 external-
    /// modification detection) doesn't need to re-`stat` separately.
    /// `nil` for a document that has never corresponded to a file on disk
    /// (a brand-new, never-saved document, or before the first save-to).
    var fileIdentity: FileIdentity?
    var lastKnownModificationDate: Date?
    var posixPermissions: Int?
    var cursorPosition: Int = 0
    var scrollOffset: NSPoint = .zero
    var cachedTextStorage: NSTextStorage?
    /// Stable for this document's lifetime, used to key its crash-
    /// recovery record while it's unnamed (ROADMAP.md M2-07). Kept even
    /// after the document gains a file — `MainWindowController` deletes
    /// the recovery record at that point rather than the ID changing
    /// meaning.
    let recoveryID: RecoveryID
    private var savedContent: String

    init(fileURL: URL? = nil, content: String = "", language: Language = .plainText, recoveryID: RecoveryID = RecoveryID()) {
        self.fileURL = fileURL
        self.content = content
        self.language = language
        self.savedContent = content
        self.recoveryID = recoveryID
    }

    /// Reconstructs an unnamed document from a crash-recovery record
    /// (ROADMAP.md M2-07), reusing its `recoveryID` so further edits keep
    /// updating the same record rather than creating a duplicate. Always
    /// marked modified: this content exists only in memory until the
    /// user saves it somewhere, so it must never look "clean."
    static func recovered(from record: RecoveryRecord) -> Document {
        let doc = Document(content: record.content, language: .plainText, recoveryID: record.recoveryID)
        doc.encoding = record.encoding
        doc.cursorPosition = record.selectionLocation
        doc.savedContent = "" // guaranteed to differ: scheduleRecoverySaveIfUnnamed never persists empty content
        doc.isModified = true
        return doc
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
        let doc = Document(
            fileURL: url,
            content: LineEndingDetector.normalize(loaded.content),
            language: Language.detect(for: url)
        )
        doc.encoding = loaded.encoding
        doc.hasByteOrderMark = loaded.hasByteOrderMark
        doc.lineEnding = LineEndingDetector.detect(loaded.content)
        doc.fileIdentity = loaded.fileIdentity
        doc.lastKnownModificationDate = loaded.modificationDate
        doc.posixPermissions = loaded.posixPermissions
        return doc
    }

    /// Re-reads this document's file from disk using an explicitly chosen
    /// encoding, bypassing auto-detection (ROADMAP.md M2-02, "Reopen with
    /// Encoding…"). Callers are responsible for resolving unsaved changes
    /// first — this discards in-memory content unconditionally.
    func reopen(forcing encoding: TextEncoding) throws {
        guard let url = fileURL else { return }
        let loaded = try TextFileLoader.load(contentsOf: url, forcing: encoding)
        content = LineEndingDetector.normalize(loaded.content)
        self.encoding = loaded.encoding
        hasByteOrderMark = loaded.hasByteOrderMark
        lineEnding = LineEndingDetector.detect(loaded.content)
        fileIdentity = loaded.fileIdentity
        lastKnownModificationDate = loaded.modificationDate
        posixPermissions = loaded.posixPermissions
        cursorPosition = 0
        scrollOffset = .zero
        cachedTextStorage = nil
        markSaved()
    }

    /// Checks whether `content` can be losslessly saved in `encoding`
    /// without writing anything (ROADMAP.md M2-04). `save()` calls this
    /// itself, but `MainWindowController` also calls it directly to show
    /// a detailed alert instead of only learning about the problem from
    /// a caught error after `save()` already tried and failed.
    func preflightSave() -> SavePreflightResult {
        SavePreflight.check(content, encoding: encoding)
    }

    func save() throws {
        guard let url = fileURL else { return }
        guard let foundationEncoding = encoding.foundationEncoding else {
            throw DocumentSaveError.unrepresentable(encoding: encoding, characters: [])
        }

        let preflight = preflightSave()
        guard preflight.isRepresentable else {
            throw DocumentSaveError.unrepresentable(encoding: encoding, characters: preflight.unrepresentableCharacters)
        }

        // `.mixed`/`.none` fall back to LF: callers that care about an
        // informed choice for a mixed-ending file (MainWindowController's
        // save flow) are expected to resolve `lineEnding` to a concrete
        // kind before calling save() — see ROADMAP.md M2-03. This is a
        // safe default, not a silent-corruption risk, since it only
        // changes which separator bytes are written, never document text.
        let targetKind: LineEndingKind
        switch lineEnding {
        case .lf: targetKind = .lf
        case .crlf: targetKind = .crlf
        case .cr: targetKind = .cr
        case .mixed, .none: targetKind = .lf
        }
        let outputText = LineEndingDetector.applying(targetKind, to: content)

        guard let encoded = outputText.data(using: foundationEncoding) else {
            throw DocumentSaveError.unrepresentable(encoding: encoding, characters: preflight.unrepresentableCharacters)
        }
        let data = (hasByteOrderMark ? (encoding.byteOrderMark ?? Data()) : Data()) + encoded

        let info: SavedFileInfo
        do {
            info = try TextFileSaver.save(data, to: url, preservingPermissionsFrom: posixPermissions)
        } catch let error as TextFileSaverError {
            throw DocumentSaveError.writeFailed(underlying: error)
        }
        fileIdentity = info.fileIdentity
        lastKnownModificationDate = info.modificationDate
        posixPermissions = info.posixPermissions
        markSaved()
    }

    func save(to url: URL) throws {
        fileURL = url
        language = Language.detect(for: url)
        // Save As to a path that already has a file at it should preserve
        // *that* file's permissions, not the permissions of whatever file
        // this Document was previously associated with.
        if let existingAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let existingPermissions = (existingAttributes[.posixPermissions] as? NSNumber)?.intValue {
            posixPermissions = existingPermissions
        } else {
            posixPermissions = nil
        }
        try save()
    }
}

enum DocumentSaveError: Error {
    case unrepresentable(encoding: TextEncoding, characters: [UnrepresentableCharacter])
    case writeFailed(underlying: TextFileSaverError)
}

extension DocumentSaveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unrepresentable(let encoding, let characters):
            if characters.isEmpty {
                return "This document contains characters that cannot be represented in \(encoding.displayName). Save as UTF-8 or another encoding instead."
            }
            let count = characters.count
            let noun = count == 1 ? "character" : "characters"
            return "\(count) \(noun) cannot be represented in \(encoding.displayName). Save as UTF-8 or another encoding instead."
        case .writeFailed(let underlying):
            return underlying.errorDescription
        }
    }
}
