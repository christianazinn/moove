import Testing
@testable import MooveKit

/// The detector's (`ObjectVocabulary`) and vision's remaining categories that used to fall back to
/// the kraft box (motorcycle, stroller, wheelchair, crib, ladder, trunk, bins / baskets, trash can,
/// toolbox, grill, lawn mower, pet crate / bed, cat tree, clock, toys, racks) get real pieces.
@Suite struct VoxelRemainingKindsTests {
    func spec(_ category: String, _ name: String, _ w: Double = 0, _ d: Double = 0, _ h: Double = 0) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: w, depthM: d, heightM: h)
    }

    func kind(_ category: String, _ name: String, _ w: Double = 0, _ d: Double = 0, _ h: Double = 0) -> VoxelModels.Kind {
        VoxelModels.kind(spec(category, name, w, d, h))
    }

    static let triangleBound = 4000

    /// (category, name, expected kind): every new builder and its named variants.
    static let pieces: [(String, String, VoxelModels.Kind)] = [
        ("motorcycle", "Motorcycle", .motorcycle), ("motorcycle", "Harley cruiser motorcycle", .motorcycle),
        ("other", "KTM dirt bike", .motorcycle),
        ("stroller", "Stroller", .stroller), ("stroller", "BOB jogging stroller", .stroller), ("other", "Vintage pram", .stroller),
        ("wheelchair", "Wheelchair", .wheelchair), ("other", "Power wheelchair", .wheelchair),
        ("grill", "Grill", .grill), ("grill", "Weber kettle grill", .grill), ("other", "Stainless gas BBQ", .grill),
        ("other", "Big Green Egg kamado grill", .grill),
        ("lawn mower", "Lawn mower", .lawnMower), ("other", "John Deere riding mower", .lawnMower),
        ("crib", "Crib", .crib), ("crib", "White wooden crib", .crib), ("other", "Graco pack n play", .crib),
        ("other", "Bassinet", .crib),
        ("ladder", "Ladder", .ladder), ("ladder", "Werner fiberglass step ladder", .ladder), ("other", "Wooden step ladder", .ladder),
        ("trunk", "Trunk", .trunk), ("trunk", "Steamer trunk", .trunk), ("other", "Cedar hope chest", .trunk),
        ("toy", "Toy chest", .trunk),
        ("basket", "Basket", .basket), ("basket", "Laundry basket", .basket), ("bin", "Storage bin", .basket),
        ("other", "Wicker hamper", .basket), ("storage", "Fabric cube bin", .basket), ("decor", "Woven seagrass basket", .basket),
        ("trash can", "Trash can", .trashCan), ("trash can", "Simplehuman step trash can", .trashCan),
        ("other", "Office wastebasket", .trashCan), ("other", "Outdoor wheelie bin", .trashCan), ("other", "Blue recycling bin", .trashCan),
        ("toolbox", "Toolbox", .toolbox), ("toolbox", "Craftsman rolling tool chest", .toolbox),
        ("pet crate", "Pet crate", .petCrate), ("other", "Wire dog crate", .petCrate), ("other", "Plastic cat carrier", .petCrate),
        ("pet bed", "Dog bed", .petBed), ("other", "Orthopedic dog bed", .petBed), ("decor", "Calming donut cat bed", .petBed),
        ("cat tree", "Cat tree", .catTree), ("other", "Cat tower with condo", .catTree),
        ("clock", "Wall clock", .clock), ("decor", "Round black wall clock", .clock), ("clock", "Grandfather clock", .clock),
        ("electronics", "Alarm clock", .clock), ("decor", "Mantel clock", .clock),
        ("toy", "Stuffed animal", .toy), ("toy", "Teddy bear", .toy), ("toy", "Dollhouse", .toy), ("toy", "Rocking horse", .toy),
        ("other", "Lego toys", .toy),
        ("coat rack", "Coat rack", .rack), ("shoe rack", "Shoe rack", .rack), ("clothes rack", "Clothes rack", .rack),
        ("furniture", "Black metal garment rack", .rack), ("furniture", "Wooden hall tree", .rack),
    ]

    static let sizes: [(Double, Double, Double)] = [(0, 0, 0), (0.05, 0.05, 0.05), (0.4, 0.15, 1.0), (1.2, 0.5, 1.1), (8, 8, 4)]

    @Test func eachBuildsABoundedNonBoxMesh() {
        for (cat, name, want) in Self.pieces {
            #expect(kind(cat, name) == want, "\(cat)/\(name) -> \(kind(cat, name))")
            for (w, d, h) in Self.sizes {
                let s = spec(cat, name, w, d, h)
                let k = VoxelModels.kind(s)
                #expect(k != .box, "\(name) \(w)x\(d)x\(h)")
                let g = VoxelModels.build(s)
                #expect(g.filledCount > 0, "\(name) \(w)x\(d)x\(h) empty")
                #expect(g.filledCount < g.nx * g.ny * g.nz, "\(name) \(w)x\(d)x\(h) is a solid block")
                let (X, Y, Z) = VoxelModels.dims(s, k)
                let m = k.minDims ?? (1, 1, 1)
                #expect(g.nx == min(160, max(X, m.0)) && g.nz == min(160, max(Z, m.2)), "\(name) \(w)x\(d)x\(h) footprint")
                #expect(g.ny <= min(160, max(Y, m.1)), "\(name) \(w)x\(d)x\(h) height")
                let tris = VoxelMesher.mesh(g).triangleCount
                if w < 3 { #expect(tris > 0 && tris < Self.triangleBound, "\(name) \(w)x\(d)x\(h): \(tris) triangles") }
            }
        }
    }

    /// The filled voxels fill the scanned (w, h, d) within one voxel, at and around the default size.
    @Test func fillsTheScannedSize() {
        var bad: [String] = []
        for (cat, name, _) in Self.pieces {
            let def = VoxelModels.kind(spec(cat, name)).defaultSize
            for f in [0.8, 1.0, 1.3] {
                let s = spec(cat, name, def.0 * f, def.1 * f, def.2 * f)
                let k = VoxelModels.kind(s)
                let e = VoxelFootprintTests.extent(VoxelModels.build(s))
                let m = k.minDims ?? (1, 1, 1)
                let want = (max(vox(s.widthM), m.0), max(vox(s.heightM), m.1), max(vox(s.depthM), m.2))
                if abs(e.0 - want.0) > 1 || abs(e.1 - want.1) > 1 || abs(e.2 - want.2) > 1 {
                    bad.append("\(cat)/\(name) [\(k)] x\(f): want \(want) filled \(e)")
                }
            }
        }
        #expect(bad.isEmpty, "\(bad.count) pieces don't fill their size:\n\(bad.joined(separator: "\n"))")
    }

    @Test func thumbnailsRenderAndAreDeterministic() {
        for (cat, name, _) in Self.pieces {
            let sprite = IsoSprite.render(VoxelModels.build(spec(cat, name)))
            #expect(sprite.faces.count > 0, "\(name)")
            #expect(Set(sprite.faces.map { $0.color }).count > 2, "\(name) looks flat")
            let s = spec(cat, name, 0.6, 0.4, 1.0)
            #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(name)")
        }
    }

    @Test func variantsDifferAndMeasuredColorsWin() {
        func mask(_ cat: String, _ name: String, _ size: (Double, Double, Double)) -> [Bool] {
            VoxelModels.build(spec(cat, name, size.0, size.1, size.2)).cells.map { $0 != 0 }
        }
        let groups: [(String, [String], (Double, Double, Double))] = [
            ("grill", ["Gas grill", "Kettle grill"], (1.2, 0.6, 1.1)),
            ("lawn mower", ["Push lawn mower", "Riding lawn mower"], (0.6, 1.5, 1.0)),
            ("crib", ["Crib", "Pack n play", "Bassinet"], (1.3, 0.75, 1.0)),
            ("trunk", ["Steamer trunk", "Toy chest", "Cedar chest"], (0.9, 0.5, 0.5)),
            ("basket", ["Wicker basket", "Laundry basket", "Hamper", "Plastic storage bin"], (0.5, 0.4, 0.45)),
            ("trash can", ["Step trash can", "Wastebasket", "Wheelie bin"], (0.5, 0.5, 0.7)),
            ("toolbox", ["Toolbox", "Rolling tool chest"], (0.6, 0.35, 0.4)),
            ("pet crate", ["Wire dog crate", "Plastic pet carrier"], (0.9, 0.6, 0.65)),
            ("pet bed", ["Round dog bed", "Orthopedic dog bed"], (0.8, 0.6, 0.2)),
            ("clock", ["Wall clock", "Alarm clock", "Mantel clock"], (0.35, 0.15, 0.35)),
            ("toy", ["Teddy bear", "Dollhouse", "Rocking horse", "Lego toys"], (0.6, 0.4, 0.6)),
            ("rack", ["Coat rack", "Shoe rack", "Clothes rack"], (1.0, 0.45, 1.4)),
        ]
        for (cat, names, size) in groups {
            let masks = names.map { mask(cat, $0, size) }
            for i in masks.indices { for j in masks.indices where j > i { #expect(masks[i] != masks[j], "\(names[i]) vs \(names[j])") } }
        }
        for (cat, name, _) in Self.pieces {
            var a = spec(cat, name), b = a
            a.primaryColor = 0xC02020; b.primaryColor = 0x2040C0
            #expect(VoxelModels.build(a) != VoxelModels.build(b), "\(name): measured color ignored")
        }
    }

    @Test func everyNewKindHasAnEnvelope() {
        let kinds: [VoxelModels.Kind] = [.motorcycle, .stroller, .wheelchair, .grill, .lawnMower, .crib, .ladder, .trunk, .basket,
                                         .trashCan, .toolbox, .petCrate, .petBed, .catTree, .clock, .toy, .rack]
        for k in kinds {
            let env = VoxelModels.envelope(k, name: VName(k.rawValue))
            #expect(env != nil, "\(k)")
            // the default size, and 0.8 / 1.3 of it, are plausible for the kind
            for f in [0.8, 1.0, 1.3] {
                let d = k.defaultSize
                #expect(env?.contains((d.0 * f, d.1 * f, d.2 * f)) == true, "\(k) x\(f)")
            }
        }
        // a clearly wrong size still re-routes: a 2 m wide, 0.4 m tall "trash can" is a bed-sized slab
        #expect(kind("trash can", "Trash can", 2.0, 1.6, 0.45) == .bed)
    }

    // MARK: routing

    /// Detector categories that still have no builder of their own (small sports / music gear).
    static let stillBoxes: Set<String> = ["ball", "helmet", "ironing board", "racket", "room divider", "saxophone", "trumpet", "weights", "yoga mat", "box"]

    @Test func detectorCategoriesRouteOffTheBox() {
        var boxed: Set<String> = []
        for (label, cat) in ObjectVocabulary.categories {
            let name = label.prefix(1).uppercased() + label.dropFirst()
            if kind(cat, name) == .box || kind(cat, cat) == .box { boxed.insert(cat) }
        }
        #expect(boxed == Self.stillBoxes, "boxed: \(boxed.sorted())")
        let cases: [(String, String, VoxelModels.Kind)] = [
            ("motorcycle", "Motorcycle", .motorcycle), ("stroller", "Stroller", .stroller), ("wheelchair", "Wheelchair", .wheelchair),
            ("crib", "Crib", .crib), ("ladder", "Ladder", .ladder), ("trunk", "Trunk", .trunk), ("bin", "Storage bin", .basket),
            ("basket", "Laundry basket", .basket), ("trash can", "Trash can", .trashCan), ("toolbox", "Toolbox", .toolbox),
            ("grill", "Grill", .grill), ("lawn mower", "Lawn mower", .lawnMower), ("pet crate", "Pet crate", .petCrate),
            ("pet bed", "Dog bed", .petBed), ("cat tree", "Cat tree", .catTree), ("clock", "Wall clock", .clock),
            ("toy", "Stuffed animal", .toy), ("toy", "Dollhouse", .toy), ("toy", "Rocking horse", .toy),
            ("coat rack", "Coat rack", .rack), ("shoe rack", "Shoe rack", .rack), ("clothes rack", "Clothes rack", .rack),
            ("workbench", "Workbench", .desk), ("cart", "Rolling cart", .bookshelf),
        ]
        for (cat, name, want) in cases {
            #expect(kind(cat, name) == want, "\(cat)/\(name)")
            #expect(kind(cat, cat) == want, "\(cat)/\(cat)")
        }
    }

    @Test func visionWordsRoute() {
        let cases: [(String, String, VoxelModels.Kind)] = [
            ("vehicle", "Honda motorbike", .motorcycle), ("other", "Ducati", .motorcycle), ("furniture", "Wheel chair", .wheelchair),
            ("baby", "Uppababy stroller", .stroller), ("furniture", "Baby crib", .crib), ("furniture", "Dog bed", .petBed),
            ("furniture", "Desk clock", .clock), ("furniture", "Toy chest", .trunk), ("furniture", "Rolling tool chest with drawers", .toolbox),
            ("storage", "Laundry hamper", .basket), ("storage", "Plastic tote", .basket), ("kitchen appliance", "Kitchen trash can", .trashCan),
            ("outdoor", "Weber grill", .grill), ("outdoor", "Lawnmower", .lawnMower), ("tools", "Toolbox", .toolbox),
            ("other", "Dog kennel", .petCrate), ("other", "Scratching post", .catTree), ("other", "Plush bunny", .toy),
            ("furniture", "Coat stand", .rack), ("chest", "Chest", .trunk), ("other", "Step ladder", .ladder),
        ]
        for (cat, name, want) in cases { #expect(kind(cat, name) == want, "\(cat)/\(name)") }
    }

    @Test func existingRoutesHold() {
        let cases: [(String, String, VoxelModels.Kind)] = [
            ("furniture", "Chest of drawers", .dresser), ("storage", "Tall chest of drawers", .dresser), ("decor", "Blanket ladder", .quiltRack),
            ("storage", "Ladder shelf", .bookshelf), ("furniture", "Bunk bed", .bed), ("furniture", "Rocking chair", .chair),
            ("furniture", "High chair", .chair), ("bicycle", "Kids BMX bike", .bike), ("scooter", "Electric scooter", .scooter),
            ("kitchenware", "Grill pan", .kitchenware), ("kitchenware", "Bread bin", .kitchenware), ("appliance", "Chest freezer", .appliance),
            ("furniture", "Ski rack", .box), ("box", "Cardboard box", .box), ("storage", "Moving box", .box), ("bag", "Tote bag", .bag),
            ("clothes", "Motorcycle jacket", .clothes), ("other", "Motorcycle helmet", .box), ("decor", "Towel rack", .quiltRack),
            ("mattress", "Crib mattress", .mattress), ("bench", "Weight bench", .bench), ("storage", "Shoe cabinet", .dresser),
            ("decor", "Throw pillow", .decor), ("furniture", "Desk lamp", .lamp),
        ]
        for (cat, name, want) in cases { #expect(kind(cat, name) == want, "\(cat)/\(name)") }
    }

    // MARK: placement

    @Test func floorThingsStayOnTheFloorAndWallClocksHang() {
        #expect(PropPlacer.role(of: spec("clock", "Wall clock", 0.35, 0.05, 0.35)) == .wall)
        #expect(PropPlacer.role(of: spec("decor", "Round wall clock")) == .wall)
        #expect(PropPlacer.role(of: spec("clock", "Grandfather clock", 0.5, 0.3, 2.0)) == .furniture)
        #expect(PropPlacer.role(of: spec("electronics", "Alarm clock", 0.15, 0.08, 0.1)) == .prop)
        #expect(PropPlacer.role(of: spec("toy", "Teddy bear", 0.3, 0.25, 0.35)) == .prop) // a plush can sit on a shelf
        for (cat, name, w, d, h) in [("trash can", "Trash can", 0.3, 0.3, 0.4), ("basket", "Basket", 0.4, 0.3, 0.3),
                                     ("toolbox", "Toolbox", 0.45, 0.2, 0.2), ("pet bed", "Cat bed", 0.5, 0.4, 0.15),
                                     ("shoe rack", "Shoe rack", 0.6, 0.3, 0.5), ("trunk", "Trunk", 0.6, 0.4, 0.4)] {
            #expect(PropPlacer.role(of: spec(cat, name, w, d, h)) == .furniture, "\(name)")
        }
        // a hung clock is the thin wall variant
        let wall = VoxelModels.build(VoxelModels.wallVariant(spec("clock", "Wall clock", 0.35, 0.2, 0.35)))
        #expect(wall.nz <= 2)
    }
}
