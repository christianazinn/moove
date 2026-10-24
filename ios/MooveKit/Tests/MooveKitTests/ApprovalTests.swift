import Foundation
import Testing
@testable import MooveKit

@Suite struct ApprovalTests {
    private func connectedDemo() async throws -> FixtureBackend {
        let backend = FixtureBackend.demo(identity: "me")
        _ = try await backend.connect(token: nil)
        return backend
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }

    @Test func pendingAndDecidedSplitAndSort() {
        var s = SyncSnapshot(me: "me")
        let t0 = Date(timeIntervalSince1970: 1_000)
        s.approvals = [
            Approval(id: 1, owner: "me", kind: .listing, refId: 7, amountCents: 100, summary: "b", requestedAt: t0.addingTimeInterval(60)),
            Approval(id: 2, owner: "me", kind: .purchase, refId: 8, amountCents: 100, summary: "a", requestedAt: t0),
            Approval(id: 3, owner: "me", kind: .purchase, refId: 9, amountCents: 100, summary: "old", status: .denied,
                     requestedAt: t0, updatedAt: t0.addingTimeInterval(10)),
            Approval(id: 4, owner: "me", kind: .purchase, refId: 9, amountCents: 100, summary: "new", status: .approved,
                     requestedAt: t0, updatedAt: t0.addingTimeInterval(20)),
            Approval(id: 5, owner: "someone-else", kind: .listing, refId: 7, amountCents: 100, summary: "x"),
        ]
        #expect(s.pendingApprovals.map(\.id) == [2, 1])
        #expect(s.decidedApprovals.map(\.id) == [4, 3])
    }

    @Test func statusRawValuesMatchContract() {
        #expect(ApprovalStatus.allCases.map(\.rawValue) == ["pending", "approved", "denied", "expired"])
        #expect(ApprovalKind.allCases.map(\.rawValue) == ["listing", "purchase"])
    }

    @Test func demoHasPendingListingApprovalForAwaitingListing() {
        let s = DemoFixtures.inventory(owner: "me")
        let pendingListing = s.pendingApprovals.filter { $0.kind == .listing }
        #expect(!pendingListing.isEmpty)
        for a in pendingListing {
            let l = s.listing(for: a)
            #expect(l?.status == .awaitingApproval)
            #expect(l?.priceCents == a.amountCents)
        }
        #expect(!s.decidedApprovals.isEmpty)
    }

    @Test func approvingPostsTheListing() async throws {
        let backend = try await connectedDemo()
        try await backend.decideApproval(approvalId: 300, status: .approved)
        let s = await firstSnapshot(backend)
        #expect(s.approvals.first { $0.id == 300 }?.status == .approved)
        let l = s.listings.first { $0.id == 200 }
        #expect(l?.status == .posted)
        #expect(l?.externalId != nil)
        #expect(l?.simulated == true)
        #expect(!s.pendingApprovals.contains { $0.id == 300 })
    }

    @Test func denyingRejectsTheListing() async throws {
        let backend = try await connectedDemo()
        try await backend.decideApproval(approvalId: 300, status: .denied)
        let s = await firstSnapshot(backend)
        #expect(s.approvals.first { $0.id == 300 }?.status == .denied)
        #expect(s.listings.first { $0.id == 200 }?.status == .rejected)
    }

    @Test func approvalForAStalePriceRejects() async throws {
        var seed = DemoFixtures.inventory(owner: "me")
        seed.listings[0].priceCents = 39_000 // price changed after the approval was requested
        let backend = FixtureBackend(identity: "me", seed: seed)
        _ = try await backend.connect(token: nil)
        try await backend.decideApproval(approvalId: 300, status: .approved)
        #expect(await firstSnapshot(backend).listings.first { $0.id == 200 }?.status == .rejected)
    }

    @Test func cannotDecideTwiceOrSomeoneElses() async throws {
        let backend = try await connectedDemo()
        try await backend.decideApproval(approvalId: 301, status: .approved)
        await #expect(throws: FixtureBackend.Failure.alreadyDecided) {
            try await backend.decideApproval(approvalId: 301, status: .denied)
        }
        await #expect(throws: FixtureBackend.Failure.invalidStatus) {
            try await backend.decideApproval(approvalId: 300, status: .expired)
        }
        await #expect(throws: FixtureBackend.Failure.noSuchApproval) {
            try await backend.decideApproval(approvalId: 9_999, status: .approved)
        }

        var seed = DemoFixtures.inventory(owner: "alice")
        seed.me = nil
        let other = FixtureBackend(identity: "bob", seed: seed)
        _ = try await other.connect(token: nil)
        await #expect(throws: FixtureBackend.Failure.unauthorized) {
            try await other.decideApproval(approvalId: 300, status: .approved)
        }
    }
}
