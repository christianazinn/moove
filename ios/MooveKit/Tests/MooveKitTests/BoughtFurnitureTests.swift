import Foundation
import Testing
@testable import MooveKit

@Suite struct BoughtFurnitureTests {
    private func item(_ id: UInt64, _ name: String, _ category: String = "", status: ShoppingStatus = .found,
                      deal: UInt64? = nil, owner: IdentityHex = "me") -> ShoppingItem {
        ShoppingItem(id: id, owner: owner, name: name, category: category, status: status, chosenDealId: deal,
                     createdAt: Date(timeIntervalSince1970: Double(id)))
    }

    private func deal(_ id: UInt64, item: UInt64) -> Deal {
        Deal(id: id, owner: "me", shoppingItemId: item, source: "target", title: "d\(id)", priceCents: 5_000)
    }

    private func visa(_ id: UInt64, deal: UInt64, _ status: PaymentStatus) -> Payment {
        Payment(id: id, owner: "me", agent: "buy", rail: .visa, purpose: "p", payee: "m", amountUsdMicros: 1,
                status: status, simulated: true, refTable: "deal", refId: deal)
    }

    // MARK: What counts as purchased

    @Test func boughtStatusCounts() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [item(1, "Sofa", "sofa", status: .bought), item(2, "Desk", "desk", status: .found)]
        #expect(s.purchasedShoppingItems.map(\.id) == [1])
    }

    @Test func settledVisaPaymentOnChosenDealCountsBeforeStatusCatchesUp() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [item(1, "Sofa", "sofa", deal: 10), item(2, "Desk", "desk", deal: 20), item(3, "Rug", "rug", deal: 30)]
        s.deals = [deal(10, item: 1), deal(20, item: 2), deal(30, item: 3)]
        s.payments = [visa(1, deal: 10, .settled), visa(2, deal: 20, .pending), visa(3, deal: 30, .failed)]
        #expect(s.purchasedShoppingItems.map(\.id) == [1])
    }

    @Test func settledPaymentOnAnUnchosenDealDoesNotCount() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [item(1, "Sofa", "sofa", deal: 11)]
        s.deals = [deal(10, item: 1), deal(11, item: 1)]
        s.payments = [visa(1, deal: 10, .settled)]
        #expect(s.purchasedShoppingItems.isEmpty)
    }

    @Test func onlyMyShoppingItems() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [item(1, "Sofa", "sofa", status: .bought, owner: "someone-else")]
        #expect(s.boughtLayoutItems.isEmpty)
    }

    // MARK: Layout items

    @Test func idsNeverCollideWithInventoryIds() {
        var s = DemoFixtures.inventory(owner: "me")
        s.items[0].disposition = .keep
        let keptId = s.items[0].id
        s.shoppingItems = [item(keptId, "Sofa", "sofa", status: .bought)]
        let ids = s.newHomeLayoutItems.map(\.id)
        #expect(Set(ids).count == ids.count)
        let bought = s.boughtLayoutItems[0]
        #expect(bought.id == BoughtFurniture.idBase + keptId)
        #expect(bought.isBought)
        #expect(BoughtFurniture.shoppingItemId(fromLayoutId: bought.id) == keptId)
        #expect(!LayoutItem(s.items[0]).isBought)
        #expect(Double(bought.id) < 9_007_199_254_740_992) // survives JSON numbers (2^53)
    }

    @Test func footprintsByCategoryAndName() {
        func f(_ category: String, _ name: String) -> BoughtFurniture.Footprint {
            BoughtFurniture.footprint(category: category, name: name)
        }
        #expect(f("bed", "Mattress").category == "bed")
        #expect(f("bed", "Mattress").heightM < 0.4)
        #expect(f("bed", "Queen bed").widthM >= 1.5)
        #expect(f("sofa", "Sofa").widthM >= 1.8)
        #expect(f("chair", "Desk chair").category == "chair") // not a desk
        #expect(f("furniture", "Desk").category == "desk")
        #expect(f("table", "Dining table").widthM == 1.5)
        #expect(f("table", "Coffee table").heightM < 0.5)
        #expect(f("furniture", "TV stand").category == "tv")
        #expect(f("storage", "Nightstand").category == "dresser")
        #expect(f("storage", "Nightstand").widthM < 0.6)
        #expect(f("storage", "Bedside table").category == "dresser") // not a table, not a bed
        #expect(f("", "Bookcase").category == "storage")
        #expect(f("", "Area rug").category == "rug")
        #expect(f("lamp", "Floor lamp").heightM > 1)
        #expect(f("decor", "Bar stools").category == "chair")
        // Name unknown: the category decides.
        #expect(f("sofa", "Something comfy").category == "sofa")
        // Neither known: a generic default that keeps the category.
        let other = f("Kitchenware", "Pots and pans")
        #expect(other.category == "kitchenware")
        #expect(other.widthM > 0 && other.depthM > 0 && other.heightM > 0)
    }

    @Test func boughtItemsAreLaidOutWithTheKeptOnes() {
        var s = DemoFixtures.inventory(owner: "me")
        s.shoppingItems = [item(1, "Sofa", "sofa", status: .bought), item(2, "Desk", "desk", status: .bought),
                           item(3, "Dining table", "table", status: .bought)]
        let items = s.newHomeLayoutItems
        let keptCount = s.items.filter { $0.disposition == .keep }.count
        #expect(items.count == keptCount + 3)
        for option in LayoutSolver(plan: DemoHouse.floorPlan).solveAll(items) {
            #expect(option.unplaced.isEmpty, "\(option.name) left \(option.unplaced) unplaced")
            let placed = Set(option.placements.map(\.itemId))
            #expect(s.boughtLayoutItems.allSatisfy { placed.contains($0.id) })
        }
        let byFunction = LayoutSolver(plan: DemoHouse.floorPlan).solve(items, style: .byFunction)
        let room = Dictionary(uniqueKeysWithValues: byFunction.placements.map { ($0.itemId, $0.room) })
        let sofaRoom = room[BoughtFurniture.layoutId(forShoppingItem: 1)].flatMap { DemoHouse.floorPlan.room(named: $0) }
        #expect(sofaRoom?.kind == .living)
    }

    // MARK: Offline demo

    @Test func offlineDemoIncludesTheBoughtMattress() {
        let s = DemoFixtures.demo(owner: "demo")
        let bought = s.boughtLayoutItems
        #expect(bought.map(\.name) == ["Mattress"])
        #expect(s.newHomeLayoutItems.contains { $0.isBought })
        let option = LayoutSolver(plan: DemoHouse.floorPlan).solve(s.newHomeLayoutItems, style: .byFunction)
        #expect(option.unplaced.isEmpty)
    }
}
