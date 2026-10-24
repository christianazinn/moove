import Foundation
import Testing
@testable import MooveKit

@Suite struct ShoppingTests {
    private func deal(_ id: UInt64, item: UInt64 = 1, source: String = "target", cents: Int64 = 5_000,
                      seller: String = "Target · new · ships", fraud: Double? = nil) -> Deal {
        Deal(id: id, owner: "me", shoppingItemId: item, source: source, title: "d\(id)", priceCents: cents,
             url: "https://example.com/\(id)", sellerInfo: seller, fraudScore: fraud)
    }

    private func visa(_ id: UInt64, deal: UInt64, _ status: PaymentStatus, simulated: Bool = true,
                      at seconds: Double = 0) -> Payment {
        Payment(id: id, owner: "me", agent: "buy", rail: .visa, purpose: "p", payee: "m", amountUsdMicros: 1,
                status: status, simulated: simulated, refTable: "deal", refId: deal,
                createdAt: Date(timeIntervalSince1970: 1_000 + seconds))
    }

    private func connectedDemo() async throws -> FixtureBackend {
        let backend = FixtureBackend.demo(identity: "me")
        _ = try await backend.connect(token: nil)
        return backend
    }

    private func latest(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }

    // MARK: Wire mapping

    @Test func statusRawValuesMatchContract() {
        #expect(ShoppingStatus.allCases.map(\.rawValue) == ["open", "searching", "found", "bought"])
        #expect(ShoppingStatus(wire: "bogus") == .open)
    }

    @Test func sentinelsBecomeNil() {
        let item = ShoppingItem(id: 1, owner: "me", name: "Sofa", chosenDealId: 0)
        #expect(item.chosenDealId == nil)
        let d = Deal(id: 1, owner: "me", shoppingItemId: 1, source: "fb", title: "t", priceCents: 1, url: "",
                     fraudScore: -1, aiTextScore: -1)
        #expect(d.url == nil && d.link == nil)
        #expect(d.fraudScore == nil && d.aiTextScore == nil && d.fraudLevel == nil)
        #expect(deal(2, fraud: 0).fraudScore == 0)
    }

    // MARK: Deals

    @Test func replayBadgeComesFromSellerInfo() {
        let replay = deal(1, seller: "IKEA · new · ships · Visa checkout · score 0.71 · cached replay")
        #expect(replay.isReplay)
        #expect(replay.sellerDetails == "IKEA · new · ships · Visa checkout · score 0.71")
        #expect(!deal(2, seller: "Target · new · ships").isReplay)
        #expect(deal(3, seller: "Cached Replay").isReplay)
        #expect(deal(3, seller: "Cached Replay").sellerDetails == "")
    }

    @Test func fraudLevelsAndBlock() {
        #expect(deal(1, fraud: 0.1).fraudLevel == .low)
        #expect(deal(2, fraud: 0.3).fraudLevel == .medium)
        #expect(deal(3, fraud: 0.7).fraudLevel == .high)
        #expect(deal(3, fraud: 0.7).isFraudBlocked)
        #expect(!deal(4, fraud: 0.69).isFraudBlocked)
        #expect(!deal(5).isFraudBlocked)
    }

    @Test func cardCheckoutOnlyForRetailMerchants() {
        #expect(deal(1, source: "ikea").supportsCardCheckout)
        #expect(deal(2, source: "Wayfair").supportsCardCheckout)
        #expect(!deal(3, source: "craigslist").supportsCardCheckout)
        #expect(!deal(4, source: "fb").supportsCardCheckout)
    }

    @Test func dealsGroupPerItemInRankOrder() {
        var s = SyncSnapshot(me: "me")
        s.deals = [deal(9, item: 2), deal(3, item: 1), deal(7, item: 2), deal(1, item: 1)]
        #expect(s.dealsByShoppingItem[1]?.map(\.id) == [1, 3])
        #expect(s.dealsByShoppingItem[2]?.map(\.id) == [7, 9])
        #expect(s.deals(for: 2).map(\.id) == [7, 9])
        #expect(s.deals(for: 5).isEmpty)
    }

    @Test func chosenDealMustBelongToTheItem() {
        var s = SyncSnapshot(me: "me")
        s.deals = [deal(1, item: 1), deal(2, item: 2)]
        #expect(s.chosenDeal(for: ShoppingItem(id: 1, owner: "me", name: "a", chosenDealId: 1))?.id == 1)
        #expect(s.chosenDeal(for: ShoppingItem(id: 1, owner: "me", name: "a", chosenDealId: 2)) == nil)
        #expect(s.chosenDeal(for: ShoppingItem(id: 1, owner: "me", name: "a")) == nil)
    }

    // MARK: Payments

    @Test func paymentBadgeStates() {
        let hold = VisaPaymentBadge(visa(1, deal: 1, .pending))
        #expect(hold.state == .hold && hold.simulated && hold.railLabel == "SIMULATED")
        let paid = VisaPaymentBadge(visa(2, deal: 1, .settled, simulated: false))
        #expect(paid.state == .paid && paid.railLabel == "SANDBOX")
        #expect(VisaPaymentBadge(visa(3, deal: 1, .failed)).state == .failed)
    }

    @Test func visaPaymentsOnlyForThatDeal() {
        var s = SyncSnapshot(me: "me")
        s.payments = [
            visa(1, deal: 7, .failed, at: 0),
            visa(2, deal: 7, .pending, at: 10),
            visa(3, deal: 8, .settled),
            Payment(id: 4, owner: "me", agent: "buy", purpose: "x402", payee: "p", amountUsdMicros: 1, simulated: true,
                    refTable: "deal", refId: 7),
            Payment(id: 5, owner: "me", agent: "buy", rail: .visa, purpose: "item", payee: "p", amountUsdMicros: 1,
                    simulated: true, refTable: "item", refId: 7),
        ]
        #expect(s.visaPayments(for: 7).map(\.id) == [2, 1])
        #expect(s.visaPayment(for: 7)?.id == 2) // hold beats an older failure
        s.payments.append(visa(6, deal: 7, .settled, at: 5))
        #expect(s.visaPayment(for: 7)?.id == 6) // settled beats everything
        #expect(s.visaPayment(for: 9) == nil)
    }

    // MARK: Checkout state

    @Test func checkoutStateWalksTheFlow() {
        var s = SyncSnapshot(me: "me")
        var item = ShoppingItem(id: 1, owner: "me", name: "Sofa")
        #expect(s.checkout(for: item) == .findingDeals)

        s.deals = [deal(10, cents: 40_000), deal(11, source: "fb"), deal(12, fraud: 0.9)]
        #expect(s.checkout(for: item) == .chooseDeal)

        item.chosenDealId = 11
        #expect(s.checkout(for: item) == .messageSeller(s.deals[1]))
        item.chosenDealId = 12
        #expect(s.checkout(for: item) == .fraudBlocked(s.deals[2]))

        item.chosenDealId = 10
        #expect(s.checkout(for: item) == .checkingOut(s.deals[0]))
        var approval = Approval(id: 5, owner: "me", kind: .purchase, refId: 10, amountCents: 40_000, summary: "Buy")
        s.approvals = [
            approval,
            Approval(id: 6, owner: "me", kind: .listing, refId: 10, amountCents: 1, summary: "x"),
            // A purchase approval for a deal that isn't synced stays in the #12 inbox only.
            Approval(id: 7, owner: "me", kind: .purchase, refId: 999, amountCents: 1, summary: "y"),
            // Not the chosen deal.
            Approval(id: 8, owner: "me", kind: .purchase, refId: 11, amountCents: 1, summary: "z"),
        ]
        #expect(s.pendingPurchaseApprovals.isEmpty) // item not on the list yet
        s.shoppingItems = [item]
        #expect(s.checkout(for: item) == .needsApproval(approval))
        #expect(s.pendingPurchaseApprovals.map(\.id) == [5])
        approval.status = .denied
        s.approvals[0] = approval
        #expect(s.checkout(for: item) == .notApproved(approval))
        approval.status = .approved
        s.approvals[0] = approval
        #expect(s.checkout(for: item) == .checkingOut(s.deals[0]))
        // An approval for a different amount doesn't clear the purchase.
        var stale = approval
        stale.amountCents = 39_000
        s.approvals[0] = stale
        #expect(s.checkout(for: item) == .notApproved(stale))
        s.approvals[0] = approval

        #expect(!s.hasPendingVisaPayment(for: item))
        let hold = visa(20, deal: 10, .pending)
        s.payments = [hold]
        #expect(s.checkout(for: item) == .payment(hold))
        #expect(s.hasPendingVisaPayment(for: item))
        s.payments = [visa(21, deal: 10, .failed)]
        #expect(!s.hasPendingVisaPayment(for: item))
    }

    @Test func sampleBadgeIsSeparateFromReplay() {
        let sample = deal(1, seller: "IKEA · new · ships · score 0.71 · sample data")
        #expect(sample.isSample && !sample.isReplay)
        #expect(sample.sellerDetails == "IKEA · new · ships · score 0.71")
        #expect(!deal(2, seller: "FB · good · cached replay").isSample)
    }

    // MARK: Fixtures

    @Test func demoHasItemsWithThreeDealsAPendingApprovalAndASimulatedSettledPayment() {
        let s = DemoFixtures.demo(owner: "me")
        #expect(s.myShoppingItems.count >= 3)
        for item in s.myShoppingItems { #expect(s.deals(for: item.id).count >= 3) }
        #expect(s.deals.allSatisfy { $0.isSample })
        #expect(s.pendingPurchaseApprovals.count == 1)
        let states = s.myShoppingItems.map { s.checkout(for: $0) }
        #expect(states.contains { if case .needsApproval = $0 { true } else { false } })
        #expect(states.contains(.chooseDeal))
        let paid = s.payments.filter { $0.rail == .visa && $0.status == .settled }
        #expect(paid.count == 1)
        #expect(paid.allSatisfy { $0.simulated })
        #expect(states.contains { if case .payment(let p) = $0 { p.simulated && p.status == .settled } else { false } })
        // Inventory fixtures are untouched.
        #expect(s.items.map(\.id) == DemoFixtures.inventory(owner: "me").items.map(\.id))
    }

    // MARK: Fixture reducers

    @Test func addAndRemoveShoppingItem() async throws {
        let backend = try await connectedDemo()
        try await backend.addShoppingItem(name: "Rug", category: "decor", reason: "Bare floors")
        var s = await latest(backend)
        let rug = try #require(s.myShoppingItems.first { $0.name == "Rug" })
        #expect(rug.status == .open && rug.chosenDealId == nil && rug.reason == "Bare floors")
        #expect(!s.shoppingItems.dropLast().contains { $0.id == rug.id })
        try await backend.removeShoppingItem(shoppingItemId: rug.id)
        s = await latest(backend)
        #expect(!s.shoppingItems.contains { $0.id == rug.id })
        try await backend.removeShoppingItem(shoppingItemId: 9_999) // no-op, like the module
    }

    @Test func choosingACheapCardDealChecksOutSimulated() async throws {
        let backend = try await connectedDemo()
        try await backend.chooseDeal(shoppingItemId: 52, dealId: 74)
        let s = await latest(backend)
        let item = try #require(s.shoppingItems.first { $0.id == 52 })
        #expect(item.chosenDealId == 74 && item.status == .bought)
        let p = try #require(s.visaPayment(for: 74))
        #expect(p.simulated && p.status == .settled && p.amountUsdMicros == 7_999 * 10_000)
    }

    @Test func choosingAnExpensiveDealAsksForApprovalThenApprovingPays() async throws {
        let backend = try await connectedDemo()
        try await backend.chooseDeal(shoppingItemId: 52, dealId: 75)
        var s = await latest(backend)
        let approval = try #require(s.purchaseApproval(for: 75))
        #expect(approval.isPending && approval.amountCents == 22_999)
        #expect(s.visaPayment(for: 75) == nil)

        try await backend.decideApproval(approvalId: approval.id, status: .approved)
        s = await latest(backend)
        #expect(s.visaPayment(for: 75)?.status == .settled)
        #expect(s.shoppingItems.first { $0.id == 52 }?.status == .bought)
    }

    @Test func approvingTheSeededSofaPaysAndDenyingDoesNot() async throws {
        let approved = try await connectedDemo()
        try await approved.decideApproval(approvalId: 85, status: .approved)
        #expect(await latest(approved).visaPayment(for: 71)?.simulated == true)

        let denied = try await connectedDemo()
        try await denied.decideApproval(approvalId: 85, status: .denied)
        let s = await latest(denied)
        #expect(s.visaPayment(for: 71) == nil)
        let sofa = try #require(s.shoppingItems.first { $0.id == 51 })
        let approval = try #require(s.approvals.first { $0.id == 85 })
        #expect(s.checkout(for: sofa) == .notApproved(approval))
    }

    @Test func marketplaceAndFlaggedDealsAreNeverPaid() async throws {
        let backend = try await connectedDemo()
        try await backend.chooseDeal(shoppingItemId: 52, dealId: 76) // craigslist, fraud 0.81
        let s = await latest(backend)
        #expect(s.visaPayments(for: 76).isEmpty && s.purchaseApproval(for: 76) == nil)
        #expect(s.shoppingItems.first { $0.id == 52 }?.status == .found)
    }

    @Test func chooseDealRejectsMismatches() async throws {
        let backend = try await connectedDemo()
        await #expect(throws: FixtureBackend.Failure.dealDoesNotMatchItem) {
            try await backend.chooseDeal(shoppingItemId: 52, dealId: 60)
        }
        await #expect(throws: FixtureBackend.Failure.noSuchShoppingItem) {
            try await backend.chooseDeal(shoppingItemId: 9_999, dealId: 60)
        }
    }
}
