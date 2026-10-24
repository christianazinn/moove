import Foundation
import Testing
@testable import MooveKit

@Suite struct MoveSummaryTests {
    let items = DemoFixtures.inventory(owner: "me").items

    @Test func countsMatchTheInventory() {
        let s = MoveSummary(items: items, sales: [], spend: [], events: [])
        #expect(s.itemCount == items.count)
        for d in Disposition.allCases {
            #expect((s.counts[d] ?? 0) == items.filter { $0.disposition == d }.count)
        }
        #expect(s.needsYou == items.filter(\.needsUser).count)
        #expect(s.counts.values.reduce(0, +) == items.count)
    }

    @Test func estimatedSalesComeFromSellItems() {
        let sales = MoveSummary.estimatedSales(from: items)
        let expected = items.filter { $0.disposition == .sell }.compactMap(\.estValueCents).reduce(0, +)
        let s = MoveSummary(items: items, sales: sales, spend: [], events: [])
        #expect(s.pendingSalesCents == expected)
        #expect(s.soldCents == 0)
        #expect(s.netMicros == expected * 10_000)
        #expect(!s.hasSimulatedMoney)
    }

    @Test func furthestStageWinsPerItem() {
        let sales: [MoveSummary.Sale] = [
            .init(itemId: 11, priceCents: 42_000, stage: .estimated, simulated: false),
            .init(itemId: 11, priceCents: 41_000, stage: .listed, simulated: true),
            .init(itemId: 20, priceCents: 2_000, stage: .estimated, simulated: false),
            .init(itemId: 20, priceCents: 1_800, stage: .sold, simulated: true),
        ]
        let s = MoveSummary(items: items, sales: sales, spend: [], events: [])
        #expect(s.soldCents == 1_800)
        #expect(s.pendingSalesCents == 41_000)
        #expect(s.hasSimulatedMoney)
    }

    @Test func listingsOverrideEstimates() {
        let snap = DemoFixtures.inventory(owner: "me")
        let sales = MoveSummary.estimatedSales(from: snap.items) + MoveSummary.sales(from: snap.listings)
        let s = MoveSummary(items: snap.items, sales: sales, spend: [], events: [])
        let sold = snap.listings.filter { $0.status == .sold }.reduce(0) { $0 + $1.priceCents }
        #expect(s.soldCents == sold)
        // Drafts fall back to the item's estimate.
        let drafts = snap.listings.filter { $0.status == .draft }.map(\.itemId)
        let draftEstimates = snap.items.filter { drafts.contains($0.id) }.compactMap(\.estValueCents).reduce(0, +)
        let listed = snap.listings.filter { $0.status == .posted || $0.status == .awaitingApproval }.reduce(0) { $0 + $1.priceCents }
        let unlisted = snap.items.filter { item in item.disposition == .sell && !snap.listings.contains { $0.itemId == item.id } }
            .compactMap(\.estValueCents).reduce(0, +)
        #expect(s.pendingSalesCents == listed + draftEstimates + unlisted)
    }

    @Test func spendIsSplitByRail() {
        let s = MoveSummary(items: items, sales: [], spend: SummaryDemo.spend, events: [])
        #expect(s.spentMicros == SummaryDemo.spend.reduce(0) { $0 + $1.amountMicros })
        #expect(s.rails.map(\.rail) == ["visa", "x402"])
        #expect(s.rails.first { $0.rail == "x402" }?.micros == 80_000)
        #expect(s.rails.allSatisfy { $0.simulatedMicros == $0.micros })
        #expect(s.netMicros == -s.spentMicros)
    }

    @Test func realPaymentsAndEventsFromFixtures() {
        let snap = DemoFixtures.inventory(owner: "me")
        #expect(!snap.payments.isEmpty && !snap.agentEvents.isEmpty)
        let spend = MoveSummary.spend(from: snap.payments)
        let s = MoveSummary(items: snap.items, sales: [], spend: spend, events: MoveSummary.events(from: snap.agentEvents))
        let paid = snap.payments.filter { $0.status != .failed }.reduce(0) { $0 + $1.amountUsdMicros }
        #expect(s.spentMicros == paid)
        #expect(spend.count == snap.payments.filter { $0.status != .failed }.count)
        #expect(s.agents.reduce(0) { $0 + $1.steps } == snap.agentEvents.count)
    }

    @Test func agentActivity() {
        let events = SummaryDemo.events(endingAt: Date(timeIntervalSince1970: 1_000_000))
        let s = MoveSummary(items: items, sales: [], spend: [], events: events, timelineLimit: 3)
        #expect(s.agents.reduce(0) { $0 + $1.steps } == events.count)
        #expect(s.agents.first.map { ["pricing", "listing", "buy"].contains($0.agent) } == true)
        #expect(s.timeline.count == 3)
        #expect(s.timeline.first?.message == events.last?.message) // newest first
    }

    @Test func impact() {
        let s = MoveSummary(items: items, sales: [], spend: [], events: [])
        let diverted = items.filter { $0.disposition == .sell || $0.disposition == .donate }
        #expect(s.divertedItems == diverted.count)
        #expect(s.divertedKg > 20 && s.divertedKg < 300)
        #expect(abs(s.keptVolumeM3 - items.filter { $0.disposition == .keep }.reduce(0) { $0 + $1.volumeM3 }) < 1e-9)
    }

    @Test func weightEstimateIsSane() {
        let bed = items.first { $0.category == "bed" }!
        let lamp = items.first { $0.category == "lamp" }!
        #expect(MoveSummary.estimatedKg(bed) > MoveSummary.estimatedKg(lamp))
        #expect(MoveSummary.estimatedKg(lamp) >= 1)
    }

    @Test func emptyMoveIsAllZeros() {
        let s = MoveSummary(items: [], sales: [], spend: [], events: [])
        #expect(s.itemCount == 0 && s.netMicros == 0 && s.divertedKg == 0 && s.rails.isEmpty && s.timeline.isEmpty)
    }
}
