import Foundation

/// Line-start anchors for lines changed since the user last cleared edit
/// marks. This is intentionally independent of the document dirty flag.
final class EditMarkSet {
    private(set) var offsets: Set<Int> = []
    var sortedOffsets: [Int] { offsets.sorted() }

    func clear() { offsets.removeAll() }

    func recordEdit(range: NSRange, replacement: String, in textBeforeEdit: NSString) {
        applyEdit(range: range, replacement: replacement)
        let safe = min(max(0, range.location), textBeforeEdit.length)
        offsets.insert(textBeforeEdit.lineRange(for: NSRange(location: safe, length: 0)).location)
    }

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

    func normalize(in text: NSString) {
        offsets = Set(offsets.map {
            let safe = min(max(0, $0), text.length)
            return text.lineRange(for: NSRange(location: safe, length: 0)).location
        })
    }

    func next(after offset: Int) -> Int? {
        offsets.filter { $0 > offset }.min() ?? offsets.min()
    }

    func previous(before offset: Int) -> Int? {
        offsets.filter { $0 < offset }.max() ?? offsets.max()
    }
}
