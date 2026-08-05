import Foundation

extension EditorViewController {
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
}
