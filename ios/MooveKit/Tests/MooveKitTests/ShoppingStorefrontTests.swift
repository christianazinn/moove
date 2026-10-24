import Foundation
import Testing
@testable import MooveKit

/// The Shopping storefront (hero, bento card sizes, deal shelves) on the Offline demo and on edge cases.
@Suite struct ShoppingStorefrontTests {
    private let demo = DemoFixtures.demo(owner: "me").storefront()

    private func tile(_ id: UInt64, status: ShoppingStatus = .found) -> StorefrontTile {
        StorefrontTile(item: ShoppingItem(id: id, owner: "me", name: "i\(id)", status: status), size: .small,
                       featured: nil, dealCount: 0, badge: StorefrontBadge("x", .neutral), ribbon: nil)
    }

    // MARK: Hero

    @Test func heroCountsWhatIsStillNeededAndPicksTheBiggestLowRiskSaving() throws {
        #expect(demo.hero.stillNeeded == 4)
        #expect(demo.hero.headline == "Your new place still needs 4 things")
        let pick = try #require(demo.hero.pick)
        #expect(pick.itemName == "Desk chair")
        #expect(pick.deal.id == 74)
        #expect(pick.deal.formattedPrice == "$79.99")
        #expect(pick.referenceCents == 22_999)
        #expect(pick.savingsPercent == 65)
        #expect(pick.savingsText == "Save $150 vs $229.99")
    }

    @Test func heroHeadlineForEmptyAndDoneLists() {
        #expect(SyncSnapshot(me: "me").storefront().hero.headline == "Your new place's list is empty")
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [ShoppingItem(id: 1, owner: "me", name: "Lamp", status: .bought)]
        let hero = s.storefront().hero
        #expect(hero.headline == "Everything on the list is bought")
        #expect(hero.pick == nil)
        s.shoppingItems.append(ShoppingItem(id: 2, owner: "me", name: "Rug"))
        #expect(s.storefront().hero.headline == "Your new place still needs 1 thing")
    }

    @Test func heroNeverPicksARiskyOrBlockedDeal() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [ShoppingItem(id: 1, owner: "me", name: "Sofa")]
        s.deals = [
            Deal(id: 10, owner: "me", shoppingItemId: 1, source: "ikea", title: "a", priceCents: 50_000, fraudScore: 0.02),
            Deal(id: 11, owner: "me", shoppingItemId: 1, source: "fb", title: "b", priceCents: 9_000, fraudScore: 0.4),
            Deal(id: 12, owner: "me", shoppingItemId: 1, source: "craigslist", title: "c", priceCents: 1_000, fraudScore: 0.9),
        ]
        // The only low-risk deal is also the priciest, so there's no honest saving to headline.
        #expect(s.storefront().hero.pick == nil)
    }

    // MARK: Bento

    @Test func demoCardSizesAndOrder() {
        let tiles = demo.tiles
        #expect(tiles.map(\.item.name) == ["Sofa", "Desk chair", "Area rug", "Dining table", "Mattress"])
        #expect(tiles.map(\.size) == [.feature, .tall, .small, .small, .wide])
        #expect(demo.rows.count == 3)
        if case .tall(_, _, let leading) = demo.rows[1] { #expect(leading) } else { Issue.record("row 2 isn't a tall row") }
    }

    @Test func demoBadgesAndRibbons() {
        let byName = Dictionary(uniqueKeysWithValues: demo.tiles.map { ($0.item.name, $0) })
        #expect(byName["Sofa"]?.badge.label == "Needs approval")
        #expect(byName["Desk chair"]?.badge.label == "3 deals")
        #expect(byName["Area rug"]?.badge.label == "Checkout failed")
        #expect(byName["Dining table"]?.badge.label == "Message seller")
        #expect(byName["Mattress"]?.badge.label == "Bought (simulated)")
        #expect(byName["Desk chair"]?.ribbon == .bestDeal)
        #expect(byName["Dining table"]?.ribbon == .localPickup)
        #expect(byName["Mattress"]?.ribbon == nil)
        // A card shows the chosen deal's price when there is one.
        #expect(byName["Sofa"]?.featured?.deal.id == 71)
        #expect(byName["Desk chair"]?.featured?.deal.id == 74)
    }

    @Test func bentoPatternIsDeterministicAndNeverLeavesAHalfRow() {
        for n in 0...12 {
            let tiles = (0..<n).map { tile(UInt64($0)) }
            let rows = SyncSnapshot.bentoRows(tiles)
            #expect(rows.flatMap(\.tiles).map(\.id) == tiles.map(\.id), "n=\(n) keeps order")
            #expect(rows == SyncSnapshot.bentoRows(tiles))
            if n > 0 { #expect(rows.first?.tiles.first?.size == .feature) }
            for row in rows {
                switch row {
                case .single(let t): #expect(t.size == .feature || t.size == .wide)
                case .pair(let a, let b): #expect(a.size == .small && b.size == .small)
                case .tall(let t, let stack, _): #expect(t.size == .tall && stack.count == 2 && stack.allSatisfy { $0.size == .small })
                }
            }
        }
        // Tall rows alternate sides: 1 feature + tall(3) + wide + pair + tall(3).
        let rows = SyncSnapshot.bentoRows((0..<10).map { tile(UInt64($0)) })
        let sides = rows.compactMap { row -> Bool? in if case .tall(_, _, let l) = row { return l } else { return nil } }
        #expect(sides == [true, false])
    }

    @Test func itemsThatNeedTheUserComeFirstAndBoughtLast() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [
            ShoppingItem(id: 1, owner: "me", name: "Bought", status: .bought),
            ShoppingItem(id: 2, owner: "me", name: "Searching", status: .searching),
            ShoppingItem(id: 3, owner: "me", name: "Pick", status: .found),
        ]
        s.deals = [Deal(id: 30, owner: "me", shoppingItemId: 3, source: "target", title: "t", priceCents: 1_000)]
        let tiles = s.storefront().tiles
        #expect(tiles.map(\.item.name) == ["Pick", "Searching", "Bought"])
        #expect(tiles.map(\.badge.label) == ["1 deal", "Finding deals…", "Bought"])
    }

    // MARK: Shelves

    @Test func demoShelves() throws {
        #expect(demo.shelves.map(\.title) == ["Best deals for your new place", "Under $100", "Local pickup", "Blocked for your safety"])
        let best = try #require(demo.shelves.first { $0.kind == .best })
        #expect(best.deals.map(\.itemName) == ["Desk chair", "Dining table", "Sofa", "Area rug"])
        #expect(!best.deals.contains { $0.deal.isFraudBlocked })
        let budget = try #require(demo.shelves.first { $0.kind == .budget })
        // The scam ($95) is blocked and the declined Target rug failed checkout, so neither is offered.
        #expect(budget.deals.map(\.deal.id) == [82, 74, 81])
        let local = try #require(demo.shelves.first { $0.kind == .local })
        #expect(local.deals.map(\.deal.id) == [79, 72])
        #expect(local.deals.map(\.distanceText) == ["7 mi", "4 mi"])
        let blocked = try #require(demo.shelves.first { $0.kind == .blocked })
        #expect(blocked.deals.map(\.deal.id) == [76])
        #expect(blocked.deals.first?.deal.fraudScore == 0.85)
    }

    @Test func budgetShelfUsesFiftyWhenTwoDealsFit() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [ShoppingItem(id: 1, owner: "me", name: "Lamp")]
        s.deals = [
            Deal(id: 10, owner: "me", shoppingItemId: 1, source: "target", title: "a", priceCents: 2_000),
            Deal(id: 11, owner: "me", shoppingItemId: 1, source: "ikea", title: "b", priceCents: 4_999),
            Deal(id: 12, owner: "me", shoppingItemId: 1, source: "amazon", title: "c", priceCents: 7_000),
        ]
        #expect(s.storefront().shelves.first { $0.kind == .budget }?.title == "Under $50")
        s.deals.removeFirst()
        // One deal under $50 isn't a shelf; two under $100 are.
        #expect(s.storefront().shelves.first { $0.kind == .budget }?.title == "Under $100")
        s.deals.removeFirst()
        #expect(s.storefront().shelves.first { $0.kind == .budget } == nil)
    }

    @Test func pickupDistanceParsing() {
        func deal(_ source: String, _ seller: String) -> Deal {
            Deal(id: 1, owner: "me", shoppingItemId: 1, source: source, title: "t", priceCents: 1, sellerInfo: seller)
        }
        #expect(deal("fb", "Seller · good · 4 mi · message seller").pickupDistance == "4 mi")
        #expect(deal("fb", "Seller · good · 2.5 mi").isLocalPickup)
        #expect(!deal("fb", "Seller · distance unknown").isLocalPickup)
        #expect(!deal("target", "Target · 3 mi").isLocalPickup, "card-checkout merchants ship")
        #expect(deal("fb", "Seller · many mi").pickupDistance == nil)
    }

    @Test func savingsNeverRoundUp() {
        let d = StorefrontDeal(deal: Deal(id: 1, owner: "me", shoppingItemId: 1, source: "t", title: "t", priceCents: 12_000),
                               itemId: 1, itemName: "x", referenceCents: 19_999)
        #expect(d.savingsPercent == 39)
        let same = StorefrontDeal(deal: d.deal, itemId: 1, itemName: "x", referenceCents: 12_000)
        #expect(same.savingsText == nil && same.savingsPercent == 0)
    }
}

@Suite struct DealRibbonTests {
    @Test func deskChairRibbons() throws {
        let s = DemoFixtures.demo(owner: "me")
        let chair = try #require(s.shoppingItems.first { $0.id == 52 })
        // Target is the low-risk cheapest; the scam is blocked, so it gets no ribbon at all.
        #expect(s.dealRibbons(for: chair) == [74: .bestDeal])
        let sofa = try #require(s.shoppingItems.first { $0.id == 51 })
        #expect(s.dealRibbons(for: sofa) == [71: .bestDeal, 72: .lowestPrice])
        let mattress = try #require(s.shoppingItems.first { $0.id == 50 })
        #expect(s.dealRibbons(for: mattress).isEmpty)
    }
}
