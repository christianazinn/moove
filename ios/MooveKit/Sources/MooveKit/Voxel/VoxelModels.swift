import Foundation

// OWNER: voxel-models agent. Ports MoveWise's static/scene/models.js builders
// ("detailed Minecraft-like" 5 cm voxel furniture) to pure Swift.
//
// Same conventions as models.js: x = width, y = up, z = depth, origin at the min corner,
// z = 0 is the back (against a wall) and every piece's FRONT faces +z (sofa seats, bed foot,
// desk drawers, screens, drawer fronts, the bookshelf's open side, the chair seat).
// Same palette, keyword routing, per-voxel jitter and hash functions (32-bit wrapping math
// matching JS Math.imul / >>>), so a piece looks like its MoveWise twin.
//
// Files: this one holds the public entry point, routing, sizing and the voxel canvas;
// VoxelModels+Furniture.swift (sofa, bed, mattress, desk, chairs, table, dresser, bookshelf,
// TV, lamp), VoxelModels+Objects.swift (books, art, photos, binder, kitchenware, plant, rug,
// clothes, electronics, decor, box) and VoxelModels+Moove.swift (Moove-only pieces: fridge and
// other appliances, fans, bean bag, mirror, quilt rack, framed photos), VoxelModels+Instruments.swift
// (guitar, piano, keyboard, drums) and VoxelModels+Gear.swift (vacuum, monitor, scooter, bags,
// fitness machines, boards) for the scan detector's extra categories (#183), VoxelModels+Household.swift
// (trunk, baskets / bins / hampers, trash can, toolbox, crib, ladder, clock, toys, coat / shoe /
// clothes racks, pet crate, pet bed, cat tree) and VoxelModels+Outdoor.swift (motorcycle, stroller,
// wheelchair, grill, lawn mower) for the rest of the detector's categories.

/// A flat top where small props can sit, in a piece's voxel coords: the half-open rectangle
/// [x0, x1) × [z0, z1), with `y` the first free voxel layer above the surface (so a prop's
/// bottom sits at `y * voxelSize` above the piece's base). `clearance`: free layers above it
/// (a bookshelf slot under the next board), nil when nothing is above.
public struct VoxelSurface: Sendable, Hashable {
    public var x0: Int, z0: Int, x1: Int, z1: Int
    public var y: Int
    public var clearance: Int?

    public init(x0: Int, z0: Int, x1: Int, z1: Int, y: Int, clearance: Int? = nil) {
        self.x0 = x0; self.z0 = z0; self.x1 = x1; self.z1 = z1
        self.y = y
        self.clearance = clearance
    }

    public var width: Int { x1 - x0 }
    public var depth: Int { z1 - z0 }
}

public enum VoxelModels {
    /// Largest grid side, in voxels (8 m).
    static let maxSide = 160

    /// A detailed voxel model for one piece, sized to its dimensions (front faces +z).
    /// Unknown categories fall back to a simple box so the scene never breaks.
    /// Deterministic: the same spec always yields the same grid.
    public static func build(_ spec: VoxelItemSpec) -> VoxelGrid { buildWithSurfaces(spec).grid }

    /// Top surfaces of the piece where small props can sit (desk / table / dresser / nightstand
    /// tops, free bookshelf slots, the TV console's front), in the same voxel coords as
    /// `build(spec)`'s grid. Empty for pieces nothing sits on (chairs, sofas, beds, props).
    public static func surfaces(_ spec: VoxelItemSpec) -> [VoxelSurface] { buildWithSurfaces(spec).surfaces }

    /// The grid and its surfaces from one build.
    public static func buildWithSurfaces(_ spec: VoxelItemSpec) -> (grid: VoxelGrid, surfaces: [VoxelSurface]) {
        let cat = trimmed(spec.category.lowercased())
        let nameV = VName(spec.name.lowercased())
        let attrs = Set(spec.attributes.map { trimmed($0.lowercased()) })
        let kind = route(category: cat, name: nameV, attrs: attrs, size: (spec.widthM, spec.depthM, spec.heightM))
        // Builders read style keywords from the name first, then the vision agent's material and
        // brand ("Desk" + "laminate" + "IKEA" reads like a white flat-pack desk). Measured photo
        // colors, when present, override the keyword palette.
        let name = VName(name: nameV.s, material: spec.material?.lowercased() ?? "", brand: spec.brand?.lowercased() ?? "",
                         primary: spec.primaryColor.map { Int($0 & 0xFFFFFF) }, secondary: spec.secondaryColor.map { Int($0 & 0xFFFFFF) })
        var (X, Y, Z) = dims(spec, kind)

        // models.js keys its seed on `${id}|X|Y|Z|name|cat|`; material/brand join it here, so the
        // same item is stable and two scanned items of one kind differ in their small details.
        let seed = strHash("\(spec.id ?? "")|\(X)|\(Y)|\(Z)|\(nameV.s)|\(cat)|\(name.material)|\(name.brand)|\(attrs.sorted().joined(separator: ","))")
        var NY = Y
        var bedTop = 0
        if kind == .rug { Y = 1; NY = 1 }
        // some builders need a minimum resolution to be recognizable
        if let m = kind.minDims { X = max(X, m.0); Y = max(Y, m.1); Z = max(Z, m.2); NY = Y }
        // a robot vacuum is a low disc whatever height a loose scan box (or the default) says
        if kind == .vacuum && Canvas.isRobotVacuum(name, Y) { Y = min(Y, 3); NY = Y }
        if kind == .bed {
            // h <= 0.7 m: h is the mattress-top height, the headboard rises above it
            if Y <= vox(0.7) { bedTop = max(3, Y); NY = max(bedTop + 3, vox(0.95)) } else { bedTop = clamp(vox(0.55), 3, Y - 3); NY = Y }
        }
        X = min(X, maxSide); NY = min(NY, maxSide); Z = min(Z, maxSide)

        let g = Canvas(X, NY, Z, seed: seed)
        let wallHung = attrs.contains(wallMountAttribute.lowercased())
        g.wear = wearLevel(spec.condition)
        g.attrs = attrs
        g.secondary = name.secondary
        switch kind {
        case .sofa: g.sofa(X, NY, Z, name)
        case .bed: g.bed(X, NY, Z, name, bedTop)
        case .mattress: g.mattress(X, NY, Z, name)
        case .desk: g.desk(X, NY, Z, name, lShape: g.attr("tableshapetype.lshaped"))
        case .chair:
            // RoomPlan's leg / chair type decides when present; otherwise keywords, then height
            let star = g.attr("chairlegtype.star") || g.attr("chairtype.swivel")
            let notOffice = g.attr("chairlegtype.four") || g.attr("chairtype.dining") || g.attr("chairtype.stool")
            if star {
                g.officeChair(X, NY, Z, name)
            } else if notOffice {
                g.diningChair(X, NY, Z, name)
            } else if name.has("office", "desk", "mesh", "gaming", "swivel", "task", "ergonomic", "herman miller", "aeron", "steelcase", "embody")
                || (Double(Y) * voxelM > 0.98 && !name.has("dining", "kitchen", "stool")) {
                g.officeChair(X, NY, Z, name)
            } else {
                g.diningChair(X, NY, Z, name)
            }
        case .table: g.table(X, NY, Z, name)
        case .dresser: g.dresser(X, NY, Z, name)
        case .bookshelf: g.bookshelf(X, NY, Z, name)
        case .tv: g.tv(X, NY, Z, name, wall: wallHung || name.has("wall mount", "wall-mount", "mounted"))
        case .lamp: g.lamp(X, NY, Z, name)
        case .books: g.books(X, NY, Z, name)
        case .art: g.art(X, NY, Z, name, wall: wallHung)
        case .photos: g.photos(X, NY, Z, name)
        case .binder: g.binder(X, NY, Z, name)
        case .kitchenware: g.kitchenware(X, NY, Z, name)
        case .plant: g.plant(X, NY, Z, name)
        case .rug: g.rug(X, NY, Z, name)
        case .clothes: g.clothes(X, NY, Z, name)
        case .electronics: g.electronics(X, NY, Z, name)
        case .decor: g.decor(X, NY, Z, name)
        case .appliance: g.appliance(X, NY, Z, name)
        case .fan: g.fan(X, NY, Z, name)
        case .beanBag: g.beanBag(X, NY, Z, name)
        case .mirror: g.mirror(X, NY, Z, name)
        case .quiltRack: g.quiltRack(X, NY, Z, name)
        case .framedPhotos: g.framedPhotos(X, NY, Z, name)
        case .stove: g.stove(X, NY, Z, name)
        case .dishwasher: g.dishwasher(X, NY, Z, name)
        case .microwave: g.microwave(X, NY, Z, name)
        case .bench: g.bench(X, NY, Z, name)
        case .ottoman: g.ottoman(X, NY, Z, name)
        case .bike: g.bike(X, NY, Z, name)
        case .suitcase: g.suitcase(X, NY, Z, name)
        case .guitar: g.guitar(X, NY, Z, name)
        case .piano: g.piano(X, NY, Z, name)
        case .keyboard: g.keyboardInstrument(X, NY, Z, name)
        case .drums: g.drums(X, NY, Z, name)
        case .vacuum: g.vacuum(X, NY, Z, name)
        case .monitor: g.monitor(X, NY, Z, name, wall: wallHung || name.has("wall mount", "wall-mount", "mounted"))
        case .scooter: g.scooter(X, NY, Z, name)
        case .bag: g.bag(X, NY, Z, name)
        case .fitness: g.fitness(X, NY, Z, name)
        case .board: g.board(X, NY, Z, name)
        case .motorcycle: g.motorcycle(X, NY, Z, name)
        case .stroller: g.stroller(X, NY, Z, name)
        case .wheelchair: g.wheelchair(X, NY, Z, name)
        case .grill: g.grill(X, NY, Z, name)
        case .lawnMower: g.lawnMower(X, NY, Z, name)
        case .crib: g.crib(X, NY, Z, name)
        case .ladder: g.ladder(X, NY, Z, name)
        case .trunk: g.trunk(X, NY, Z, name)
        case .basket: g.basket(X, NY, Z, name)
        case .trashCan: g.trashCan(X, NY, Z, name)
        case .toolbox: g.toolbox(X, NY, Z, name)
        case .petCrate: g.petCrate(X, NY, Z, name)
        case .petBed: g.petBed(X, NY, Z, name)
        case .catTree: g.catTree(X, NY, Z, name)
        case .clock: g.clock(X, NY, Z, name)
        case .toy: g.toy(X, NY, Z, name)
        case .rack: g.rack(X, NY, Z, name)
        case .box: g.kraftBox(X, NY, Z, name)
        }
        return (g.output(), g.surfaces)
    }

    /// Attribute that asks for the flat, wall-hung version of a piece (see `wallVariant`).
    public static let wallMountAttribute = "Mount.wall"

    /// The thin, wall-hung version of a piece: art loses its easel leg, a TV / monitor its feet
    /// (it gets a wall bracket), and the depth shrinks to at most 8 cm. Front still faces +z.
    public static func wallVariant(_ spec: VoxelItemSpec) -> VoxelItemSpec {
        var s = spec
        let d = spec.depthM.isFinite && spec.depthM > 0 ? spec.depthM : 0.08
        s.depthM = min(d, 0.08)
        if !s.attributes.contains(wallMountAttribute) { s.attributes.append(wallMountAttribute) }
        return s
    }

    /// Condition 1 (broken) ... 5 (like new) to a wear amount 3 ... 0. Unknown condition: crisp.
    static func wearLevel(_ condition: Int?) -> Double {
        guard let c = condition else { return 0 }
        switch c {
        case ...1: return 3
        case 2: return 2
        case 3: return 1
        case 4: return 0.4
        default: return 0
        }
    }

    /// Which builder a spec uses (exposed for tests and debugging).
    static func kind(_ spec: VoxelItemSpec) -> Kind {
        route(category: trimmed(spec.category.lowercased()), name: VName(spec.name.lowercased()),
              attrs: Set(spec.attributes.map { trimmed($0.lowercased()) }), size: (spec.widthM, spec.depthM, spec.heightM))
    }

    enum Kind: String, Sendable, CaseIterable {
        case sofa, bed, mattress, desk, chair, table, dresser, bookshelf, tv, lamp, books, art, photos, binder
        case kitchenware, plant, rug, clothes, electronics, decor, appliance, fan, beanBag, mirror, quiltRack
        case framedPhotos, stove, dishwasher, microwave, bench, ottoman, bike, suitcase
        case guitar, piano, keyboard, drums, vacuum, monitor, scooter, bag, fitness, board
        case motorcycle, stroller, wheelchair, grill, lawnMower, crib, ladder, trunk, basket, trashCan, toolbox
        case petCrate, petBed, catTree, clock, toy, rack, box

        /// Default size (w, d, h) in meters when a dimension is missing or invalid.
        var defaultSize: (Double, Double, Double) {
            switch self {
            case .sofa: (2.0, 0.9, 0.85)
            case .bed: (1.6, 2.1, 0.5)
            case .mattress: (1.5, 2.0, 0.25)
            case .desk: (1.2, 0.6, 0.75)
            case .chair: (0.55, 0.55, 0.9)
            case .table: (1.4, 0.8, 0.75)
            case .dresser: (1.0, 0.5, 0.9)
            case .bookshelf: (0.8, 0.3, 1.8)
            case .tv: (1.0, 0.2, 0.6)
            case .lamp: (0.4, 0.4, 1.6)
            case .books: (0.4, 0.3, 0.3)
            case .art: (0.6, 0.04, 0.8)
            case .photos: (0.33, 0.2, 0.12)
            case .binder: (0.3, 0.06, 0.33)
            case .plant: (0.5, 0.5, 1.0)
            case .rug: (2.0, 1.4, 0.02)
            case .kitchenware: (0.6, 0.4, 0.4)
            case .clothes: (0.5, 0.4, 0.3)
            case .electronics: (0.4, 0.3, 0.2)
            case .decor: (0.25, 0.25, 0.4)
            case .appliance: (0.5, 0.5, 0.85)
            case .fan: (0.5, 0.2, 0.5)
            case .beanBag: (0.9, 0.9, 0.7)
            case .mirror: (0.6, 0.05, 0.9)
            case .quiltRack: (0.9, 0.3, 0.9)
            case .framedPhotos: (0.4, 0.05, 0.5)
            case .stove: (0.76, 0.65, 0.92)
            case .dishwasher: (0.6, 0.6, 0.86)
            case .microwave: (0.5, 0.38, 0.3)
            case .bench: (1.2, 0.4, 0.45)
            case .ottoman: (0.6, 0.6, 0.42)
            case .bike: (1.7, 0.6, 1.0)
            case .suitcase: (0.45, 0.28, 0.7)
            case .guitar: (0.4, 0.3, 1.05)
            case .piano: (1.5, 0.6, 1.2)
            case .keyboard: (1.3, 0.45, 0.85)
            case .drums: (1.6, 1.3, 1.3)
            case .vacuum: (0.35, 0.3, 1.1)
            case .monitor: (0.6, 0.2, 0.45)
            case .scooter: (1.05, 0.45, 1.1)
            case .bag: (0.32, 0.22, 0.45)
            case .fitness: (0.8, 1.8, 1.4)
            case .board: (0.8, 0.22, 0.12)
            case .motorcycle: (2.1, 0.8, 1.15)
            case .stroller: (0.6, 0.95, 1.05)
            case .wheelchair: (0.65, 0.95, 0.95)
            case .grill: (1.2, 0.6, 1.1)
            case .lawnMower: (0.55, 1.4, 1.0)
            case .crib: (1.35, 0.75, 1.0)
            case .ladder: (0.5, 0.65, 1.5)
            case .trunk: (0.9, 0.5, 0.5)
            case .basket: (0.5, 0.4, 0.45)
            case .trashCan: (0.4, 0.35, 0.65)
            case .toolbox: (0.5, 0.25, 0.25)
            case .petCrate: (0.9, 0.6, 0.65)
            case .petBed: (0.8, 0.6, 0.2)
            case .catTree: (0.55, 0.5, 1.5)
            case .clock: (0.35, 0.05, 0.35)
            case .toy: (0.35, 0.3, 0.4)
            case .rack: (0.5, 0.5, 1.8)
            case .box: (0.5, 0.4, 0.4)
            }
        }

        /// Minimum (X, Y, Z) voxels for the builder to read as what it is.
        var minDims: (Int, Int, Int)? {
            switch self {
            case .sofa: (8, 6, 6)
            case .bed: (6, 4, 8)
            case .desk, .table: (3, 3, 3)
            case .chair: (5, 7, 5)
            case .dresser: (4, 4, 3)
            case .bookshelf: (4, 5, 3)
            case .tv: (6, 4, 1)
            case .lamp: (3, 6, 3)
            case .plant: (4, 6, 4)
            case .kitchenware: (5, 4, 4)
            case .appliance: (5, 6, 4)
            case .fan: (6, 6, 2)
            case .beanBag: (6, 5, 6)
            case .mirror: (4, 5, 1)
            case .quiltRack: (8, 8, 3)
            case .framedPhotos: (4, 5, 1)
            case .stove, .dishwasher: (8, 10, 8)
            case .microwave: (6, 4, 4)
            case .bench: (8, 4, 4)
            case .ottoman: (5, 4, 5)
            case .bike: (16, 10, 3)
            case .suitcase: (5, 8, 3)
            case .guitar: (5, 12, 1)
            case .piano: (10, 10, 4)
            case .keyboard: (10, 2, 3)
            case .drums: (14, 12, 10)
            case .vacuum: (4, 2, 4)
            case .monitor: (5, 4, 1)
            case .scooter: (12, 10, 3)
            case .bag: (4, 4, 3)
            case .fitness: (8, 8, 8)
            case .board: (3, 2, 2)
            case .motorcycle: (16, 10, 4)
            case .stroller, .wheelchair: (7, 9, 7)
            case .grill: (8, 10, 6)
            case .lawnMower: (7, 8, 7)
            case .crib: (8, 8, 6)
            case .ladder: (4, 10, 2)
            case .trunk: (6, 5, 4)
            case .basket: (5, 4, 4)
            case .trashCan: (4, 6, 4)
            case .toolbox: (6, 4, 3)
            case .petCrate: (7, 6, 6)
            case .petBed: (6, 3, 5)
            case .catTree: (6, 12, 6)
            case .clock: (5, 5, 1)
            case .toy: (6, 6, 5)
            case .rack: (5, 8, 3)
            default: nil
            }
        }
    }

    // MARK: routing

    /// Picks a builder from category + name keywords (models.js `route`, extended for Moove's
    /// categories: bed, chair, table, storage, lamp, appliance, decor, sofa), then checks the
    /// pick against the scanned size (`saneKind`, VoxelModels+Sanity.swift): a tall thin "pillow"
    /// is drawn as a lamp, a table-shaped RoomPlan "storage" as a table.
    /// A user's fix-it choice (`UserKind.table`, `ItemFix`) wins over everything, size check included.
    static func route(category cat: String, name n: VName, attrs: Set<String> = [], size: (Double, Double, Double)? = nil) -> Kind {
        if let user = ItemFix.voxelKind(lowercasedAttributes: attrs) { return user }
        let named = routeByName(category: cat, name: n, attrs: attrs, size: size)
        return saneKind(named, category: cat, name: n, attrs: attrs, size: size)
    }

    /// The builder the category, name and RoomPlan attributes ask for, before the size check.
    static func routeByName(category cat: String, name n: VName, attrs: Set<String> = [], size: (Double, Double, Double)? = nil) -> Kind {
        // RoomPlan attributes first: they come from the scan itself
        if attrs.contains("storagetype.shelf") { return .bookshelf }
        if attrs.contains("storagetype.cabinet") { return .dresser }
        if attrs.contains(where: { $0.hasPrefix("chairtype.") || $0.hasPrefix("chairlegtype.") }) && !n.has("sofa", "couch") { return .chair }
        if attrs.contains(where: { $0.hasPrefix("sofatype.") }) { return .sofa }
        if attrs.contains("tableshapetype.lshaped") && (cat == "table" || cat == "desk") { return .desk }
        if n.has("mattress") && !n.has("frame") { return .mattress }
        if n.has("bean bag", "beanbag", "bean-bag", "pouf", "floor cushion") { return .beanBag }
        // throw pillows and cushions are soft decor (drawn as a pillow), whatever the category
        if isPillow(n) { return .decor }
        if n.has("sectional", "sofa", "couch", "loveseat", "futon", "settee", "armchair") { return .sofa }
        if n.has("bookcase", "bookshelf", "book shelf", "shelving", "shelf unit", "étagère") { return .bookshelf }
        // the vision agent's specific names ("black standing desk") beat a broad category ("furniture"),
        // but not a small-object one: a "coffee table book" stays books, a "TV remote" electronics.
        // Order matters: a "desk lamp" is a lamp, a "desk chair" a chair, a "desk with drawers" a desk
        let small = smallCategories.contains(cat) || (cat == "electronics" && !isTV(n))
        if !small {
            // the detector's remaining categories by name, before the furniture words: a "wheel
            // chair" isn't a chair, a "dog bed" not a bed, a "desk clock" not a desk, a "dirt bike"
            // not a bicycle, a "toy chest" not a dresser
            if let k = householdKind(n) { return k }
            if n.word("lamp", "lamps", "sconce", "lantern") { return .lamp }
            if n.word("chair", "chairs", "stool", "stools", "recliner") { return .chair }
            if n.has("tv stand", "tv console", "tv cabinet", "tv unit", "media console", "entertainment center") { return .dresser }
            if n.has("desk", "workstation", "computer armoire", "roll top", "rolltop", "roll-top", "dressing table")
                || n.word("vanity", "secretary") { return .desk }
            // before the rug check: a "carpet cleaner" is a vacuum
            if isVacuum(n) { return .vacuum }
        }
        if n.has("dresser", "chest of drawers", "nightstand", "night stand", "bedside", "sideboard", "credenza", "armoire", "wardrobe")
            || n.word("drawers", "cabinet") { return .dresser }
        if n.word("rug") || n.has("carpet") { return .rug }
        if n.has("quilt rack", "blanket rack", "blanket ladder", "quilt ladder", "towel rack") { return .quiltRack }
        if n.has("mirror") { return .mirror }
        if n.has("frame") && n.has("photo", "picture", "portrait") { return .framedPhotos }
        if n.has("fridge", "refrigerator", "freezer") { return .appliance }
        if !small {
            if n.has("dishwasher") { return .dishwasher }
            if n.has("washing machine") || (n.word("washer", "dryer") && !n.has("hair dryer", "pressure washer")) { return .appliance }
            if n.has("microwave") { return .microwave }
            if n.word("stove", "range", "oven", "cooktop") && !n.has("toaster oven", "dutch oven") { return .stove }
        }
        if n.word("fan", "fans") { return .fan }
        if !small {
            if isFitness(n) { return .fitness } // an "exercise bike" isn't a bike
            if n.word("bike", "bicycle", "e-bike", "ebike") { return .bike }
            if n.has("suitcase", "luggage", "carry-on", "carry on") { return .suitcase }
            if n.has("ottoman", "footstool", "foot stool", "pouf") { return .ottoman }
            if n.word("bench", "settle") { return .bench }
            if n.has("bed frame", "bunk bed", "daybed", "platform bed", "headboard") || n.word("bed") { return .bed }
            if isTV(n) { return .tv }
            if n.word("table", "tables") { return .table }
            // #183: the detector's (#98) and vision's (#131) extra categories, after the furniture
            // words so a "piano bench" stays a bench and a "drum table" a table
            if let k = instrumentKind(n, loose: false, size: size) { return k }
            if isMonitor(n) { return .monitor }
            if n.word("scooter", "scooters", "e-scooter", "escooter", "moped", "vespa") { return .scooter }
            if isBoard(n) { return .board }
            if isBag(n) && cat != "luggage" && cat != "suitcase" { return .bag }
        }
        switch cat {
        case "sofa", "couch": return .sofa
        case "bed": return .bed
        case "mattress": return .mattress
        case "desk": return .desk
        case "chair": return .chair
        case "table": return n.has("desk", "workstation") ? .desk : .table
        case "dresser", "nightstand", "cabinet", "wardrobe": return .dresser
        case "bookshelf", "bookcase", "shelf", "shelving": return .bookshelf
        case "lamp", "light", "lighting": return .lamp
        case "tv", "television": return .tv
        case "books", "book": return .books
        case "art": return .art
        case "photos": return .photos
        case "trading_cards": return .binder
        case "plant", "plants": return .plant
        case "rug": return .rug
        case "kitchenware", "kitchen": return .kitchenware
        case "clothes", "clothing": return .clothes
        case "electronics":
            if isTV(n) { return .tv }
            if isMonitor(n) { return .monitor }
            if let k = instrumentKind(n, loose: false, size: size), k != .electronics { return k } // "Casio keyboard"
            if isClock(n) { return .clock } // an alarm clock
            return .electronics
        // #183: the detector's (#98, `ObjectVocabulary`) and vision's (#131) extra categories
        case "instrument", "instruments", "musical instrument", "musical_instrument", "music":
            return instrumentKind(n, loose: true, size: size) ?? .guitar
        case "guitar", "guitars", "ukulele", "violin", "viola", "cello", "bass guitar", "banjo", "mandolin": return .guitar
        case "piano": return instrumentKind(n, loose: true, size: size) == .keyboard ? .keyboard : .piano
        case "keyboard instrument", "keyboard_instrument", "synthesizer", "synth", "digital piano": return .keyboard
        case "keyboard":
            // a computer keyboard is narrow; a musical one is most of a meter
            if let w = size?.0, w.isFinite, w > 0, w < 0.6, instrumentKind(n, loose: false, size: size) != .keyboard { return .electronics }
            return .keyboard
        case "drums", "drum", "drum kit", "drum set": return .drums
        case "amplifier", "amp": return .electronics
        case "monitor", "monitors", "display", "screen", "computer monitor": return isTV(n) ? .tv : .monitor
        case "vacuum", "vacuums", "vacuum cleaner", "hoover", "robot vacuum": return .vacuum
        case "scooter", "scooters", "e-scooter", "kick scooter", "moped": return .scooter
        case "bag", "bags", "backpack", "backpacks", "duffel", "duffel bag", "tote", "handbag", "purse",
             "golf clubs", "golf bag", "punching bag":
            return .bag
        case "treadmill", "exercise bike", "rowing machine", "elliptical", "fitness", "exercise equipment", "gym equipment":
            return .fitness
        case "skateboard", "surfboard", "snowboard", "skis", "ski", "longboard", "paddleboard": return .board
        case "computer", "laptop", "printer", "speaker", "speakers", "game console", "projector", "turntable",
             "record player", "router", "camera":
            return isTV(n) ? .tv : isMonitor(n) ? .monitor : .electronics
        case "coffee machine", "coffee maker", "espresso machine", "toaster", "blender", "sewing machine", "air purifier",
             "heater", "space heater", "humidifier", "dehumidifier", "air conditioner", "water dispenser":
            return .appliance
        case "vase", "sculpture": return .decor
        case "plant stand": return .plant
        case "appliance", "appliances", "refrigerator", "fridge", "washer", "dryer", "washerdryer", "washer_dryer": return .appliance
        case "stove", "oven", "range": return .stove
        case "dishwasher": return .dishwasher
        case "microwave": return .microwave
        case "fan": return .fan
        case "mirror": return .mirror
        case "bench": return .bench
        case "ottoman": return .ottoman
        case "bike", "bicycle": return .bike
        case "suitcase", "luggage": return .suitcase
        case "box", "boxes": return .box
        case "storage":
            if n.word("bin", "bins", "tote", "totes", "basket", "baskets", "hamper") { return .basket }
            return n.word("box", "crate", "container") ? .box : .bookshelf
        // the rest of the detector's categories (`ObjectVocabulary`) and their vision-agent synonyms
        case "motorcycle", "motorbike", "dirt bike": return .motorcycle
        case "stroller", "pram", "pushchair", "buggy": return .stroller
        case "wheelchair": return .wheelchair
        case "grill", "bbq", "barbecue", "smoker": return .grill
        case "lawn mower", "mower", "lawnmower": return .lawnMower
        case "crib", "bassinet", "playpen", "baby furniture": return .crib
        case "ladder", "step ladder", "stepladder": return .ladder
        case "trunk", "chest", "toy chest", "footlocker": return .trunk
        case "bin", "bins", "basket", "baskets", "hamper", "laundry basket", "storage bin": return .basket
        case "trash can", "trash", "garbage can", "trash bin", "wastebasket", "recycling bin", "garbage": return .trashCan
        case "toolbox", "tool box", "tools", "tool chest": return .toolbox
        case "pet crate", "crate", "kennel", "dog crate", "pet carrier": return .petCrate
        case "pet bed", "dog bed", "cat bed": return .petBed
        case "cat tree", "cat tower", "scratching post": return .catTree
        case "clock", "clocks", "wall clock": return .clock
        case "toy", "toys", "stuffed animal", "plush", "dollhouse", "rocking horse": return .toy
        case "coat rack", "shoe rack", "clothes rack", "rack", "garment rack", "coat stand", "hat stand": return .rack
        case "workbench", "work bench": return .desk
        case "cart", "rolling cart", "utility cart": return n.has("bar cart", "tea cart") ? .table : .bookshelf
        case "decor":
            // a wall clock, a basket, a cat bed, a plush: household things, but not a "toy motorcycle" figurine
            if let k = householdKind(n), ![.motorcycle, .stroller, .wheelchair, .grill, .lawnMower, .desk].contains(k) { return k }
            if n.word("art", "artwork", "painting", "canvas", "poster", "print") { return .art }
            if n.word("plant", "plants", "succulent", "fern", "monstera") { return .plant }
            if n.word("photos") { return .photos }
            return .decor
        default: return size.map(shapeKind) ?? .box
        }
    }

    /// A musical instrument named in `n`, or an amp (`.electronics`). `loose`: the category already
    /// says "instrument", so a bare "keyboard" / "drum" counts.
    static func instrumentKind(_ n: VName, loose: Bool, size: (Double, Double, Double)? = nil) -> Kind? {
        if n.word("amp", "amps", "amplifier", "pedalboard") && (loose || n.has("guitar", "bass", "keyboard", "instrument", "marshall", "fender")) {
            return .electronics
        }
        if n.word("drums", "drumset", "drumkit", "cajon") || n.has("drum kit", "drum set", "snare", "e-kit", "v-drums") || (loose && n.word("drum")) {
            return .drums
        }
        if n.has("synth", "keytar", "digital piano", "stage piano", "midi keyboard", "electronic keyboard", "digital keyboard",
                 "keyboard piano", "piano keyboard", "musical keyboard", "music keyboard", "keyboard stand") { return .keyboard }
        if n.word("keyboard", "keyboards") {
            let wide = size.map { $0.0.isFinite && $0.0 >= 0.75 } ?? false
            if loose || wide || n.has("casio", "yamaha", "korg", "roland", "nord", "kawai", "alesis", "piano") { return .keyboard }
        }
        if n.word("piano", "pianos", "pianoforte", "pianola") || n.has("baby grand", "grand piano", "upright piano") { return .piano }
        if n.has("guitar", "ukulele", "double bass", "upright bass")
            || n.word("violin", "violins", "viola", "cello", "cellos", "fiddle", "uke", "banjo", "mandolin") { return .guitar }
        return nil
    }

    /// The detector's remaining categories (#183 follow-up) by name: vehicles, baby and pet gear,
    /// household storage, clocks, toys, racks, outdoor gear. Checked before the furniture words.
    static func householdKind(_ n: VName) -> Kind? {
        if n.word("motorcycle", "motorcycles", "motorbike", "motorbikes", "motocross", "sportbike", "harley", "ducati")
            || n.has("dirt bike", "pit bike", "harley-davidson") {
            if !n.word("helmet", "jacket", "gloves", "glove", "boots", "cover", "battery", "jack", "lift", "gear", "toy") { return .motorcycle }
        }
        if n.word("wheelchair", "wheelchairs") || n.has("wheel chair", "transport chair") { return .wheelchair }
        if n.word("stroller", "strollers", "pram", "pushchair", "pushchairs") || n.has("baby jogger", "jogging stroller")
            || (n.word("buggy") && !n.has("golf", "beach", "dune")) { return .stroller }
        if n.has("pet crate", "dog crate", "cat crate", "puppy crate", "dog cage", "pet cage", "pet carrier", "cat carrier",
                 "dog carrier", "dog playpen", "pet playpen", "puppy pen", "dog pen") || n.word("kennel", "kennels") { return .petCrate }
        if n.has("dog bed", "cat bed", "pet bed", "puppy bed", "dog sofa", "pet sofa", "pet cushion") { return .petBed }
        if n.has("cat tree", "cat tower", "cat condo", "cat scratcher", "scratching post", "scratch post", "cat gym") { return .catTree }
        if (n.word("crib", "cribs", "bassinet", "bassinets", "playpen", "playpens", "cradle")
            || n.has("baby cot", "cot bed", "pack n play", "pack 'n play", "pack and play", "pack-n-play", "play yard", "play pen"))
            && !n.word("sheet", "sheets", "bumper", "mobile", "mattress") { return .crib }
        if n.word("toolbox", "toolboxes", "toolchest") || n.has("tool box", "tool chest", "tool cabinet", "tool case", "tool cart") { return .toolbox }
        if n.word("trunk", "trunks", "footlocker") || n.has("foot locker", "toy chest", "toy box", "toybox", "hope chest", "blanket chest",
                                                            "cedar chest", "storage chest", "treasure chest", "wooden chest") {
            if !n.has("tree trunk", "trunk organizer") { return .trunk }
        }
        if n.has("trash can", "trashcan", "garbage can", "garbage bin", "trash bin", "waste bin", "wastebasket", "waste basket",
                 "wastepaper", "recycling bin", "recycle bin", "dustbin", "rubbish bin", "pedal bin", "wheelie bin", "compost bin", "litter bin")
            || (n.word("trash", "garbage", "rubbish") && !n.word("bag", "bags", "compactor")) { return .trashCan }
        if n.word("basket", "baskets", "hamper", "hampers", "bin", "bins") || n.has("storage tote", "plastic tote") { return .basket }
        if isClock(n) { return .clock }
        if n.has("coat rack", "coat stand", "coat tree", "hat stand", "hat rack", "hall tree", "shoe rack", "shoe shelf", "shoe stand",
                 "shoe organizer", "clothes rack", "clothing rack", "garment rack", "clothes rail", "clothes stand", "rolling rack") { return .rack }
        if (n.word("ladder", "ladders", "stepladder", "stepladders") || n.has("step ladder", "step-ladder"))
            && !n.has("blanket", "quilt", "towel", "shelf", "bookcase", "desk", "plant", "rack") { return .ladder }
        if n.word("grill", "grills", "bbq", "barbecue", "barbeque", "smoker", "hibachi", "kamado", "traeger") || n.has("big green egg", "weber kettle") {
            if !n.has("grill pan", "foreman", "panini", "griddle", "indoor", "brush", "cover", "grill tool", "grill mat") { return .grill }
        }
        if n.word("mower", "mowers", "lawnmower", "lawnmowers") || n.has("lawn mower", "lawn tractor") { return .lawnMower }
        if n.word("workbench", "workbenches") { return .desk }
        return toyKind(n)
    }

    static func isClock(_ n: VName) -> Bool { n.word("clock", "clocks") }

    static func toyKind(_ n: VName) -> Kind? {
        n.word("toy", "toys", "teddy", "plush", "plushie", "plushies", "dollhouse", "doll", "dolls", "lego")
            || n.has("stuffed animal", "stuffed toy", "soft toy", "doll house", "rocking horse", "play kitchen") ? .toy : nil
    }

    /// A computer monitor / display (TV words are checked first by the callers).
    static func isMonitor(_ n: VName) -> Bool {
        if n.has("baby monitor", "heart rate", "blood pressure", "glucose", "monitor stand", "monitor riser", "monitor arm",
                 "monitor mount", "monitor light") { return false }
        return n.word("monitor", "monitors") || n.has("computer screen", "pc screen", "computer display", "studio display", "pro display",
                                                       "lcd display", "led display", "gaming display", "imac", "all-in-one computer",
                                                       "all in one computer", "ultrawide")
    }

    static func isVacuum(_ n: VName) -> Bool {
        if n.has("sealer", "storage", "vacuum bag", "vacuum-sealed", "vacuum sealed", "insulated", "flask", "tube") { return false }
        return n.word("vacuum", "vacuums", "hoover", "roomba", "roborock", "robovac", "shopvac", "shop-vac", "dustbuster")
            || n.has("shop vac", "vacuum cleaner", "carpet cleaner", "carpet shampooer", "robot vacuum", "stick vac")
    }

    static func isFitness(_ n: VName) -> Bool {
        n.word("treadmill", "treadmills", "elliptical", "rower")
            || n.has("rowing machine", "exercise bike", "stationary bike", "spin bike", "indoor bike", "indoor cycle", "peloton",
                     "recumbent bike", "air bike", "assault bike", "cross trainer", "cross-trainer", "walking pad")
    }

    static func isBoard(_ n: VName) -> Bool {
        if n.word("skateboard", "skateboards", "longboard", "surfboard", "surfboards", "snowboard", "snowboards", "skis",
                  "paddleboard", "bodyboard", "wakeboard", "skimboard") || n.has("paddle board") { return true }
        return n.word("ski") && !n.has("boot", "jacket", "pants", "goggles", "helmet", "pole", "glove", "mask", "rack")
    }

    static func isBag(_ n: VName) -> Bool {
        n.word("backpack", "backpacks", "rucksack", "knapsack", "duffel", "duffle", "holdall", "tote", "totes", "handbag", "purse",
               "bag", "bags", "satchel", "briefcase", "daypack")
    }

    /// The name is a TV itself, not a TV accessory ("TV remote", "TV antenna").
    static func isTV(_ n: VName) -> Bool {
        n.word("tv", "television", "tvs") && !n.word("remote", "remotes", "antenna", "cable", "cables", "stick", "box")
    }

    /// Categories that already name a small object; furniture words in the name ("coffee table
    /// book", "chair cushion") describe it rather than make it furniture.
    static let smallCategories: Set<String> = [
        "books", "book", "art", "photos", "kitchenware", "kitchen", "clothes", "clothing", "plant", "plants",
        "binder", "trading_cards", "decor",
    ]

    /// Last resort for a broad category ("furniture", "other") whose name has no keyword: the
    /// likeliest piece for the scanned (w, d, h) in meters. Small or odd shapes stay boxes.
    static func shapeKind(_ s: (Double, Double, Double)) -> Kind {
        let (w, d, h) = s
        guard w.isFinite, d.isFinite, h.isFinite, w > 0, d > 0, h > 0 else { return .box }
        let foot = max(w, d), slim = min(w, d)
        if h < 0.35 && foot >= 1.2 { return .rug }
        if h >= 1.2 && slim <= 0.5 { return .bookshelf }
        if h >= 0.6 && h <= 0.85 && foot >= 0.9 { return slim <= 0.75 ? .desk : .table }
        if h >= 0.4 && h <= 0.7 && foot >= 1.4 && slim >= 0.9 { return .bed }
        if h >= 0.65 && h <= 1.2 && foot >= 0.6 && foot <= 1.6 && slim >= 0.4 { return .dresser }
        return .box
    }

    // MARK: sizing

    /// Voxel dims (X, Y, Z) from the spec, using the kind's defaults for missing/invalid sizes.
    static func dims(_ spec: VoxelItemSpec, _ kind: Kind) -> (Int, Int, Int) {
        let def = kind.defaultSize
        func num(_ v: Double, _ d: Double) -> Double { v.isFinite && v > 0 ? v : d }
        let w = clampD(num(spec.widthM, def.0), voxelM, 8)
        let d = clampD(num(spec.depthM, def.1), voxelM, 8)
        let h = clampD(num(spec.heightM, def.2), voxelM, 4)
        return (vox(w), vox(h), vox(d))
    }

    static func trimmed(_ s: String) -> String {
        let isWS: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        return String(s.drop(while: isWS).reversed().drop(while: isWS).reversed())
    }
}

// MARK: - math helpers (JS semantics)

let voxelM = 0.05

@inline(__always) func clamp(_ v: Int, _ a: Int, _ b: Int) -> Int { max(a, min(b, v)) }
@inline(__always) func clampD(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }

/// JS Math.round (half toward +infinity); non-finite values become 0 so nothing traps.
@inline(__always) func rd(_ v: Double) -> Int {
    guard v.isFinite else { return 0 }
    return Int((max(-1e9, min(1e9, v)) + 0.5).rounded(.down))
}

/// Math.floor / Math.ceil as Int, trap-free.
@inline(__always) func fl(_ v: Double) -> Int {
    guard v.isFinite else { return 0 }
    return Int(max(-1e9, min(1e9, v)).rounded(.down))
}

@inline(__always) func ce(_ v: Double) -> Int {
    guard v.isFinite else { return 0 }
    return Int(max(-1e9, min(1e9, v)).rounded(.up))
}

/// Math.floor(a / b) for ints.
@inline(__always) func fdiv(_ a: Int, _ b: Int) -> Int { fl(Double(a) / Double(b)) }

@inline(__always) func D(_ i: Int) -> Double { Double(i) }

/// Half-open integer range that is simply empty when b <= a (Swift's a..<b would trap).
/// Closed integer range that is simply empty when b < a.
@inline(__always) func thru(_ a: Int, _ b: Int) -> StrideThrough<Int> { stride(from: a, through: b, by: 1) }

@inline(__always) func upTo(_ a: Int, _ b: Int) -> StrideTo<Int> { stride(from: a, to: b, by: 1) }

func vox(_ m: Double) -> Int { max(1, rd(m / voxelM)) }

/// FNV-1a over UTF-16 code units (JS charCodeAt).
func strHash(_ s: String) -> UInt32 {
    var h: UInt32 = 2_166_136_261
    for u in s.utf16 {
        h ^= UInt32(u)
        h = h &* 16_777_619
    }
    return h
}

@inline(__always) func u32(_ i: Int) -> UInt32 { UInt32(truncatingIfNeeded: i) }

/// Deterministic 0..<1 hash of a lattice point.
func hash3(_ x: Int, _ y: Int, _ z: Int, _ s: UInt32) -> Double {
    var h = u32(x) &* 374_761_393 &+ u32(y) &* 668_265_263 &+ u32(z) &* 1_440_662_683 &+ s &* 1_274_126_177
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h) / 4_294_967_296
}

func shade(_ c: Int, _ f: Double) -> Int {
    let r = clamp(rd(D((c >> 16) & 255) * f), 0, 255)
    let g = clamp(rd(D((c >> 8) & 255) * f), 0, 255)
    let b = clamp(rd(D(c & 255) * f), 0, 255)
    return (r << 16) | (g << 8) | b
}

func mix(_ a: Int, _ b: Int, _ t: Double) -> Int {
    let r = rd(D((a >> 16) & 255) * (1 - t) + D((b >> 16) & 255) * t)
    let g = rd(D((a >> 8) & 255) * (1 - t) + D((b >> 8) & 255) * t)
    let bl = rd(D(a & 255) * (1 - t) + D(b & 255) * t)
    return (clamp(r, 0, 255) << 16) | (clamp(g, 0, 255) << 8) | clamp(bl, 0, 255)
}

// MARK: - palette

enum P {
    static let cream = 0xEFE7D6
    static let linen = 0xD8CBB3
    static let oatmeal = 0xCDBFA6
    static let oak = 0xC49A6C
    static let birch = 0xD9BF94
    static let walnut = 0x6E4A33
    static let darkWood = 0x4A3324
    static let sage = 0x8B9A7B
    static let sageDark = 0x6C7B5E
    static let charcoal = 0x34322F
    static let black = 0x232220
    static let grey = 0x8F8D88
    static let white = 0xECE7DD
    static let brass = 0xC29A55
    static let metal = 0x9A9FA3
    static let terracotta = 0xC0704A
    static let rust = 0x9C5236
    static let navy = 0x3F5A73
    static let mustard = 0xC9A25A
    static let blush = 0xD9A99E
    static let kraft = 0xB98D5E
    static let glass = 0x9FC1D6
    static let screen = 0x15181D
    static let bulb = 0xFFD78A
}

let keywordColors: [([String], Int)] = [
    (["grey", "gray", "charcoal grey", "slate"], 0x8F8D88),
    (["charcoal"], 0x3A3835),
    (["black"], 0x2B2A28),
    (["white", "ivory"], 0xEBE6DC),
    (["cream"], 0xE9DFCB),
    (["oak"], 0xC49A6C),
    (["walnut"], 0x6E4A33),
    (["navy", "blue", "denim"], 0x5B7896),
    (["green", "sage", "olive"], 0x7F9471),
    (["red", "burgundy", "crimson"], 0xA8473D),
    (["pink", "blush", "rose"], 0xD9A5A0),
    (["beige", "tan", "linen", "sand"], 0xD6C4A4),
    (["brown"], 0x7A5A40),
    (["leather"], 0x8A5A3A),
    (["metal", "steel", "chrome", "aluminum", "aluminium"], 0x9A9FA3),
    (["pine", "birch", "bamboo"], 0xD9BF94),
    (["wood", "wooden", "timber"], 0xC49A6C),
]

/// Extra material words (vision-agent materials) not covered by `keywordColors`.
let materialColors: [([String], Int)] = [
    (["laminate", "melamine"], 0xEBE6DC),
    (["particleboard", "particle board", "mdf", "plywood"], 0xD9BF94),
    (["plastic", "acrylic", "resin"], 0xE4E1DA),
    (["marble", "stone", "concrete"], 0xE7E2D8),
    (["rattan", "wicker", "cane", "jute", "seagrass"], 0xC9A875),
    (["mesh"], 0x34322F),
    (["iron", "wrought"], 0x2B2A28),
    (["brass", "gold"], 0xC29A55),
    (["teak", "mahogany", "cherry"], 0x8A5A3A),
    (["maple", "ash"], 0xD9BF94),
]

func keywordColor(_ n: VName, _ table: [([String], Int)]) -> Int? {
    for (words, c) in table where n.word(words) { return c }
    return nil
}

/// The color a name (then its material, then its brand) asks for, else `fallback`.
/// Name color words win over the material ("white oak desk" is white).
func colorFromName(_ n: VName, _ fallback: Int) -> Int {
    if let p = n.primary { return p == 0 ? 0x010101 : p }
    let velvet = n.word("velvet")
    for part in n.parts {
        if let c = keywordColor(part, keywordColors) { return velvet ? shade(c, 0.85) : c }
    }
    if velvet { return 0x6F7D63 } // velvet without a color: deep sage
    for part in n.parts {
        if let c = keywordColor(part, materialColors) { return c }
    }
    // IKEA's flat-pack look: birch veneer instead of dark wood
    if n.brand.contains("ikea") && (fallback == P.oak || fallback == P.walnut || fallback == P.darkWood) { return P.birch }
    return fallback
}

let bookColors = [
    0x7A3B2E, 0x3F5A73, 0x8B9A7B, 0xC9A25A, 0xE8E0D0, 0x4E6B5C, 0xA8473D,
    0x2F2E2C, 0xD9A5A0, 0x6E4A33, 0x7E95A8, 0xB9764F, 0x5D6B47, 0xD8CBB3,
]

// MARK: - name matching (stand-ins for the JS regexes; \b = ASCII word boundary)

struct VName: Sendable {
    let s: String
    let b: [UInt8]
    /// Name, material and brand on their own (for color priority); just [self] for plain text.
    private let sub: [VName]
    let material: String
    let brand: String
    /// Photo-measured main / accent colors (override keyword colors when set).
    var primary: Int? = nil
    var secondary: Int? = nil

    init(_ s: String) {
        self.s = s
        b = Array(s.utf8)
        sub = []
        material = ""
        brand = ""
    }

    /// Searchable text "name | material | brand"; colors prefer the name, then the material.
    init(name: String, material: String, brand: String, primary: Int? = nil, secondary: Int? = nil) {
        self.primary = primary
        self.secondary = secondary
        let full = material.isEmpty && brand.isEmpty ? name : "\(name) | \(material) | \(brand)"
        s = full
        b = Array(full.utf8)
        sub = [VName(name), VName(material), VName(brand)]
        self.material = material
        self.brand = brand
    }

    private init(bytes: [UInt8]) {
        b = bytes
        s = String(decoding: bytes, as: UTF8.self)
        sub = []
        material = ""
        brand = ""
    }

    var parts: [VName] { sub.isEmpty ? [self] : sub }

    @inline(__always) static func isWord(_ c: UInt8) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    /// Start offsets of `needle` in the name.
    func occurrences(_ needle: String) -> [Int] {
        let n = Array(needle.utf8)
        guard !n.isEmpty, n.count <= b.count else { return [] }
        var out: [Int] = []
        for i in 0...(b.count - n.count) {
            var ok = true
            for j in 0..<n.count where b[i + j] != n[j] { ok = false; break }
            if ok { out.append(i) }
        }
        return out
    }

    func has(_ subs: String...) -> Bool { subs.contains { !occurrences($0).isEmpty } }

    func word(_ words: String...) -> Bool { word(words) }

    func word(_ words: [String]) -> Bool {
        for w in words {
            let len = w.utf8.count
            for i in occurrences(w) {
                let before = i == 0 || !Self.isWord(b[i - 1])
                let after = i + len >= b.count || !Self.isWord(b[i + len])
                if before && after { return true }
            }
        }
        return false
    }

    /// The name with every whole-word occurrence of `words` removed (JS replace(/\b(..)\b/g, "")).
    func removingWords(_ words: String...) -> VName {
        var bytes = b
        for w in words {
            let cur = VName(bytes: bytes)
            let len = w.utf8.count
            var cut: [Int] = []
            for i in cur.occurrences(w) {
                let before = i == 0 || !Self.isWord(bytes[i - 1])
                let after = i + len >= bytes.count || !Self.isWord(bytes[i + len])
                if before && after { cut.append(i) }
            }
            for i in cut.reversed() { bytes.removeSubrange(i..<(i + len)) }
        }
        var out = VName(bytes: bytes)
        out.primary = primary
        out.secondary = secondary
        return out
    }

    /// The first number matching /(\d+)\s*-?\s*(kw)/ (or a single digit when `multiDigit` is false).
    func number(before keywords: [String], multiDigit: Bool) -> Int? {
        let kws = keywords.map { Array($0.utf8) }
        let isDigit: (UInt8) -> Bool = { $0 >= 48 && $0 <= 57 }
        let isSpace: (UInt8) -> Bool = { $0 == 32 || $0 == 9 || $0 == 10 || $0 == 13 }
        var i = 0
        while i < b.count {
            guard isDigit(b[i]) else { i += 1; continue }
            var j = i + 1
            if multiDigit { while j < b.count && isDigit(b[j]) { j += 1 } }
            var value = 0
            for k in i..<j { value = min(1_000_000, value * 10 + Int(b[k] - 48)) }
            var p = j
            while p < b.count && isSpace(b[p]) { p += 1 }
            if p < b.count && b[p] == 45 { p += 1 }
            while p < b.count && isSpace(b[p]) { p += 1 }
            for kw in kws where p + kw.count <= b.count && Array(b[p..<(p + kw.count)]) == kw { return value }
            i += 1
        }
        return nil
    }
}

// MARK: - canvas

/// A working voxel grid with MoveWise's drawing primitives. Cells carry a FLAT flag (no jitter:
/// screens, bulbs, glass); `output()` applies the per-voxel color jitter and returns a VoxelGrid.
/// Local to one build call, never shared.
final class Canvas {
    static let present: UInt32 = 0x1000000
    static let flatBit: UInt32 = 0x2000000

    let nx: Int, ny: Int, nz: Int
    let seed: UInt32
    var cells: [UInt32]
    private var rngState: UInt32
    /// 0 (crisp) ... 3 (worn out), from the item's condition.
    var wear: Double = 0
    /// RoomPlan attributes, lowercased ("chairtype.stool", ...).
    var attrs: Set<String> = []
    /// Photo-measured accent color, if any.
    var secondary: Int?
    /// Top surfaces builders report for props (MoveWise's `g.surface`).
    var surfaces: [VoxelSurface] = []

    /// Records a prop surface: half-open [x0, x1) × [z0, z1), `y` the first free layer above it,
    /// `clearance` the free layers above it (nil: open). Clipped to the grid; empty rects are dropped.
    func surface(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int, _ y: Int, clearance: Int? = nil) {
        let xs = max(0, x0), zs = max(0, z0), xe = min(nx, x1), ze = min(nz, z1)
        guard xe > xs, ze > zs, y >= 0 else { return }
        surfaces.append(VoxelSurface(x0: xs, z0: zs, x1: xe, z1: ze, y: y, clearance: clearance))
    }

    func attr(_ a: String) -> Bool { attrs.contains(a) }

    init(_ nx: Int, _ ny: Int, _ nz: Int, seed: UInt32) {
        self.nx = max(1, nx)
        self.ny = max(1, ny)
        self.nz = max(1, nz)
        self.seed = seed
        rngState = seed
        cells = Array(repeating: 0, count: self.nx * self.ny * self.nz)
    }

    /// mulberry32, seeded like models.js.
    func rand() -> Double {
        rngState = rngState &+ 0x6D2B_79F5
        let a = rngState
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }

    @inline(__always) func idx(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * nz + z) * nx + x }
    @inline(__always) func inb(_ x: Int, _ y: Int, _ z: Int) -> Bool { x >= 0 && y >= 0 && z >= 0 && x < nx && y < ny && z < nz }

    func set(_ x: Int, _ y: Int, _ z: Int, _ c: Int, flat: Bool = false) {
        guard inb(x, y, z) else { return }
        cells[idx(x, y, z)] = u32(c & 0xFFFFFF) | Self.present | (flat ? Self.flatBit : 0)
    }

    func clear(_ x: Int, _ y: Int, _ z: Int) {
        if inb(x, y, z) { cells[idx(x, y, z)] = 0 }
    }

    func has(_ x: Int, _ y: Int, _ z: Int) -> Bool { inb(x, y, z) && cells[idx(x, y, z)] != 0 }

    /// Half-open box [x0,x1) × [y0,y1) × [z0,z1). The closure returns a color, nil to skip, or a
    /// negative number to clear the cell.
    func box(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, flat: Bool = false, _ c: (Int, Int, Int) -> Int?) {
        let xs = max(0, x0), ys = max(0, y0), zs = max(0, z0)
        let xe = min(nx, x1), ye = min(ny, y1), ze = min(nz, z1)
        guard xs < xe, ys < ye, zs < ze else { return }
        let bits = Self.present | (flat ? Self.flatBit : 0)
        for y in ys..<ye {
            for z in zs..<ze {
                for x in xs..<xe {
                    guard let col = c(x, y, z) else { continue }
                    cells[idx(x, y, z)] = col < 0 ? 0 : (u32(col & 0xFFFFFF) | bits)
                }
            }
        }
    }

    func box(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ c: Int, flat: Bool = false) {
        box(x0, y0, z0, x1, y1, z1, flat: flat) { _, _, _ in c }
    }

    enum Axis { case x, y, z }

    /// Wood with grain stripes running along `axis`.
    func wood(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ c: Int, _ axis: Axis? = nil) {
        let s = seed
        let ax: Axis
        if let axis { ax = axis } else {
            let dx = x1 - x0, dy = y1 - y0, dz = z1 - z0
            ax = dx >= dy && dx >= dz ? .x : dz >= dy ? .z : .y
        }
        let dark = shade(c, 0.88), light = shade(c, 1.06)
        box(x0, y0, z0, x1, y1, z1) { x, y, z in
            let k: Double
            let run: Int
            switch ax {
            case .x: k = hash3(0, y, z, s); run = x
            case .z: k = hash3(x, y, 0, s); run = z
            case .y: k = hash3(x, 0, z, s); run = y
            }
            // occasional knot / grain break along the run
            let brk = hash3(run >> 2, Int(k * 97), 3, s) < 0.12
            if k < 0.3 { return brk ? c : dark }
            if k > 0.86 { return light }
            return c
        }
    }

    /// Vertical cylinder centered at (cx, cz) (can be .5), radius r, layers [y0, y1).
    /// The closure gets (x, y, z, d2) and returns a color or nil to skip.
    func cyl(_ cx: Double, _ cz: Double, _ r: Double, _ y0: Int, _ y1: Int, hollow: Bool = false, flat: Bool = false, _ c: (Int, Int, Int, Double) -> Int?) {
        guard r.isFinite, cx.isFinite, cz.isFinite, r > 0 else { return }
        let r2 = r * r, ri2 = (r - 1) * (r - 1)
        let ys = max(0, y0), ye = min(ny, y1)
        guard ys < ye else { return }
        for z in thru(max(0, fl(cz - r)), min(nz - 1, ce(cz + r))) {
            for x in thru(max(0, fl(cx - r)), min(nx - 1, ce(cx + r))) {
                let d2 = (D(x) - cx) * (D(x) - cx) + (D(z) - cz) * (D(z) - cz)
                if d2 > r2 { continue }
                if hollow && d2 < ri2 { continue }
                for y in ys..<ye {
                    if let col = c(x, y, z, d2) { set(x, y, z, col, flat: flat) }
                }
            }
        }
    }

    func cyl(_ cx: Double, _ cz: Double, _ r: Double, _ y0: Int, _ y1: Int, _ c: Int, hollow: Bool = false, flat: Bool = false) {
        cyl(cx, cz, r, y0, y1, hollow: hollow, flat: flat) { _, _, _, _ in c }
    }

    func ellipsoid(_ cx: Double, _ cy: Double, _ cz: Double, _ rx: Double, _ ry: Double, _ rz: Double, _ c: (Int, Int, Int, Double) -> Int?) {
        guard rx > 0, ry > 0, rz > 0, [cx, cy, cz, rx, ry, rz].allSatisfy(\.isFinite) else { return }
        for y in thru(max(0, fl(cy - ry)), min(ny - 1, ce(cy + ry))) {
            for z in thru(max(0, fl(cz - rz)), min(nz - 1, ce(cz + rz))) {
                for x in thru(max(0, fl(cx - rx)), min(nx - 1, ce(cx + rx))) {
                    let dx = (D(x) - cx) / rx, dy = (D(y) - cy) / ry, dz = (D(z) - cz) / rz
                    let d = dx * dx + dy * dy + dz * dz
                    if d > 1 { continue }
                    if let col = c(x, y, z, d) { set(x, y, z, col) }
                }
            }
        }
    }

    func ellipsoid(_ cx: Double, _ cy: Double, _ cz: Double, _ rx: Double, _ ry: Double, _ rz: Double, _ c: Int) {
        ellipsoid(cx, cy, cz, rx, ry, rz) { _, _, _, _ in c }
    }

    func line(_ x0: Double, _ y0: Double, _ z0: Double, _ x1: Double, _ y1: Double, _ z1: Double, _ c: Int, thick: Bool = false, flat: Bool = false) {
        let span = max(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
        guard span.isFinite else { return }
        let n = max(1, min(4096, ce(span * 1.5)))
        for i in 0...n {
            let t = D(i) / D(n)
            let x = rd(x0 + (x1 - x0) * t), y = rd(y0 + (y1 - y0) * t), z = rd(z0 + (z1 - z0) * t)
            set(x, y, z, c, flat: flat)
            if thick { set(x + 1, y, z, c, flat: flat); set(x, y, z + 1, c, flat: flat); set(x + 1, y, z + 1, c, flat: flat) }
        }
    }

    func line(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ c: Int) {
        line(D(x0), D(y0), D(z0), D(x1), D(y1), D(z1), c)
    }

    /// Two distinct accent colors (pillows, throws, bins) that stand out from `base`.
    /// A per-item detail: picked from the seed, so each scanned piece gets its own pair.
    func accentPair(avoiding base: Int) -> (Int, Int) {
        let all = [P.sage, P.mustard, P.blush, P.navy, P.rust, P.cream, P.terracotta, 0x7E95A8]
        let dist: (Int) -> Int = { c in
            abs(((c >> 16) & 255) - ((base >> 16) & 255)) + abs(((c >> 8) & 255) - ((base >> 8) & 255)) + abs((c & 255) - (base & 255))
        }
        if let s = secondary {
            let other = all.filter { dist($0) > 70 && $0 != s }
            return (s, other.isEmpty ? P.cream : other[Int(seed % UInt32(other.count))])
        }
        var pal = all.filter { dist($0) > 70 }
        if pal.count < 2 { pal = all }
        let i = Int(seed % UInt32(pal.count))
        let j = (i + 1 + Int((seed >> 8) % UInt32(pal.count - 1))) % pal.count
        return (pal[i], pal[j])
    }

    /// True when a wear-driven defect (missing knob, slat, ...) should happen at this spot:
    /// never on crisp items, likelier the worse the condition.
    func worn(_ x: Int, _ y: Int, _ z: Int, _ chance: Double) -> Bool {
        wear >= 1.5 && hash3(x, y, z, seed ^ 0x9E37_79B9) < chance * (wear - 1)
    }

    /// The finished grid, with models.js's ±4.5% per-voxel brightness jitter on non-flat voxels,
    /// plus wear from the item's condition: faded colors, scuffed edges and a few stains.
    func output() -> VoxelGrid {
        var out = VoxelGrid(nx: nx, ny: ny, nz: nz)
        var any = false
        let w = wear
        let scuffSeed = seed ^ 0x5BD1_E995, stainSeed = seed ^ 0x27D4_EB2D
        for y in 0..<ny {
            for z in 0..<nz {
                for x in 0..<nx {
                    let v = cells[idx(x, y, z)]
                    if v == 0 { continue }
                    var c = Int(v & 0xFFFFFF)
                    if v & Self.flatBit == 0 {
                        c = shade(c, 1 + (hash3(x, y, z, seed) - 0.5) * 0.09)
                        if w > 0 {
                            // fade toward grey, scuff exposed edges, blotchy stains on worn pieces
                            let lum = (((c >> 16) & 255) * 30 + ((c >> 8) & 255) * 59 + (c & 255) * 11) / 100
                            c = mix(c, mix(lum * 0x010101, 0xD8D0C0, 0.3), 0.12 * w)
                            let exposed = !has(x - 1, y, z) || !has(x + 1, y, z) || !has(x, y + 1, z) || !has(x, y, z - 1) || !has(x, y, z + 1)
                            if exposed && hash3(x, y, z, scuffSeed) < 0.035 * w { c = shade(c, 0.76) }
                            if w >= 1.5 && hash3(x >> 1, y >> 1, z >> 1, stainSeed) < 0.02 * (w - 1) { c = mix(c, 0x5E4A32, 0.4) }
                        }
                    }
                    out[x, y, z] = VoxelColor(c == 0 ? 0x010101 : c)
                    any = true
                }
            }
        }
        if !any { out[0, 0, 0] = VoxelColor(P.kraft) }
        return out
    }
}
