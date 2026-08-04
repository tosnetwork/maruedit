import AppKit
import MaruEditCore

/// Owns syntax-highlighting scheduling and validity. The editor supplies only
/// immutable text/range snapshots; regex work runs off the main thread and
/// attributes are applied only when the captured document revision is still
/// current.
final class SyntaxHighlightCoordinator {
    static let largeFileThreshold = 100_000
    static let contextBuffer = 3_000

    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let revisionLock = NSLock()
    private var pendingDebounce: DispatchWorkItem?
    private var pendingMatch: DispatchWorkItem?
    private var storedRevision: UInt64 = 0
    var revision: UInt64 {
        revisionLock.lock(); defer { revisionLock.unlock() }
        return storedRevision
    }
    private(set) var isLargeFileMode = false
    private(set) var lastAppliedRange: NSRange?
    private(set) var lastWorkWasTruncated = false

    init(
        workerQueue: DispatchQueue = DispatchQueue(
            label: "com.maruedit.syntax-highlight", qos: .userInitiated),
        callbackQueue: DispatchQueue = .main
    ) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
    }

    deinit { cancel() }

    func cancel() {
        _ = nextRevision()
        pendingDebounce?.cancel()
        pendingMatch?.cancel()
        pendingDebounce = nil
        pendingMatch = nil
    }

    /// Debounces a highlight request. `visibleRange == nil` means the whole
    /// document is required. Visible requests expand to line boundaries plus
    /// context so multiline rules and scrolling do not expose unstyled edges.
    func schedule(
        storage: NSTextStorage,
        language: Language,
        visibleRange: NSRange?,
        font: NSFont,
        baseForeground: NSColor = Theme.foreground,
        delay: TimeInterval = 0.05,
        highlighter: SyntaxHighlighter? = nil,
        completion: (() -> Void)? = nil
    ) {
        let requestedRevision = nextRevision()
        pendingDebounce?.cancel()
        pendingMatch?.cancel()

        let snapshot = storage.string
        let length = (snapshot as NSString).length
        isLargeFileMode = length > Self.largeFileThreshold
        lastWorkWasTruncated = false
        guard length > 0 else {
            lastAppliedRange = nil
            completion?()
            return
        }

        if isLargeFileMode {
            // Large-file mode deliberately disables regex highlighting. Clear
            // stale syntax colors once, preserving characters and all non-color
            // attributes.
            let entire = NSRange(location: 0, length: length)
            storage.addAttribute(.foregroundColor, value: baseForeground, range: entire)
            lastAppliedRange = nil
            completion?()
            return
        }

        let target = Self.requiredContextRange(
            for: visibleRange ?? NSRange(location: 0, length: length), in: snapshot,
            buffer: visibleRange == nil ? 0 : Self.contextBuffer)
        let matcher = highlighter ?? SyntaxHighlighter(language: language)
        let debounce = DispatchWorkItem { [weak self, weak storage] in
            guard let self, let storage, self.isCurrent(requestedRevision) else { return }
            let matchWork = DispatchWorkItem { [weak self, weak storage] in
                guard let self, let storage, self.isCurrent(requestedRevision) else { return }
                let batch = matcher.matchBatch(
                    in: snapshot, range: target,
                    isCancelled: { !self.isCurrent(requestedRevision) })
                self.callbackQueue.async { [weak self, weak storage] in
                    guard let self, let storage,
                          self.isCurrent(requestedRevision),
                          storage.string == snapshot else { return }
                    storage.beginEditing()
                    storage.addAttributes([
                        .foregroundColor: baseForeground,
                        .font: font,
                    ], range: target)
                    for match in batch.matches where NSMaxRange(match.range) <= storage.length {
                        storage.addAttribute(
                            .foregroundColor, value: match.color, range: match.range)
                    }
                    storage.endEditing()
                    self.lastAppliedRange = target
                    self.lastWorkWasTruncated = batch.wasTruncated
                    completion?()
                }
            }
            self.pendingMatch = matchWork
            self.workerQueue.async(execute: matchWork)
        }
        pendingDebounce = debounce
        callbackQueue.asyncAfter(deadline: .now() + delay, execute: debounce)
    }

    private func nextRevision() -> UInt64 {
        revisionLock.lock(); defer { revisionLock.unlock() }
        storedRevision &+= 1
        return storedRevision
    }

    private func isCurrent(_ candidate: UInt64) -> Bool {
        revisionLock.lock(); defer { revisionLock.unlock() }
        return candidate == storedRevision
    }

    static func requiredContextRange(
        for requestedRange: NSRange, in text: String, buffer: Int = contextBuffer
    ) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let safe = NSIntersectionRange(requestedRange, NSRange(location: 0, length: ns.length))
        let start = max(0, safe.location - buffer)
        let end = min(ns.length, NSMaxRange(safe) + buffer)
        return ns.lineRange(for: NSRange(location: start, length: max(0, end - start)))
    }
}
