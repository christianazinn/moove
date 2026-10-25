import Foundation
import Testing
@testable import MooveKit

/// The Shopping cart sheet: bought lines, totals, payment labels and the room each piece goes to.
@Suite struct ShoppingCartTests {
    private func payment(_ id: UInt64, deal: UInt64, cents: Int64, status: PaymentStatus = .settled,
                         simulated: Bool = true) -> Payment {
        Payment(id: id, owner: "me", agent: "buy", rail: .visa, purpose: "p", payee: "m",
                amountUsdMicros: cents * 10_000, status: status, simulated: simulated, refTable: "deal", refId: deal)
    }

    @Test func offlineDemoHasTheSimulatedMattress() throws {
        let cart = DemoFixtures.demo(owner: "me").shoppingCart()
        #expect(cart.count == 1)
        let line = try #require(cart.lines.first)
        #expect(line.item.name == "Mattress")
        #expect(line.title == "8\" memory foam mattress, Full")
        #expect(line.seller.hasPrefix("Target"))
        #expect(line.formattedAmount == "$179.99")
        #expect(line.status == .paidSimulated)
        #expect(line.statusLabel == "Paid (simulated)")
        #expect(cart.summary == "1 thing · $179.99, simulated")
        #expect(cart.accessibilityLabel == "Cart, 1 bought")
    }

    @Test func emptyCart() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [ShoppingItem(id: 1, owner: "me", name: "Lamp", status: .found)]
        let cart = s.shoppingCart()
        #expect(cart.isEmpty)
        #expect(cart.summary == "Nothing bought yet")
        #expect(cart.accessibilityLabel == "Cart, 0 bought")
    }

    @Test func totalsLabelsAndRooms() throws {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [
            ShoppingItem(id: 1, owner: "me", name: "Mattress", category: "bed", status: .bought, chosenDealId: 10),
            // Settled payment, status not caught up yet: still bought.
            ShoppingItem(id: 2, owner: "me", name: "Sofa", category: "sofa", status: .found, chosenDealId: 20),
            // Marketplace deal marked bought, no Visa payment.
            ShoppingItem(id: 3, owner: "me", name: "Dining table", category: "table", status: .bought, chosenDealId: 30),
            // Only a hold: not bought.
            ShoppingItem(id: 4, owner: "me", name: "Rug", status: .found, chosenDealId: 40),
            // Someone else's.
            ShoppingItem(id: 5, owner: "them", name: "Desk", status: .bought),
        ]
        s.deals = [
            Deal(id: 10, owner: "me", shoppingItemId: 1, source: "target", title: "Foam mattress", priceCents: 17_999),
            Deal(id: 20, owner: "me", shoppingItemId: 2, source: "wayfair", title: "Gray sofa", priceCents: 42_999),
            Deal(id: 30, owner: "me", shoppingItemId: 3, source: "craigslist", title: "Oak table", priceCents: 12_000,
                 sellerInfo: "Dana · good · 7 mi"),
            Deal(id: 40, owner: "me", shoppingItemId: 4, source: "amazon", title: "Rug", priceCents: 6_499),
        ]
        s.payments = [
            payment(1, deal: 10, cents: 17_999),
            payment(2, deal: 20, cents: 42_999, simulated: false),
            payment(3, deal: 40, cents: 6_499, status: .pending),
        ]
        s.newHomes = [NewHome(id: 7, owner: "me", name: "New", source: .demo, floorPlanJson: "{}")]
        s.layouts = [Layout(id: 1, owner: "me", newHomeId: 7, name: "Cozy", placementsJson: Layout.encode([
            Placement(itemId: BoughtFurniture.layoutId(forShoppingItem: 1), room: "Bedroom", x: 0, y: 0),
            Placement(itemId: 1, room: "Kitchen", x: 0, y: 0),
        ]))]

        let cart = s.shoppingCart()
        #expect(cart.lines.map(\.id) == [1, 2, 3])
        #expect(cart.lines.map(\.status) == [.paidSimulated, .visaSandbox, .bought])
        #expect(cart.lines[0].room == "Bedroom")
        #expect(cart.lines[0].statusLabel == "Delivering to Bedroom")
        #expect(cart.lines[1].room == nil)
        #expect(cart.lines[1].statusLabel == "Visa sandbox")
        #expect(cart.lines[2].seller == "Craigslist · Dana")
        #expect(cart.totalUsdMicros == (17_999 + 42_999 + 12_000) * 10_000)
        #expect(cart.summary == "3 things · $729.98, simulated + Visa sandbox")
        #expect(cart.lines[0].accessibilitySummary == "Foam mattress, from Target, $179.99, Paid (simulated), goes to the Bedroom")
    }

    @Test func singleRailNotes() {
        var s = SyncSnapshot(me: "me")
        s.shoppingItems = [ShoppingItem(id: 1, owner: "me", name: "Table", status: .bought)]
        #expect(s.shoppingCart().summary == "1 thing · $0.00")
        s.shoppingItems = [ShoppingItem(id: 1, owner: "me", name: "Sofa", status: .found, chosenDealId: 20)]
        s.deals = [Deal(id: 20, owner: "me", shoppingItemId: 1, source: "wayfair", title: "Sofa", priceCents: 42_999)]
        s.payments = [payment(2, deal: 20, cents: 42_999, simulated: false)]
        #expect(s.shoppingCart().summary == "1 thing · $429.99, Visa sandbox")
    }
}
