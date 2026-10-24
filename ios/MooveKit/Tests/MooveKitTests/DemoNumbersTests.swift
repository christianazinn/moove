import Foundation
import Testing
@testable import MooveKit

/// Judges see the Offline demo, so its numbers must agree across Spending, Listings, Shopping and
/// Summary. Every expected figure here is re-derived from the fixture rows, independently of the
/// `SpendingLog` / `MoveSummary` math, and checked against what the screens compute.
@Suite struct DemoNumbersTests {
    private let me: IdentityHex = "me"

    private func connectedDemo() async throws -> FixtureBackend {
        let backend = FixtureBackend.demo(identity: me)
        _ = try await backend.connect(token: nil)
        return backend
    }

    private func latest(_ backend: FixtureBackend) async throws -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return try #require(await it.next())
    }

    // MARK: Independent derivations from the rows

    /// Payments that cost something (failed ones didn't).
    private func counted(_ s: SyncSnapshot) -> [Payment] { s.payments.filter { $0.status != .failed } }

    private func sum(_ payments: [Payment]) -> Int64 { payments.reduce(0) { $0 + $1.amountUsdMicros } }

    /// Sold: each sell item with a sold listing, at that listing's price.
    private func soldCents(_ s: SyncSnapshot) -> Int64 {
        s.items.filter { $0.disposition == .sell }.compactMap { item in
            s.listings.first { $0.itemId == item.id && $0.status == .sold }?.priceCents
        }.reduce(0, +)
    }

    /// Still selling: each unsold sell item at its live (posted or awaiting approval) listing's
    /// price, or at its estimate when it has no live listing (drafts, rejected, failed).
    private func stillSellingCents(_ s: SyncSnapshot) -> Int64 {
        s.items.filter { $0.disposition == .sell }.compactMap { item -> Int64? in
            let mine = s.listings.filter { $0.itemId == item.id }
            if mine.contains(where: { $0.status == .sold }) { return nil }
            if let live = mine.first(where: { $0.status == .posted || $0.status == .awaitingApproval }) { return live.priceCents }
            return item.estValueCents
        }.reduce(0, +)
    }

    /// Checks one snapshot's Spending totals and Summary Money block against the rows.
    private func checkMoneyAgrees(_ s: SyncSnapshot) {
        let log = s.spendingLog()
        let summary = MoveSummary(snapshot: s)
        let paid = counted(s)

        // Spending totals row.
        #expect(log.realSpentUsdMicros == sum(paid.filter { !$0.simulated }))
        #expect(log.simulatedSpentUsdMicros == sum(paid.filter(\.simulated)))
        #expect(log.budgets.map(\.refusals).reduce(0, +) == s.agentEvents.filter(\.isRefusal).count)

        // Summary Money block, against the rows and against Spending.
        #expect(summary.soldCents == soldCents(s))
        #expect(summary.pendingSalesCents == stillSellingCents(s))
        #expect(summary.spentMicros == sum(paid))
        #expect(summary.spentMicros == log.totalSpentUsdMicros)
        #expect(summary.netMicros == (soldCents(s) + stillSellingCents(s)) * 10_000 - sum(paid))

        // One line per rail that has spend, matching Spending's per-rail totals and simulated share.
        let rails = Set(paid.map(\.rail))
        #expect(Set(summary.rails.map(\.rail)) == Set(rails.map(\.rawValue)))
        for rail in rails {
            let line = summary.rails.first { $0.rail == rail.rawValue }
            #expect(line?.micros == log.totalsByRail[rail])
            #expect(line?.micros == sum(paid.filter { $0.rail == rail }))
            #expect(line?.simulatedMicros == sum(paid.filter { $0.rail == rail && $0.simulated }))
        }
        #expect(summary.rails.map(\.micros) == summary.rails.map(\.micros).sorted(by: >))

        // The Simulated tag: the screen shows it when any money is simulated (fixture rows exist, so
        // the "demo activity" stand-ins are never used).
        #expect(!s.payments.isEmpty)
        let anySimulated = paid.contains(where: \.simulated)
            || s.listings.contains { $0.simulated && [.sold, .posted, .awaitingApproval].contains($0.status) }
        #expect(summary.hasSimulatedMoney == anySimulated)
        #expect(summary.hasSimulatedMoney)
    }

    /// Row-level rules that must hold before and after the scripted demo actions.
    private func checkRows(_ s: SyncSnapshot) {
        // Only the one real $0.01 x402 payment is not simulated; everything else is labeled.
        let real = s.payments.filter { !$0.simulated }
        #expect(real.map(\.id) == [500])
        #expect(real.first?.rail == .x402)
        #expect(real.first?.amountUsdMicros == 10_000)
        #expect(real.first?.status == .settled)
        #expect(real.first?.txHash == DemoFixtures.realX402TxHash)
        #expect(DemoFixtures.realX402TxHash.hasPrefix("0xc7942646") && DemoFixtures.realX402TxHash.hasSuffix("136c"))
        for p in s.payments where p.simulated { #expect(p.txHash == nil && p.explorerURL == nil, "payment \(p.id)") }
        for p in s.payments where p.rail == .visa { #expect(p.simulated, "visa payment \(p.id)") }
        for l in s.listings { #expect(l.simulated, "listing \(l.id)") }
        for d in s.deals { #expect(d.isSample || d.isReplay, "deal \(d.id) isn't labeled sample/replay") }

        // Every approval points at a row that exists, for the same amount.
        for a in s.approvals {
            switch a.kind {
            case .listing:
                let listing = s.listings.first { $0.id == a.refId }
                #expect(listing != nil, "approval \(a.id) -> listing \(a.refId)")
                #expect(listing?.priceCents == a.amountCents, "approval \(a.id) amount")
            case .purchase:
                let deal = s.deals.first { $0.id == a.refId }
                #expect(deal != nil, "approval \(a.id) -> deal \(a.refId)")
                #expect(deal?.priceCents == a.amountCents, "approval \(a.id) amount")
                // The buy agent only asks for deals it could pay by card.
                #expect(deal?.supportsCardCheckout == true, "approval \(a.id) is for a deal the agent can't buy")
            }
        }

        // Every chosen deal belongs to its shopping item; every Visa payment points at a deal.
        for item in s.shoppingItems {
            if let id = item.chosenDealId {
                #expect(s.deals.first { $0.id == id }?.shoppingItemId == item.id, "shopping item \(item.id) -> deal \(id)")
            }
        }
        for p in s.payments where p.rail == .visa {
            #expect(p.refTable == "deal" && s.deals.contains { $0.id == p.refId }, "visa payment \(p.id)")
        }

        // Bought items have a settled payment for their chosen deal, and anything paid is Bought.
        // The docs and screens quote a $100 limit, the module default; the fixture user must have it.
        let threshold = s.users.first { $0.identity == s.me }?.approvalThresholdCents
        #expect(threshold == 10_000)
        for item in s.shoppingItems {
            let deal = s.chosenDeal(for: item)
            let settled = deal.map { d in s.visaPayments(for: d.id).contains { $0.status == .settled } } ?? false
            #expect((item.status == .bought) == settled, "shopping item \(item.id)")
            // Over the threshold, a purchase only goes through with an approval for that price.
            if settled, let deal, let threshold, deal.priceCents > threshold {
                let approval = s.purchaseApproval(for: deal.id)
                #expect(approval?.status == .approved && approval?.amountCents == deal.priceCents, "shopping item \(item.id)")
            }
        }
    }

    // MARK: Tests

    @Test func spendingTotalsMatchTheDocs() {
        let s = DemoFixtures.demo(owner: me)
        let paid = counted(s)
        let log = s.spendingLog()
        let simX402 = sum(paid.filter { $0.simulated && $0.rail == .x402 })
        let simVisa = sum(paid.filter { $0.simulated && $0.rail == .visa })
        // docs/demo-commerce.md, Step 2.
        #expect(UsdMicros.format(log.realSpentUsdMicros) == "$0.01")
        #expect(UsdMicros.format(simX402) == "$0.015")
        #expect(UsdMicros.format(simVisa) == "$179.99")
        #expect(log.simulatedSpentUsdMicros == simX402 + simVisa)
        #expect(UsdMicros.format(log.simulatedSpentUsdMicros) == "$180.005")
        #expect(log.budgets.map(\.refusals).reduce(0, +) == 1)
        checkMoneyAgrees(s)
    }

    @Test func fixtureRowsAreConsistent() {
        checkRows(DemoFixtures.demo(owner: me))
    }

    @Test func summaryCountsMatchTheInventory() {
        let s = DemoFixtures.demo(owner: me)
        let summary = MoveSummary(snapshot: s)
        #expect(summary.itemCount == s.items.count)
        for d in Disposition.allCases {
            #expect((summary.counts[d] ?? 0) == s.items.filter { $0.disposition == d }.count, "\(d)")
        }
        #expect(summary.counts.values.reduce(0, +) == s.items.count)
        #expect(summary.needsYou == s.items.filter { $0.disposition == .undecided || $0.maybeSentimental }.count)
        #expect(summary.divertedItems == s.items.filter { $0.disposition == .sell || $0.disposition == .donate }.count)
    }

    @Test func summaryMoneyBlock() {
        let s = DemoFixtures.demo(owner: me)
        checkMoneyAgrees(s)
        let summary = MoveSummary(snapshot: s)
        // Every rail line is tagged: Visa all simulated, x402 partly (the real $0.01 isn't).
        let visa = summary.rails.first { $0.rail == "visa" }
        let x402 = summary.rails.first { $0.rail == "x402" }
        #expect(visa?.simulatedMicros == visa?.micros)
        #expect((x402?.simulatedMicros ?? 0) > 0 && x402?.simulatedMicros != x402?.micros)
        #expect(summary.rails.map(\.rail) == ["visa", "x402"])
    }

    @Test func scriptedDemoKeepsSpendingAndSummaryInAgreement() async throws {
        let backend = try await connectedDemo()
        let before = try await latest(backend)
        let threshold = try #require(before.users.first { $0.identity == me }?.approvalThresholdCents)

        // Step 3: approve the $410 Aeron listing.
        let aeron = try #require(before.pendingApprovals.first { $0.kind == .listing })
        #expect(aeron.refId == 200)
        try await backend.decideApproval(approvalId: aeron.id, status: .approved)

        // Step 4: choose the Target chair (under the threshold, so it's paid right away).
        let chairItem = try #require(before.shoppingItems.first { $0.name == "Desk chair" })
        let chair = try #require(before.deals(for: chairItem.id).first { $0.source == "target" })
        #expect(chair.priceCents <= threshold)
        try await backend.chooseDeal(shoppingItemId: chairItem.id, dealId: chair.id)

        // Step 5: approve the sofa.
        let sofa = try #require(before.pendingApprovals.first { $0.kind == .purchase })
        let sofaDeal = try #require(before.deals.first { $0.id == sofa.refId })
        try await backend.decideApproval(approvalId: sofa.id, status: .approved)

        let after = try await latest(backend)
        #expect(after.pendingApprovals.isEmpty)
        #expect(after.listings.first { $0.id == 200 }?.status == .posted)
        #expect(after.shoppingItems.first { $0.id == chairItem.id }?.status == .bought)
        #expect(after.shoppingItems.first { $0.id == sofaDeal.shoppingItemId }?.status == .bought)

        // Exactly two new payments, the chair and the sofa, both simulated Visa.
        let new = after.payments.filter { p in !before.payments.contains { $0.id == p.id } }
        #expect(new.map(\.refId).sorted() == [chair.id, sofaDeal.id].sorted())
        #expect(new.allSatisfy { $0.rail == .visa && $0.simulated && $0.status == .settled })
        #expect(sum(new) == (chair.priceCents + sofaDeal.priceCents) * 10_000)

        // Spending grows by exactly the new simulated spend; Summary agrees with it.
        let logBefore = before.spendingLog(), logAfter = after.spendingLog()
        #expect(logAfter.realSpentUsdMicros == logBefore.realSpentUsdMicros)
        #expect(logAfter.simulatedSpentUsdMicros == logBefore.simulatedSpentUsdMicros + sum(new))
        // Approving the Aeron moves it from awaiting approval to posted: still selling, same price.
        #expect(MoveSummary(snapshot: after).pendingSalesCents == MoveSummary(snapshot: before).pendingSalesCents)
        #expect(MoveSummary(snapshot: after).netMicros == MoveSummary(snapshot: before).netMicros - sum(new))
        checkMoneyAgrees(after)
        checkRows(after)
    }
}
