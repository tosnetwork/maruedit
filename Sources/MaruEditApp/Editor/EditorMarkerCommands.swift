import Foundation

extension EditorViewController {
    func applySearchColorLayerEdit(range: NSRange, replacement: String) {
        let delta = (replacement as NSString).length - range.length
        let editEnd = NSMaxRange(range)
        guard let document else { return }
        document.searchColorLayers = document.searchColorLayers.map { layer in
            var updated = layer
            updated.ranges = layer.ranges.compactMap { existing in
                if editEnd <= existing.location {
                    return NSRange(location: max(0, existing.location + delta), length: existing.length)
                }
                if range.location >= NSMaxRange(existing) { return existing }
                let start = min(existing.location, range.location)
                let end = max(start, NSMaxRange(existing) + delta)
                return end > start ? NSRange(location: start, length: end - start) : nil
            }
            return updated
        }
    }

    func applyTemporaryColorMarkerEdit(range: NSRange, replacement: String) {
        let delta = (replacement as NSString).length - range.length
        let editEnd = NSMaxRange(range)
        temporaryColorMarkers = temporaryColorMarkers.compactMap { marker in
            if editEnd <= marker.range.location {
                return TemporaryColorMarker(
                    range: NSRange(location: max(0, marker.range.location + delta), length: marker.range.length),
                    color: marker.color)
            }
            if range.location >= NSMaxRange(marker.range) { return marker }
            let start = min(marker.range.location, range.location)
            let end = max(start, NSMaxRange(marker.range) + delta)
            guard end > start else { return nil }
            return TemporaryColorMarker(range: NSRange(location: start, length: end - start), color: marker.color)
        }
    }

    func addTemporaryColorMarkers(_ color: MarkerColor? = nil) {
        let chosen = color ?? temporaryColorMarkerColor
        temporaryColorMarkerColor = chosen
        let additions = selectionSet.ranges.filter { $0.length > 0 }.map {
            TemporaryColorMarker(range: $0, color: chosen)
        }
        guard !additions.isEmpty else { return }
        temporaryColorMarkers.removeAll { existing in
            additions.contains { NSIntersectionRange(existing.range, $0.range).length > 0 }
        }
        temporaryColorMarkers.append(contentsOf: additions)
        temporaryColorMarkers.sort { $0.range.location < $1.range.location }
        refreshColorOverlays()
    }

    func removeTemporaryColorMarkersInSelection() {
        let selections = selectionSet.ranges
        temporaryColorMarkers.removeAll { marker in
            selections.contains { selection in
                selection.length == 0
                    ? NSLocationInRange(selection.location, marker.range)
                    : NSIntersectionRange(selection, marker.range).length > 0
            }
        }
        refreshColorOverlays()
    }

    func clearTemporaryColorMarkers() {
        temporaryColorMarkers.removeAll()
        refreshColorOverlays()
    }

    func selectTemporaryColorMarkers() {
        let ranges = temporaryColorMarkers.map(\.range)
        guard let first = ranges.first else { return }
        setSelections(ranges, primaryRange: first)
    }

    func nextTemporaryColorMarker() { navigateTemporaryColorMarker(forward: true) }
    func previousTemporaryColorMarker() { navigateTemporaryColorMarker(forward: false) }

    private func navigateTemporaryColorMarker(forward: Bool) {
        guard !temporaryColorMarkers.isEmpty else { return }
        let current = selectionSet.primaryRange.location
        let marker = forward
            ? temporaryColorMarkers.first(where: { $0.range.location > current }) ?? temporaryColorMarkers.first
            : temporaryColorMarkers.last(where: { $0.range.location < current }) ?? temporaryColorMarkers.last
        guard let marker else { return }
        setSelections([marker.range], primaryRange: marker.range)
        textView.scrollRangeToVisible(marker.range)
    }

    func nextHighlightedLine() { navigateHighlightedLine(forward: true) }
    func previousHighlightedLine() { navigateHighlightedLine(forward: false) }

    private func navigateHighlightedLine(forward: Bool) {
        let lines = syntaxHighlightedLineRanges()
        guard !lines.isEmpty else { return }
        let current = selectionSet.primaryRange.location
        let target = forward
            ? lines.first(where: { $0.location > current }) ?? lines.first
            : lines.last(where: { $0.location < current }) ?? lines.last
        guard let target else { return }
        let cursor = NSRange(location: target.location, length: 0)
        setSelections([cursor], primaryRange: cursor)
        textView.scrollRangeToVisible(cursor)
    }

    func selectHighlightedLineArea() {
        let lines = syntaxHighlightedLineRanges()
        let cursor = selectionSet.primaryRange.location
        guard let index = lines.firstIndex(where: { NSLocationInRange(cursor, $0) || cursor == NSMaxRange($0) }) else { return }
        var start = index, end = index
        while start > 0, NSMaxRange(lines[start - 1]) == lines[start].location { start -= 1 }
        while end + 1 < lines.count, NSMaxRange(lines[end]) == lines[end + 1].location { end += 1 }
        let range = NSRange(
            location: lines[start].location,
            length: NSMaxRange(lines[end]) - lines[start].location)
        setSelections([range], primaryRange: range)
    }

    private func syntaxHighlightedLineRanges() -> [NSRange] {
        guard let language = document?.language else { return [] }
        let text = textView.string
        let ns = text as NSString
        let budget = SyntaxHighlighter.WorkBudget(
            maximumDuration: 0.5, maximumMatches: 100_000,
            maximumUTF16Length: min(ns.length, 10_000_000))
        let matches = SyntaxHighlighter(language: language).matchBatch(
            in: text, range: NSRange(location: 0, length: ns.length), budget: budget).matches
        var seen = Set<Int>()
        return matches.compactMap { match in
            let line = ns.lineRange(for: NSRange(location: match.range.location, length: 0))
            return seen.insert(line.location).inserted ? line : nil
        }.sorted { $0.location < $1.location }
    }

    func toggleMarker(_ color: MarkerColor) {
        guard let markers = document?.colorMarkers else { return }
        markers.toggle(lineAt: selectionSet.primaryRange.location, color: color,
                       in: textView.string as NSString)
        refreshBookmarkGutter()
    }
    func nextMarker() { navigateMarker(forward: true) }
    func previousMarker() { navigateMarker(forward: false) }
    func clearMarkers() { document?.colorMarkers.clear(); refreshBookmarkGutter() }
    private func navigateMarker(forward: Bool) {
        guard let markers = document?.colorMarkers else { return }
        let current = selectionSet.primaryRange.location
        let offset = forward ? markers.next(after: current) : markers.previous(before: current)
        guard let offset else { return }
        let range = NSRange(location: offset, length: 0)
        setSelections([range], primaryRange: range)
        textView.scrollRangeToVisible(range)
    }

    func nextEditMark() { navigateEditMark(forward: true) }
    func previousEditMark() { navigateEditMark(forward: false) }
    func clearEditMarks() { document?.editMarks.clear(); refreshBookmarkGutter() }

    private func navigateEditMark(forward: Bool) {
        guard let marks = document?.editMarks else { return }
        let current = selectionSet.primaryRange.location
        let offset = forward ? marks.next(after: current) : marks.previous(before: current)
        guard let offset else { return }
        let range = NSRange(location: offset, length: 0)
        setSelections([range], primaryRange: range)
        textView.scrollRangeToVisible(range)
    }
}
