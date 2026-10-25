import Foundation
import Testing
@testable import MooveKit

/// Move (layout, fly-in, truck, boxes) uses the items Review shows under Keep (#335).
@Suite struct MoveItemsTests {
    let demo = DemoFixtures.demo(owner: "demo")

    private func keepPile(_ items: [Item]) -> Set<UInt64> {
        Set(Review.piles(items).first { $0.destination == .keep }?.items.map(\.id) ?? [])
    }

    @Test func demoMoveSetIsReviewsKeepPile() {
        let move = MoveItems.of(demo.withoutBuiltIns(), demo: demo)
        #expect(!move.isDemo) // the demo snapshot has kept items of its own
        #expect(Set(move.kept.map(\.id)) == keepPile(demo.withoutBuiltIns().items))
        #expect(!move.kept.isEmpty)
        // The sentimental guitar still waits on you: not laid out, but it rides with you.
        #expect(move.withYou.map(\.id) == [18])
        #expect(!move.kept.contains { $0.id == 18 })
    }

    @Test func layoutTruckAndBoxesCarryTheSameItems() {
        let move = MoveItems.of(demo.withoutBuiltIns(), demo: demo)
        let plan = PackingPlanner.plan(items: move.packed, bought: move.bought)
        let planned = Set(plan.boxes.flatMap(\.contents).compactMap(\.itemId)).union(plan.furniture.map(\.id))
        #expect(planned == Set(move.packed.map(\.id)))
        let load = TruckLoader.load(plan: plan, items: move.packed)
        let cargo = load.placements.map(\.item) + load.unloaded
        let truckIds = Set(cargo.compactMap(\.itemId))
        #expect(truckIds.isSubset(of: Set(move.kept.map(\.id))))
        // Bought pieces are delivered, never packed.
        #expect(plan.delivered.count == move.bought.count)
    }

    @Test func emptyInventoryFallsBackToTheDemoSet() {
        let empty = SyncSnapshot(me: "me")
        let move = MoveItems.of(empty, demo: demo)
        #expect(move.isDemo)
        #expect(Set(move.kept.map(\.id)) == keepPile(demo.items))
    }

    @Test func roomsLeftBehindStayOut() {
        let move = MoveItems.of(demo.withoutBuiltIns().selectingRooms([1: false]), demo: demo)
        #expect(move.kept.isEmpty)
        #expect(move.withYou.isEmpty)
    }

    @Test func soldAndUndecidedPlainItemsNeverMove() {
        let move = MoveItems.of(demo.withoutBuiltIns(), demo: demo)
        let ids = Set(move.packed.map(\.id))
        for id: UInt64 in [11, 17, 19, 20] { #expect(!ids.contains(id)) }
    }
}
