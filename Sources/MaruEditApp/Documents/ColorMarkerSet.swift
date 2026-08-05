import Foundation

enum MarkerColor: String, CaseIterable { case red, yellow, blue, green }

final class ColorMarkerSet {
    private(set) var markers: [Int: MarkerColor] = [:]

    @discardableResult
    func toggle(lineAt offset: Int, color: MarkerColor, in text: NSString) -> Bool {
        let anchor = lineStart(at: offset, in: text)
        if markers[anchor] == color { markers.removeValue(forKey: anchor); return false }
        markers[anchor] = color
        return true
    }

    func clear() { markers.removeAll() }
    func restore(_ saved: [Int: MarkerColor]) { markers = saved }
    func next(after offset: Int) -> Int? {
        markers.keys.filter { $0 > offset }.min() ?? markers.keys.min()
    }
    func previous(before offset: Int) -> Int? {
        markers.keys.filter { $0 < offset }.max() ?? markers.keys.max()
    }
    func applyEdit(range: NSRange, replacement: String) {
        let delta = (replacement as NSString).length - range.length
        let end = NSMaxRange(range)
        var updated: [Int: MarkerColor] = [:]
        for (anchor, color) in markers {
            let value = anchor < range.location ? anchor
                : anchor >= end ? max(0, anchor + delta) : range.location
            updated[value] = color
        }
        markers = updated
    }
    func normalize(in text: NSString) {
        markers = Dictionary(markers.map { (lineStart(at: $0.key, in: text), $0.value) },
                             uniquingKeysWith: { _, latest in latest })
    }
    private func lineStart(at offset: Int, in text: NSString) -> Int {
        text.lineRange(for: NSRange(location: min(max(0, offset), text.length), length: 0)).location
    }
}
