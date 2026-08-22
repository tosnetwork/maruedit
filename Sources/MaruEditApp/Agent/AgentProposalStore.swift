import AppKit
import MaruEditCore

/// Edits queued for a human to accept or reject, and the budget that keeps them
/// from eating the editor.
///
/// A proposal is **immutable**. It is never rewritten, relocated, or merged: if
/// the document moved while it sat in the queue, applying its stored ranges
/// anyway is exactly the lost-update bug this design exists to prevent, so it
/// becomes `conflicted` and the agent re-proposes.
@MainActor
final class AgentProposalStore {

    enum Status: String {
        case pending, applied, rejected, conflicted, expired
    }

    /// Bounds, because request-rate limiting does not bound retained state: a
    /// buggy but authorized agent could otherwise pin hundreds of megabytes of
    /// proposal text without exceeding any rate limit.
    static let maximumEditBytesPerCall = 1024 * 1024
    static let maximumPendingPerConnection = 8
    static let maximumPendingPerDocument = 4
    static let maximumBytesPerConnection = 4 * 1024 * 1024
    static let maximumBytesPerProcess = 32 * 1024 * 1024
    static let lifetime: TimeInterval = 600
    static let maximumLabelCharacters = 200

    struct Proposal {
        let id: String
        let connectionID: AutomationID
        let documentID: AutomationID
        let baseRevision: UInt64
        let baseMetadataRevision: UInt64
        let edits: [AutomationEdit]
        let expectedDigests: [String?]
        let label: String
        let createdAt: Date
        var status: Status = .pending
        var resultingRevision: UInt64?

        var byteCount: Int {
            edits.reduce(0) { $0 + $1.replacement.utf8.count }
        }
    }

    private(set) var proposals: [String: Proposal] = [:]
    private var counter: UInt64 = 0

    var onChange: (() -> Void)?

    var pending: [Proposal] {
        proposals.values.filter { $0.status == .pending }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Creation

    func create(
        connectionID: AutomationID,
        documentID: AutomationID,
        baseRevision: UInt64,
        baseMetadataRevision: UInt64,
        edits: [AutomationEdit],
        expectedDigests: [String?],
        label: String
    ) -> Result<Proposal, AgentToolFailure> {
        expireStale()

        let bytes = edits.reduce(0) { $0 + $1.replacement.utf8.count }
        guard bytes <= Self.maximumEditBytesPerCall else {
            return .failure(AgentToolFailure(
                code: "limit.edit_bytes",
                message: "Edits exceed \(Self.maximumEditBytesPerCall) bytes in one call."))
        }
        let mine = pending.filter { $0.connectionID == connectionID }
        guard mine.count < Self.maximumPendingPerConnection else {
            return .failure(AgentToolFailure(
                code: "limit.pending_proposals",
                message: "You already have \(mine.count) proposals waiting for review."))
        }
        guard pending.filter({ $0.documentID == documentID }).count < Self.maximumPendingPerDocument else {
            return .failure(AgentToolFailure(
                code: "limit.pending_proposals",
                message: "This document already has the maximum number of proposals waiting."))
        }
        guard mine.reduce(0, { $0 + $1.byteCount }) + bytes <= Self.maximumBytesPerConnection,
              pending.reduce(0, { $0 + $1.byteCount }) + bytes <= Self.maximumBytesPerProcess
        else {
            return .failure(AgentToolFailure(
                code: "limit.proposal_bytes",
                message: "Too much text is already waiting for review."))
        }

        counter &+= 1
        let proposal = Proposal(
            id: "prp_\(String(counter, radix: 16))",
            connectionID: connectionID,
            documentID: documentID,
            baseRevision: baseRevision,
            baseMetadataRevision: baseMetadataRevision,
            edits: edits,
            expectedDigests: expectedDigests,
            label: String(label.prefix(Self.maximumLabelCharacters)),
            createdAt: Date())
        proposals[proposal.id] = proposal
        onChange?()
        return .success(proposal)
    }

    // MARK: - Lifecycle

    func proposal(_ id: String) -> Proposal? {
        expireStale()
        return proposals[id]
    }

    func mark(_ id: String, _ status: Status, resultingRevision: UInt64? = nil) {
        guard var proposal = proposals[id] else { return }
        proposal.status = status
        proposal.resultingRevision = resultingRevision
        proposals[id] = proposal
        onChange?()
    }

    /// Expiry is not announced: no notification channel exists before Phase 4,
    /// and an agent that cares learns it from its next `review_status` poll.
    func expireStale(now: Date = Date()) {
        var changed = false
        for (id, proposal) in proposals
        where proposal.status == .pending && now.timeIntervalSince(proposal.createdAt) > Self.lifetime {
            proposals[id]?.status = .expired
            changed = true
        }
        if changed { onChange?() }
    }

    func dropAll(for connectionID: AutomationID) {
        for (id, proposal) in proposals where proposal.connectionID == connectionID && proposal.status == .pending {
            proposals[id]?.status = .expired
        }
        onChange?()
    }

    func dropAll(forDocument documentID: AutomationID) {
        for (id, proposal) in proposals where proposal.documentID == documentID && proposal.status == .pending {
            proposals[id]?.status = .expired
        }
        onChange?()
    }
}
