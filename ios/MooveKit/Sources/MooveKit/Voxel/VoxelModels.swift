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
// other appliances, fans, bean bag, mirror, quilt rack, framed photos).

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
        case framedPhotos, stove, dishwasher, microwave, bench, ottoman, bike, suitcase, box

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
            default: nil
            }
        }
    }

    // MARK: routing

    /// Picks a builder from category + name keywords (models.js `route`, extended for Moove's
    /// categories: bed, chair, table, storage, lamp, appliance, decor, sofa).
    static func route(category cat: String, name n: VName, attrs: Set<String> = [], size: (Double, Double, Double)? = nil) -> Kind {
        // RoomPlan attributes first: they come from the scan itself
        if attrs.contains("storagetype.shelf") { return .bookshelf }
        if attrs.contains("storagetype.cabinet") { return .dresser }
        if attrs.contains(where: { $0.hasPrefix("chairtype.") || $0.hasPrefix("chairlegtype.") }) && !n.has("sofa", "couch") { return .chair }
        if attrs.contains(where: { $0.hasPrefix("sofatype.") }) { return .sofa }
        if attrs.contains("tableshapetype.lshaped") && (cat == "table" || cat == "desk") { return .desk }
        if n.has("mattress") && !n.has("frame") { return .mattress }
        if n.has("bean bag", "beanbag", "bean-bag", "pouf", "floor cushion") { return .beanBag }
        if n.has("sectional", "sofa", "couch", "loveseat", "futon", "settee", "armchair") { return .sofa }
        if n.has("bookcase", "bookshelf", "book shelf", "shelving", "shelf unit", "étagère") { return .bookshelf }
        // the vision agent's specific names ("black standing desk") beat a broad category ("furniture");
        // order matters: a "desk lamp" is a lamp, a "desk chair" a chair, a "desk with drawers" a desk
        if n.word("lamp", "lamps", "sconce", "lantern") { return .lamp }
        if n.word("chair", "chairs", "stool", "stools", "recliner") { return .chair }
        if n.has("tv stand", "tv console", "tv cabinet", "tv unit", "media console", "entertainment center") { return .dresser }
        if n.has("desk", "workstation", "computer armoire", "roll top", "rolltop", "roll-top", "dressing table")
            || n.word("vanity", "secretary") { return .desk }
        if n.has("dresser", "chest of drawers", "nightstand", "night stand", "bedside", "sideboard", "credenza", "armoire", "wardrobe")
            || n.word("drawers", "cabinet") { return .dresser }
        if n.word("rug") || n.has("carpet") { return .rug }
        if n.has("quilt rack", "blanket rack", "blanket ladder", "quilt ladder", "towel rack") { return .quiltRack }
        if n.has("mirror") { return .mirror }
        if n.has("frame") && n.has("photo", "picture", "portrait") { return .framedPhotos }
        if n.has("fridge", "refrigerator", "freezer") { return .appliance }
        if n.has("dishwasher") { return .dishwasher }
        if n.has("washing machine") || (n.word("washer", "dryer") && !n.has("hair dryer", "pressure washer")) { return .appliance }
        if n.has("microwave") { return .microwave }
        if n.word("stove", "range", "oven", "cooktop") && !n.has("toaster oven", "dutch oven") { return .stove }
        if n.word("fan", "fans") { return .fan }
        if n.word("bike", "bicycle", "e-bike", "ebike") { return .bike }
        if n.has("suitcase", "luggage", "carry-on", "carry on") { return .suitcase }
        if n.has("ottoman", "footstool", "foot stool", "pouf") { return .ottoman }
        if n.word("bench", "settle") { return .bench }
        if n.has("bed frame", "bunk bed", "daybed", "platform bed", "headboard") || n.word("bed") { return .bed }
        if n.word("tv", "television", "tvs") { return .tv }
        if n.word("table", "tables") { return .table }
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
        case "electronics": return n.word("tv", "television") ? .tv : .electronics
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
        case "storage": return n.word("bin", "tote", "box", "crate", "basket", "container") ? .box : .bookshelf
        case "decor":
            if n.word("art", "artwork", "painting", "canvas", "poster", "print") { return .art }
            if n.word("plant", "plants", "succulent", "fern", "monstera") { return .plant }
            if n.word("photos") { return .photos }
            return .decor
        default: return size.map(shapeKind) ?? .box
        }
    }

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
