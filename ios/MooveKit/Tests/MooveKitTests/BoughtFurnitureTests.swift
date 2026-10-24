import Foundation
import Testing
@testable import MooveKit

@Suite struct BoughtFurnitureTests {
    private func item(_ id: UInt64, _ name: String, _ category: String = "", status: ShoppingStatus = .found,
                      deal: UInt64? = nil, owner: IdentityHex = "me") -> ShoppingItem {
        ShoppingItem(id: id, owner: owner, name: name, category: category, status: status, chosenDealId: deal,
                     createdAt: Date(timeIntervalSince1970: Double(id)))
    }

    private func deal(_ id: UInt64, item: UInt64, title: String? = nil) -> Deal {
        Deal(id: id, owner: "me", shoppingItemId: item, source: "target", title: title ?? "d\(id)", priceCents: 5_000)
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
        #expect(f("bed", "Mattress").category == "mattress") // the voxel builder has its own mattress
        #expect(f("bed", "Mattress").heightM < 0.4)
        #expect(f("bed", "Queen bed").widthM >= 1.5)
        #expect(f("sofa", "Sofa").widthM >= 1.8)
        #expect(f("chair", "Desk chair").category == "chair") // not a desk
        #expect(f("furniture", "Desk").category == "desk")
        #expect(f("table", "Dining table").widthM == 1.5)
        #expect(f("table", "Coffee table").heightM < 0.5)
        #expect(f("furniture", "TV stand").category == "dresser") // a low cabinet, not a screen
        #expect(f("tv stand", "TV stand").heightM < 0.7)
        #expect(f("tv", "Smart TV").category == "tv")
        #expect(f("storage", "Nightstand").category == "dresser")
        #expect(f("storage", "Nightstand").widthM < 0.6)
        #expect(f("storage", "Bedside table").category == "dresser") // not a table, not a bed
        #expect(f("", "Bookcase").category == "storage")
        #expect(f("", "Area rug").category == "rug")
        #expect(f("lamp", "Floor lamp").heightM > 1)
        #expect(f("decor", "Bar stools").category == "chair")
        // Name unknown: the category decides.
        #expect(f("sofa", "Something comfy").category == "sofa")
        #expect(f("cookware", "Cookware set").category == "kitchenware")
        #expect(f("shower curtain", "Shower curtain set").category == "decor")
        #expect(f("dining chair", "Dining chairs").category == "chair")
        #expect(f("furniture", "Accent armchair").category == "sofa")
        #expect(f("", "Mini fridge").category == "appliance")
        // Name unknown, category a builder key (or an alias of one): kept.
        #expect(f("Electronics", "Gadget").category == "electronics")
        #expect(f("Couch", "Something").category == "sofa")
        // Neither known: a generic default in a real builder category.
        let other = f("gizmos", "Thingamajig")
        #expect(other.category == "decor")
        #expect(other.widthM > 0 && other.depthM > 0 && other.heightM > 0)
    }

    /// Every footprint category is one the voxel router switches on, never the kraft-box fallback.
    @Test func everyCategoryIsAVoxelBuilderKey() {
        for rule in BoughtFurniture.rules {
            #expect(BoughtFurniture.voxelCategories.contains(rule.footprint.category), "\(rule.keywords)")
            let spec = VoxelItemSpec(category: rule.footprint.category, name: rule.keywords[0],
                                     widthM: rule.footprint.widthM, depthM: rule.footprint.depthM, heightM: rule.footprint.heightM)
            #expect(VoxelModels.kind(spec) != .box, "\(rule.keywords) routes to the unknown box")
        }
        for cat in BoughtFurniture.voxelCategories where cat != "storage" {
            #expect(VoxelModels.kind(VoxelItemSpec(category: cat, name: "thing", widthM: 1, depthM: 1, heightM: 1)) != .box, "\(cat)")
        }
    }

    // MARK: Names for the voxel model

    @Test func nameIsTheChosenDealTitle() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [item(1, "Dining table", "dining table", status: .bought, deal: 10), item(2, "Sofa", "sofa", status: .bought)]
        s.deals = [deal(9, item: 1, title: "Glass trestle table"), deal(10, item: 1, title: "Round walnut dining table")]
        let byId = Dictionary(uniqueKeysWithValues: s.boughtLayoutItems.map { ($0.id, $0) })
        let table = byId[BoughtFurniture.layoutId(forShoppingItem: 1)]
        #expect(table?.name == "Round walnut dining table")
        #expect(table?.category == "table")
        #expect(table?.widthM == 1.5) // per-category default: deals carry no dimensions
        // No chosen deal: the item's own name.
        #expect(byId[BoughtFurniture.layoutId(forShoppingItem: 2)]?.name == "Sofa")
    }

    @Test func dealTitleThatWouldDrawSomethingElseFallsBackToTheItemName() {
        #expect(BoughtFurniture.modelName(itemName: "Floor lamp", dealTitle: "Arc floor lamp for sofa", category: "lamp") == "Floor lamp")
        #expect(BoughtFurniture.modelName(itemName: "TV stand", dealTitle: "TV stand with bookshelf", category: "dresser") == "TV stand")
        #expect(BoughtFurniture.modelName(itemName: "Sofa", dealTitle: "  ", category: "sofa") == "Sofa")
        #expect(BoughtFurniture.modelName(itemName: "Sofa", dealTitle: nil, category: "sofa") == "Sofa")
    }

    @Test func itemWordIsKeptWhenTheTitleLacksIt() {
        #expect(BoughtFurniture.modelName(itemName: "Nightstand", dealTitle: "2-drawer bedside table, white", category: "dresser")
                == "2-drawer bedside table, white · Nightstand")
        #expect(BoughtFurniture.modelName(itemName: "Dining chairs", dealTitle: "Set of 4 windsor dining chairs, oak", category: "chair")
                == "Set of 4 windsor dining chairs, oak")
        #expect(BoughtFurniture.modelName(itemName: "Mattress", dealTitle: "8\" memory foam mattress, Full", category: "mattress")
                == "8\" memory foam mattress, Full")
    }

    @Test func boughtItemsDrawLikeTheirKind() {
        func kind(_ i: LayoutItem) -> VoxelModels.Kind {
            VoxelModels.kind(VoxelItemSpec(category: i.category, name: i.name, widthM: i.widthM, depthM: i.depthM, heightM: i.heightM))
        }
        let mattress = LayoutItem(bought: item(1, "Mattress", "bed"), deal: deal(1, item: 1, title: "Hybrid mattress, Full"))
        #expect(kind(mattress) == .mattress)
        let stand = LayoutItem(bought: item(2, "TV stand", "tv stand"), deal: deal(2, item: 2, title: "Mid-century walnut media console"))
        #expect(kind(stand) == .dresser)
        let rug = LayoutItem(bought: item(3, "Area rug", "rug"), deal: deal(3, item: 3, title: "Round jute rug, 6 ft"))
        #expect(kind(rug) == .rug)
    }

    @Test func mattressesAndTVStandsGoToTheirRooms() {
        #expect(LayoutSolver.preferredKinds(for: LayoutItem(bought: item(1, "Mattress", "bed"))) == [.bedroom])
        let stand = LayoutItem(bought: item(2, "TV stand", "tv stand"), deal: deal(2, item: 2, title: "Walnut media console"))
        #expect(LayoutSolver.preferredKinds(for: stand).first == .living)
        #expect(LayoutSolver.preferredKinds(for: LayoutItem(bought: item(3, "Dresser", "dresser"))).first == .bedroom)
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
        #expect(bought.map(\.name) == ["8\" memory foam mattress, Full"]) // the chosen deal's title
        #expect(bought.map(\.category) == ["mattress"])
        #expect(s.newHomeLayoutItems.contains { $0.isBought })
        let option = LayoutSolver(plan: DemoHouse.floorPlan).solve(s.newHomeLayoutItems, style: .byFunction)
        #expect(option.unplaced.isEmpty)
    }
}
