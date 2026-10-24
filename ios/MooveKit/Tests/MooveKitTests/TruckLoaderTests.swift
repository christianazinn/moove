import Foundation
import Testing
@testable import MooveKit

@Suite struct TruckLoaderTests {
    func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double),
              fragile: Bool = false, sentimental: Bool = false, _ disposition: Disposition = .keep) -> Item {
        Item(id: id, owner: "me", roomId: 1, name: name, category: category, widthM: dims.0, heightM: dims.1,
             depthM: dims.2, disposition: disposition, fragile: fragile, maybeSentimental: sentimental)
    }

    var bigMove: [Item] {
        [
            item(1, "Sofa", "sofa", (2.1, 0.85, 0.95)),
            item(2, "Dining table", "table", (1.6, 0.75, 0.9)),
            item(3, "Kitchenware set", "kitchenware", (0.4, 0.3, 0.3), fragile: true),
            item(4, "Box of paperbacks", "books", (0.4, 0.3, 0.3)),
            item(5, "Desk lamp", "lamp", (0.2, 0.4, 0.2), fragile: true),
            item(6, "Queen bed frame", "bed", (1.6, 0.4, 2.1)),
            item(7, "Wall art", "art", (0.8, 0.6, 0.04), fragile: true),
            item(8, "Dresser", "dresser", (1.2, 0.8, 0.5)),
            item(9, "Old letters", "decor", (0.3, 0.1, 0.2), sentimental: true, .undecided),
            item(10, "Queen mattress", "mattress", (1.5, 0.3, 2.0)),
            item(11, "Armchair", "chair", (0.8, 0.9, 0.8)),
            item(12, "Bookshelf", "storage", (0.8, 1.8, 0.3)),
            item(13, "Grandma's quilt chest", "decor", (1.3, 0.6, 0.5), sentimental: true, .undecided),
            item(14, "TV", "tv", (1.2, 0.7, 0.1)),
        ]
    }

    var demoItems: [Item] { DemoFixtures.inventory(owner: "me").items }

    func loads() -> [(String, TruckLoad)] {
        var out: [(String, TruckLoad)] = []
        for (name, items) in [("demo", demoItems), ("big", bigMove)] {
            let plan = PackingPlanner.plan(items: items)
            out.append((name, TruckLoader.load(plan: plan, items: items)))
            for size in TruckSize.allCases { out.append(("\(name) \(size)", TruckLoader.load(plan: plan, items: items, truck: size))) }
        }
        return out
    }

    @Test func cargoDimsMatchCapacity() {
        for size in TruckSize.allCases {
            let ratio = size.cargoVolumeM3 / size.capacityM3
            #expect(ratio > 0.9 && ratio < 1.15, "\(size): \(size.cargoVolumeM3) m³ vs \(size.capacityM3)")
        }
    }

    @Test func cargoSkipsCarAndKeepWithYou() {
        let plan = PackingPlanner.plan(items: bigMove)
        let cargo = TruckLoader.cargo(plan: plan, items: bigMove)
        #expect(!cargo.contains { $0.itemId == 13 }, "the sentimental chest rides in the car")
        let keepBoxes = Set(plan.boxes.filter(\.keepWithYou).map { "b\($0.id)" })
        #expect(!keepBoxes.isEmpty)
        #expect(cargo.allSatisfy { !keepBoxes.contains($0.id) })
        #expect(cargo.contains { $0.itemId == 1 })
        #expect(cargo.filter(\.isBox).count == plan.boxes.count - keepBoxes.count)
    }

    @Test func everythingLoadsInThePlannedTruck() {
        for items in [demoItems, bigMove] {
            let plan = PackingPlanner.plan(items: items)
            let load = TruckLoader.load(plan: plan, items: items)
            let sizes = TruckSize.allCases
            #expect(sizes.firstIndex(of: load.truck)! >= sizes.firstIndex(of: plan.truck.truck)!)
            print("planned \(plan.truck.truck), loaded \(load.truck) at \(Int(load.fill * 100))%")
            #expect(load.unloaded.isEmpty, "unloaded: \(load.unloaded.map(\.name)) in \(load.truck)")
            #expect(load.placements.count == TruckLoader.cargo(plan: plan, items: items).count)
        }
    }

    @Test func noOverlapsAndInsideBounds() {
        for (name, load) in loads() {
            let c = load.truck.cargoM
            for p in load.placements {
                #expect(p.x >= -1e-9 && p.y >= -1e-9 && p.z >= -1e-9, "\(name): \(p.item.name) below zero")
                #expect(p.x + p.sizeX <= c.length + 1e-6 && p.top <= c.height + 1e-6 && p.z + p.sizeZ <= c.width + 1e-6,
                        "\(name): \(p.item.name) outside the cargo box")
            }
            for (i, a) in load.placements.enumerated() {
                for b in load.placements[(i + 1)...] {
                    #expect(!a.overlaps(b), "\(name): \(a.item.name) overlaps \(b.item.name)")
                }
            }
        }
    }

    @Test func extentsMatchTheItem() {
        for (_, load) in loads() {
            for p in load.placements {
                let mine = [p.sizeX, p.sizeY, p.sizeZ].sorted()
                let its = [p.item.widthM, p.item.depthM, p.item.heightM].sorted()
                #expect(zip(mine, its).allSatisfy { abs($0 - $1) < 1e-9 })
                if p.tilt == .none { #expect(abs(p.sizeY - p.item.heightM) < 1e-9) }
                if p.item.isBox { #expect(p.tilt == .none) }
            }
        }
    }

    @Test func deterministic() {
        let plan = PackingPlanner.plan(items: bigMove)
        let a = TruckLoader.load(plan: plan, items: bigMove)
        let b = TruckLoader.load(plan: plan, items: bigMove.reversed())
        #expect(a == b)
    }

    @Test func stackingRules() {
        for (name, load) in loads() {
            for top in load.placements where top.y > 1e-6 {
                #expect(top.item.isBox, "\(name): only boxes ride on top (\(top.item.name))")
                let under = load.placements.filter { top.restsOn($0) }
                #expect(!under.isEmpty, "\(name): \(top.item.name) floats")
                for u in under {
                    #expect(u.order < top.order)
                    if u.item.fragile { #expect(top.item.fragile, "\(name): \(top.item.name) on fragile \(u.item.name)") }
                    if u.item.isBox {
                        let slack = u.item.fragile ? 0 : TruckLoader.heavierOnTopKg
                        #expect(top.item.weightKg <= u.item.weightKg + slack + 1e-9, "\(name): heavy \(top.item.name) on \(u.item.name)")
                    } else {
                        #expect(u.item.carriesBoxes, "\(name): box on \(u.item.name)")
                    }
                }
            }
        }
    }

    @Test func loadOrderFurnitureFirstOpenFirstLast() {
        let plan = PackingPlanner.plan(items: bigMove)
        let load = TruckLoader.load(plan: plan, items: bigMove)
        let kinds = load.placements.map { $0.item.isBox ? ($0.item.openFirst ? 2 : 1) : 0 }
        #expect(kinds == kinds.sorted())
        #expect(load.placements.map(\.order) == Array(1...load.placements.count))
        // The first piece goes against the cab wall, the open-first tote near the door.
        #expect(load.placements.first?.x == 0)
        if let open = load.placements.first(where: \.item.openFirst) {
            let maxX = load.placements.map(\.x).max() ?? 0
            #expect(open.x >= maxX * 0.5)
        }
    }

    @Test func mattressStandsOnEdge() {
        let plan = PackingPlanner.plan(items: bigMove)
        let load = TruckLoader.load(plan: plan, items: bigMove)
        let mattress = load.placements.first { $0.item.itemId == 10 }
        #expect(mattress != nil)
        #expect(mattress?.tilt != TruckPlacement.Tilt.none)
    }

    @Test func fillMatchesVolumeRatio() {
        for (name, load) in loads() {
            let placed = load.placements.reduce(0) { $0 + $1.item.volumeM3 }
            #expect(abs(load.fill - placed / load.truck.cargoVolumeM3) < 1e-9, "\(name)")
            #expect(load.fill >= 0 && load.fill <= 1)
        }
        // Close to the planner's own load estimate (which adds packing slack).
        let plan = PackingPlanner.plan(items: bigMove)
        let load = TruckLoader.load(plan: plan, items: bigMove)
        let estimate = plan.truck.loadM3 / load.truck.cargoVolumeM3
        #expect(load.fill <= estimate + 1e-9 && load.fill >= estimate * 0.6, "fill \(load.fill) vs estimate \(estimate)")
    }

    @Test func tooSmallTruckReportsUnloaded() {
        let plan = PackingPlanner.plan(items: bigMove)
        let load = TruckLoader.load(plan: plan, items: bigMove, truck: .cargoVan)
        let cargo = TruckLoader.cargo(plan: plan, items: bigMove)
        #expect(load.placements.count + load.unloaded.count == cargo.count)
        #expect(!load.unloaded.isEmpty)
    }

    @Test func emptyPlanLoadsNothing() {
        let load = TruckLoader.load(plan: .empty, items: [])
        #expect(load.placements.isEmpty && load.unloaded.isEmpty && load.fill == 0)
    }

    @Test func boughtPiecesAreDeliveredNotLoaded() {
        let s = DemoFixtures.demo(owner: "me")
        let withBought = PackingPlanner.plan(items: s.items, bought: s.boughtPieces)
        #expect(!withBought.delivered.isEmpty)
        let a = TruckLoader.load(plan: withBought, items: s.items)
        let b = TruckLoader.load(plan: PackingPlanner.plan(items: s.items), items: s.items)
        #expect(a == b, "bought pieces ship to the new place, so the load is the same")
        #expect(!a.placements.contains { p in withBought.delivered.contains { $0.name == p.item.name } })
    }

    /// The 3D truck is the plan's truck unless that truck genuinely can't hold the load.
    @Test func loaderKeepsThePlannedTruckUnlessItCantFit() {
        let demo = DemoFixtures.demo(owner: "me")
        for (items, bought) in [(demoItems, [BoughtPiece]()), (demo.items, demo.boughtPieces), (bigMove, [])] {
            let plan = PackingPlanner.plan(items: items, bought: bought)
            let load = TruckLoader.load(plan: plan, items: items)
            let inPlanned = TruckLoader.load(plan: plan, items: items, truck: plan.truck.truck)
            if inPlanned.unloaded.isEmpty {
                #expect(load.truck == plan.truck.truck)
                #expect(load.sizeNote(planned: plan.truck.truck) == nil)
            } else {
                #expect(load.truck != plan.truck.truck, "stepped up because \(inPlanned.unloaded.count) pieces didn't fit")
                #expect(load.sizeNote(planned: plan.truck.truck) != nil)
            }
        }
        let note = TruckLoad(truck: .ft10, placements: [], unloaded: [], fill: 0).sizeNote(planned: .cargoVan)
        #expect(note == "Fits a cargo van by volume; packs best in a 10 ft truck.")
    }

    @Test func truckShellAndBoxesBuild() {
        for size in TruckSize.allCases {
            let f = VoxelTruck.frame(size)
            let g = VoxelTruck.build(size)
            #expect(g.nx == f.nx && g.ny == f.ny && g.nz == f.nz)
            // The cargo space is empty (open roof and near side) and the floor under it is solid.
            let mid = (f.doorX + f.cabWallX) / 2
            #expect(g[mid, f.floorY + 2, f.farZ + f.width / 2] == nil)
            #expect(g[mid, f.floorY - 1, f.farZ + f.width / 2] != nil)
            #expect(g[mid, f.floorY + f.height + 1, f.farZ + 2] == nil, "no roof")
            #expect(g[mid, f.floorY + 4, f.farZ + f.width] == nil, "no near wall")
        }
        for size in BoxSize.allCases {
            let g = VoxelMovingBox.build(size, room: "Kitchen", fragile: true)
            #expect(g.filledCount > 0)
            #expect(VoxelMesher.mesh(g).triangleCount > 0)
        }
    }

    @Test func placementCenterLandsInTheCargoSpace() {
        let plan = PackingPlanner.plan(items: bigMove)
        let load = TruckLoader.load(plan: plan, items: bigMove)
        let f = VoxelTruck.frame(load.truck), s = VoxelGrid.voxelSize
        for p in load.placements {
            let c = VoxelTruck.center(of: p, in: load.truck)
            #expect(c.x > Double(f.doorX) * s - 1e-6 && c.x < Double(f.cabWallX) * s + 1e-6)
            #expect(c.y > Double(f.floorY) * s - 1e-6)
            #expect(c.z > Double(f.farZ) * s - 1e-6 && c.z < Double(f.farZ + f.width) * s + 1e-6)
        }
    }
}
