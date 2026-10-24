import Foundation

public enum ApprovalKind: String, Codable, Sendable, CaseIterable {
    case listing, purchase
}

public enum ApprovalStatus: String, Codable, Sendable, CaseIterable {
    case pending, approved, denied, expired

    /// Statuses the owner can pick in `decide_approval`. `expired` is set by the worker.
    public static let decisions: [ApprovalStatus] = [.approved, .denied]
}

/// Mirror of the `approval` table (#12). The worker writes a `pending` row when
/// a listing or purchase is over the user's threshold; the owner decides it in
/// the app or on their phone via Auth0 Guardian (CIBA), both through `decide_approval`.
public struct Approval: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var kind: ApprovalKind
    /// `listing.id` for `.listing`, `deal.id` for `.purchase`.
    public var refId: UInt64
    public var amountCents: Int64
    public var summary: String
    public var status: ApprovalStatus
    public var requestedAt: Date
    public var updatedAt: Date

    public init(
        id: UInt64, owner: IdentityHex, kind: ApprovalKind, refId: UInt64, amountCents: Int64, summary: String,
        status: ApprovalStatus = .pending, requestedAt: Date = .now, updatedAt: Date? = nil
    ) {
        self.id = id
        self.owner = owner
        self.kind = kind
        self.refId = refId
        self.amountCents = amountCents
        self.summary = summary
        self.status = status
        self.requestedAt = requestedAt
        self.updatedAt = updatedAt ?? requestedAt
    }

    public var isPending: Bool { status == .pending }
}

extension SyncSnapshot {
    /// The signed-in user's undecided approvals, oldest first (first asked, first answered).
    public var pendingApprovals: [Approval] {
        approvals.filter { $0.owner == me && $0.isPending }.sorted { ($0.requestedAt, $0.id) < ($1.requestedAt, $1.id) }
    }

    /// The signed-in user's decided approvals, newest decision first.
    public var decidedApprovals: [Approval] {
        approvals.filter { $0.owner == me && !$0.isPending }.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
    }

    /// The listing an approval gates, if it's a listing approval and the listing is synced.
    public func listing(for approval: Approval) -> Listing? {
        guard approval.kind == .listing else { return nil }
        return listings.first { $0.id == approval.refId }
    }
}
