import Foundation

public enum ApprovalKind: String, Codable, Sendable, CaseIterable {
    case listing, purchase
}

public enum ApprovalStatus: String, Codable, Sendable, CaseIterable {
    case pending, approved, denied, expired

    /// Statuses `decide_approval` accepts (owner only, #42). `expired` is set only by the worker's
    /// `expire_approval` after `APPROVAL_EXPIRE_HOURS` without an answer (#186).
    public static let decisions: [ApprovalStatus] = [.approved, .denied]
}

/// Mirror of the `approval` table (#12). The worker writes a `pending` row when
/// a listing or purchase is over the user's threshold; the owner decides it in
/// the app (`decide_approval`, `decided_via = "app"`) or on their phone via Auth0 Guardian (CIBA, relayed
/// by the worker through `record_ciba_decision`, `decided_via = "ciba"`).
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

/// The worker's approval-expiry defaults (`agents/src/agents/approval-expiry.ts`, #186/#214): a pending
/// approval expires after `APPROVAL_EXPIRE_HOURS` without an answer, and the listing or buy agent asks
/// again at most `APPROVAL_MAX_REASKS` times. The app can't read the worker's env, so it mirrors them.
public enum ApprovalExpiry {
    public static let hours = 12
    public static let maxReasks = 2
    /// The first ask plus the re-asks.
    public static var maxAsks: Int { maxReasks + 1 }
}

/// Where one approval sits among the asks for the same listing or deal (#186). The agents re-ask with a
/// new approval row on the same `refId`, so rows group by owner, kind and `refId`, ordered by id (the
/// worker's `afterExpiry` treats the highest id as the latest).
public struct ApprovalAsks: Sendable, Equatable {
    /// 1 for the first ask, 2 after one expiry, and so on. Counts expired asks, like the agents' cap.
    public var askNumber: Int
    /// Earlier asks for the same listing or deal that expired, newest first.
    public var expiredBefore: [Approval]
    /// A newer approval exists for the same listing or deal: the agent asked again.
    public var askedAgain: Bool

    public var isReask: Bool { askNumber > 1 }
}

extension SyncSnapshot {
    /// Every approval for the same listing or deal as `approval`, oldest first.
    public func approvalGroup(for approval: Approval) -> [Approval] {
        approvals.filter { $0.owner == approval.owner && $0.kind == approval.kind && $0.refId == approval.refId }
            .sorted { $0.id < $1.id }
    }

    /// The re-ask count and the expired asks before `approval`.
    public func asks(for approval: Approval) -> ApprovalAsks {
        let group = approvalGroup(for: approval)
        let expired = group.filter { $0.id < approval.id && $0.status == .expired }
        return ApprovalAsks(askNumber: expired.count + 1, expiredBefore: expired.reversed(),
                            askedAgain: group.contains { $0.id > approval.id })
    }
}
