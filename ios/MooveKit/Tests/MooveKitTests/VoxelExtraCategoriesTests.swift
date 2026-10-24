import Testing
@testable import MooveKit

/// #183: the scan detector's (#98, `ObjectVocabulary`) and the vision agent's (#131) extra
/// categories get real voxel pieces instead of the kraft-box fallback.
@Suite struct VoxelExtraCategoriesTests {
    func spec(_ category: String, _ name: String, _ w: Double = 0, _ d: Double = 0, _ h: Double = 0) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: w, depthM: d, heightM: h)
    }

    func kind(_ category: String, _ name: String, _ w: Double = 0, _ d: Double = 0, _ h: Double = 0) -> VoxelModels.Kind {
        VoxelModels.kind(spec(category, name, w, d, h))
    }

    /// Mesh triangles for one piece stay well under what a list of thumbnails / a dollhouse can draw.
    static let triangleBound = 4000

    /// (category, name, expected kind): every new builder and its named variants.
    static let pieces: [(String, String, VoxelModels.Kind)] = [
        ("guitar", "Acoustic guitar", .guitar), ("guitar", "Sunburst Fender Stratocaster electric guitar", .guitar),
        ("guitar", "Ukulele", .guitar), ("instrument", "Violin", .guitar), ("instrument", "Cello", .guitar),
        ("instrument", "Guitar in hard case", .guitar), ("instrument", "Bass guitar", .guitar),
        ("piano", "Piano", .piano), ("piano", "Walnut upright piano", .piano), ("instrument", "Baby grand piano", .piano),
        ("keyboard instrument", "Keyboard instrument", .keyboard), ("instrument", "Yamaha keyboard on stand", .keyboard),
        ("instrument", "Korg synth", .keyboard), ("piano", "Roland digital piano", .keyboard),
        ("drums", "Drums", .drums), ("instrument", "Pearl drum kit", .drums), ("instrument", "Roland electronic drum kit", .drums),
        ("vacuum", "Vacuum", .vacuum), ("vacuum", "Upright vacuum cleaner", .vacuum), ("vacuum", "Dyson cordless stick vacuum", .vacuum),
        ("vacuum", "Roomba robot vacuum", .vacuum), ("vacuum", "Shop vac", .vacuum), ("vacuum", "Henry canister vacuum", .vacuum),
        ("monitor", "Monitor", .monitor), ("monitor", "Dell 27 inch monitor", .monitor), ("electronics", "Curved ultrawide monitor", .monitor),
        ("monitor", "Dual monitors", .monitor), ("electronics", "Apple iMac", .monitor),
        ("scooter", "Scooter", .scooter), ("scooter", "Kick scooter", .scooter), ("scooter", "Xiaomi electric scooter", .scooter),
        ("scooter", "Kids scooter", .scooter),
        ("bag", "Bag", .bag), ("backpack", "Backpack", .bag), ("bag", "Black North Face backpack", .bag), ("bag", "Duffel bag", .bag),
        ("bag", "Canvas tote bag", .bag), ("bag", "Leather briefcase", .bag), ("golf clubs", "Golf clubs", .bag),
        ("punching bag", "Punching bag", .bag),
        ("treadmill", "Treadmill", .fitness), ("exercise bike", "Peloton exercise bike", .fitness),
        ("rowing machine", "Rowing machine", .fitness), ("rowing machine", "WaterRower water rower", .fitness),
        ("other", "Elliptical cross trainer", .fitness),
        ("skateboard", "Skateboard", .board), ("surfboard", "Surfboard", .board), ("snowboard", "Snowboard", .board),
        ("skis", "Skis", .board),
    ]

    /// (w, d, h) in meters: defaults (0 = missing), tiny (clamped up to minDims), the detector's
    /// usual boxes, and huge.
    static let sizes: [(Double, Double, Double)] = [(0, 0, 0), (0.05, 0.05, 0.05), (0.4, 0.15, 1.0), (1.2, 0.5, 1.1), (8, 8, 4)]

    @Test func eachNewCategoryBuildsABoundedNonBoxMesh() {
        for (cat, name, want) in Self.pieces {
            for (w, d, h) in Self.sizes {
                let s = spec(cat, name, w, d, h)
                let k = VoxelModels.kind(s)
                #expect(k == want, "\(cat)/\(name) -> \(k)")
                #expect(k != .box)
                let g = VoxelModels.build(s)
                #expect(g.filledCount > 0, "\(name) \(w)x\(d)x\(h) empty")
                #expect(g.filledCount < g.nx * g.ny * g.nz, "\(name) \(w)x\(d)x\(h) is a solid block")
                #expect(g.cells.allSatisfy { $0 == 0 || $0 & 0x1000000 != 0 })
                // the grid is the spec's size (kind defaults for missing dims, raised to minDims,
                // capped at 8 m; a robot vacuum is a low disc)
                let (X, Y, Z) = VoxelModels.dims(s, k)
                let m = k.minDims ?? (1, 1, 1)
                #expect(g.nx == min(160, max(X, m.0)) && g.nz == min(160, max(Z, m.2)), "\(name) \(w)x\(d)x\(h) footprint")
                #expect(g.ny <= min(160, max(Y, m.1)), "\(name) \(w)x\(d)x\(h) height")
                let tris = VoxelMesher.mesh(g).triangleCount
                if w < 3 { #expect(tris > 0 && tris < Self.triangleBound, "\(name) \(w)x\(d)x\(h): \(tris) triangles") }
            }
        }
    }

    @Test func thumbnailsRender() {
        for (cat, name, _) in Self.pieces {
            let sprite = IsoSprite.render(VoxelModels.build(spec(cat, name)))
            #expect(sprite.faces.count > 0, "\(name)")
            #expect(Set(sprite.faces.map { $0.color }).count > 2, "\(name) looks flat")
        }
    }

    @Test func deterministic() {
        for (cat, name, _) in Self.pieces {
            let s = spec(cat, name, 0.6, 0.4, 1.0)
            #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(name)")
        }
    }

    @Test func variantsDiffer() {
        func mask(_ cat: String, _ name: String, _ w: Double, _ d: Double, _ h: Double) -> [Bool] {
            VoxelModels.build(spec(cat, name, w, d, h)).cells.map { $0 != 0 }
        }
        let groups: [(String, [String], (Double, Double, Double))] = [
            ("guitar", ["Acoustic guitar", "Electric guitar", "Violin", "Guitar case"], (0.4, 0.3, 1.05)),
            ("vacuum", ["Upright vacuum", "Stick vacuum", "Canister vacuum"], (0.35, 0.3, 1.1)),
            ("scooter", ["Kick scooter", "Electric scooter", "Kids scooter"], (1.05, 0.45, 1.1)),
            ("bag", ["Backpack", "Tote bag", "Duffel bag", "Golf bag", "Briefcase"], (0.4, 0.25, 0.45)),
            ("fitness", ["Treadmill", "Exercise bike", "Rowing machine"], (0.8, 1.8, 1.2)),
            ("piano", ["Upright piano", "Grand piano"], (1.5, 1.5, 1.0)),
            ("drums", ["Drum kit", "Electronic drum kit"], (1.6, 1.3, 1.3)),
            ("monitor", ["Monitor", "Dual monitor", "Curved monitor", "iMac"], (1.0, 0.25, 0.5)),
        ]
        for (cat, names, (w, d, h)) in groups {
            let masks = names.map { mask(cat, $0, w, d, h) }
            for i in masks.indices { for j in masks.indices where j > i { #expect(masks[i] != masks[j], "\(names[i]) vs \(names[j])") } }
        }
        // colors come from the name, and measured colors win
        #expect(VoxelModels.build(spec("scooter", "Red kick scooter")) != VoxelModels.build(spec("scooter", "Blue kick scooter")))
        var red = spec("bag", "Backpack"), blue = red
        red.primaryColor = 0xC02020; blue.primaryColor = 0x2040C0
        #expect(VoxelModels.build(red) != VoxelModels.build(blue))
    }

    @Test func robotVacuumIsALowDisc() {
        let g = VoxelModels.build(spec("vacuum", "Roomba robot vacuum")) // no size: still low
        #expect(g.ny <= 3)
        let low = VoxelModels.build(spec("vacuum", "Vacuum", 0.34, 0.34, 0.09)) // a detector box that low is a robot
        #expect(low.ny <= 3)
        #expect(low[0, 0, 0] == nil && low[low.nx / 2, 0, low.nz / 2] != nil) // round
        let upright = VoxelModels.build(spec("vacuum", "Upright vacuum"))
        #expect(upright.ny >= 20)
    }

    @Test func uprightPianoLidIsAPropSurface() {
        let s = spec("piano", "Upright piano")
        let surfaces = VoxelModels.surfaces(s)
        #expect(surfaces.count == 1)
        #expect(surfaces.first?.y == VoxelModels.build(s).ny)
        #expect(PropPlacer.role(of: s) == .furniture)
    }

    @Test func floorGearStaysOnTheFloor() {
        // small floor things aren't props to put on a desk; a monitor is
        #expect(PropPlacer.role(of: spec("vacuum", "Roomba", 0.34, 0.34, 0.09)) == .furniture)
        #expect(PropPlacer.role(of: spec("backpack", "Backpack", 0.3, 0.2, 0.45)) == .furniture)
        #expect(PropPlacer.role(of: spec("skateboard", "Skateboard", 0.8, 0.22, 0.12)) == .furniture)
        #expect(PropPlacer.role(of: spec("monitor", "Monitor", 0.6, 0.2, 0.45)) == .prop)
    }

    // MARK: routing

    @Test func detectorCategoriesRoute() {
        // every ObjectVocabulary category with a sensible builder (name = the category, as a fresh scan has it)
        let cases: [(String, VoxelModels.Kind)] = [
            ("scooter", .scooter), ("bicycle", .bike), ("guitar", .guitar), ("piano", .piano), ("keyboard instrument", .keyboard),
            ("drums", .drums), ("violin", .guitar), ("cello", .guitar), ("amplifier", .electronics), ("monitor", .monitor),
            ("computer", .electronics), ("laptop", .electronics), ("printer", .electronics), ("speaker", .electronics),
            ("game console", .electronics), ("projector", .electronics), ("turntable", .electronics), ("television", .tv),
            ("microwave", .microwave), ("coffee machine", .appliance), ("toaster", .appliance), ("blender", .appliance),
            ("vacuum", .vacuum), ("air purifier", .appliance), ("fan", .fan), ("heater", .appliance), ("humidifier", .appliance),
            ("air conditioner", .appliance), ("sewing machine", .appliance), ("refrigerator", .appliance), ("washerDryer", .appliance),
            ("water dispenser", .appliance), ("lamp", .lamp), ("chair", .chair), ("ottoman", .ottoman), ("bean bag", .beanBag),
            ("sofa", .sofa), ("bed", .bed), ("mattress", .mattress), ("bench", .bench), ("table", .table), ("storage", .bookshelf),
            ("shelf", .bookshelf), ("mirror", .mirror), ("rug", .rug), ("art", .art), ("vase", .decor), ("plant", .plant),
            ("plant stand", .plant), ("decor", .decor), ("box", .box), ("suitcase", .suitcase), ("backpack", .bag), ("bag", .bag),
            ("golf clubs", .bag), ("punching bag", .bag), ("treadmill", .fitness), ("exercise bike", .fitness),
            ("rowing machine", .fitness), ("skateboard", .board), ("surfboard", .board), ("skis", .board), ("snowboard", .board),
        ]
        for (cat, want) in cases {
            let name = cat.prefix(1).uppercased() + cat.dropFirst()
            #expect(kind(cat, name) == want, "\(cat)")
        }
    }

    @Test func visionWordsRoute() {
        // #131: "If none fits, a short plain noun (e.g. "instrument", "bicycle", "bag")"
        let cases: [(String, String, VoxelModels.Kind)] = [
            ("instrument", "Acoustic guitar", .guitar), ("instrument", "Instrument", .guitar), // unknown instrument: a guitar
            ("instrument", "Yamaha upright piano", .piano), ("instrument", "Casio keyboard", .keyboard),
            ("instrument", "Snare drum", .drums), ("instrument", "Fender guitar amp", .electronics),
            ("bicycle", "Blue road bicycle", .bike), ("bike", "Bike", .bike), ("other", "Trek mountain bike", .bike),
            ("bag", "Gym duffel", .bag), ("bag", "Leather handbag", .bag), ("other", "Hiking backpack", .bag),
            ("furniture", "Black rucksack", .bag), ("display", "Display", .monitor), ("screen", "Screen", .monitor),
            ("monitor", "LG gaming monitor", .monitor), ("electronics", "Samsung computer monitor", .monitor),
            ("other", "Hoover upright", .vacuum), ("appliance", "Roborock robot vacuum", .vacuum), ("other", "Bissell carpet cleaner", .vacuum),
            ("other", "Razor kick scooter", .scooter), ("other", "Segway e-scooter", .scooter),
            ("other", "Peloton bike", .fitness), ("other", "NordicTrack treadmill", .fitness),
        ]
        for (cat, name, want) in cases { #expect(kind(cat, name) == want, "\(cat)/\(name)") }
    }

    @Test func existingRoutesHold() {
        let cases: [(String, String, VoxelModels.Kind)] = [
            ("tv", "TV", .tv), ("monitor", "Samsung TV", .tv), ("display", "Television", .tv), ("electronics", "TV remote", .electronics),
            ("furniture", "Desk lamp", .lamp), ("furniture", "Black mesh office desk chair", .chair), ("furniture", "Piano bench", .bench),
            ("furniture", "Piano stool", .chair), ("furniture", "Drum side table", .table), ("ottoman", "Drum ottoman", .ottoman),
            ("electronics", "Wireless keyboard", .electronics), ("electronics", "Laptop", .electronics),
            ("electronics", "Baby monitor", .electronics), ("furniture", "Computer desk with keyboard tray", .desk),
            ("luggage", "Duffel bag", .suitcase), ("suitcase", "Carry-on suitcase", .suitcase), ("decor", "Bean bag chair", .beanBag),
            ("other", "Exercise bike", .fitness), ("bike", "Kids BMX bike", .bike), ("kitchenware", "Vacuum sealer", .kitchenware),
            ("kitchenware", "Vacuum flask", .kitchenware), ("clothes", "Ski jacket", .clothes), ("furniture", "Ski rack", .box),
            ("rug", "Persian carpet", .rug), ("decor", "Orange vase", .decor), ("storage", "Storage bin", .basket),
        ]
        for (cat, name, want) in cases { #expect(kind(cat, name) == want, "\(cat)/\(name)") }
        #expect(kind("keyboard", "Logitech keyboard", 0.44, 0.14, 0.03) == .electronics) // a computer keyboard is narrow
        #expect(kind("keyboard", "Keyboard", 1.2, 0.35, 0.9) == .keyboard)
    }
}
