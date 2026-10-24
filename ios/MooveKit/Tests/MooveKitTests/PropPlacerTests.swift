import Foundation
import Testing
@testable import MooveKit

@Suite struct SurfaceTests {
    func spec(_ category: String, _ name: String, _ w: Double, _ d: Double, _ h: Double) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: w, depthM: d, heightM: h, id: name)
    }

    static let holders: [(String, String, Double, Double, Double)] = [
        ("desk", "Oak desk", 1.2, 0.6, 0.75),
        ("desk", "IKEA white desk with drawers", 1.4, 0.7, 0.75),
        ("desk", "L-shaped corner desk", 1.6, 1.2, 0.75),
        ("table", "Dining table", 1.6, 0.9, 0.75),
        ("table", "Round bistro table", 0.8, 0.8, 0.75),
        ("table", "Glass coffee table", 1.0, 0.6, 0.45),
        ("storage", "Walnut dresser", 1.2, 0.5, 0.9),
        ("storage", "Nightstand", 0.45, 0.4, 0.55),
        ("storage", "Bookshelf", 0.8, 0.3, 1.8),
        ("storage", "Kallax cube shelf", 0.8, 0.4, 0.8),
        ("tv", "TV on media console", 1.4, 0.45, 1.2),
    ]

    @Test func holdersHaveSurfacesNotFloatingOrBuried() {
        for h in Self.holders {
            let s = spec(h.0, h.1, h.2, h.3, h.4)
            let (g, surfaces) = VoxelModels.buildWithSurfaces(s)
            #expect(!surfaces.isEmpty, "\(h.1) has a surface")
            #expect(VoxelModels.build(s) == g)
            #expect(VoxelModels.surfaces(s) == surfaces)
            for sf in surfaces {
                #expect(sf.x0 >= 0 && sf.z0 >= 0 && sf.x1 <= g.nx && sf.z1 <= g.nz && sf.width > 0 && sf.depth > 0 && sf.y >= 1 && sf.y <= g.ny)
                var under = 0, total = 0, above = 0
                let top = sf.clearance.map { sf.y + $0 } ?? g.ny
                for z in sf.z0..<sf.z1 {
                    for x in sf.x0..<sf.x1 {
                        total += 1
                        if g[x, sf.y - 1, z] != nil { under += 1 }
                        for y in sf.y..<top where g[x, y, z] != nil { above += 1 }
                    }
                }
                #expect(Double(under) >= Double(total) * 0.9, "\(h.1): surface at y=\(sf.y) is solid underneath (\(under)/\(total))")
                #expect(above == 0, "\(h.1): nothing in the way above y=\(sf.y)")
            }
        }
    }

    @Test func bookshelfHasShelfSlots() {
        let surfaces = VoxelModels.surfaces(spec("storage", "Bookshelf", 0.8, 0.3, 1.8))
        #expect(surfaces.contains { $0.clearance != nil }, "a free shelf slot")
        #expect(surfaces.contains { $0.clearance == nil && $0.y == VoxelModels.build(spec("storage", "Bookshelf", 0.8, 0.3, 1.8)).ny })
    }

    @Test func seatsAndPropsHaveNone() {
        for s in [spec("chair", "Desk chair", 0.6, 0.6, 1.0), spec("sofa", "Sofa", 2, 0.9, 0.85), spec("bed", "Queen bed", 1.6, 2.1, 0.5),
                  spec("lamp", "Table lamp", 0.3, 0.3, 0.5), spec("storage", "Wardrobe", 1.0, 0.6, 2.0)] {
            #expect(VoxelModels.surfaces(s).isEmpty, "\(s.name)")
        }
    }

    @Test func wallVariantIsThin() {
        let art = spec("art", "Framed canvas print", 0.6, 0.3, 0.8)
        let normal = VoxelModels.build(art), flat = VoxelModels.build(VoxelModels.wallVariant(art))
        #expect(normal.nz > 2 && flat.nz <= 2)
        #expect(flat.filledCount > 0)
        let tv = spec("tv", "Samsung TV", 1.2, 0.25, 0.7)
        let wtv = VoxelModels.build(VoxelModels.wallVariant(tv))
        #expect(wtv.nz <= 2)
        // no feet: the bottom row is only the panel, nothing sticking forward
        #expect(VoxelModels.wallVariant(VoxelModels.wallVariant(tv)) == VoxelModels.wallVariant(tv))
    }
}

@Suite struct PropPlacerTests {
    static let V = VoxelGrid.voxelSize
    static let plan = FloorPlan(
        rooms: [.rectangle("Bedroom", kind: .bedroom, x: 0, y: 0, width: 4.2, depth: 3.6)],
        doors: [WallOpening(from: PlanPoint(0.4, 3.6), to: PlanPoint(1.3, 3.6))],
        windows: [WallOpening(from: PlanPoint(1.5, 0), to: PlanPoint(2.7, 0))]
    )

    static let items: [LayoutItem] = [
        LayoutItem(id: 1, name: "Queen bed", category: "bed", widthM: 1.6, depthM: 2.1, heightM: 0.5),
        LayoutItem(id: 2, name: "Nightstand", category: "storage", widthM: 0.45, depthM: 0.4, heightM: 0.55),
        LayoutItem(id: 3, name: "Bookshelf", category: "storage", widthM: 0.8, depthM: 0.3, heightM: 1.8),
        LayoutItem(id: 4, name: "Oak desk", category: "desk", widthM: 1.2, depthM: 0.6, heightM: 0.75),
        LayoutItem(id: 5, name: "Table lamp", category: "lamp", widthM: 0.3, depthM: 0.3, heightM: 0.45),
        LayoutItem(id: 6, name: "Framed photos", category: "photos", widthM: 0.2, depthM: 0.05, heightM: 0.25),
        LayoutItem(id: 7, name: "Stack of books", category: "books", widthM: 0.3, depthM: 0.22, heightM: 0.2),
        LayoutItem(id: 8, name: "Monitor", category: "electronics", widthM: 0.6, depthM: 0.2, heightM: 0.45),
        LayoutItem(id: 9, name: "Abstract art print", category: "art", widthM: 0.6, depthM: 0.04, heightM: 0.5),
        LayoutItem(id: 10, name: "Round mirror", category: "decor", widthM: 0.5, depthM: 0.04, heightM: 0.5),
        LayoutItem(id: 11, name: "Wall mounted TV", category: "electronics", widthM: 1.0, depthM: 0.1, heightM: 0.6),
        LayoutItem(id: 12, name: "Desk chair", category: "chair", widthM: 0.6, depthM: 0.6, heightM: 1.0),
        LayoutItem(id: 13, name: "Floor lamp", category: "lamp", widthM: 0.4, depthM: 0.4, heightM: 1.6),
    ]
    static var specs: [UInt64: VoxelItemSpec] { Dictionary(uniqueKeysWithValues: items.map { ($0.id, VoxelItemSpec($0)) }) }

    static func layout() -> (before: [Placement], after: [Placement]) {
        let before = LayoutSolver(plan: plan).solve(items, style: .byFunction).placements
        return (before, PropPlacer(plan: plan).place(before, items: items))
    }

    @Test func roles() {
        let s = Self.specs
        #expect(PropPlacer.role(of: s[1]!) == .furniture)
        #expect(PropPlacer.role(of: s[2]!) == .furniture) // a nightstand is small but furniture
        #expect(PropPlacer.role(of: s[5]!) == .prop)
        #expect(PropPlacer.role(of: s[6]!) == .prop) // short framed photo: shelf, not wall
        #expect(PropPlacer.role(of: s[8]!) == .prop)
        #expect(PropPlacer.role(of: s[9]!) == .wall)
        #expect(PropPlacer.role(of: s[10]!) == .wall)
        #expect(PropPlacer.role(of: s[11]!) == .wall)
        #expect(PropPlacer.role(of: s[12]!) == .furniture)
        #expect(PropPlacer.role(of: s[13]!) == .furniture)
        let tv = VoxelItemSpec(category: "tv", name: "TV", widthM: 1, depthM: 0.1, heightM: 0.6)
        #expect(PropPlacer.role(of: tv) == .prop) // a small TV goes on a dresser / stand
        #expect(PropPlacer.role(of: VoxelItemSpec(category: "tv", name: "TV", widthM: 1.4, depthM: 0.45, heightM: 1.2)) == .furniture)
        #expect(PropPlacer.role(of: tv, elevationM: 1.0) == .wall) // scanned on the wall
    }

    @Test func propsLandOnTheRightFurniture() {
        let (before, after) = Self.layout()
        #expect(before.count == after.count)
        let by = Dictionary(uniqueKeysWithValues: after.map { ($0.itemId, $0) })
        #expect(by[5]?.onTopOf == 2, "lamp on the nightstand")
        #expect(by[6]?.onTopOf == 3, "photos on the bookshelf")
        #expect(by[8]?.onTopOf == 4, "monitor on the desk")
        #expect(by[7]?.onTopOf != nil, "books on something")
        for id: UInt64 in [1, 2, 3, 4, 12, 13] {
            #expect(by[id] == before.first { $0.itemId == id }, "furniture \(id) unchanged")
        }
        // Same input, same output.
        #expect(PropPlacer(plan: Self.plan).place(before, items: Self.items) == after)
    }

    @Test func noPropFloatsOrSinksAndStaysOnItsParent() {
        let (_, after) = Self.layout()
        let by = Dictionary(uniqueKeysWithValues: after.map { ($0.itemId, $0) })
        let V = Self.V
        for p in after {
            guard let parentId = p.onTopOf, let parent = by[parentId] else { continue }
            let pg = VoxelModels.build(Self.specs[parentId]!), g = VoxelModels.build(Self.specs[p.itemId]!)
            let elev = try! #require(p.elevationM)
            let ey = Int((elev / V).rounded())
            #expect(abs(Double(ey) * V - elev) < 1e-9, "elevation on a voxel layer")
            // The prop's footprint in the parent's local voxel coords.
            let rect = OrientedRect(center: PlanPoint(p.x, p.y), halfWidth: Double(g.nx) * V / 2, halfDepth: Double(g.nz) * V / 2, rotationDeg: p.rotationDeg)
            let r = parent.rotationDeg * .pi / 180
            let ax = PlanPoint(cos(r), -sin(r)), az = PlanPoint(sin(r), cos(r))
            let local = rect.corners.map { c -> (Double, Double) in
                let v = c - PlanPoint(parent.x, parent.y)
                return (v.dot(ax) / V + Double(pg.nx) / 2, v.dot(az) / V + Double(pg.nz) / 2)
            }
            let x0 = local.map(\.0).min()!, x1 = local.map(\.0).max()!, z0 = local.map(\.1).min()!, z1 = local.map(\.1).max()!
            #expect(x0 >= -1e-6 && z0 >= -1e-6 && x1 <= Double(pg.nx) + 1e-6 && z1 <= Double(pg.nz) + 1e-6, "item \(p.itemId) within parent \(parentId)")
            let xs = Int(x0.rounded())..<Int(x1.rounded()), zs = Int(z0.rounded())..<Int(z1.rounded())
            var under = 0, total = 0, inside = 0
            for z in zs {
                for x in xs {
                    total += 1
                    if pg[x, ey - 1, z] != nil { under += 1 }
                    for y in ey..<(ey + g.ny) where pg[x, y, z] != nil { inside += 1 }
                }
            }
            #expect(under * 10 >= total * 9, "item \(p.itemId) rests on \(parentId) (\(under)/\(total))")
            #expect(inside == 0, "item \(p.itemId) doesn't sink into \(parentId)")
        }
    }

    @Test func propsDontOverlapEachOther() {
        let (_, after) = Self.layout()
        let props = after.filter { $0.onTopOf != nil }
        #expect(props.count >= 4)
        for (i, a) in props.enumerated() {
            for b in props[(i + 1)...] where a.onTopOf == b.onTopOf && a.elevationM == b.elevationM {
                let ga = VoxelModels.build(Self.specs[a.itemId]!), gb = VoxelModels.build(Self.specs[b.itemId]!)
                let ra = OrientedRect(center: PlanPoint(a.x, a.y), halfWidth: Double(ga.nx) * Self.V / 2, halfDepth: Double(ga.nz) * Self.V / 2, rotationDeg: a.rotationDeg)
                let rb = OrientedRect(center: PlanPoint(b.x, b.y), halfWidth: Double(gb.nx) * Self.V / 2, halfDepth: Double(gb.nz) * Self.V / 2, rotationDeg: b.rotationDeg)
                #expect(!ra.overlaps(rb), "\(a.itemId) vs \(b.itemId)")
            }
        }
    }

    @Test func wallItemsHangOnAWallFacingIn() {
        let (_, after) = Self.layout()
        let room = Self.plan.rooms[0]
        let hung = after.filter(\.isWallMounted)
        #expect(Set(hung.map(\.itemId)) == [9, 10, 11])
        for p in hung {
            let g = VoxelModels.build(VoxelModels.wallVariant(Self.specs[p.itemId]!))
            let bottom = try! #require(p.elevationM)
            #expect(bottom >= 0.1 && bottom + Double(g.ny) * Self.V <= 1.1 + 1e-9, "\(p.itemId) under the cut walls")
            // Back against the nearest wall's inner face, front toward the room.
            let edgeDistance = room.edges.map { PropPlacer.distance(PlanPoint(p.x, p.y), $0.0, $0.1) }.min()!
            #expect(abs(edgeDistance - (Self.V + 0.005 + Double(g.nz) * Self.V / 2)) < 1e-6)
            let r = p.rotationDeg * .pi / 180
            let front = PlanPoint(sin(r), cos(r))
            #expect(front.dot(room.centroid - PlanPoint(p.x, p.y)) > 0, "\(p.itemId) faces in")
            // Clear of the window (y = 0, x 1.5 ... 2.7) and the door.
            if abs(p.y) < 0.2 { #expect(p.x + Double(g.nx) * Self.V / 2 <= 1.5 || p.x - Double(g.nx) * Self.V / 2 >= 2.7) }
        }
        // Hung items don't overlap each other.
        for (i, a) in hung.enumerated() {
            for b in hung[(i + 1)...] {
                let ga = VoxelModels.build(VoxelModels.wallVariant(Self.specs[a.itemId]!)), gb = VoxelModels.build(VoxelModels.wallVariant(Self.specs[b.itemId]!))
                let ra = OrientedRect(center: PlanPoint(a.x, a.y), halfWidth: Double(ga.nx) * Self.V / 2, halfDepth: 0.05, rotationDeg: a.rotationDeg)
                let rb = OrientedRect(center: PlanPoint(b.x, b.y), halfWidth: Double(gb.nx) * Self.V / 2, halfDepth: 0.05, rotationDeg: b.rotationDeg)
                let vertical = a.elevationM! < b.elevationM! + Double(gb.ny) * Self.V && b.elevationM! < a.elevationM! + Double(ga.ny) * Self.V
                #expect(!(ra.overlaps(rb) && vertical), "\(a.itemId) vs \(b.itemId)")
            }
        }
    }

    @Test func tallWallItemsLeanAndScanHeightIsKept() {
        let room = FloorPlan(rooms: [.rectangle("Room", x: 0, y: 0, width: 3, depth: 3)])
        let big = VoxelItemSpec(category: "decor", name: "Floor mirror", widthM: 0.6, depthM: 0.05, heightM: 1.6)
        let tv = VoxelItemSpec(category: "tv", name: "TV", widthM: 1.0, depthM: 0.1, heightM: 0.5)
        let placements = [Placement(itemId: 1, room: "Room", x: 1.5, y: 0.2),
                          Placement(itemId: 2, room: "Room", x: 0.2, y: 1.5, rotationDeg: 90, elevationM: 0.4)]
        let out = PropPlacer(plan: room).place(placements, specs: [1: big, 2: tv])
        #expect(out[0].isWallMounted && out[0].elevationM == 0, "leans on the floor")
        #expect(abs(out[0].y - (2 * Self.V + 0.005 + 0.025)) < 1e-6, "in front of the baseboard, at the near wall")
        #expect(out[1].isWallMounted && out[1].elevationM == 0.4, "scanned height kept")
        #expect(abs(out[1].rotationDeg - 90) < 1e-9 && out[1].x < 0.2)
        // Taller walls: hung at the gallery height.
        let tall = PropPlacer(plan: room, wallTopM: 2.6).place([Placement(itemId: 2, room: "Room", x: 1.5, y: 0.2)], specs: [2: VoxelModels.wallVariant(tv).with(name: "Wall TV")])
        #expect(abs(tall[0].elevationM! - (1.45 - 0.25)) < 1e-9)
    }

    // Scanned positions (Lisa's iPad scan): what the scan located stays where it was seen.
    static let scanRoom = FloorPlan(rooms: [.rectangle("Room", x: 0, y: 0, width: 4, depth: 4)])
    static let scanItems: [LayoutItem] = [
        LayoutItem(id: 1, name: "Oak desk", category: "desk", widthM: 1.2, depthM: 0.6, heightM: 0.75),
        LayoutItem(id: 2, name: "Nightstand", category: "storage", widthM: 0.45, depthM: 0.4, heightM: 0.55),
        LayoutItem(id: 3, name: "Table lamp", category: "lamp", widthM: 0.3, depthM: 0.3, heightM: 0.45),
        LayoutItem(id: 4, name: "Stack of books", category: "books", widthM: 0.3, depthM: 0.22, heightM: 0.2),
        LayoutItem(id: 5, name: "Abstract art print", category: "art", widthM: 0.6, depthM: 0.04, heightM: 0.5),
    ]
    static let desk = Placement(itemId: 1, room: "Room", x: 1.0, y: 3.0)
    static let nightstand = Placement(itemId: 2, room: "Room", x: 3.5, y: 0.5)

    @Test func scannedLampOnTheFloorStaysPut() {
        let lamp = Placement(itemId: 3, room: "Room", x: 2.5, y: 2.0, rotationDeg: 90)
        let out = PropPlacer(plan: Self.scanRoom).place([Self.desk, Self.nightstand, lamp], items: Self.scanItems, scanned: [1, 2, 3])
        #expect(out[2] == lamp, "not moved onto the nightstand")
        // Unscanned, the same lamp still goes to the nightstand.
        let free = PropPlacer(plan: Self.scanRoom).place([Self.desk, Self.nightstand, lamp], items: Self.scanItems, scanned: [1, 2])
        #expect(free[2].onTopOf == 2)
    }

    @Test func scannedLampOverADeskSitsOnItAtItsOwnSpot() {
        let lamp = Placement(itemId: 3, room: "Room", x: 1.4, y: 3.1, rotationDeg: 30)
        let out = PropPlacer(plan: Self.scanRoom).place([Self.desk, Self.nightstand, lamp], items: Self.scanItems, scanned: [1, 2, 3])
        let deskTop = VoxelModels.buildWithSurfaces(VoxelItemSpec(Self.scanItems[0])).surfaces.map(\.y).max()!
        #expect(out[2].onTopOf == 1, "on the desk, not the nightstand")
        #expect(out[2].x == 1.4 && out[2].y == 3.1 && out[2].rotationDeg == 30)
        #expect(abs(out[2].elevationM! - Double(deskTop) * Self.V) < 1e-9)
        // Just past the desk's edge (within 15 cm) still counts; far past it doesn't.
        let edge = Placement(itemId: 3, room: "Room", x: 1.0, y: 3.38)
        #expect(PropPlacer(plan: Self.scanRoom).place([Self.desk, edge], items: Self.scanItems, scanned: [1, 3])[1].onTopOf == 1)
        let off = Placement(itemId: 3, room: "Room", x: 1.0, y: 3.6)
        #expect(PropPlacer(plan: Self.scanRoom).place([Self.desk, off], items: Self.scanItems, scanned: [1, 3])[1] == off)
    }

    @Test func unscannedBookStillGoesOnASurfaceAroundAScannedLamp() {
        let lamp = Placement(itemId: 3, room: "Room", x: 1.0, y: 3.0)
        let book = Placement(itemId: 4, room: "Room", x: 2, y: 2)
        let out = PropPlacer(plan: Self.scanRoom).place([Self.desk, Self.nightstand, lamp, book], items: Self.scanItems, scanned: [1, 2, 3])
        #expect(out[2].onTopOf == 1 && out[2].x == 1.0 && out[2].y == 3.0)
        #expect(out[3].onTopOf != nil, "the book found a surface")
        if out[3].onTopOf == 1 { #expect(hypot(out[3].x - 1.0, out[3].y - 3.0) > 0.2, "not on top of the lamp") }
    }

    @Test func scannedWallArtKeepsItsWallAndSpot() {
        // Scanned near the left wall (x = 0) at y = 1.2; the nearest-wall re-hang would also pick
        // x = 0, but an unscanned piece blocked there would slide. Scanned ones keep y.
        let art = Placement(itemId: 5, room: "Room", x: 0.1, y: 1.2, elevationM: 0.5)
        let out = PropPlacer(plan: Self.scanRoom).place([art], items: Self.scanItems, scanned: [5])
        #expect(out[0].isWallMounted)
        #expect(abs(out[0].y - 1.2) < 1e-9 && out[0].x < 0.1)
        #expect(out[0].elevationM == 0.5)
        // A window over that spot doesn't push a scanned piece along the wall.
        let windowed = FloorPlan(rooms: Self.scanRoom.rooms, windows: [WallOpening(from: PlanPoint(0, 0.8), to: PlanPoint(0, 1.6))])
        let kept = PropPlacer(plan: windowed).place([art], items: Self.scanItems, scanned: [5])
        #expect(abs(kept[0].y - 1.2) < 1e-9)
        let slid = PropPlacer(plan: windowed).place([art], items: Self.scanItems)
        #expect(abs(slid[0].y - 1.2) > 0.1)
    }

    @Test func scanPropsWithoutPlacementsJoinTheRoom() {
        let (before, _) = Self.layout()
        let furniture = before.filter { [1, 2, 3, 4, 12, 13].contains($0.itemId) }
        let out = PropPlacer(plan: Self.plan).place(furniture, items: Self.items, extraRoom: "Bedroom")
        let ids = Set(out.map(\.itemId))
        #expect(ids.isSuperset(of: [5, 6, 8, 9, 10, 11]))
        #expect(out.first { $0.itemId == 5 }?.onTopOf == 2)
        // Without a room, nothing is added.
        #expect(PropPlacer(plan: Self.plan).place(furniture, items: Self.items).count == furniture.count)
    }

    @Test func placementJSONIsBackwardCompatible() throws {
        let old = #"[{"itemId":3,"room":"Bedroom","rotationDeg":90,"x":1.5,"y":2}]"#
        let decoded = try JSONDecoder().decode([Placement].self, from: Data(old.utf8))
        #expect(decoded == [Placement(itemId: 3, room: "Bedroom", x: 1.5, y: 2, rotationDeg: 90)])
        #expect(Layout.encode(decoded) == old)
        let lifted = [Placement(itemId: 5, room: "Bedroom", x: 1, y: 1, rotationDeg: 0, elevationM: 0.55, onTopOf: 2),
                      Placement(itemId: 9, room: "Bedroom", x: 2, y: 0.1, rotationDeg: 0, elevationM: 0.6, wallMounted: true)]
        let json = Layout.encode(lifted)
        #expect(json.contains("\"onTopOf\":2") && json.contains("\"elevationM\":0.55") && json.contains("\"wallMounted\":true"))
        let layout = Layout(id: 1, owner: "me", newHomeId: 1, name: "x", placementsJson: json)
        #expect(layout.placements == lifted)
    }
}

private extension VoxelItemSpec {
    func with(name: String) -> VoxelItemSpec {
        var s = self
        s.name = name
        return s
    }
}
