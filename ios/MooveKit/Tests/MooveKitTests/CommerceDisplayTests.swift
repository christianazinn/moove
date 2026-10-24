import Foundation
import Testing
@testable import MooveKit

@Suite struct CommerceDisplayTests {
    // MARK: Screen state

    @Test func screenStateMapsStatusWhenThereAreNoRows() {
        #expect(CommerceScreenState(status: .connected, hasRows: false) == .empty)
        #expect(CommerceScreenState(status: .connecting, hasRows: false) == .loading)
        #expect(CommerceScreenState(status: .disconnected, hasRows: false) == .offline("Not connected to the backend."))
        #expect(CommerceScreenState(status: .failed("timed out"), hasRows: false) == .offline("timed out"))
        #expect(CommerceScreenState(status: .failed(""), hasRows: false) == .offline("Couldn't reach the backend."))
        if case .offline(let why) = CommerceScreenState(status: .reconnecting(attempt: 2), hasRows: false) {
            #expect(why.contains("attempt 2"))
        } else {
            Issue.record("reconnecting with no rows should be offline")
        }
    }

    @Test func rowsAlwaysShowEvenWhenOffline() {
        for status: SyncStatus in [.connected, .connecting, .disconnected, .failed("x"), .reconnecting(attempt: 1)] {
            #expect(CommerceScreenState(status: status, hasRows: true) == .content)
        }
        #expect(CommerceScreenState.loading.title == "Connecting…")
        #expect(CommerceScreenState.offline("x").title == "Can't reach the backend")
        #expect(CommerceScreenState.empty.title == nil)
    }

    // MARK: Formatting and spoken labels

    @Test func centsFormat() {
        #expect(CentsFormat.usd(41_000) == "$410")
        #expect(CentsFormat.usd(42_999) == "$429.99")
        #expect(CentsFormat.usd(150_000) == "$1,500")
        #expect(CentsFormat.usd(1_205) == "$12.05")
        #expect(CentsFormat.usd(0) == "$0")
    }

    @Test func paymentSummaryLeadsWithAmountSimulatedAndStatus() {
        let sim = Payment(id: 1, owner: "me", agent: "pricing", purpose: "Comps", payee: "simulated",
                          amountUsdMicros: 10_000, status: .settled, simulated: true)
        #expect(sim.accessibilitySummary.hasPrefix("$0.01, simulated, settled."))
        #expect(sim.accessibilitySummary.contains("Pricing agent"))
        #expect(sim.railTag == "SIMULATED")

        let real = Payment(id: 2, owner: "me", agent: "pricing", purpose: "Comps", payee: "0x", amountUsdMicros: 10_000,
                           txHash: "0xabc", status: .settled, simulated: false)
        #expect(real.accessibilitySummary.hasPrefix("$0.01, on-chain testnet USDC, settled."))
        #expect(real.railTag == "BASE SEPOLIA")

        let card = Payment(id: 3, owner: "me", agent: "buy", rail: .visa, purpose: "Sofa", payee: "m",
                           amountUsdMicros: 17_999 * 10_000, status: .failed, simulated: false)
        #expect(card.accessibilitySummary.hasPrefix("$179.99, Visa sandbox, failed."))
        #expect(card.railTag == "VISA SANDBOX")
    }

    @Test func agentDisplayName() {
        #expect("pricing".agentDisplayName == "Pricing agent")
        #expect("".agentDisplayName == "Agent")
    }

    @Test func simulatedListingIsNeverLiveOnEbay() {
        #expect(ListingStatus.posted.displayLabel(simulated: true) == "Posted (simulated)")
        #expect(ListingStatus.posted.displayLabel(simulated: false) == "Live on eBay")
        #expect(ListingStatus.sold.displayLabel(simulated: true) == "Sold (simulated)")
        #expect(ListingStatus.failed.displayLabel(simulated: true) == "Failed to post")
        for status in ListingStatus.allCases {
            #expect(!status.displayLabel(simulated: true).contains("eBay"))
        }
        let sim = Listing(id: 1, owner: "me", itemId: 1, title: "Desk", description: "", priceCents: 3_500,
                          status: .posted, externalId: "123", simulated: true)
        #expect(sim.displayExternalId == nil)
        #expect(sim.accessibilitySummary == "Desk, $35, posted (simulated), simulated listing, not on eBay")
        var real = sim
        real.simulated = false
        #expect(real.displayExternalId == "123")
        #expect(real.accessibilitySummary == "Desk, $35, live on ebay")
    }

    @Test func approvalOutcomesAndSummary() {
        let a = Approval(id: 1, owner: "me", kind: .listing, refId: 1, amountCents: 41_000, summary: "Sell chair for $410")
        #expect(a.outcomeText == nil)
        #expect(a.accessibilitySummary == "Sell, $410, waiting on you. Sell chair for $410")
        var denied = a
        denied.status = .denied
        #expect(denied.outcomeText == "You denied it. The listing wasn't posted.")
        denied.kind = .purchase
        #expect(denied.outcomeText == "You denied it. Nothing was bought.")
        #expect(denied.accessibilitySummary.hasPrefix("Buy, $410, denied."))
    }

    @Test func dealSummaryAndFraudBlockedIsNotChoosable() {
        let fraud = Deal(id: 1, owner: "me", shoppingItemId: 1, source: "craigslist", title: "Aeron", priceCents: 9_500,
                         sellerInfo: "Craigslist · sample data", fraudScore: 0.81)
        #expect(!fraud.isChoosable)
        #expect(fraud.accessibilitySummary == "$95, Aeron, from craigslist, message seller, likely fraud 0.81, sample data, not a live listing")
        let clean = Deal(id: 2, owner: "me", shoppingItemId: 1, source: "target", title: "Chair", priceCents: 7_999)
        #expect(clean.isChoosable)
        #expect(clean.accessibilitySummary == "$79.99, Chair, from target, Visa checkout, not fraud-screened yet")
    }

    @Test func visaBadgeSummary() {
        let p = Payment(id: 1, owner: "me", agent: "buy", rail: .visa, purpose: "", payee: "", amountUsdMicros: 1,
                        status: .settled, simulated: true)
        #expect(VisaPaymentBadge(p).accessibilitySummary(amount: "$179.99") == "$179.99, simulated, no money moved, paid")
    }

    // MARK: Problems

    @Test func latestProblemPicksTheNewestErrorOrRefusalNote() {
        var s = SyncSnapshot(me: "me")
        let t0 = Date(timeIntervalSince1970: 1_000)
        s.agentEvents = [
            AgentEvent(id: 1, owner: "me", agent: "listing", kind: .error, message: "Posting failed: old", refTable: "listing", refId: 5, createdAt: t0),
            AgentEvent(id: 2, owner: "me", agent: "listing", kind: .error, message: "Posting failed: new", refTable: "listing", refId: 5, createdAt: t0.addingTimeInterval(5)),
            AgentEvent(id: 3, owner: "me", agent: "listing", kind: .plan, message: "Posting again", refTable: "listing", refId: 5, createdAt: t0.addingTimeInterval(9)),
            AgentEvent(id: 4, owner: "me", agent: "listing", kind: .approval, message: "Not posting: denied", refTable: "listing", refId: 6, createdAt: t0),
            AgentEvent(id: 5, owner: "me", agent: "buy", kind: .result, message: "No deals found for \"Rug\"", refTable: "shopping_item", refId: 7, createdAt: t0),
        ]
        #expect(s.latestProblem(refTable: "listing", refId: 5)?.id == 2)
        let failed = Listing(id: 5, owner: "me", itemId: 1, title: "", description: "", priceCents: 1, status: .failed)
        let rejected = Listing(id: 6, owner: "me", itemId: 1, title: "", description: "", priceCents: 1, status: .rejected)
        var posted = failed
        posted.status = .posted
        #expect(s.problem(for: failed) == "Posting failed: new")
        #expect(s.problem(for: rejected) == "Not posting: denied")
        #expect(s.problem(for: posted) == nil)
        #expect(s.dealSearchProblem(for: ShoppingItem(id: 7, owner: "me", name: "Rug")) == "No deals found for \"Rug\"")
        #expect(s.checkoutProblem(dealId: 99) == nil)
    }

    // MARK: Offline demo fixtures cover every commerce state

    @Test func demoCoversEveryCommerceScreenState() {
        let s = DemoFixtures.demo(owner: "me")

        // Spending: a real payment with a tx link, simulated ones without, a refusal, failures.
        let log = s.spendingLog()
        #expect(log.entries.contains { if case .refusal = $0 { true } else { false } })
        #expect(s.payments.contains { !$0.simulated && $0.explorerURL != nil })
        #expect(s.payments.filter(\.simulated).allSatisfy { $0.explorerURL == nil })
        #expect(s.payments.contains { $0.rail == .visa && $0.status == .failed && $0.simulated })

        // Listings: every group has a row, and the ones that didn't post say why.
        for status in [ListingStatus.awaitingApproval, .posted, .draft, .sold, .rejected, .failed] {
            #expect(s.listings.contains { $0.status == status }, "no \(status) listing")
        }
        for l in s.listings where l.status == .failed || l.status == .rejected {
            #expect(s.problem(for: l) != nil, "listing \(l.id) has no reason")
        }

        // Approvals: one pending listing and one pending purchase, both resolvable, plus a denial.
        let pending = s.pendingApprovals
        #expect(pending.count == 2)
        #expect(pending.contains { $0.kind == .listing && s.listing(for: $0) != nil })
        #expect(pending.contains { $0.kind == .purchase && s.deal(for: $0) != nil })
        #expect(s.decidedApprovals.contains { $0.status == .denied })

        // Shopping: a fraud-flagged deal, a failed checkout with a reason, a paid one, one to choose.
        #expect(s.deals.contains { $0.isFraudBlocked && !$0.isChoosable })
        let states = s.myShoppingItems.map { s.checkout(for: $0) }
        #expect(states.contains(.chooseDeal))
        let failed = states.compactMap { if case .payment(let p) = $0, p.status == .failed { p } else { nil } }
        #expect(failed.count == 1)
        #expect(s.checkoutProblem(dealId: failed[0].refId) != nil)

        // Every failed payment, Visa or x402, says why.
        for p in s.payments where p.status == .failed {
            #expect(s.failureReason(for: p) != nil, "payment \(p.id) has no reason")
        }
        #expect(s.payments.filter { $0.status != .failed }.allSatisfy { s.failureReason(for: $0) == nil })
    }

    @Test func failedCheckoutUnlocksChoosingAnotherDeal() async throws {
        let backend = FixtureBackend.demo(identity: "me")
        _ = try await backend.connect(token: nil)
        var it = backend.snapshots().makeAsyncIterator()
        let before = await it.next()!
        let rug = try #require(before.myShoppingItems.first { $0.name == "Area rug" })
        #expect(!before.isCheckoutLocked(rug))
        try await backend.chooseDeal(shoppingItemId: rug.id, dealId: 82)
        var after = backend.snapshots().makeAsyncIterator()
        let s = await after.next()!
        let item = try #require(s.myShoppingItems.first { $0.id == rug.id })
        #expect(item.status == .bought)
        #expect(s.visaPayment(for: 82)?.status == .settled)
        #expect(s.visaPayment(for: 82)?.simulated == true)
    }
}
