import Foundation
import Testing
@testable import MooveKit

/// Render budget for the demo dollhouse (#224): triangle counts and build time of the voxel
/// meshes the app draws for the demo room and the demo house, so a builder or mesher change
/// that blows up the geometry fails CI instead of showing up as a slow device demo.
/// Budgets are today's numbers with ~1.5-2x headroom (see ios/CLAUDE.md, ios-newhome).
@Suite struct RenderBudgetTests {
    // MARK: budgets

    // Today (Oct 24, Linux debug): biggest item the bed (~10.7k at default size; sofa 6.1k,
    // mattress 5.9k, bookshelf 5.6k, the rest under 5k); demo bedroom (the seeded Bedroom, #243)
    // shell 3.5k + 12 items = 27.6k; demo house shell 15.7k + 8 laid-out items = 38.4k (shells
    // count the base plus the wall pieces shown at the worst yaw: tall back walls, low near
    // walls); building + meshing all of it 0.4-1.1 s.

    /// Any one item mesh (demo item or a kind at its default size). Leaves room for new builders.
    static let perItemTriangleCap = 20_000
    /// The demo bedroom dollhouse: shell + every demo item.
    static let bedroomTriangleBudget = 60_000
    /// The demo house: shell + the kept and bought items laid out (worst layout style).
    static let houseTriangleBudget = 50_000
    /// Building + meshing the bedroom, the house and every demo item. Loose on purpose (debug
    /// build, shared CI runner, tests running in parallel) so it is not flaky; it only trips
    /// on a real blow-up (several times today's time).
    static let totalBuildTimeBudget = Duration.seconds(5)

    // MARK: fixtures

    static let owner: IdentityHex = "budget"
    static var demoItems: [Item] { DemoFixtures.inventory(owner: owner).items }
    static let scanColors = DemoFixtures.scanColors()

    /// The demo bedroom (`DemoFixtures.roomGeometry()`, 4 x 3.5 m) as the one-room plan the
    /// app's dollhouse transform makes of it: min corner at (0, 0), the door on the south
    /// wall, the window on the east wall.
    static let bedroomPlan = FloorPlan(
        rooms: [.rectangle("Bedroom", x: 0, y: 0, width: 4, depth: 3.5)],
        doors: [WallOpening(from: PlanPoint(0.575, 3.5), to: PlanPoint(1.425, 3.5))],
        windows: [WallOpening(from: PlanPoint(4, 0.35), to: PlanPoint(4, 1.55))],
        wallHeightM: 2.5)

    /// One `(category, name)` that routes to each kind; kinds missing here (new builders)
    /// fall back to their raw value as category and name.
    static let kindSamples: [VoxelModels.Kind: (String, String)] = [
        .sofa: ("sofa", "sofa"), .bed: ("bed", "bed"), .mattress: ("mattress", "mattress"), .desk: ("desk", "desk"),
        .chair: ("chair", "chair"), .table: ("table", "table"), .dresser: ("dresser", "dresser"),
        .bookshelf: ("storage", "bookshelf"), .tv: ("tv", "tv"), .lamp: ("lamp", "lamp"), .books: ("books", "books"),
        .art: ("art", "art"), .photos: ("photos", "photos"), .binder: ("trading_cards", "binder"),
        .kitchenware: ("kitchenware", "pots"), .plant: ("plant", "plant"), .rug: ("rug", "rug"),
        .clothes: ("clothes", "clothes"), .electronics: ("electronics", "laptop"), .decor: ("decor", "vase"),
        .appliance: ("appliance", "coffee maker"), .fan: ("appliance", "box fan"), .beanBag: ("sofa", "bean bag"),
        .mirror: ("decor", "mirror"), .quiltRack: ("decor", "quilt rack"), .framedPhotos: ("decor", "framed photos"),
        .box: ("box", "cardboard box"),
        .motorcycle: ("motorcycle", "motorcycle"), .stroller: ("stroller", "stroller"), .wheelchair: ("wheelchair", "wheelchair"),
        .grill: ("grill", "grill"), .lawnMower: ("lawn mower", "lawn mower"), .crib: ("crib", "crib"), .ladder: ("ladder", "ladder"),
        .trunk: ("trunk", "trunk"), .basket: ("basket", "laundry basket"), .trashCan: ("trash can", "trash can"),
        .toolbox: ("toolbox", "toolbox"), .petCrate: ("pet crate", "pet crate"), .petBed: ("pet bed", "dog bed"),
        .catTree: ("cat tree", "cat tree"), .clock: ("clock", "wall clock"), .toy: ("toy", "stuffed animal"),
        .rack: ("coat rack", "coat rack"),
        .toilet: ("toilet", "toilet"), .sink: ("sink", "sink"), .bathtub: ("bathtub", "bathtub"), .fireplace: ("fireplace", "fireplace"),
        .stairs: ("stairs", "stairs"), .screen: ("room divider", "room divider"), .softGoods: ("other", "folded blanket"),
        .unknown: ("other", "other"), .ball: ("ball", "basketball"), .helmet: ("helmet", "bike helmet"),
        .racket: ("racket", "tennis racket"), .weights: ("weights", "dumbbell"), .yogaMat: ("yoga mat", "yoga mat"),
        .ironingBoard: ("ironing board", "ironing board"), .horn: ("saxophone", "saxophone"),
    ]

    static func triangles(_ spec: VoxelItemSpec) -> Int { VoxelMesher.mesh(VoxelModels.build(spec)).triangleCount }

    /// Triangles of every placed item, as `FurnitureLayer` draws it (wall-hung ones with the wall variant).
    static func triangles(_ placements: [Placement], items: [LayoutItem]) -> [(String, Int)] {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return placements.compactMap { p in
            guard let item = byId[p.itemId] else { return nil }
            let spec = p.wallMounted == true ? VoxelModels.wallVariant(VoxelItemSpec(item)) : VoxelItemSpec(item)
            return (item.name, triangles(spec))
        }
    }

    // MARK: (1) every demo inventory item

    @Test func demoItemsUnderPerItemCap() {
        for item in Self.demoItems {
            var spec = VoxelItemSpec(item)
            if let c = Self.scanColors.colors(for: item) { spec.primaryColor = c.primary; spec.secondaryColor = c.secondary }
            let n = Self.triangles(spec)
            #expect(n > 0 && n <= Self.perItemTriangleCap, "\(item.name): \(n) triangles (cap \(Self.perItemTriangleCap))")
        }
    }

    // MARK: (4) every kind at its default size

    @Test func everyKindUnderPerItemCap() {
        for kind in VoxelModels.Kind.allCases {
            let (cat, name) = Self.kindSamples[kind] ?? (kind.rawValue, kind.rawValue)
            let spec = VoxelItemSpec(category: cat, name: name, widthM: 0, depthM: 0, heightM: 0) // default size
            if Self.kindSamples[kind] != nil { #expect(VoxelModels.kind(spec) == kind, "\(cat)/\(name) should route to \(kind)") }
            let n = Self.triangles(spec)
            #expect(n > 0 && n <= Self.perItemTriangleCap, "\(kind): \(n) triangles (cap \(Self.perItemTriangleCap))")
        }
    }

    // MARK: (2) the demo bedroom dollhouse

    /// The shell as the app draws it: the cut-away base plus the full-height back walls
    /// and the low near walls (`VoxelHouse.buildLayers`), worst case over the camera's turn.
    static func shellTriangles(_ plan: FloorPlan, wallColor: VoxelColor? = nil, floorColor: VoxelColor? = nil) -> Int {
        let layers = VoxelHouse.buildLayers(plan, wallColor: wallColor, floorColor: floorColor)
        let base = VoxelMesher.mesh(layers.base, centered: false).triangleCount
        let pieces = layers.layers.map { ($0, VoxelMesher.mesh($0.grid, centered: false).triangleCount) }
        let worst = (0..<72).map { step in
            let a = Double(step) * 5 * .pi / 180
            return pieces.filter { $0.0.isShown(viewFromTarget: SIMD2(sin(a), cos(a))) }.map(\.1).reduce(0, +)
        }.max() ?? 0
        return base + worst
    }

    static func bedroomTriangles() -> (shell: Int, items: Int) {
        let shell = shellTriangles(bedroomPlan, wallColor: scanColors.wallColor, floorColor: scanColors.floorColor)
        let items = demoItems.map { triangles(VoxelItemSpec(LayoutItem($0, colors: scanColors))) }.reduce(0, +)
        return (shell, items)
    }

    @Test func demoBedroomUnderBudget() {
        let (shell, items) = Self.bedroomTriangles()
        #expect(shell + items <= Self.bedroomTriangleBudget,
                "bedroom: shell \(shell) + items \(items) = \(shell + items) triangles (budget \(Self.bedroomTriangleBudget))")
    }

    // MARK: (3) the demo house with the kept items laid out

    static func houseTriangles() -> (shell: Int, items: Int, placed: Int) {
        let plan = DemoHouse.floorPlan
        let shell = shellTriangles(plan)
        // As NewHomeView: kept demo items (with the demo room's colors) plus bought ones,
        // laid out and then dressed by PropPlacer. Every style, worst case counts.
        let demo = DemoFixtures.demo(owner: owner)
        let items = demo.items.filter { $0.disposition == .keep }.map { LayoutItem($0, colors: scanColors) } + demo.boughtLayoutItems
        let placer = PropPlacer(plan: plan)
        var worst = 0, placed = 0
        for option in LayoutSolver(plan: plan).solveAll(items) {
            let placements = placer.place(option.placements, items: items)
            let n = triangles(placements, items: items).map(\.1).reduce(0, +)
            if n > worst { worst = n; placed = placements.count }
        }
        return (shell, worst, placed)
    }

    @Test func demoHouseUnderBudget() {
        let (shell, items, placed) = Self.houseTriangles()
        #expect(placed > 0)
        #expect(shell + items <= Self.houseTriangleBudget,
                "house: shell \(shell) + \(placed) items \(items) = \(shell + items) triangles (budget \(Self.houseTriangleBudget))")
    }

    // MARK: (5) build time

    @Test func demoBuildTimeUnderBudget() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = Self.bedroomTriangles()
            _ = Self.houseTriangles()
            for item in Self.demoItems { _ = Self.triangles(VoxelItemSpec(item)) }
        }
        #expect(elapsed < Self.totalBuildTimeBudget, "demo voxel build took \(elapsed) (budget \(Self.totalBuildTimeBudget))")
    }

    /// Prints today's numbers (`swift test --filter RenderBudgetTests`), to re-pick budgets.
    @Test func report() {
        var maxItem = ("", 0)
        for kind in VoxelModels.Kind.allCases {
            let (cat, name) = Self.kindSamples[kind] ?? (kind.rawValue, kind.rawValue)
            let n = Self.triangles(VoxelItemSpec(category: cat, name: name, widthM: 0, depthM: 0, heightM: 0))
            if n > maxItem.1 { maxItem = ("kind \(kind)", n) }
        }
        for item in Self.demoItems {
            let n = Self.triangles(VoxelItemSpec(item))
            if n > maxItem.1 { maxItem = (item.name, n) }
        }
        let bedroom = Self.bedroomTriangles()
        let house = Self.houseTriangles()
        let elapsed = ContinuousClock().measure { _ = Self.bedroomTriangles(); _ = Self.houseTriangles() }
        print("render budget: max item \(maxItem.0) \(maxItem.1); bedroom shell \(bedroom.shell) + items \(bedroom.items);"
              + " house shell \(house.shell) + \(house.placed) items \(house.items); build \(elapsed)")
    }
}
