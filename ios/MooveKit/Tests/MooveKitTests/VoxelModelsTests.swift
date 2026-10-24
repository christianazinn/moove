import Testing
@testable import MooveKit

@Suite struct VoxelModelsTests {
    static let fixtureSpecs: [VoxelItemSpec] = DemoFixtures.inventory(owner: "me").items.map(VoxelItemSpec.init)

    func spec(_ category: String, _ name: String, _ w: Double, _ d: Double, _ h: Double) -> VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: w, depthM: d, heightM: h)
    }

    func colors(_ g: VoxelGrid) -> Set<VoxelColor> {
        var out = Set<VoxelColor>()
        for y in 0..<g.ny { for z in 0..<g.nz { for x in 0..<g.nx { if let c = g[x, y, z] { out.insert(c) } } } }
        return out
    }

    /// Filled voxels in the z-slab [z0, z1) above height y0.
    func filled(_ g: VoxelGrid, z z0: Int, _ z1: Int, above y0: Int = 0) -> Int {
        var n = 0
        for y in stride(from: y0, to: g.ny, by: 1) { for z in stride(from: max(0, z0), to: min(g.nz, z1), by: 1) { for x in 0..<g.nx where g[x, y, z] != nil { n += 1 } } }
        return n
    }

    @Test func fixtureItemsBuildWithinBounds() {
        #expect(Self.fixtureSpecs.count == 12)
        for s in Self.fixtureSpecs {
            let g = VoxelModels.build(s)
            print("voxels \(s.name) [\(VoxelModels.kind(s))]: \(g.nx)x\(g.ny)x\(g.nz), \(g.filledCount) filled, \(colors(g).count) colors")
            #expect(g.filledCount > 0, "\(s.name) is empty")
            #expect(g.nx >= VoxelGrid.count(s.widthM) && g.nz >= VoxelGrid.count(s.depthM), "\(s.name) footprint shrank")
            #expect(g.nx <= 160 && g.ny <= 160 && g.nz <= 160)
            // only the bed may grow taller than its spec (headboard above the mattress top)
            if VoxelModels.kind(s) != .bed { #expect(g.ny >= VoxelGrid.count(s.heightM) && g.ny <= max(VoxelGrid.count(s.heightM), 8), "\(s.name) height") }
            #expect(g.cells.allSatisfy { $0 == 0 || $0 & 0x1000000 != 0 })
        }
    }

    @Test func fixtureRouting() {
        let kinds = Dictionary(uniqueKeysWithValues: Self.fixtureSpecs.map { ($0.name, VoxelModels.kind($0)) })
        #expect(kinds["Queen bed frame"] == .bed)
        #expect(kinds["Office chair"] == .chair)
        #expect(kinds["Desk"] == .desk)
        #expect(kinds["Bookshelf"] == .bookshelf)
        #expect(kinds["Floor lamp"] == .lamp)
        #expect(kinds["Nightstand"] == .dresser)
        #expect(kinds["Box fan"] == .fan)
        #expect(kinds["Broken mirror"] == .mirror)
        #expect(kinds["Grandma's quilt rack"] == .quiltRack)
        #expect(kinds["Framed photos"] == .framedPhotos)
        #expect(kinds["Bean bag"] == .beanBag)
        #expect(kinds["Mini fridge"] == .appliance)
        #expect(VoxelModels.kind(spec("sofa", "Grey velvet 3-seat sofa", 2.2, 0.9, 0.85)) == .sofa)
        #expect(VoxelModels.kind(spec("storage", "Plastic storage bin", 0.6, 0.4, 0.35)) == .box)
        #expect(VoxelModels.kind(spec("decor", "Monstera plant", 0.5, 0.5, 1)) == .plant)
        #expect(VoxelModels.kind(spec("appliance", "Samsung TV", 1.2, 0.2, 0.7)) == .tv)
        #expect(VoxelModels.kind(spec("chair", "Pine dining chair", 0.45, 0.5, 0.9)) == .chair)
    }

    @Test func deterministic() {
        for s in Self.fixtureSpecs + [spec("sofa", "L-shaped sectional", 2.8, 2.0, 0.85), spec("decor", "Monstera plant", 0.6, 0.6, 1.2)] {
            #expect(VoxelModels.build(s) == VoxelModels.build(s), "\(s.name)")
        }
        // a different name gives a different seed (jitter), same shape
        let a = VoxelModels.build(spec("sofa", "Sofa", 2, 0.9, 0.85))
        let b = VoxelModels.build(spec("sofa", "Couch", 2, 0.9, 0.85))
        #expect(a != b)
    }

    @Test func sofaIsRicherThanABox() {
        let sofa = VoxelModels.build(spec("sofa", "Linen sofa", 2, 0.9, 0.85))
        let box = VoxelModels.build(spec("mystery", "Thing", 2, 0.9, 0.85))
        #expect(colors(sofa).count > colors(box).count)
        // a sofa is not a solid block: seat in front is lower than the backrest
        #expect(sofa.filledCount < sofa.nx * sofa.ny * sofa.nz * 3 / 4)
    }

    @Test func frontFacesPositiveZ() {
        // bed: the headboard is at the back (low z) and rises well above the duvet at the foot
        let bed = VoxelModels.build(Self.fixtureSpecs.first { $0.name == "Queen bed frame" }!)
        #expect(bed.ny > VoxelGrid.count(0.4))
        let topY = bed.ny - 2
        #expect(filled(bed, z: 0, 2, above: topY) > bed.nx)
        #expect(filled(bed, z: bed.nz - 3, bed.nz, above: topY) == 0)

        // sofa: the backrest (top layers) sits at low z, the front of the seat is open above seat height
        let sofa = VoxelModels.build(spec("sofa", "Sofa", 2, 0.9, 0.85))
        let high = sofa.ny * 3 / 4
        #expect(filled(sofa, z: 0, sofa.nz / 3, above: high) > filled(sofa, z: sofa.nz * 2 / 3, sofa.nz, above: high) * 3)

        // office chair: backrest at low z
        let chair = VoxelModels.build(Self.fixtureSpecs.first { $0.name == "Office chair" }!)
        let chairHigh = chair.ny - 4
        #expect(filled(chair, z: 0, chair.nz / 2, above: chairHigh) > 0)
        #expect(filled(chair, z: chair.nz / 2 + 2, chair.nz, above: chairHigh) == 0)

        // bookshelf: back panel at z = 0, so the back face is (almost) full and books are visible from +z
        let shelf = VoxelModels.build(Self.fixtureSpecs.first { $0.name == "Bookshelf" }!)
        #expect(filled(shelf, z: 0, 1) > shelf.nx * shelf.ny * 9 / 10)
        #expect(colors(shelf).count > 20)
    }

    @Test func degenerateSpecsNeverCrash() {
        let weird: [VoxelItemSpec] = [
            spec("", "", 0, 0, 0),
            spec("sofa", "", -1, -2, -3),
            spec("bed", "", .nan, .infinity, -.infinity),
            spec("table", "round table", 1e9, 1e9, 1e9),
            spec("chair", "office", 0.01, 0.01, 0.01),
            spec("lamp", "arc floor lamp", 0.05, 0.05, 3),
            spec("storage", "99999999999999999999 shelf bookcase", 0.3, 0.2, 4),
            spec("sofa", "9 seat l-shaped sectional", 8, 8, 4),
            spec("decor", "cracked mirror", 0.05, 0.05, 0.05),
            spec("appliance", "box fan", 0.05, 0.05, 0.05),
            spec("appliance", "pedestal fan", 0.4, 0.4, 1.3),
            spec("appliance", "washer", 0.6, 0.6, 0.85),
            spec("appliance", "microwave", 0.5, 0.35, 0.3),
            spec("art", "", 0.05, 0.05, 0.05),
            spec("electronics", "speaker", 0.05, 0.05, 0.05),
            spec("trading_cards", "red binder", 0.05, 0.05, 0.05),
            spec("books", "box of books", 0.05, 0.05, 0.05),
            spec("rug", "navy rug", 8, 8, 0),
            spec("  SOFA \n", "ÉTAGÈRE 🛋️ 3-seat", 2, 1, 1),
        ]
        for s in weird {
            let g = VoxelModels.build(s)
            #expect(g.filledCount > 0)
            #expect(g.nx <= 160 && g.ny <= 160 && g.nz <= 160)
        }
        let huge = VoxelModels.build(spec("table", "", 1e9, 1e9, 1e9))
        #expect(huge.nx == 160 && huge.nz == 160)
    }

    @Test func unknownCategoryIsABox() {
        let s = spec("spaceship", "Mystery thing", 0.5, 0.4, 0.4)
        #expect(VoxelModels.kind(s) == .box)
        let g = VoxelModels.build(s)
        #expect(g.nx == 10 && g.ny == 8 && g.nz == 8)
        #expect(g.filledCount == 10 * 8 * 8) // a solid kraft box
    }

    @Test func everyKindBuilds() {
        let samples: [(String, String)] = [
            ("sofa", "armchair"), ("bed", "grey bed"), ("mattress", "memory foam mattress"), ("desk", "white desk"),
            ("chair", "dining chair"), ("table", "round bistro table"), ("dresser", "walnut dresser"),
            ("storage", "ikea 5 shelf bookcase"), ("tv", "tv"), ("lamp", "table lamp"), ("books", "books"),
            ("art", "gold framed painting"), ("photos", "photos"), ("trading_cards", "binder"), ("kitchenware", "copper pots"),
            ("plant", "plant"), ("rug", "rug"), ("clothes", "laundry hamper"), ("clothes", "shirts"),
            ("electronics", "laptop"), ("electronics", "monitor"), ("electronics", "game console"),
            ("decor", "candle"), ("decor", "vase"), ("tv", "wall mounted tv"),
        ]
        for (cat, name) in samples {
            let g = VoxelModels.build(spec(cat, name, 0, 0, 0)) // default sizes
            #expect(g.filledCount > 0, "\(cat)/\(name)")
            #expect(colors(g).count > 2, "\(cat)/\(name) looks flat")
        }
    }

    @Test func helpersMatchJavaScript() {
        // FNV-1a of "" and "a" (JS strHash)
        #expect(strHash("") == 2_166_136_261)
        #expect(strHash("a") == 0xE40C_292C)
        #expect(rd(2.5) == 3 && rd(-2.5) == -2 && rd(.nan) == 0)
        let n = VName("3-seat grey sofa")
        #expect(n.number(before: ["seat"], multiDigit: false) == 3)
        #expect(n.word("grey") && !n.word("gre") && n.has("gre"))
        #expect(VName("12 shelves").number(before: ["shel"], multiDigit: true) == 12)
        #expect(shade(0x808080, 2) == 0xFFFFFF)
    }

    // MARK: per-item variation (scan data drives the look; the seed only the small details)

    @Test func itemInitCarriesScanData() {
        let item = DemoFixtures.inventory(owner: "me").items.first { $0.name == "Queen bed frame" }!
        let s = VoxelItemSpec(item)
        #expect(s.id == "demo-10" && s.material == "oak" && s.brand == "IKEA" && s.condition == 4)
        #expect(s.attributes.isEmpty && s.primaryColor == nil && s.secondaryColor == nil)
    }

    @Test func itemInitCarriesAttributesAndColors() {
        let chair = DemoFixtures.inventory(owner: "me").items.first { $0.name == "Office chair" }!
        let s = VoxelItemSpec(chair)
        #expect(s.attributes.contains("ChairLegType.star"))
        #expect(s.primaryColor == 0x3A3D42 && s.secondaryColor == 0x1E1F21)
        #expect(VoxelModels.kind(s) == .chair)
        // Measured colors change the model; attributes and colors both reach the builder.
        var plain = chair
        plain.colors = nil
        #expect(VoxelModels.build(VoxelItemSpec(plain)) != VoxelModels.build(s))
    }

    @Test func differentItemsOfOneKindDiffer() {
        for (cat, name, w, d, h) in [("sofa", "Sofa", 2.0, 0.9, 0.85), ("table", "Dining table", 1.6, 0.9, 0.75),
                                     ("chair", "Dining chair", 0.45, 0.5, 0.9), ("storage", "Bookshelf", 0.8, 0.3, 1.8),
                                     ("decor", "Plant", 0.5, 0.5, 1.0), ("bed", "Bed", 1.6, 2.1, 0.5)] {
            let a = VoxelModels.build(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h, id: "scan-a"))
            let b = VoxelModels.build(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h, id: "scan-b"))
            #expect(a != b, "\(name)")
            #expect(a.nx == b.nx && a.ny == b.ny && a.nz == b.nz)
            #expect(a == VoxelModels.build(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h, id: "scan-a")))
        }
    }

    func dominant(_ g: VoxelGrid) -> (r: Int, g: Int, b: Int) {
        // mean color, which a dominant material moves
        var r = 0, gg = 0, b = 0, n = 0
        for c in g.cells where c != 0 { r += Int((c >> 16) & 255); gg += Int((c >> 8) & 255); b += Int(c & 255); n += 1 }
        return (r / max(1, n), gg / max(1, n), b / max(1, n))
    }

    @Test func materialSetsThePalette() {
        func dresser(_ m: String) -> VoxelGrid {
            VoxelModels.build(VoxelItemSpec(category: "storage", name: "Dresser", widthM: 1, depthM: 0.5, heightM: 0.9, id: "x", material: m))
        }
        let walnut = dominant(dresser("walnut")), white = dominant(dresser("white"))
        #expect(white.r + white.g + white.b > walnut.r + walnut.g + walnut.b + 200)
        // name color words win over the material
        let named = VoxelModels.build(VoxelItemSpec(category: "storage", name: "White dresser", widthM: 1, depthM: 0.5, heightM: 0.9, id: "x", material: "walnut"))
        let n = dominant(named)
        #expect(n.r + n.g + n.b > walnut.r + walnut.g + walnut.b + 200)
        // IKEA flat-pack: birch instead of dark wood
        let ikea = dominant(VoxelModels.build(VoxelItemSpec(category: "storage", name: "Dresser", widthM: 1, depthM: 0.5, heightM: 0.9, id: "x", brand: "IKEA")))
        #expect(ikea.r > walnut.r + 60)
    }

    @Test func conditionAddsWear() {
        func chair(_ c: Int?) -> VoxelGrid {
            VoxelModels.build(VoxelItemSpec(category: "chair", name: "Dining chair", widthM: 0.45, depthM: 0.5, heightM: 0.9, id: "x", condition: c))
        }
        #expect(chair(1) != chair(5))
        #expect(chair(5) == chair(nil))
        // worn pieces are duller
        let crisp = colors(chair(5)).count, worn = chair(1)
        #expect(worn.filledCount <= chair(5).filledCount && crisp > 2)
        // a badly worn TV is cracked, a broken mirror (condition 1) too
        let tv1 = VoxelModels.build(VoxelItemSpec(category: "tv", name: "TV", widthM: 1.2, depthM: 0.2, heightM: 0.7, condition: 1))
        let tv5 = VoxelModels.build(VoxelItemSpec(category: "tv", name: "TV", widthM: 1.2, depthM: 0.2, heightM: 0.7, condition: 5))
        #expect(colors(tv1).contains(0x9AA3AD) && !colors(tv5).contains(0x9AA3AD))
    }

    @Test func sizeDrivesStructure() {
        // a 0.9 m "sofa" is an armchair (one seat, no second pillow); 2.4 m has three seats
        func seams(_ g: VoxelGrid) -> Int {
            // count distinct back-cushion columns at mid back height across x
            var n = 0, inGap = true
            let y = g.ny - 1, z = 4 // the top row has gaps between back cushions
            for x in 0..<g.nx { let on = g[x, y, z] != nil; if on && inGap { n += 1 }; inGap = !on }
            return n
        }
        let wide = VoxelModels.build(spec("sofa", "Sofa", 2.4, 0.9, 0.85))
        let narrow = VoxelModels.build(spec("sofa", "Sofa", 0.9, 0.9, 0.85))
        #expect(seams(wide) == 3)
        #expect(seams(narrow) == 1)
        // coffee vs dining vs bar height tables come out different
        let coffee = VoxelModels.build(spec("table", "Table", 1.2, 0.6, 0.45))
        let bar = VoxelModels.build(spec("table", "Table", 1.2, 0.6, 1.05))
        #expect(coffee.ny < bar.ny)
        // bookshelf compartments from height
        let tall = VoxelModels.build(spec("storage", "Bookshelf", 0.8, 0.3, 2.0))
        let low = VoxelModels.build(spec("storage", "Bookshelf", 0.8, 0.3, 0.8))
        #expect(colors(tall).count >= colors(low).count)
    }

    @Test func styleVariantsBuildAndDiffer() {
        let variants: [(String, String, String, Double, Double, Double)] = [
            ("table", "Dining table", "Trestle farmhouse table", 1.8, 0.9, 0.75),
            ("table", "Dining table", "Glass dining table", 1.8, 0.9, 0.75),
            ("table", "Dining table", "Mid-century table", 1.8, 0.9, 0.75),
            ("table", "Dining table", "Round pedestal table", 1.8, 0.9, 0.75),
            ("table", "Desk", "Standing desk", 1.4, 0.7, 0.75),
            ("table", "Desk", "L-shaped desk", 1.6, 1.4, 0.75),
            ("chair", "Dining chair", "Windsor chair", 0.45, 0.5, 0.9),
            ("chair", "Dining chair", "Upholstered dining chair", 0.45, 0.5, 0.9),
            ("chair", "Dining chair", "Metal cafe chair", 0.45, 0.5, 0.9),
            ("chair", "Dining chair", "Bar stool", 0.45, 0.5, 0.9),
            ("sofa", "Sofa", "Leather chesterfield sofa", 2.2, 0.9, 0.85),
            ("sofa", "Sofa", "Skirted sofa", 2.2, 0.9, 0.85),
            ("bed", "Bed", "Upholstered tufted bed", 1.6, 2.1, 0.5),
            ("bed", "Bed", "Metal bed", 1.6, 2.1, 0.5),
            ("bed", "Bed", "Platform bed", 1.6, 2.1, 0.5),
            ("bed", "Bed", "Sleigh bed", 1.6, 2.1, 0.5),
            ("storage", "Bookshelf", "Kallax cube shelf", 0.8, 0.4, 1.5),
            ("storage", "Bookshelf", "Ladder shelf", 0.8, 0.4, 1.5),
            ("storage", "Bookshelf", "Bookcase with doors", 0.8, 0.4, 1.5),
            ("storage", "Dresser", "Wardrobe", 1.0, 0.6, 1.9),
            ("storage", "Dresser", "Sideboard", 1.6, 0.45, 0.8),
            ("storage", "Nightstand", "Nightstand with open shelf", 0.45, 0.4, 0.55),
            ("lamp", "Floor lamp", "Torchiere floor lamp", 0.4, 0.4, 1.7),
            ("lamp", "Floor lamp", "Tripod floor lamp", 0.5, 0.5, 1.6),
            ("lamp", "Lamp", "Desk lamp", 0.3, 0.3, 0.5),
            ("decor", "Plant", "Snake plant", 0.4, 0.4, 0.9),
            ("decor", "Plant", "Cactus plant", 0.4, 0.4, 0.9),
            ("decor", "Plant", "Fiddle leaf fig tree", 0.6, 0.6, 1.6),
            ("decor", "Plant", "Pothos plant", 0.4, 0.4, 0.5),
            ("rug", "Rug", "Striped rug", 2, 1.4, 0.02),
            ("rug", "Rug", "Round rug", 2, 2, 0.02),
            ("rug", "Rug", "Jute rug", 2, 1.4, 0.02),
            ("rug", "Rug", "Moroccan rug", 2, 1.4, 0.02),
            ("decor", "Mirror", "Round mirror", 0.6, 0.05, 0.6),
            ("appliance", "Fridge", "French door fridge", 0.7, 0.75, 1.8), // >= 0.8 m wide is french-door by size
            ("appliance", "Fan", "Pedestal fan", 0.45, 0.45, 0.6),
        ]
        for (cat, plain, styled, w, d, h) in variants {
            let a = VoxelModels.build(VoxelItemSpec(category: cat, name: plain, widthM: w, depthM: d, heightM: h, id: "same"))
            let b = VoxelModels.build(VoxelItemSpec(category: cat, name: styled, widthM: w, depthM: d, heightM: h, id: "same"))
            #expect(b.filledCount > 0, "\(styled)")
            // a different shape, or (rugs, glass) a clearly different overall color
            let ma = dominant(a), mb = dominant(b)
            let colorShift = abs(ma.r - mb.r) + abs(ma.g - mb.g) + abs(ma.b - mb.b)
            #expect(a.filledCount != b.filledCount || colorShift > 12, "\(styled) looks like a plain \(plain)")
        }
    }

    // MARK: RoomPlan attributes and photo colors

    func attributed(_ cat: String, _ name: String, _ w: Double, _ d: Double, _ h: Double, _ attrs: [String]) -> VoxelGrid {
        VoxelModels.build(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h, id: "same", attributes: attrs))
    }

    @Test func chairLegTypeDecides() {
        let star = attributed("chair", "Chair", 0.6, 0.6, 0.9, ["ChairLegType.star"])
        let four = attributed("chair", "Chair", 0.6, 0.6, 0.9, ["ChairLegType.four"])
        #expect(star.filledCount != four.filledCount)
        // a star base has casters (wheel color) on the floor; four legs sit at the corners
        #expect(four[0, 0, 0] != nil && star[0, 0, 0] == nil)
        // attribute beats the keyword: an "office chair" scanned with four legs is not a swivel chair
        let kw = attributed("chair", "Office chair", 0.6, 0.6, 0.9, ["ChairLegType.four"])
        #expect(kw[0, 0, 0] != nil)
        // stool: the seat is the top (no back); a dining chair's top layer is only its back rail at low z
        let stool = attributed("chair", "Chair", 0.4, 0.4, 0.75, ["ChairType.stool"])
        let chair = attributed("chair", "Chair", 0.4, 0.4, 0.75, ["ChairType.dining"])
        #expect(filled(stool, z: stool.nz / 2, stool.nz, above: stool.ny - 1) > 0)
        #expect(filled(chair, z: chair.nz / 2, chair.nz, above: chair.ny - 1) == 0)
        let noBack = attributed("chair", "Chair", 0.4, 0.4, 0.75, ["ChairType.dining", "ChairBackType.missing"])
        #expect(noBack.filledCount != chair.filledCount)
    }

    @Test func tableShapeAndType() {
        let round = attributed("table", "Table", 1.2, 1.2, 0.75, ["TableShapeType.circularElliptic"])
        let rect = attributed("table", "Round table", 1.2, 1.2, 0.75, ["TableShapeType.rectangular"])
        let top = round.ny - 1
        #expect(round[0, top, 0] == nil && round[round.nx / 2, top, round.nz / 2] != nil) // corners cut: a round top
        #expect(rect[0, top, 0] != nil) // the attribute beats the "round" keyword
        let coffee = attributed("table", "Table", 1.2, 0.6, 0.75, ["TableType.coffee"])
        let dining = attributed("table", "Table", 1.2, 0.6, 0.75, ["TableType.dining"])
        #expect(coffee.filledCount != dining.filledCount)
        #expect(VoxelModels.kind(VoxelItemSpec(category: "storage", name: "Bookshelf", widthM: 1, depthM: 0.4, heightM: 1, attributes: ["StorageType.cabinet"])) == .dresser)
        #expect(VoxelModels.kind(VoxelItemSpec(category: "storage", name: "Cabinet", widthM: 1, depthM: 0.4, heightM: 1, attributes: ["StorageType.shelf"])) == .bookshelf)
        let l = attributed("sofa", "Sofa", 2.4, 1.6, 0.85, ["SofaType.lShaped"])
        let r = attributed("sofa", "Sofa", 2.4, 1.6, 0.85, ["SofaType.rectangular"])
        #expect(l.filledCount != r.filledCount)
    }

    @Test func primaryColorOverridesPalette() {
        let red: VoxelColor = 0xB03030
        let plain = VoxelModels.build(VoxelItemSpec(category: "storage", name: "Oak dresser", widthM: 1, depthM: 0.5, heightM: 0.9, id: "x"))
        let photo = VoxelModels.build(VoxelItemSpec(category: "storage", name: "Oak dresser", widthM: 1, depthM: 0.5, heightM: 0.9, id: "x", primaryColor: red))
        let m = dominant(photo)
        #expect(m.r > m.g + 50 && m.r > m.b + 50)
        #expect(dominant(plain).g > m.g + 20)
        // secondary color drives the sofa's accent pillows
        let sofa = VoxelModels.build(VoxelItemSpec(category: "sofa", name: "Sofa", widthM: 2, depthM: 0.9, heightM: 0.85, id: "x", secondaryColor: 0x2050C0))
        #expect(colors(sofa).contains { c in (c & 0xFF) > 0xA0 && ((c >> 16) & 0xFF) < 0x40 })
    }
}
