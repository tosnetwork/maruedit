import Foundation

/// Document-owned bookmark anchors expressed as UTF-16 offsets. Anchoring at
/// line starts lets ordinary edits move bookmarks deterministically without
/// coupling the model to a particular editor or window.
final class BookmarkSet {
    private(set) var offsets: Set<Int> = []

    func contains(lineAt offset: Int, in text: NSString) -> Bool {
        offsets.contains(Self.lineStart(at: offset, in: text))
    }

    @discardableResult
    func toggle(lineAt offset: Int, in text: NSString) -> Bool {
        let anchor = Self.lineStart(at: offset, in: text)
        if offsets.remove(anchor) != nil { return false }
        offsets.insert(anchor)
        return true
    }

    func clear() { offsets.removeAll() }

    func restore(_ savedOffsets: Set<Int>) { offsets = savedOffsets }

    func next(after offset: Int, wrapping: Bool) -> Int? {
        offsets.filter { $0 > offset }.min() ?? (wrapping ? offsets.min() : nil)
    }

    func previous(before offset: Int, wrapping: Bool) -> Int? {
        offsets.filter { $0 < offset }.max() ?? (wrapping ? offsets.max() : nil)
    }

    /// Move anchors through a replacement expressed in the pre-edit string.
    func applyEdit(range: NSRange, replacement: String) {
        let insertedLength = (replacement as NSString).length
        let removedEnd = NSMaxRange(range)
        let delta = insertedLength - range.length
        offsets = Set(offsets.map { anchor in
            if anchor < range.location { return anchor }
            if anchor >= removedEnd { return max(0, anchor + delta) }
            return range.location
        })
    }

    func clamp(toUTF16Length length: Int) {
        offsets = Set(offsets.map { min(max(0, $0), length) })
    }

    func normalize(in text: NSString) {
        offsets = Set(offsets.map { Self.lineStart(at: $0, in: text) })
    }

    private static func lineStart(at offset: Int, in text: NSString) -> Int {
        let safe = min(max(0, offset), text.length)
        return text.lineRange(for: NSRange(location: safe, length: 0)).location
    }
}
