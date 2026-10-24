import Foundation

// OWNER: voxel-models agent. Shape sanity for routing (Lisa's iPad scan, Oct 24: "the cabinet was
// too big where there should've been a table ... a weird vertical thing it called pillow that was
// a lamp").
//
// Names come from RoomPlan, the extra detector and Claude vision, and any of them can be wrong
// about what the box is. The scanned size can't be: it is what the drawn piece has to fill. So
// after the name picks a builder, the measured (w, d, h) is checked against a generous envelope
// for that kind. When the size is clearly not that kind AND clearly is another (a 1.5 m tall,
// 30 cm wide "pillow" is a floor lamp), the piece is drawn by its shape instead. The item keeps
// its name; only the voxel model changes.
//
// What stays as it was:
// - specific RoomPlan attributes (StorageType.shelf, ChairType.*, SofaType.*, TableShapeType.lShaped)
//   come from the scan itself and win, except a StorageType.cabinet that is clearly a table top;
// - small-object categories (#141: books, electronics, kitchenware, ...) have no envelope;
// - missing or invalid sizes skip the check (the kind's default size is used, so it fits).

extension VoxelModels {
    /// A plausible size for a kind, in meters: the footprint's short and long side and the
    /// height. Generous on purpose (a nightstand and a wardrobe are both `.dresser`); `tolerance`
    /// adds slack on top, so only a clearly wrong size re-routes.
    struct Envelope: Sendable {
        var short: ClosedRange<Double>
        var long: ClosedRange<Double>
        var height: ClosedRange<Double>
        /// Largest height / long side (a 1.3 m tall, 30 cm wide "table" is not a table).
        var maxAspect: Double = .infinity

        static let tolerance = 0.2

        func contains(_ s: (Double, Double, Double)) -> Bool {
            let (w, d, h) = s
            let short = min(w, d), long = max(w, d)
            func ok(_ v: Double, _ r: ClosedRange<Double>) -> Bool {
                v >= r.lowerBound * (1 - Self.tolerance) && v <= r.upperBound * (1 + Self.tolerance)
            }
            return ok(short, self.short) && ok(long, self.long) && ok(h, height) && h <= maxAspect * long * (1 + Self.tolerance)
        }
    }

    /// The envelope a kind's piece fits in (nil: any size is fine, e.g. small objects, appliances,
    /// instruments, and rugs / mattresses, which a move often leaves rolled up or on their side).
    static func envelope(_ kind: Kind, name n: VName) -> Envelope? {
        switch kind {
        case .sofa: Envelope(short: 0.55...2.3, long: 0.8...4.5, height: 0.4...1.3)
        case .bed: Envelope(short: 0.7...2.4, long: 1.2...2.8, height: 0.15...2.0)
        case .desk: Envelope(short: 0.35...1.8, long: 0.6...3.2, height: 0.55...2.1)
        case .chair: Envelope(short: 0.3...1.1, long: 0.3...1.3, height: 0.4...1.4)
        case .table: Envelope(short: 0.3...1.8, long: 0.3...3.6, height: 0.3...1.15, maxAspect: 2.2)
        case .dresser: Envelope(short: 0.25...1.0, long: 0.35...3.0, height: 0.3...2.4)
        case .bookshelf: Envelope(short: 0.15...0.55, long: 0.3...3.0, height: 0.3...2.7)
        case .lamp: Envelope(short: 0.08...0.9, long: 0.1...1.0, height: 0.15...2.3)
        case .ottoman: Envelope(short: 0.3...1.2, long: 0.3...1.8, height: 0.2...0.6)
        case .bench: Envelope(short: 0.25...0.9, long: 0.6...2.6, height: 0.25...1.0)
        // the detector's remaining categories: wide on purpose (a step stool-sized "ladder" and an
        // extension ladder, a bassinet and a crib), only a clearly wrong size re-routes
        case .motorcycle: Envelope(short: 0.35...1.2, long: 1.2...2.7, height: 0.6...1.7)
        case .stroller: Envelope(short: 0.3...0.9, long: 0.4...1.3, height: 0.4...1.3)
        case .wheelchair: Envelope(short: 0.4...0.9, long: 0.5...1.3, height: 0.5...1.25)
        case .grill: Envelope(short: 0.25...1.0, long: 0.35...2.0, height: 0.2...1.6)
        case .lawnMower: Envelope(short: 0.3...1.3, long: 0.45...2.4, height: 0.25...1.3)
        case .crib: Envelope(short: 0.35...1.1, long: 0.6...1.6, height: 0.5...1.4)
        case .ladder: Envelope(short: 0.03...1.0, long: 0.25...1.2, height: 0.4...3.2)
        case .trunk: Envelope(short: 0.2...0.9, long: 0.3...1.5, height: 0.15...0.95)
        case .basket: Envelope(short: 0.12...0.8, long: 0.15...1.0, height: 0.08...0.95)
        case .trashCan: Envelope(short: 0.15...0.8, long: 0.15...1.0, height: 0.2...1.3)
        case .toolbox: Envelope(short: 0.1...0.8, long: 0.25...1.6, height: 0.08...1.6)
        case .petCrate: Envelope(short: 0.25...1.0, long: 0.35...1.4, height: 0.2...1.1)
        case .petBed: Envelope(short: 0.25...1.2, long: 0.3...1.6, height: 0.04...0.5)
        case .catTree: Envelope(short: 0.25...1.0, long: 0.3...1.3, height: 0.35...2.5)
        case .clock: Envelope(short: 0.0...0.6, long: 0.08...0.8, height: 0.06...2.4)
        case .toy: Envelope(short: 0.0...1.2, long: 0.05...1.6, height: 0.04...1.6)
        case .rack: Envelope(short: 0.12...0.8, long: 0.25...2.0, height: 0.2...2.1)
        case .decor:
            // a pillow / cushion is thin one way (it may stand up against a sofa back) and never tall
            isPillow(n) ? Envelope(short: 0.0...1.0, long: 0.2...1.3, height: 0.04...0.6) : nil
        default: nil
        }
    }

    /// A throw pillow / cushion (not a "floor cushion" bean bag or a "pillow top" mattress, which route first).
    static func isPillow(_ n: VName) -> Bool {
        n.word("pillow", "pillows", "cushion", "cushions", "bolster")
    }

    /// The likeliest kind for a measured (w, d, h) alone, or nil when the shape doesn't say.
    /// Only clear silhouettes: a tall thin pole (lamp, or a plant when the name says so), a
    /// tall wide shallow case (bookshelf), a big low slab (bed), a table top on legs, a
    /// waist-high case (dresser).
    static func kindByShape(_ s: (Double, Double, Double), name n: VName) -> Kind? {
        let (w, d, h) = s
        let foot = max(w, d), slim = min(w, d)
        if h > 1.0 && foot < 0.6 {
            let planty = n.word("plant", "plants", "tree", "palm", "fern", "ficus", "monstera", "succulent", "cactus", "leaf",
                                "leaves", "flower", "flowers", "bamboo", "olive", "fig")
            return planty ? .plant : .lamp
        }
        if h >= 1.2 && slim <= 0.6 && foot >= 0.6 { return .bookshelf }
        if h >= 0.15 && h <= 0.7 && foot >= 1.8 && slim >= 0.9 { return .bed }
        if h >= 0.3 && h <= 0.95 && slim >= 0.45 && foot >= 0.5 { return .table }
        if h >= 0.65 && h <= 1.4 && foot >= 0.5 && foot <= 2.2 && slim >= 0.3 && slim < 0.45 { return .dresser }
        return nil
    }

    /// A RoomPlan "storage" box that is really a table: low, and deep both ways (a dining or
    /// coffee table read as a sideboard). Storage this deep is rare; shallow sideboards, TV
    /// stands and nightstands stay storage.
    static func tableShapedStorage(_ s: (Double, Double, Double), minSlim: Double) -> Bool {
        let (w, d, h) = s
        return h <= 0.85 && min(w, d) >= minSlim && max(w, d) >= 0.8
    }

    /// `kind` (what the name says) checked against the scanned size; see the file comment.
    static func saneKind(_ kind: Kind, category cat: String, name n: VName, attrs: Set<String>,
                         size: (Double, Double, Double)?) -> Kind {
        guard let s = size, s.0.isFinite, s.1.isFinite, s.2.isFinite, s.0 > 0, s.1 > 0, s.2 > 0 else { return kind }
        let caseWords = n.has("cabinet", "dresser", "drawer", "chest", "sideboard", "credenza", "buffet", "console", "wardrobe",
                              "armoire", "nightstand", "night stand", "bedside", "tv stand", "media")
            || n.has("shelf", "shelves", "shelving", "bookcase", "cubby", "cubbies")
        // RoomPlan's StorageType.cabinet on a deep, low box: a table top (deeper than any cabinet)
        if attrs.contains("storagetype.cabinet") {
            return !caseWords && tableShapedStorage(s, minSlim: 0.7) ? .table : kind
        }
        // other specific RoomPlan attributes are the scan's own reading of the piece
        if attrs.contains("storagetype.shelf") || attrs.contains("tableshapetype.lshaped")
            || attrs.contains(where: { $0.hasPrefix("chairtype.") || $0.hasPrefix("chairlegtype.") || $0.hasPrefix("sofatype.") }) {
            return kind
        }
        // plain RoomPlan "storage" (no name of its own) with a table's proportions
        if cat == "storage" && kind == .bookshelf && !caseWords && tableShapedStorage(s, minSlim: 0.5) { return .table }
        guard let env = envelope(kind, name: n), !env.contains(s) else { return kind }
        // the name's kind doesn't fit: draw what the shape clearly is, if anything
        guard let byShape = kindByShape(s, name: n), byShape != kind else { return kind }
        if let alt = envelope(byShape, name: n), !alt.contains(s) { return kind }
        return byShape
    }
}
