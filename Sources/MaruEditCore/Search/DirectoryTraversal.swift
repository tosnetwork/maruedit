import Foundation

/// Walks the directories in a `GrepRequest` and reports the files worth
/// searching (ROADMAP.md M3-04).
///
/// Hand-rolled rather than built on `FileManager.enumerator(at:)` because
/// this needs three things that enumerator does not give clearly: an
/// explicit symlink policy with a loop guard, a *reported* skip for every
/// file left out, and per-directory error recovery that continues the scan.
///
/// Pure and synchronous with no UI or global state; callers run it on a
/// background queue (ROADMAP.md M3-04, "No main-actor traversal").
public enum DirectoryTraversal {

    public static func traverse(
        _ request: GrepRequest,
        isCancelled: () -> Bool = { false },
        onFile: (URL) -> Void,
        onSkip: (URL, SkipReason) -> Void = { _, _ in }
    ) {
        let includes = request.includeGlobs.map(GlobPattern.init)
        let excludes = request.excludeGlobs.map(GlobPattern.init)
        var visitedDirectories = Set<String>()

        for root in request.roots {
            guard !isCancelled() else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                onSkip(root, .unreadable("No such file or directory"))
                continue
            }
            if isDirectory.boolValue {
                walk(
                    directory: root, root: root, request: request,
                    includes: includes, excludes: excludes,
                    visitedDirectories: &visitedDirectories,
                    isCancelled: isCancelled, onFile: onFile, onSkip: onSkip
                )
            } else {
                // A file named directly as a root is searched even when a
                // filter would have excluded it during traversal: the user
                // asked for that exact file.
                consider(
                    file: root, root: root.deletingLastPathComponent(), request: request,
                    includes: [], excludes: excludes, onFile: onFile, onSkip: onSkip
                )
            }
        }
    }

    // MARK: - Directories

    private static func walk(
        directory: URL,
        root: URL,
        request: GrepRequest,
        includes: [GlobPattern],
        excludes: [GlobPattern],
        visitedDirectories: inout Set<String>,
        isCancelled: () -> Bool,
        onFile: (URL) -> Void,
        onSkip: (URL, SkipReason) -> Void
    ) {
        guard !isCancelled() else { return }

        // Canonicalized so a directory reached twice through different
        // symlink paths — including a link pointing at its own ancestor —
        // is walked once and never loops.
        let canonical = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard visitedDirectories.insert(canonical).inserted else {
            onSkip(directory, .alreadyVisited)
            return
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                    .isPackageKey, .isHiddenKey, .fileSizeKey,
                ],
                options: []
            )
        } catch {
            // A directory the user can't read must not end the scan
            // (ROADMAP.md M3-04 acceptance).
            onSkip(directory, .unreadable((error as NSError).localizedDescription))
            return
        }

        for url in contents.sorted(by: { $0.path < $1.path }) {
            guard !isCancelled() else { return }
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                .isPackageKey, .isHiddenKey, .fileSizeKey,
            ])

            let name = url.lastPathComponent
            if !request.includesHiddenFiles, name.hasPrefix(".") || values?.isHidden == true {
                onSkip(url, .hidden)
                continue
            }
            if let excluded = excludes.firstMatch(relativePath: relativePath(of: url, from: root)) {
                onSkip(url, .excludedByGlob(excluded.pattern))
                continue
            }
            if values?.isSymbolicLink == true, !request.followsSymbolicLinks {
                onSkip(url, .symbolicLink)
                continue
            }

            // A symlink's own resource values describe the link, not what
            // it points at, so following one means asking the target
            // whether this is a directory.
            var effectiveValues = values
            if values?.isSymbolicLink == true {
                effectiveValues = try? url.resolvingSymlinksInPath().resourceValues(
                    forKeys: [.isDirectoryKey, .isRegularFileKey, .isPackageKey, .fileSizeKey])
            }

            if effectiveValues?.isDirectory == true {
                if effectiveValues?.isPackage == true, !request.traversesPackages {
                    onSkip(url, .package)
                    continue
                }
                guard request.isRecursive else { continue }
                walk(
                    directory: url, root: root, request: request,
                    includes: includes, excludes: excludes,
                    visitedDirectories: &visitedDirectories,
                    isCancelled: isCancelled, onFile: onFile, onSkip: onSkip
                )
                continue
            }

            consider(
                file: url, root: root, request: request,
                includes: includes, excludes: excludes, onFile: onFile, onSkip: onSkip
            )
        }
    }

    // MARK: - Files

    private static func consider(
        file url: URL,
        root: URL,
        request: GrepRequest,
        includes: [GlobPattern],
        excludes: [GlobPattern],
        onFile: (URL) -> Void,
        onSkip: (URL, SkipReason) -> Void
    ) {
        let relative = relativePath(of: url, from: root)

        if let excluded = excludes.firstMatch(relativePath: relative) {
            onSkip(url, .excludedByGlob(excluded.pattern))
            return
        }
        if !includes.isEmpty, includes.firstMatch(relativePath: relative) == nil {
            onSkip(url, .notIncludedByGlob)
            return
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(values?.fileSize ?? 0)
        if size > request.maximumFileSize {
            onSkip(url, .tooLarge(size: size, limit: request.maximumFileSize))
            return
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            onSkip(url, .unreadable("Permission denied"))
            return
        }
        if BinaryContentDetector.isProbablyBinaryFile(at: url) {
            onSkip(url, .binary)
            return
        }
        onFile(url)
    }

    /// Path relative to the search root, so glob patterns describe what the
    /// user sees in the results list rather than an absolute path that
    /// happens to contain someone's home directory name.
    static func relativePath(of url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return path }
        let trimmed = path.dropFirst(rootPath.count)
        return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
    }
}
