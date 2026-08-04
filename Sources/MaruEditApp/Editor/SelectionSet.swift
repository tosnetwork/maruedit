import Foundation

/// Per-editor normalized selection state. Ranges use TextKit's UTF-16
/// coordinate space and the primary selection is tracked explicitly.
final class SelectionSet {
    private(set) var ranges: [NSRange]
    private(set) var primaryIndex: Int

    init(ranges: [NSRange] = [NSRange(location: 0, length: 0)], primaryIndex: Int = 0) {
        let normalized = Self.normalize(ranges)
        self.ranges = normalized.isEmpty ? [NSRange(location: 0, length: 0)] : normalized
        self.primaryIndex = min(max(0, primaryIndex), self.ranges.count - 1)
    }

    var primaryRange: NSRange { ranges[primaryIndex] }

    /// Replaces the state and returns whether its normalized value changed.
    @discardableResult
    func update(ranges newRanges: [NSRange], primaryRange: NSRange? = nil) -> Bool {
        var normalized = Self.normalize(newRanges)
        if normalized.isEmpty { normalized = [NSRange(location: 0, length: 0)] }

        let requestedPrimary = primaryRange ?? newRanges.first
        let newPrimaryIndex = requestedPrimary.flatMap { requested in
            normalized.firstIndex { NSLocationInRange(requested.location, $0) || $0 == requested }
        } ?? 0

        guard normalized != ranges || newPrimaryIndex != primaryIndex else { return false }
        ranges = normalized
        primaryIndex = newPrimaryIndex
        return true
    }

    static func normalize(_ ranges: [NSRange]) -> [NSRange] {
        var valid: [NSRange] = []
        for range in ranges where range.location != NSNotFound {
            valid.append(NSRange(location: range.location, length: max(0, range.length)))
        }
        valid.sort {
            $0.location == $1.location ? $0.length < $1.length : $0.location < $1.location
        }

        var result: [NSRange] = []
        for range in valid {
            guard let last = result.last else {
                result.append(range)
                continue
            }
            if range == last { continue }
            // Empty cursors at an existing selection location are already
            // represented by that selection. Adjacent non-empty selections
            // remain distinct; only actual overlap is merged.
            let overlaps = range.location < NSMaxRange(last)
                || (range.length == 0 && NSLocationInRange(range.location, last))
            if overlaps {
                let end = max(NSMaxRange(last), NSMaxRange(range))
                result[result.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                result.append(range)
            }
        }
        return result
    }
}
