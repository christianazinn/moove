import Foundation
import Testing
@testable import MooveKit

/// The commerce screens draw voxel thumbnails for shopping items, their deals and the items behind
/// listings. Routing changes (#263, #273: new kinds, size sanity) must keep every Offline-demo row
/// drawing what it is, never the plain box: "Herman Miller Aeron" a chair, a mattress a mattress,
/// sofa deals a sofa, rugs a rug.
@Suite struct CommerceVoxelRoutingTests {
    private let snapshot = DemoFixtures.demo(owner: "me")

    /// What each shopping item (and every deal under it) should look like.
    private let expectedByItem: [String: VoxelModels.Kind] = [
        "Mattress": .mattress, "Sofa": .sofa, "Desk chair": .chair, "Dining table": .table, "Area rug": .rug,
    ]

    @Test func everyShoppingItemAndDealRoutesToItsKind() {
        let items = snapshot.myShoppingItems
        #expect(Set(items.map(\.name)) == Set(expectedByItem.keys), "shopping fixture changed: update this table")
        for item in items {
            let expected = expectedByItem[item.name]
            let kind = VoxelModels.kind(ShoppingThumbnails.spec(for: item))
            #expect(kind == expected, "\(item.name) -> \(kind)")
            #expect(kind != .box)
            for deal in snapshot.deals(for: item.id) {
                let dealKind = VoxelModels.kind(ShoppingThumbnails.spec(for: deal, item: item))
                #expect(dealKind == expected, "deal \(deal.id) \"\(deal.title)\" -> \(dealKind)")
            }
        }
    }

    /// Every deal title alone (no shopping item, e.g. a purchase approval whose item isn't synced).
    @Test func dealTitlesAloneNeverDrawABox() {
        #expect(!snapshot.deals.isEmpty)
        for deal in snapshot.deals {
            let kind = VoxelModels.kind(ShoppingThumbnails.spec(for: deal, item: nil))
            #expect(kind != .box, "deal \(deal.id) \"\(deal.title)\" -> box")
        }
        let aeron = snapshot.deals.first { $0.title.contains("Aeron") }
        #expect(aeron.map { VoxelModels.kind(ShoppingThumbnails.spec(for: $0, item: nil)) } == .chair)
    }

    /// The items behind the Offline-demo listings (the mesh chair, the one item the sort agent sells).
    @Test func listedItemsRouteToTheirKind() {
        let expected: [UInt64: VoxelModels.Kind] = [17: .chair]
        let listed = Set(snapshot.listings.map(\.itemId))
        #expect(listed == Set(expected.keys), "listing fixture changed: update this table")
        for id in listed {
            guard let item = snapshot.items.first(where: { $0.id == id }) else {
                Issue.record("listing points at missing item \(id)"); continue
            }
            let kind = VoxelModels.kind(VoxelItemSpec(item))
            #expect(kind == expected[id], "\(item.name) -> \(kind)")
        }
    }
}

/// Commerce screens and hidden rooms (#271): hiding a room is a local Inventory filter. Money and
/// approvals for its items are real, so the commerce rows must survive `hidingRooms`.
@Suite struct CommerceHiddenRoomTests {
    @Test func hidingARoomKeepsEveryCommerceRow() {
        let s = DemoFixtures.demo(owner: "me")
        let rooms = Set(s.items.map(\.roomId))
        #expect(!rooms.isEmpty)
        let hidden = s.hidingRooms(rooms)
        #expect(hidden.items.isEmpty)
        #expect(hidden.listings == s.listings)
        #expect(hidden.approvals == s.approvals)
        #expect(hidden.payments == s.payments)
        #expect(hidden.agentEvents == s.agentEvents)
        #expect(hidden.shoppingItems == s.shoppingItems)
        #expect(hidden.deals == s.deals)
        #expect(hidden.pendingApprovals == s.pendingApprovals)
        #expect(hidden.spendingSplit().yours.entries == s.spendingSplit().yours.entries)
    }
}
