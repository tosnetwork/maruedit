import Foundation

/// One portable Exuberant/Universal Ctags destination.
public struct TagDestination: Equatable, Sendable {
    public let name: String
    public let relativePath: String
    public let line: Int?
    public let searchPattern: String?

    public init(name: String, relativePath: String, line: Int? = nil, searchPattern: String? = nil) {
        self.name = name
        self.relativePath = relativePath
        self.line = line
        self.searchPattern = searchPattern
    }
}

/// Bounded parser and resolver for the portable fields of a ctags `tags` file.
public struct TagIndex: Sendable {
    public static let maximumEntries = 200_000
    public let destinations: [TagDestination]

    public init(contents: String) {
        var parsed: [TagDestination] = []
        parsed.reserveCapacity(min(4_096, contents.utf8.count / 32))
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard parsed.count < Self.maximumEntries, !rawLine.hasPrefix("!_TAG_") else { continue }
            let fields = rawLine.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            let address = String(fields[2]).split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            if let line = Int(address), line > 0 {
                parsed.append(TagDestination(name: String(fields[0]), relativePath: String(fields[1]), line: line))
            } else if let pattern = Self.pattern(from: address) {
                parsed.append(TagDestination(name: String(fields[0]), relativePath: String(fields[1]), searchPattern: pattern))
            }
        }
        destinations = parsed
    }

    public func matches(named name: String) -> [TagDestination] {
        destinations.filter { $0.name == name }
    }

    /// Resolves a tag path without allowing a crafted index to escape its project root.
    public static func fileURL(for destination: TagDestination, relativeTo root: URL) -> URL? {
        let base = root.standardizedFileURL
        let candidate = base.appendingPathComponent(destination.relativePath).standardizedFileURL
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard candidate.path == base.path || candidate.path.hasPrefix(prefix) else { return nil }
        return candidate
    }

    public static func utf16Offset(for destination: TagDestination, in text: String) -> Int? {
        let ns = text as NSString
        if let line = destination.line {
            var offset = 0
            for _ in 1..<line {
                guard offset < ns.length else { return nil }
                offset = NSMaxRange(ns.lineRange(for: NSRange(location: offset, length: 0)))
            }
            return offset
        }
        guard let pattern = destination.searchPattern else { return nil }
        return ns.range(of: pattern).location == NSNotFound ? nil : ns.range(of: pattern).location
    }

    private static func pattern(from address: String) -> String? {
        guard address.count >= 4, address.hasPrefix("/^") || address.hasPrefix("?^") else { return nil }
        let delimiter = address.first!
        guard address.hasSuffix("$\(delimiter)") else { return nil }
        let start = address.index(address.startIndex, offsetBy: 2)
        let end = address.index(address.endIndex, offsetBy: -2)
        return String(address[start..<end])
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
