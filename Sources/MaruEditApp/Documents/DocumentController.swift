import Foundation

/// Owns the set of open documents and which one is current, for one
/// window. Extracted from `MainWindowController` (ROADMAP.md M1-02) so
/// document lifecycle — create, open, save, close — is understandable and
/// testable independently of tab-bar/sidebar/window UI concerns.
///
/// This intentionally does not touch AppKit UI (tab bar, window title,
/// sidebar, cursor restoration). Callers are responsible for refreshing
/// UI after calling into it, exactly as `MainWindowController` did before
/// this extraction — the goal here is ownership of state and file I/O
/// coordination, not a new UI-update delegate protocol.
final class DocumentController {
    private(set) var documents: [Document] = []
    private(set) var currentIndex: Int = -1

    var currentDocument: Document? {
        document(at: currentIndex)
    }

    func document(at index: Int) -> Document? {
        guard index >= 0, index < documents.count else { return nil }
        return documents[index]
    }

    func indexOfDocument(withURL url: URL) -> Int? {
        documents.firstIndex(where: { $0.fileURL == url })
    }

    @discardableResult
    func newDocument() -> Document {
        let doc = Document()
        documents.append(doc)
        currentIndex = documents.count - 1
        return doc
    }

    /// Activates the tab for `url` if it's already open, otherwise opens
    /// it as a new tab. Mirrors the prior `MainWindowController.openFile`.
    @discardableResult
    func open(url: URL) throws -> (document: Document, wasAlreadyOpen: Bool) {
        if let i = indexOfDocument(withURL: url) {
            currentIndex = i
            return (documents[i], true)
        }
        let doc = try Document.open(url: url)
        documents.append(doc)
        currentIndex = documents.count - 1
        return (doc, false)
    }

    /// Opens `url`, replacing the current tab if it's an unmodified blank
    /// tab (or already showing the same file); otherwise appends a new
    /// tab. Mirrors the prior `MainWindowController.openFileInCurrentTab`.
    @discardableResult
    func openInCurrentTab(url: URL) throws -> (document: Document, wasAlreadyOpen: Bool) {
        if let i = indexOfDocument(withURL: url) {
            currentIndex = i
            return (documents[i], true)
        }
        let doc = try Document.open(url: url)
        if let cur = currentDocument, !cur.isModified, cur.fileURL == nil || cur.fileURL == url {
            documents[currentIndex] = doc
        } else {
            documents.append(doc)
            currentIndex = documents.count - 1
        }
        return (doc, false)
    }

    /// Removes the document at `index`. If that empties the list, creates
    /// a fresh blank document so there is always at least one tab open.
    /// Returns `true` when it had to auto-create that replacement, so
    /// callers can skip cursor-restoration on the brand-new blank tab.
    @discardableResult
    func closeDocument(at index: Int) -> Bool {
        guard index >= 0, index < documents.count else { return false }
        documents.remove(at: index)
        if documents.isEmpty {
            _ = newDocument()
            return true
        }
        currentIndex = min(index, documents.count - 1)
        return false
    }

    func selectDocument(at index: Int) {
        guard index >= 0, index < documents.count else { return }
        currentIndex = index
    }

    /// Sets the current index to `savedIndex`, clamped into range. Used
    /// only by session restore, which must always land on some valid
    /// document rather than silently no-op on an out-of-range value.
    func selectDocumentClamped(to savedIndex: Int) {
        guard !documents.isEmpty else { return }
        currentIndex = max(0, min(savedIndex, documents.count - 1))
    }

    /// Drops the auto-created blank tab left over from `newDocument()` at
    /// window-init time, if session restore populated real documents
    /// alongside it. Mirrors the prior inline logic in `restoreSession()`.
    func pruneLeftoverBlankDocument() {
        guard documents.count > 1,
              let i = documents.firstIndex(where: { $0.fileURL == nil && !$0.isModified && $0.content.isEmpty })
        else { return }
        documents.remove(at: i)
        if currentIndex >= i, currentIndex > 0 { currentIndex -= 1 }
        if currentIndex >= documents.count { currentIndex = documents.count - 1 }
    }
}
