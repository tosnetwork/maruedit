import AppKit

final class ClipboardHistoryStore {
    private(set) var entries: [String] = []
    private var lastChangeCount: Int?
    let limit: Int

    init(limit: Int = 30) { self.limit = max(1, limit) }

    func poll(_ pasteboard: NSPasteboard = .general) {
        guard lastChangeCount != pasteboard.changeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let value = pasteboard.string(forType: .string), !value.isEmpty else { return }
        entries.removeAll { $0 == value }
        entries.insert(value, at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
    }

    func clear() { entries.removeAll() }
}
