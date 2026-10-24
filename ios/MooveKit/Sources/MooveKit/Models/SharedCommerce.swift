import Foundation

// Listings and approvals for items in rooms shared with the user (#195).
//
// The module's per-user views `my_listing` / `my_approval` (#200) return the
// user's own rows plus listings for items in rooms they joined and the listing
// approvals that gate them. Room members may decide those listing approvals
// (`decide_approval`); purchase approvals stay owner-only and never reach other
// users. So `approvals` can hold someone else's *listing* approval, never their
// purchase approval.

extension SyncSnapshot {
    /// Pending listing approvals someone else owns, for an item in a room the
    /// user joined. Any room member can approve or deny them (#200). Oldest first.
    public var sharedPendingApprovals: [Approval] {
        approvals.filter { $0.owner != me && $0.kind == .listing && $0.isPending }
            .sorted { ($0.requestedAt, $0.id) < ($1.requestedAt, $1.id) }
    }

    /// Everything waiting on this user: their own pending approvals, then shared-room ones.
    public var actionableApprovals: [Approval] { pendingApprovals + sharedPendingApprovals }

    /// Whether `decide_approval` accepts this user's decision: the owner, or
    /// (for a listing approval) a member of the item's room.
    public func canDecide(_ approval: Approval) -> Bool {
        guard approval.isPending else { return false }
        return approval.owner == me || approval.kind == .listing
    }

    /// The owner's name when their user row is synced (`my_user` only returns
    /// the signed-in user today), otherwise "the owner".
    public func ownerName(_ owner: IdentityHex) -> String {
        if let name = users.first(where: { $0.identity == owner })?.name, !name.isEmpty { return name }
        return "the owner"
    }

    /// True when the listing belongs to someone else (a shared-room item).
    public func isShared(_ listing: Listing) -> Bool { listing.owner != me }
}
