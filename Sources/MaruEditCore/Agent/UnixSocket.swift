import Foundation

/// Thin, blocking AF_UNIX helpers.
///
/// Deliberately small: the socket is a private channel between two processes
/// on one machine, so it needs correct permissions, a peer-credential check,
/// and framing — not a networking layer.
public enum UnixSocket {
    public enum SocketError: Error, Equatable {
        case pathTooLong(String)
        case createFailed(Int32)
        case bindFailed(Int32)
        case listenFailed(Int32)
        case connectFailed(Int32)
        case peerCredentialsUnavailable
        case wrongUser(uid_t)
        case closed
    }

    /// `sockaddr_un.sun_path` is 104 bytes on Darwin. Failing here beats
    /// silently binding a truncated path, which is a different socket than the
    /// one everyone else is looking for.
    public static let maximumPathLength = 103

    private static func address(for path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard bytes.count <= maximumPathLength else { throw SocketError.pathTooLong(path) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }

    /// Writing to a socket whose peer has gone raises `SIGPIPE`, which
    /// terminates the process by default — an agent that quits at the wrong
    /// moment would take the editor and any unsaved work with it. Every socket
    /// this module creates opts out and gets `EPIPE` instead.
    private static func configure(_ descriptor: Int32) {
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// A peer that stops reading must not be able to freeze the editor, so
    /// writes give up rather than blocking forever.
    private static func setWriteTimeout(_ descriptor: Int32, seconds: Int) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(
            descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout,
            socklen_t(MemoryLayout<timeval>.size))
    }

    /// Creates a listening socket with `0600` permissions.
    ///
    /// The mode is set with `umask` around `bind` rather than `chmod`
    /// afterwards, so there is no window in which the socket exists and is
    /// world-writable.
    public static func listen(at path: String, backlog: Int32 = 8) throws -> Int32 {
        unlink(path)
        var addr = try address(for: path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketError.createFailed(errno) }
        configure(descriptor)

        let previousMask = umask(0o177)
        let bound = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0 else {
            let code = errno
            close(descriptor)
            throw SocketError.bindFailed(code)
        }
        guard Foundation.listen(descriptor, backlog) == 0 else {
            let code = errno
            close(descriptor)
            throw SocketError.listenFailed(code)
        }
        return descriptor
    }

    public static func connect(to path: String) throws -> Int32 {
        var addr = try address(for: path)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SocketError.createFailed(errno) }
        configure(descriptor)
        setWriteTimeout(descriptor, seconds: 30)
        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Foundation.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            close(descriptor)
            throw SocketError.connectFailed(code)
        }
        return descriptor
    }

    /// The connecting process's effective uid, captured by the kernel at
    /// `connect` time.
    ///
    /// This proves *same user* and nothing more. It is a precondition, not an
    /// authorization: every agent launches the same bridge, so uid equality
    /// says only that the peer is not somebody else's account.
    public static func peerUID(_ descriptor: Int32) throws -> uid_t {
        var credentials = xucred()
        var size = socklen_t(MemoryLayout<xucred>.size)
        let result = withUnsafeMutablePointer(to: &credentials) { pointer -> Int32 in
            getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERCRED, pointer, &size)
        }
        guard result == 0, credentials.cr_version == XUCRED_VERSION else {
            throw SocketError.peerCredentialsUnavailable
        }
        return credentials.cr_uid
    }

    public static func requireSameUser(_ descriptor: Int32) throws {
        let peer = try peerUID(descriptor)
        guard peer == getuid() else { throw SocketError.wrongUser(peer) }
    }

    // MARK: - Blocking IO

    /// Prepares an accepted connection: no `SIGPIPE`, and a bounded write.
    public static func prepareAccepted(_ descriptor: Int32, writeTimeoutSeconds: Int = 5) {
        configure(descriptor)
        setWriteTimeout(descriptor, seconds: writeTimeoutSeconds)
    }

    public static func writeAll(_ descriptor: Int32, _ data: Data) throws {
        var remaining = data
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { raw -> Int in
                write(descriptor, raw.baseAddress, raw.count)
            }
            if written > 0 {
                remaining.removeFirst(written)
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                // EPIPE (the peer went away) and EAGAIN (it stopped reading
                // and the timeout fired) are both "this connection is over".
                throw SocketError.closed
            }
        }
    }

    /// Reads whatever is available. An empty result means the peer closed.
    public static func read(_ descriptor: Int32, maximum: Int = 64 * 1024) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: maximum)
        let count = buffer.withUnsafeMutableBytes { raw -> Int in
            Foundation.read(descriptor, raw.baseAddress, raw.count)
        }
        if count > 0 { return Data(buffer.prefix(count)) }
        if count == 0 { return Data() }
        if errno == EINTR { return try read(descriptor, maximum: maximum) }
        throw SocketError.closed
    }
}
