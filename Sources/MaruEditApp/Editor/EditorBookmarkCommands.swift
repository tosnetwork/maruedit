import Foundation

extension EditorViewController {
    func toggleBookmark() {
        guard let bookmarks = document?.bookmarks else { return }
        bookmarks.toggle(lineAt: selectionSet.primaryRange.location, in: textView.string as NSString)
        refreshBookmarkGutter()
    }

    func nextBookmark() { navigateToBookmark(forward: true) }
    func previousBookmark() { navigateToBookmark(forward: false) }

    func clearBookmarks() {
        document?.bookmarks.clear()
        refreshBookmarkGutter()
    }

    private func navigateToBookmark(forward: Bool) {
        guard let bookmarks = document?.bookmarks else { return }
        let current = selectionSet.primaryRange.location
        let destination = forward
            ? bookmarks.next(after: current, wrapping: true)
            : bookmarks.previous(before: current, wrapping: true)
        guard let destination else { return }
        let range = NSRange(location: destination, length: 0)
        setSelections([range], primaryRange: range)
        textView.scrollRangeToVisible(range)
    }
}
