import Foundation

/// Framing for the private bridge↔app channel.
///
/// A four-byte big-endian length followed by that many bytes of UTF-8 JSON.
/// The length is checked before anything is allocated, so a malformed or
/// hostile frame cannot make the app reserve 4 GiB because someone sent
/// `0xFFFFFFFF`.
///
/// The public MCP side does not use this — stdio JSON-RPC is line-delimited —
/// so the two framings never meet.
public enum AgentFraming {
    /// Matches ADR-011 §4.2's limit. A document larger than this is refused
    /// with a structured error rather than truncated.
    public static let maximumFrameBytes = 16 * 1024 * 1024

    public enum FramingError: Error, Equatable {
        case frameTooLarge(Int)
        case truncated
        case notUTF8
    }

    public static func encode(_ payload: Data) throws -> Data {
        guard payload.count <= maximumFrameBytes else {
            throw FramingError.frameTooLarge(payload.count)
        }
        var header = UInt32(payload.count).bigEndian
        var out = Data(bytes: &header, count: 4)
        out.append(payload)
        return out
    }

    /// Pulls one complete frame off the front of `buffer`, if there is one.
    ///
    /// Returns `nil` when more bytes are needed, which is the normal case on a
    /// stream socket: a frame arrives in as many reads as the kernel feels
    /// like, and a reader that assumes one read is one message works fine in
    /// tests and fails in production.
    public static func decode(from buffer: inout Data) throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let length = buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= UInt32(maximumFrameBytes) else {
            throw FramingError.frameTooLarge(Int(length))
        }
        let total = 4 + Int(length)
        guard buffer.count >= total else { return nil }
        let payload = buffer.subdata(in: 4..<total)
        buffer.removeSubrange(0..<total)
        return payload
    }
}
