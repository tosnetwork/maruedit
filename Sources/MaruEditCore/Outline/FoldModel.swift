import Foundation

public struct FoldRegion: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let startLine: Int
    public let endLine: Int
    /// The content hidden when collapsed. The symbol's own line remains visible.
    public let hiddenUTF16Range: NSRange
    public let level: Int
}

/// UI-independent folding state derived from an outline. Region identifiers
/// are based on symbol kind/title occurrence rather than line numbers so a
/// collapsed region survives edits that merely move it within the document.
public struct FoldModel: Equatable, Sendable {
    public private(set) var regions: [FoldRegion]
    public private(set) var collapsedRegionIDs: Set<String>

    public init(
        text: String, symbols: [OutlineSymbol], collapsedRegionIDs: Set<String> = []
    ) {
        regions = Self.makeRegions(text: text, symbols: symbols)
        let valid = Set(regions.map(\.id))
        self.collapsedRegionIDs = collapsedRegionIDs.intersection(valid)
    }

    public func isCollapsed(_ region: FoldRegion) -> Bool {
        collapsedRegionIDs.contains(region.id)
    }

    @discardableResult
    public mutating func toggle(regionID: String) -> Bool {
        guard regions.contains(where: { $0.id == regionID }) else { return false }
        if collapsedRegionIDs.remove(regionID) != nil { return false }
        collapsedRegionIDs.insert(regionID)
        return true
    }

    public mutating func collapseAll() {
        collapsedRegionIDs = Set(regions.map(\.id))
    }

    public mutating func expandAll() {
        collapsedRegionIDs.removeAll()
    }

    public mutating func rebuild(text: String, symbols: [OutlineSymbol]) {
        let previous = collapsedRegionIDs
        regions = Self.makeRegions(text: text, symbols: symbols)
        collapsedRegionIDs = previous.intersection(Set(regions.map(\.id)))
    }

    public func region(startingAtLine line: Int) -> FoldRegion? {
        regions.first { $0.startLine == line }
    }

    public func collapsedRanges() -> [NSRange] {
        regions.filter(isCollapsed).map(\.hiddenUTF16Range)
    }

    private static func makeRegions(text: String, symbols: [OutlineSymbol]) -> [FoldRegion] {
        guard !symbols.isEmpty else { return [] }
        let lineIndex = LineIndex(text)
        var occurrences: [String: Int] = [:]
        var output: [FoldRegion] = []
        for (index, symbol) in symbols.enumerated() {
            let nextBoundary = symbols[(index + 1)...].first { $0.level <= symbol.level }
            let endLine = (nextBoundary?.line ?? lineIndex.lineCount) - 1
            guard endLine > symbol.line,
                  let hiddenStart = lineIndex.utf16Offset(forLine: symbol.line + 1) else { continue }
            let hiddenEnd = nextBoundary.flatMap {
                lineIndex.utf16Offset(forLine: $0.line)
            } ?? lineIndex.utf16Length
            guard hiddenEnd > hiddenStart else { continue }
            let base = "\(symbol.kind.rawValue):\(symbol.title)"
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            output.append(FoldRegion(
                id: "\(base):\(occurrence)", title: symbol.title,
                startLine: symbol.line, endLine: endLine,
                hiddenUTF16Range: NSRange(
                    location: hiddenStart, length: hiddenEnd - hiddenStart),
                level: symbol.level))
        }
        return output
    }
}
