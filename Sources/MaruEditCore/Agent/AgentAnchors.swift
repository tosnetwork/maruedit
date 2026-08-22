import CryptoKit
import Foundation

/// Digest-verifiable handles into a document snapshot.
///
/// An anchor is valid **only at the revision that minted it** — it is a
/// snapshot handle, not a tracked range. That is a deliberate limitation: a
/// tracked anchor needs boundary affinity, overlap semantics, lifetime, and
/// memory bounds all specified and tested, which is a feature rather than a
/// footnote (ADR-012 OQ-2).
///
/// So what does it buy over a bare offset? The agent proves it is editing the
/// region it actually read by echoing a 32-byte digest, instead of quoting a
/// paragraph of surrounding text back. That is the difference between an exact
/// check and the fuzzy string matching this whole design exists to replace.
public struct AgentAnchor: Equatable, Sendable {
    public let id: String
    public let revision: UInt64
    public let start: Int
    public let end: Int
    public let digest: String

    public init(id: String, revision: UInt64, start: Int, end: Int, digest: String) {
        self.id = id
        self.revision = revision
        self.start = start
        self.end = end
        self.digest = digest
    }

    public var json: JSONValue {
        .object([
            "anchorId": .string(id),
            "revision": .int(Int(revision)),
            "start": .int(start),
            "end": .int(end),
            "digest": .string(digest),
        ])
    }
}

public enum AgentDigest {
    /// SHA-256 over the UTF-8 bytes of the LF-normalized region, printed as
    /// `sha256:` plus lowercase hex.
    public static func of(_ text: String) -> String {
        let canonical = TextCanonicalization.canonical(text)
        let hash = SHA256.hash(data: Data(canonical.utf8))
        return "sha256:" + hash.map { String(format: "%02x", $0) }.joined()
    }
}

/// Per-connection anchor storage.
///
/// Owned by the app, never the bridge: quota enforcement and cleanup need to
/// see the document, and the bridge cannot. Anchors die with the revision that
/// minted them, with the document, and with the connection — which is why no
/// separate expiry timer is needed.
public final class AgentAnchorStore {
    /// Bounds are numbers, not adjectives: "bounded" without a figure is not a
    /// bound, and an unbounded anchor set is both a token cost and a leak.
    public static let maximumPerCall = 32
    public static let maximumPerConnection = 256

    private var anchors: [String: AgentAnchor] = [:]
    private var order: [String] = []
    private var counter: UInt64 = 0

    public init() {}

    public var count: Int { anchors.count }

    public func mint(revision: UInt64, start: Int, end: Int, text: String) -> AgentAnchor {
        counter &+= 1
        let anchor = AgentAnchor(
            id: "a_\(String(counter, radix: 16))",
            revision: revision,
            start: start,
            end: end,
            digest: AgentDigest.of(text))
        anchors[anchor.id] = anchor
        order.append(anchor.id)
        while order.count > Self.maximumPerConnection {
            let oldest = order.removeFirst()
            anchors.removeValue(forKey: oldest)
        }
        return anchor
    }

    public func anchor(_ id: String) -> AgentAnchor? { anchors[id] }

    /// Drops every anchor minted before `revision`, which is every anchor
    /// whenever the text changes at all.
    public func invalidate(atOrBefore revision: UInt64) {
        let survivors = anchors.filter { $0.value.revision > revision }
        anchors = survivors
        order = order.filter { survivors[$0] != nil }
    }

    public func removeAll() {
        anchors.removeAll()
        order.removeAll()
    }
}
