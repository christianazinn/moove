import Foundation
import Testing
@testable import MooveKit

/// Listings and approvals for items in rooms shared with the user (#195, #200).
@Suite struct SharedCommerceTests {
    /// What `my_listing` / `my_approval` send a member of the seed user's room:
    /// their own rows plus the seed user's listing and its listing approvals.
    private func joinedSnapshot() -> SyncSnapshot {
        var s = SyncSnapshot(me: "me")
        s.listings = [
            Listing(id: 1, owner: "seed", itemId: 10, title: "Chair", description: "", priceCents: 41_000,
                    status: .awaitingApproval),
            Listing(id: 3, owner: "me", itemId: 30, title: "Desk", description: "", priceCents: 12_000,
                    status: .awaitingApproval),
        ]
        let t0 = Date(timeIntervalSince1970: 1_000)
        s.approvals = [
            Approval(id: 1, owner: "seed", kind: .listing, refId: 1, amountCents: 41_000, summary: "Chair", requestedAt: t0),
            Approval(id: 3, owner: "me", kind: .listing, refId: 3, amountCents: 12_000, summary: "Mine",
                     requestedAt: t0.addingTimeInterval(60)),
            Approval(id: 5, owner: "me", kind: .purchase, refId: 7, amountCents: 20_000, summary: "My purchase",
                     requestedAt: t0.addingTimeInterval(30)),
            Approval(id: 6, owner: "seed", kind: .listing, refId: 1, amountCents: 41_000, summary: "Done", status: .approved),
        ]
        return s
    }

    @Test func sharedApprovalsAreSeparateFromMineButActionable() {
        let s = joinedSnapshot()
        #expect(s.pendingApprovals.map(\.id) == [5, 3])
        #expect(s.sharedPendingApprovals.map(\.id) == [1])
        #expect(s.actionableApprovals.map(\.id) == [5, 3, 1])
        #expect(s.listing(for: s.sharedPendingApprovals[0])?.itemId == 10)
        // Decided shared approvals don't land in the member's History.
        #expect(s.decidedApprovals.allSatisfy { $0.owner == "me" })
    }

    @Test func membersDecideListingsButNotOthersPurchases() {
        let s = joinedSnapshot()
        let byId = Dictionary(uniqueKeysWithValues: s.approvals.map { ($0.id, $0) })
        #expect(s.canDecide(byId[1]!))
        #expect(s.canDecide(byId[5]!))
        #expect(!s.canDecide(byId[6]!)) // already decided
        let othersPurchase = Approval(id: 9, owner: "seed", kind: .purchase, refId: 1, amountCents: 1, summary: "")
        #expect(!s.canDecide(othersPurchase))
    }

    @Test func ownerNameFallsBackWhenOwnerRowIsntSynced() {
        var s = joinedSnapshot()
        #expect(s.ownerName("seed") == "the owner")
        s.users = [User(identity: "seed", name: "Demo Mover")]
        #expect(s.ownerName("seed") == "Demo Mover")
        #expect(s.isShared(s.listings[0]))
        #expect(!s.isShared(s.listings[1]))
    }

    @Test func ownerOnlyDemoHasNoSharedApprovals() {
        let s = DemoFixtures.inventory(owner: "me")
        #expect(s.sharedPendingApprovals.isEmpty)
        #expect(s.actionableApprovals == s.pendingApprovals)
    }
}
