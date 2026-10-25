import Foundation
import Testing
@testable import MooveKit

/// The Shopping storefront (hero, category sections with bento cards and deal rows, the blocked
/// section) on the Offline demo and on edge cases.
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
        // Each category's most urgent open item gets the feature card; the bought mattress a wide one.
        #expect(tiles.map(\.size) == [.feature, .feature, .feature, .feature, .wide])
    }

    // MARK: Sections

    @Test func demoItemsLandInTheirFunctionHalls() {
        let hall = Dictionary(uniqueKeysWithValues: DemoFixtures.demo(owner: "me").shoppingItems.map { ($0.name, FunctionHall.of($0)) })
        #expect(hall == ["Mattress": .sleep, "Sofa": .sitAndLounge, "Desk chair": .workAndStudy,
                         "Dining table": .kitchenAndDining, "Area rug": .lightAndDecor])
    }

    @Test func demoSectionsNeedYouFirstBoughtLast() throws {
        #expect(demo.sections.map(\.hall) == [.sitAndLounge, .workAndStudy, .lightAndDecor, .kitchenAndDining, .sleep])
        #expect(demo.sections.map(\.title) == ["Sit & lounge", "Work & study", "Light & decor", "Kitchen & dining", "Sleep"])
        #expect(demo.sections.map(\.subtitle) == [
            "1 to buy · from $150", "1 to buy · from $79.99", "1 to buy · from $64.99", "1 to buy · from $120", "1 bought",
        ])
        #expect(demo.sections.map(\.needsYou) == [1, 1, 1, 1, 0])
        let sleep = try #require(demo.sections.last)
        #expect(sleep.tiles.map(\.badge.label) == ["Bought (simulated)"])
        #expect(sleep.deals == nil, "nothing to buy, so no deal row")
    }

    @Test func demoCategoryDealRowsAreBestFirstAndNeverOfferTheScam() throws {
        let work = try #require(demo.sections.first { $0.hall == .workAndStudy }?.deals)
        #expect(work.kind == .best)
        #expect(work.title == "Work & study deals")
        // The $95 Aeron scam is blocked, so the chair row only has the two real chairs.
        #expect(work.deals.map(\.deal.id) == [74, 75])
        let rug = try #require(demo.sections.first { $0.hall == .lightAndDecor }?.deals)
        // The Target rug's checkout was declined, so it isn't offered again.
        #expect(rug.deals.map(\.deal.id) == [82, 81])
        let sofa = try #require(demo.sections.first { $0.hall == .sitAndLounge }?.deals)
        #expect(sofa.deals.map(\.deal.id) == [72, 71, 70])
        #expect(Set(demo.sections.compactMap(\.deals?.id)).count == 4, "shelf ids are unique")
    }

    @Test func blockedIsItsOwnSectionAtTheEnd() throws {
        let blocked = try #require(demo.blocked)
        #expect(blocked.kind == .blocked)
        #expect(blocked.title == "Blocked for your safety")
        #expect(blocked.deals.map(\.deal.id) == [76])
        #expect(blocked.deals.first?.deal.fraudScore == 0.85)
        #expect(!demo.sections.contains { $0.deals?.deals.contains { $0.deal.isFraudBlocked } == true })
        #expect(SyncSnapshot(me: "me").storefront().blocked == nil)
    }

    @Test func sectionsOrderByWhatNeedsYouThenHowMuchIsLeft() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [
            ShoppingItem(id: 1, owner: "me", name: "Lamp", status: .searching),
            ShoppingItem(id: 2, owner: "me", name: "Floor lamp", status: .searching),
            ShoppingItem(id: 3, owner: "me", name: "Bookshelf", status: .found),
            ShoppingItem(id: 4, owner: "me", name: "Dog bed", status: .found),
            ShoppingItem(id: 5, owner: "me", name: "Toaster", status: .bought),
            ShoppingItem(id: 6, owner: "me", name: "Kettle", status: .searching),
        ]
        s.deals = [
            Deal(id: 30, owner: "me", shoppingItemId: 3, source: "ikea", title: "BILLY", priceCents: 5_000),
            Deal(id: 31, owner: "me", shoppingItemId: 4, source: "target", title: "Pet bed", priceCents: 3_000),
        ]
        let front = s.storefront()
        // Storage needs a choice; Light & decor has two still to buy; Kitchen has one open and one
        // bought; the curiosities (pet things) come last among open categories.
        #expect(front.sections.map(\.hall) == [.storage, .lightAndDecor, .kitchenAndDining, .everythingElse])
        let kitchen = front.sections[2]
        #expect(kitchen.tiles.map(\.item.name) == ["Kettle", "Toaster"], "bought after open")
        #expect(kitchen.tiles.map(\.size) == [.feature, .wide])
        #expect(kitchen.subtitle == "1 to buy · 1 bought")
        #expect(front.sections[1].tiles.map(\.size) == [.feature, .wide])
        #expect(front.sections.first?.subtitle == "1 to buy · from $50")
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

    // MARK: Deals

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
