import Foundation

/// Containment for the one place this profile touches the filesystem.
///
/// Canonicalizing a path and comparing strings passes a review and loses a
/// race: a component can be replaced between the check and the open. So
/// containment is enforced by walking down from an opened root descriptor,
/// refusing a symlink at every component, and using the descriptor that walk
/// produced — never by reopening the path that was checked.
public enum AgentFileAccess {

    public enum AccessError: Error, Equatable {
        case noAuthorizedRoot
        case escapesRoot(String)
        case symlinkComponent(String)
        case notAFile(String)
        case tooLarge(Int)
        case unreadable(Int32)
    }

    /// Files larger than this are refused rather than read into a tool result.
    public static let maximumFileBytes = 8 * 1024 * 1024

    /// An open handle to a verified file, plus the identity that was verified.
    public struct VerifiedFile {
        public let descriptor: Int32
        public let path: String
        public let size: Int
        /// Identity of the file this descriptor actually names, taken from
        /// `fstat` on the descriptor itself.
        ///
        /// A path is a name, not a thing: between naming a file and using it,
        /// the binding can change. Carrying the identity forward is what lets a
        /// later save ask "is this still the file I read?" instead of trusting
        /// a string.
        public let identity: FileIdentity
        public let modificationDate: Date
        public let permissions: Int

        public func close() { Foundation.close(descriptor) }
    }

    /// Splits a path into components relative to `root`, or fails if it points
    /// outside. This is the string-level check; it is necessary but is not the
    /// boundary — `open(relativeTo:)` below is.
    public static func relativeComponents(of path: String, under root: String) -> [String]? {
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        guard normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/") else {
            return nil
        }
        let suffix = String(normalizedPath.dropFirst(normalizedRoot.count))
        let components = suffix.split(separator: "/").map(String.init)
        // `..` never survives standardization of an absolute path, but a
        // component that is literally ".." would mean the caller built the path
        // by hand; refuse rather than resolve it here.
        guard !components.contains("..") else { return nil }
        return components
    }

    /// Walks from `root` to `path` one component at a time, refusing symlinks.
    ///
    /// `O_NOFOLLOW` on each `openat` is what closes the race: swapping a
    /// component for a symlink after the check makes the open fail rather than
    /// silently redirect.
    public static func open(path: String, underAnyOf roots: [String]) throws -> VerifiedFile {
        guard !roots.isEmpty else { throw AccessError.noAuthorizedRoot }
        guard let (root, components) = roots.lazy.compactMap({ root -> (String, [String])? in
            relativeComponents(of: path, under: root).map { (root, $0) }
        }).first else {
            throw AccessError.escapesRoot(path)
        }
        guard !components.isEmpty else { throw AccessError.notAFile(path) }

        // The root is opened with `O_NOFOLLOW` too: a root that is itself a
        // symlink, or has been replaced by one, would otherwise be followed
        // before the per-component checks ever begin.
        var directory = Foundation.open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directory >= 0 else { throw AccessError.unreadable(errno) }

        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard next >= 0 else {
                let failure = classify(component, relativeTo: directory, errno: errno)
                close(directory)
                throw failure
            }
            close(directory)
            directory = next
        }

        let name = components[components.count - 1]
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            let failure = classify(name, relativeTo: directory, errno: errno)
            close(directory)
            throw failure
        }
        close(directory)

        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            close(descriptor)
            throw AccessError.unreadable(errno)
        }
        guard (status.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            throw AccessError.notAFile(path)
        }
        guard status.st_size <= maximumFileBytes else {
            close(descriptor)
            throw AccessError.tooLarge(Int(status.st_size))
        }
        return VerifiedFile(
            descriptor: descriptor,
            path: path,
            size: Int(status.st_size),
            identity: FileIdentity(
                deviceID: Int32(status.st_dev), inodeNumber: UInt64(status.st_ino)),
            modificationDate: Date(
                timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)
                    + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000),
            permissions: Int(status.st_mode & 0o7777))
    }

    /// Says why a component could not be entered.
    ///
    /// The errno alone is not enough to tell the interesting case from the dull
    /// one: `O_NOFOLLOW` on a symlink to a directory reports `ENOTDIR` on
    /// Darwin rather than `ELOOP`, which is indistinguishable from a plain file
    /// in the middle of a path. Asking the filesystem what the component
    /// actually is — without following it — gives the honest answer.
    private static func classify(
        _ component: String, relativeTo directory: Int32, errno code: Int32
    ) -> AccessError {
        var status = stat()
        if fstatat(directory, component, &status, AT_SYMLINK_NOFOLLOW) == 0,
           (status.st_mode & S_IFMT) == S_IFLNK {
            return .symlinkComponent(component)
        }
        if code == ELOOP { return .symlinkComponent(component) }
        return .unreadable(code)
    }

    /// Reads the whole verified file from its descriptor.
    ///
    /// The descriptor is the authority: reopening by path here would hand back
    /// the race the walk just closed.
    /// Reads the whole file from offset zero.
    ///
    /// `pread` rather than `read`, so the call does not depend on or disturb
    /// the descriptor's position. A `VerifiedFile` is held as a handle to a
    /// specific file — that is the point of opening it carefully — and a
    /// handle whose second read silently returns nothing is a trap for every
    /// later caller, including a retry after a decode failure.
    public static func read(_ file: VerifiedFile) throws -> Data {
        var data = Data()
        data.reserveCapacity(file.size)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var offset: off_t = 0
        while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                Foundation.pread(file.descriptor, raw.baseAddress, raw.count, offset)
            }
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
                offset += off_t(count)
                // A file growing while it is read must not make this loop
                // unbounded; the size limit was checked against the size at
                // open, so that is the amount this call is entitled to.
                if data.count >= file.size { break }
            } else if count == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw AccessError.unreadable(errno)
            }
        }
        return data
    }
}
