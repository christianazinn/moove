import Foundation
import Testing
@testable import MooveKit

@Suite struct ItemFixTests {
    private func kind(_ name: String, _ cat: String, attrs: [String] = [], _ w: Double = 1, _ d: Double = 0.5, _ h: Double = 0.75) -> VoxelModels.Kind {
        VoxelModels.kind(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h, attributes: attrs))
    }

    // MARK: Attributes

    @Test func chipSetsKindAndKeepsRoomPlanAttributes() {
        let attrs = ["StorageType.cabinet", "Mount.wall"]
        let set = ItemFix.setting(.table, in: attrs)
        #expect(set == ["StorageType.cabinet", "Mount.wall", "UserKind.table"])
        #expect(ItemFix.quickKind(in: set) == .table)
        // a second chip replaces the first; Other clears it
        let shelf = ItemFix.setting(.shelf, in: set)
        #expect(shelf == ["StorageType.cabinet", "Mount.wall", "UserKind.bookshelf"])
        #expect(ItemFix.quickKind(in: shelf) == .shelf)
        #expect(ItemFix.setting(.other, in: shelf) == attrs)
        // every written attribute passes the module's Type.value check
        for k in ItemFix.QuickKind.allCases { #expect(k.attribute.map(ScanObject.isValidAttribute) ?? true) }
    }

    @Test func turnsCycleAndToggle() {
        var a = ["SofaType.lShaped"]
        a = ItemFix.turningAround(a)
        #expect(a == ["SofaType.lShaped", "UserRotate.180"])
        #expect(ItemFix.turnDeg(in: a) == 180)
        #expect(ItemFix.turningAround(a) == ["SofaType.lShaped"])  // toggles back
        var r: [String] = []
        var seen: [Int] = []
        for _ in 0..<4 {
            r = ItemFix.rotating90(r)
            seen.append(ItemFix.turnDeg(in: r))
        }
        #expect(seen == [90, 180, 270, 0])
        #expect(r.isEmpty)
        #expect(ItemFix.turningAround(["UserRotate.90"]) == ["UserRotate.270"])
        #expect(ScanObject.isValidAttribute("UserRotate.270"))
        #expect(ItemFix.turnDeg(in: ["UserRotate.45"]) == 0)  // only quarter turns count
    }

    @Test func genericNamesGetTheChipWord() {
        #expect(ItemFix.apply(.table, name: "Storage", category: "storage", attributes: []).name == "Table")
        #expect(ItemFix.apply(.lamp, name: "pillow", category: "decor", attributes: []).name == nil)
        #expect(ItemFix.apply(.lamp, name: "Decor", category: "decor", attributes: []).name == "Lamp")
        #expect(ItemFix.apply(.other, name: "Storage", category: "storage", attributes: []).name == nil)
        #expect(ItemFix.apply(.lamp, name: "pillow", category: "decor", attributes: []).attributes == ["UserKind.lamp"])
    }

    @Test func renameSetsKindOnlyWhenTheNameNamesOne() {
        #expect(ItemFix.renamed(to: "Coffee table", attributes: ["StorageType.cabinet"]) == ["StorageType.cabinet", "UserKind.table"])
        #expect(ItemFix.renamed(to: "Floor lamp", attributes: ["UserKind.box"]) == ["UserKind.lamp"])
        #expect(ItemFix.renamed(to: "Grandma's thing", attributes: ["UserKind.chair"]) == ["UserKind.chair"])
        #expect(ItemFix.renamed(to: "Moving box", attributes: []) == ["UserKind.box"])
    }

    // MARK: Routing

    @Test func userKindWinsOverEverything() {
        // RoomPlan said cabinet: drawn as a dresser until the user says table
        #expect(kind("Storage", "storage", attrs: ["StorageType.cabinet"]) == .dresser)
        #expect(kind("Storage", "storage", attrs: ["StorageType.cabinet", "UserKind.table"]) == .table)
        // a lamp named "pillow" (tall and thin) — the user's lamp, and the user's choice beats the size check too
        #expect(kind("pillow", "decor", attrs: ["UserKind.lamp"], 0.3, 0.3, 1.5) == .lamp)
        #expect(kind("Sofa", "sofa", attrs: ["UserKind.plant"], 0.4, 0.4, 0.4) == .plant)
        // case-insensitive, and an unknown kind is ignored
        #expect(kind("Thing", "other", attrs: ["userkind.BOOKSHELF"]) == .bookshelf)
        #expect(kind("Desk", "desk", attrs: ["UserKind.spaceship"]) == .desk)
        // the turn alone doesn't change the model
        #expect(kind("Desk", "desk", attrs: ["UserRotate.180"]) == .desk)
    }

    @Test func layoutItemsCarryTheUserKindSoDollhousesAgree() {
        var item = Item(id: 7, owner: "me", roomId: 1, name: "Storage", category: "storage", widthM: 1.2, heightM: 0.45, depthM: 0.6)
        item.attributes = ["StorageType.cabinet", "UserKind.table", "UserRotate.90"]
        let layout = LayoutItem(item)
        #expect(layout.attributes == ["UserKind.table"])
        #expect(VoxelModels.kind(VoxelItemSpec(layout)) == .table)
        #expect(VoxelModels.kind(VoxelItemSpec(item)) == .table)
        // the turn isn't part of the model spec (no rebuild, same seed)
        #expect(!VoxelItemSpec(item).attributes.contains("UserRotate.90"))
    }

    // MARK: Placement

    @Test func turnsApplyOnTopOfTheScannedYaw() {
        var a = Item(id: 1, owner: "me", roomId: 1, name: "Desk", category: "desk", widthM: 1, heightM: 0.75, depthM: 0.6)
        a.attributes = ["UserRotate.180"]
        var b = a
        b.id = 2
        b.attributes = ["UserRotate.90"]
        let c = Item(id: 3, owner: "me", roomId: 1, name: "Bed", category: "bed", widthM: 1.5, heightM: 0.5, depthM: 2)
        let placements = [
            Placement(itemId: 1, room: "R", x: 1, y: 1, rotationDeg: 270),
            Placement(itemId: 2, room: "R", x: 2, y: 1, rotationDeg: 300),
            Placement(itemId: 3, room: "R", x: 3, y: 1, rotationDeg: 90),
            Placement(itemId: 4, room: "R", x: 4, y: 1, rotationDeg: 45),
        ]
        let turned = ItemFix.applyingTurns(placements, items: [a, b, c])
        #expect(turned.map(\.rotationDeg) == [90, 30, 90, 45])
        #expect(ItemFix.rotationDeg(180, turnedBy: ["UserRotate.180"]) == 0)
        #expect(a.userTurnDeg == 180)
    }

    // MARK: Offline demo backend

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }

    private func demoBackend() async throws -> FixtureBackend {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Bedroom", objects: [
            ScanObject(scanObjectId: "a", category: "storage", widthM: 1.2, heightM: 0.45, depthM: 0.6, attributes: ["StorageType.cabinet"]),
            ScanObject(scanObjectId: "b", category: "decor", widthM: 0.3, heightM: 1.5, depthM: 0.3),
        ]))
        return backend
    }

    @Test func fixtureRenamesDeletesAndSetsAttributes() async throws {
        let backend = try await demoBackend()
        let items = await firstSnapshot(backend).items
        let cabinet = try #require(items.first { $0.scanObjectId == "a" })
        let pillow = try #require(items.first { $0.scanObjectId == "b" })

        try await backend.renameItem(itemId: cabinet.id, name: "Coffee table")
        try await backend.setItemAttributes(itemId: cabinet.id, attributes: ItemFix.turningAround(ItemFix.setting(.table, in: cabinet.attributes)))
        try await backend.deleteItem(itemId: pillow.id)

        let snap = await firstSnapshot(backend)
        let fixed = try #require(snap.items.first { $0.id == cabinet.id })
        #expect(fixed.name == "Coffee table")
        #expect(fixed.attributes == ["StorageType.cabinet", "UserKind.table", "UserRotate.180"])
        #expect(VoxelModels.kind(VoxelItemSpec(fixed)) == .table)
        #expect(!snap.items.contains { $0.id == pillow.id })
    }

    @Test func fixtureChecksLikeTheModule() async throws {
        let backend = try await demoBackend()
        let item = try #require(await firstSnapshot(backend).items.first)
        await #expect(throws: FixtureBackend.Failure.invalidAttribute) {
            try await backend.setItemAttributes(itemId: item.id, attributes: ["user.kind:table"])
        }
        await #expect(throws: FixtureBackend.Failure.invalidAttribute) {
            try await backend.setItemAttributes(itemId: item.id, attributes: (0...ScanObject.maxAttributes).map { "T.v\($0)" })
        }
        await #expect(throws: FixtureBackend.Failure.nameTooLong) {
            try await backend.renameItem(itemId: item.id, name: String(repeating: "x", count: FixtureBackend.maxNameLength + 1))
        }
        await #expect(throws: FixtureBackend.Failure.noSuchItem) { try await backend.deleteItem(itemId: 9999) }
        await #expect(throws: FixtureBackend.Failure.noSuchItem) { try await backend.renameItem(itemId: 9999, name: "x") }
        // duplicates collapse, order kept
        try await backend.setItemAttributes(itemId: item.id, attributes: ["UserKind.table", "StorageType.cabinet", "UserKind.table"])
        #expect(await firstSnapshot(backend).items.first { $0.id == item.id }?.attributes == ["UserKind.table", "StorageType.cabinet"])
    }
}
