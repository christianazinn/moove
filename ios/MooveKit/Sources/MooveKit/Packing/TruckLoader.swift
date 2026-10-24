import Foundation

// The truck in 3D (Pack > See it in 3D): where every piece of furniture and every box goes
// in the planner's truck, in load order. Pure and deterministic, so it's tested on Linux and the
// app only draws the result.

extension TruckSize {
    /// Inside of the cargo box in meters: length (cab wall to door), width, height.
    /// Rounded U-Haul-style numbers whose volume is close to `capacityM3`.
    public var cargoM: (length: Double, width: Double, height: Double) {
        switch self {
        case .cargoVan: return (2.9, 1.7, 1.4)
        case .ft10: return (3.0, 1.9, 1.9)
        case .ft15: return (4.5, 2.3, 2.05)
        case .ft20: return (5.5, 2.3, 2.25)
        case .ft26: return (7.7, 2.4, 2.45)
        }
    }

    public var cargoVolumeM3: Double {
        let c = cargoM
        return c.length * c.width * c.height
    }
}

/// One thing that goes on the truck.
public struct TruckCargoItem: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// A loose piece (the item's category, for the voxel model).
        case furniture(category: String)
        case box(BoxSize)
    }

    /// "f<itemId>" for furniture, "b<boxId>" for boxes.
    public var id: String
    public var name: String
    public var kind: Kind
    /// Destination room ("Bedroom", "Open first").
    public var room: String
    /// The model's own axes: width (x), depth (z), height (y), in meters.
    public var widthM: Double
    public var depthM: Double
    public var heightM: Double
    public var weightKg: Double
    public var fragile: Bool
    /// Open-first boxes go on last, by the door.
    public var openFirst: Bool
    /// Furniture: the inventory item; boxes: nil.
    public var itemId: UInt64?
    /// Boxes: the box number.
    public var boxId: Int?

    public init(id: String, name: String, kind: Kind, room: String, widthM: Double, depthM: Double, heightM: Double,
                weightKg: Double, fragile: Bool = false, openFirst: Bool = false, itemId: UInt64? = nil, boxId: Int? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.room = room
        self.widthM = widthM
        self.depthM = depthM
        self.heightM = heightM
        self.weightKg = weightKg
        self.fragile = fragile
        self.openFirst = openFirst
        self.itemId = itemId
        self.boxId = boxId
    }

    public var volumeM3: Double { widthM * depthM * heightM }
    public var isBox: Bool { if case .box = kind { return true } else { return false } }

    var category: String {
        if case let .furniture(c) = kind { return c.lowercased() }
        return "box"
    }

    /// Can stand on its side or lie down when it must (mattresses always stand on edge).
    /// Boxes keep their this-side-up; fridges and other appliances stay upright.
    var canTip: Bool {
        guard !isBox else { return false }
        return !["appliance", "refrigerator", "washer", "dryer"].contains(category)
    }

    /// Mattresses and taken-apart bed frames stand on edge against the wall.
    var prefersOnEdge: Bool {
        let n = name.lowercased()
        return ["mattress", "bed"].contains(category) || n.contains("mattress") || n.contains("bed frame")
    }

    /// Boxes and flat-topped case goods can carry boxes.
    var carriesBoxes: Bool {
        if isBox { return !fragile }
        return ["dresser", "desk", "table", "storage", "cabinet", "appliance", "washer", "dryer"].contains(category)
    }
}

/// Where one cargo item sits. Cargo axes: x from the cab wall (0) to the door (`length`),
/// y up from the floor, z across the width. `x/y/z` is the min corner, `size*` the extents
/// along those axes after turning.
public struct TruckPlacement: Sendable, Hashable, Identifiable {
    /// How the model is turned before `yawDeg`.
    public enum Tilt: String, Sendable, Hashable {
        /// Standing as it does at home.
        case none
        /// Rolled 90° about its width axis: its depth points up (a mattress on its long edge).
        case depthUp
        /// Rolled 90° about its depth axis: its width points up (a sofa on its end).
        case widthUp
    }

    public var item: TruckCargoItem
    /// 1-based position in the load order.
    public var order: Int
    public var x: Double
    public var y: Double
    public var z: Double
    public var sizeX: Double
    public var sizeY: Double
    public var sizeZ: Double
    /// 0: the model's width runs along the truck (x); 90: across it (z).
    public var yawDeg: Int
    public var tilt: Tilt

    public var id: String { item.id }
    public var volumeM3: Double { sizeX * sizeY * sizeZ }
    public var top: Double { y + sizeY }
    /// Bottom center, cargo axes.
    public var center: (x: Double, y: Double, z: Double) { (x + sizeX / 2, y + sizeY / 2, z + sizeZ / 2) }

    func overlaps(_ o: TruckPlacement, eps: Double = 1e-6) -> Bool {
        x < o.x + o.sizeX - eps && o.x < x + sizeX - eps
            && y < o.y + o.sizeY - eps && o.y < y + sizeY - eps
            && z < o.z + o.sizeZ - eps && o.z < z + sizeZ - eps
    }

    /// Footprint overlap area with `o` (x/z only).
    func footprintOverlap(_ o: TruckPlacement) -> Double {
        let dx = min(x + sizeX, o.x + o.sizeX) - max(x, o.x)
        let dz = min(z + sizeZ, o.z + o.sizeZ) - max(z, o.z)
        return dx > 0 && dz > 0 ? dx * dz : 0
    }

    /// `self` sits directly on `o`.
    public func restsOn(_ o: TruckPlacement) -> Bool {
        abs(y - o.top) < 1e-6 && footprintOverlap(o) > 1e-6
    }
}

public struct TruckLoad: Sendable, Hashable {
    public var truck: TruckSize
    /// In load order (first on = against the cab wall).
    public var placements: [TruckPlacement]
    /// What didn't fit (a second trip / second truck).
    public var unloaded: [TruckCargoItem]
    /// Placed volume / cargo volume, 0...1.
    public var fill: Double

    public var furnitureCount: Int { placements.filter { !$0.item.isBox }.count }
    public var boxCount: Int { placements.filter(\.item.isBox).count }

    public static let empty = TruckLoad(truck: .cargoVan, placements: [], unloaded: [], fill: 0)

    /// Shown on both the 2D truck card and the 3D view when real shapes needed a bigger truck
    /// than the volume estimate (`planned`): "Fits a cargo van by volume; packs best in a 10 ft truck."
    /// Nil when the load fits the planned truck.
    public func sizeNote(planned: TruckSize) -> String? {
        guard truck != planned else { return nil }
        let a = planned.label, b = truck.label.lowercased()
        let article = a.lowercased().first.map { "aeiou".contains($0) } == true ? "an" : "a"
        return "Fits \(article) \(a.lowercased()) by volume; packs best in a \(b)."
    }
}

/// Loads the plan's truck like movers do, as a greedy 3D "extreme point" packer:
/// - Load order: big furniture first (largest volume), then boxes heaviest first with fragile
///   ones after the sturdy ones, then open-first boxes last so they come off first.
/// - Each piece goes where the load's back face stays nearest the cab wall, then lowest, then
///   left (so the load builds up in tiers from the cab back to the door). Mattresses stand on
///   edge; other furniture tips or lies down only when no upright spot is left (appliances never).
/// - A piece off the floor needs ≥ 60% of its footprint on things that can carry it: boxes
///   and flat-topped case goods (dressers, desks, tables), never chairs or sofas. Nothing rests
///   on a sturdy box more than 6 kg lighter than itself, and only lighter fragile boxes ever rest on
///   fragile ones.
/// - Never overlaps, never leaves the cargo box. What doesn't fit is reported as `unloaded`.
public enum TruckLoader {
    static let eps = 1e-6
    static let minSupport = 0.6
    /// A box may sit on a sturdy box at most this much heavier than it (never on a lighter fragile one).
    public static let heavierOnTopKg = 6.0
    static let keepWithYouRoom = "Keep with you"

    /// The truck the plan picked, loaded with its furniture and boxes. Keep-with-you boxes and
    /// sentimental pieces that ride in the car stay off; bought items are delivered, so they
    /// aren't in the plan at all.
    ///
    /// Without a `truck`, starts from the plan's pick (a volume estimate) and moves up a size
    /// while pieces are left over, since real shapes pack worse than cubic meters.
    public static func load(plan: PackingPlan, items: [Item], truck: TruckSize? = nil) -> TruckLoad {
        let cargo = cargo(plan: plan, items: items)
        if let truck { return load(cargo, truck: truck) }
        let sizes = TruckSize.allCases.drop { $0 != plan.truck.truck }
        var result = TruckLoad.empty
        for size in sizes {
            result = load(cargo, truck: size)
            if result.unloaded.isEmpty { break }
        }
        return result
    }

    /// The plan's on-truck furniture and boxes as cargo.
    public static func cargo(plan: PackingPlan, items: [Item]) -> [TruckCargoItem] {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [TruckCargoItem] = []
        for note in plan.furniture where note.room != keepWithYouRoom {
            guard let item = byId[note.id] else { continue }
            let w = max(0.05, item.widthM), d = max(0.05, item.depthM), h = max(0.05, item.heightM)
            out.append(TruckCargoItem(
                id: "f\(item.id)", name: note.name, kind: .furniture(category: item.category), room: note.room,
                widthM: w, depthM: d, heightM: h, weightKg: furnitureKg(item), fragile: item.fragile, itemId: item.id))
        }
        for box in plan.boxes where !box.keepWithYou {
            let d = box.size.dimsM
            out.append(TruckCargoItem(
                id: "b\(box.id)", name: "Box \(box.id) · \(box.title)", kind: .box(box.size), room: box.room,
                widthM: d.w, depthM: d.d, heightM: d.h, weightKg: max(0.5, box.weightKg), fragile: box.fragile,
                openFirst: box.openFirst, boxId: box.id))
        }
        return out
    }

    /// A rough weight from the bounding volume (furniture is mostly air).
    static func furnitureKg(_ item: Item) -> Double {
        let c = item.category.lowercased()
        let perM3: Double
        switch c {
        case "appliance", "refrigerator", "washer", "dryer": perM3 = 110
        case "mattress", "sofa", "couch": perM3 = 45
        case "dresser", "storage", "bookshelf", "cabinet", "desk": perM3 = 90
        default: perM3 = 60
        }
        return min(150, max(3, item.volumeM3 * perM3))
    }

    /// Load order: furniture biggest first, then sturdy boxes heaviest first, fragile boxes
    /// heaviest first, and open-first boxes last.
    public static func loadOrder(_ cargo: [TruckCargoItem]) -> [TruckCargoItem] {
        func rank(_ c: TruckCargoItem) -> Int {
            if !c.isBox { return 0 }
            if c.openFirst { return 3 }
            return c.fragile ? 2 : 1
        }
        return cargo.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            if ra == 0, abs(a.volumeM3 - b.volumeM3) > 1e-9 { return a.volumeM3 > b.volumeM3 }
            if ra > 0, abs(a.weightKg - b.weightKg) > 1e-9 { return a.weightKg > b.weightKg }
            if ra > 0, abs(a.volumeM3 - b.volumeM3) > 1e-9 { return a.volumeM3 > b.volumeM3 }
            return a.id < b.id
        }
    }

    public static func load(_ cargo: [TruckCargoItem], truck: TruckSize) -> TruckLoad {
        let c = truck.cargoM
        var placed: [TruckPlacement] = []
        var unloaded: [TruckCargoItem] = []
        var points: [(x: Double, y: Double, z: Double)] = [(0, 0, 0)]

        for item in loadOrder(cargo) {
            let turns = orientations(item)
            // Every free point × turn: the preferred stance if it fits anywhere, then the spot that
            // keeps the load's back face nearest the cab, then lowest, then left.
            var best: TruckPlacement?
            var bestKey: (Int, Int, Int, Int, Int) = (.max, .max, .max, .max, .max)
            for p in points {
                for (ti, t) in turns.enumerated() {
                    let cand = TruckPlacement(item: item, order: placed.count + 1, x: p.x, y: p.y, z: p.z,
                                              sizeX: t.sx, sizeY: t.sy, sizeZ: t.sz, yawDeg: t.yaw, tilt: t.tilt)
                    // Open-first boxes go by the door instead: furthest back first.
                    let reach = item.openFirst ? -cm(cand.x) : cm(cand.x + cand.sizeX)
                    let key = (t.rank, reach, cm(cand.y), cm(cand.z), ti)
                    guard key < bestKey, fits(cand, in: c, among: placed) else { continue }
                    best = cand
                    bestKey = key
                }
            }
            guard let b = best else { unloaded.append(item); continue }
            placed.append(b)
            // New corners around it: its far edges, on its top and down at the floor and far wall.
            for x in [b.x, b.x + b.sizeX] where x < c.length - eps {
                for y in [0, b.y, b.top] where y < c.height - eps {
                    for z in [0, b.z, b.z + b.sizeZ] where z < c.width - eps
                        && !points.contains(where: { abs($0.x - x) < eps && abs($0.y - y) < eps && abs($0.z - z) < eps }) {
                        points.append((x, y, z))
                    }
                }
            }
            // Drop points now inside something.
            points.removeAll { p in placed.contains { inside(p, $0) } }
        }
        let volume = placed.reduce(0) { $0 + $1.volumeM3 }
        return TruckLoad(truck: truck, placements: placed, unloaded: unloaded, fill: volume / truck.cargoVolumeM3)
    }

    struct Turn {
        var sx: Double, sy: Double, sz: Double
        var yaw: Int
        var tilt: TruckPlacement.Tilt
        /// 0 for the preferred stance, 1 for the fallback one.
        var rank = 0
    }

    static func cm(_ m: Double) -> Int { Int((m * 100).rounded()) }

    /// Turns to try, best first. Upright: the turn with the shorter run along the truck first,
    /// so pieces line up across the width. Mattresses: on edge first, tallest that fits.
    static func orientations(_ item: TruckCargoItem) -> [Turn] {
        let w = item.widthM, d = item.depthM, h = item.heightM
        // (model width, model depth, up) per tilt; yaw 0 puts the first along x.
        func turns(_ a: Double, _ b: Double, _ up: Double, _ tilt: TruckPlacement.Tilt) -> [Turn] {
            let t0 = Turn(sx: a, sy: up, sz: b, yaw: 0, tilt: tilt)
            let t90 = Turn(sx: b, sy: up, sz: a, yaw: 90, tilt: tilt)
            return a <= b ? [t0, t90] : [t90, t0]
        }
        let upright = turns(w, d, h, .none)
        guard item.canTip else { return upright }
        // depthUp: depth points up, the model's height lies along its old depth axis.
        var tipped = (turns(w, h, d, .depthUp) + turns(h, d, w, .widthUp)).sorted { $0.sy > $1.sy }
        var up = upright
        if item.prefersOnEdge { for i in up.indices { up[i].rank = 1 } } else { for i in tipped.indices { tipped[i].rank = 1 } }
        return item.prefersOnEdge ? tipped + up : up + tipped
    }

    static func inside(_ p: (x: Double, y: Double, z: Double), _ b: TruckPlacement) -> Bool {
        p.x > b.x - eps && p.x < b.x + b.sizeX - eps
            && p.y > b.y - eps && p.y < b.top - eps
            && p.z > b.z - eps && p.z < b.z + b.sizeZ - eps
    }

    static func fits(_ cand: TruckPlacement, in c: (length: Double, width: Double, height: Double), among placed: [TruckPlacement]) -> Bool {
        guard cand.x >= -eps, cand.y >= -eps, cand.z >= -eps,
              cand.x + cand.sizeX <= c.length + eps, cand.top <= c.height + eps, cand.z + cand.sizeZ <= c.width + eps
        else { return false }
        if placed.contains(where: { $0.overlaps(cand) }) { return false }
        guard cand.y > eps else { return true }
        // Off the floor: only boxes ride on top, on things that can carry them.
        guard cand.item.isBox else { return false }
        var supported = 0.0
        for o in placed where abs(o.top - cand.y) < eps {
            let a = cand.footprintOverlap(o)
            guard a > eps else { continue }
            guard o.item.carriesBoxes || (o.item.isBox && o.item.fragile && cand.item.fragile) else { return false }
            if o.item.isBox && cand.item.weightKg > o.item.weightKg + (o.item.fragile ? 0 : heavierOnTopKg) + eps { return false }
            supported += a
        }
        return supported >= minSupport * cand.sizeX * cand.sizeZ - eps
    }
}
