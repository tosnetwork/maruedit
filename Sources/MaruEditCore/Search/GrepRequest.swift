import Foundation

/// Everything a Grep run needs: what to look for, where, and which files
/// to leave out (ROADMAP.md section 11.3).
///
/// The search itself is described by the same `SearchQuery` the Find Bar
/// builds, so a pattern behaves identically in one document and across a
/// directory tree.
public struct GrepRequest: Sendable, Equatable {
    public var query: SearchQuery
    public var roots: [URL]
    /// Files must match at least one of these to be searched. Empty means
    /// "no restriction" rather than "match nothing".
    public var includeGlobs: [String]
    /// Files and directories matching any of these are skipped. Applied to
    /// directories too, so excluding `node_modules` prunes the whole
    /// subtree instead of filtering thousands of files one by one.
    public var excludeGlobs: [String]
    public var includesHiddenFiles: Bool
    /// Off by default: a symlinked directory can point anywhere, including
    /// back into the tree being scanned (ROADMAP.md 11.3, "symbolic links
    /// disabled by default").
    public var followsSymbolicLinks: Bool
    public var traversesPackages: Bool
    public var isRecursive: Bool
    public var maximumFileSize: Int64

    public static let defaultMaximumFileSize: Int64 = 10 * 1024 * 1024

    public init(
        query: SearchQuery,
        roots: [URL],
        includeGlobs: [String] = [],
        excludeGlobs: [String] = [],
        includesHiddenFiles: Bool = false,
        followsSymbolicLinks: Bool = false,
        traversesPackages: Bool = false,
        isRecursive: Bool = true,
        maximumFileSize: Int64 = GrepRequest.defaultMaximumFileSize
    ) {
        self.query = query
        self.roots = roots
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.includesHiddenFiles = includesHiddenFiles
        self.followsSymbolicLinks = followsSymbolicLinks
        self.traversesPackages = traversesPackages
        self.isRecursive = isRecursive
        self.maximumFileSize = maximumFileSize
    }
}

/// Why a file or directory was not searched. Every skip is reported rather
/// than silently dropped, so a Grep that found nothing can explain whether
/// it looked.
public enum SkipReason: Sendable, Equatable {
    case hidden
    case excludedByGlob(String)
    case notIncludedByGlob
    case symbolicLink
    case package
    /// A directory reached twice through symlinks — the guard against
    /// symlink loops.
    case alreadyVisited
    case tooLarge(size: Int64, limit: Int64)
    case binary
    case unreadable(String)
}

extension SkipReason {
    public var describedReason: String {
        switch self {
        case .hidden: return "hidden"
        case .excludedByGlob(let pattern): return "excluded by \(pattern)"
        case .notIncludedByGlob: return "not matched by the include filter"
        case .symbolicLink: return "symbolic link"
        case .package: return "package contents"
        case .alreadyVisited: return "already visited (symlink loop)"
        case .tooLarge(let size, let limit): return "\(size) bytes exceeds the \(limit)-byte limit"
        case .binary: return "binary file"
        case .unreadable(let message): return message
        }
    }
}
