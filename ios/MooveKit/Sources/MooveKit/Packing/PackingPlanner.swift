import Foundation

/// Turns what you're moving into numbered moving boxes, furniture notes, a
/// supplies list, a truck estimate and a packing schedule. Deterministic: the
/// same items always give the same plan.
///
/// Rules (ported from the MoveWise packing planner):
/// - Big furniture (beds, sofas, tables, desks, dressers, chairs, storage over
///   0.25 m³, appliances over 0.1 m³, and anything that fits no box) gets a
///   `FurnitureNote` with take-apart and wrapping steps instead of a box.
///   A floor lamp is a note for the base, and its shade goes in a box.
/// - Small things go in boxes grouped by destination room, then kind, then
///   fragility. Each room also gets typical everyday contents (`itemId == nil`).
/// - No box weighs over its size's `maxKg` (all are 20 kg or less). Fragile
///   boxes stay at or under 8 kg, so nothing heavy ever shares a box with them.
/// - There's always an open-first tote and a keep-with-you box (sentimental
///   items, documents, valuables) when anything is moving. Sentimental things
///   too big for a box get a note in "Keep with you" and ride in the car.
/// - Box numbers follow the schedule: what you pack first gets the lowest
///   numbers. Within a stage boxes go by room (A-Z), then kind.
public enum PackingPlanner {
    /// Share of a box's volume you can fill once things are wrapped.
    static let packingEfficiency = 0.7
    /// Fragile boxes stay at or under this, so heavy things never ride with them.
    public static let fragileMaxKg = 8.0
    static let keepWithYouRoom = "Keep with you"
    static let openFirstRoom = "Open first"

    /// - Parameters:
    ///   - items: the inventory. Only `.keep` items move, plus undecided
    ///     sentimental items, which go in "Keep with you". Others are ignored,
    ///     so passing the whole inventory is fine.
    ///   - destinationRoom: item id -> room name in the new home (from the saved
    ///     layout). Missing items are guessed from their category.
    public static func plan(items: [Item], destinationRoom: [UInt64: String] = [:]) -> PackingPlan {
        let moving = movingItems(items)
        guard !moving.isEmpty else { return .empty }
        let rooms = RoomGuesser(items: moving, mapped: destinationRoom)

        var units: [PackUnit] = []
        var furniture: [FurnitureNote] = []
        var keepUnits: [PackUnit] = []
        for item in moving {
            let room = rooms.room(for: item)
            switch handling(of: item, room: room) {
            case let .boxed(unit):
                if unit.kind == .keepWithYou { keepUnits.append(unit) } else { units.append(unit) }
            case let .furniture(steps):
                furniture.append(FurnitureNote(id: item.id, name: item.name, room: room, steps: steps))
            case let .floorLamp(shade, steps):
                units.append(shade)
                furniture.append(FurnitureNote(id: item.id, name: "\(item.name): base and pole", room: room, steps: steps))
            case let .car(steps):
                furniture.append(FurnitureNote(id: item.id, name: item.name, room: keepWithYouRoom, steps: steps))
            case let .expanded(parts):
                units += parts
            }
        }

        // Typical everyday contents per destination room, skipping kinds the scan already has there.
        let destinations = Set(furniture.map(\.room) + units.map(\.room)).subtracting([keepWithYouRoom]).sorted()
        for room in destinations {
            let scannedKinds = Set(units.filter { $0.room == room && $0.itemId != nil }.map(\.kind))
            for line in PackingTemplates.typical(for: roomKind(named: room)) where !scannedKinds.contains(line.kind) {
                units.append(PackUnit(typical: line, room: room))
            }
        }
        units += PackingTemplates.openFirst.map { PackUnit(typical: $0, room: openFirstRoom) }
        keepUnits += PackingTemplates.keepWithYou.map { PackUnit(typical: $0, room: keepWithYouRoom) }
        // The keep-with-you box is one group: fragile if anything in it is.
        let keepFragile = keepUnits.contains(where: \.fragile)
        units += keepUnits.map { var u = $0; u.fragile = keepFragile; return u }

        let numbered = finalize(merge(pack(units)))
        let boxes = numbered.map(\.box)
        furniture.sort { a, b in
            let ak = a.room == keepWithYouRoom, bk = b.room == keepWithYouRoom
            if ak != bk { return bk }
            return (a.room, a.name, a.id) < (b.room, b.name, b.id)
        }
        return PackingPlan(
            boxes: boxes,
            furniture: furniture,
            supplies: supplies(boxes: boxes, furniture: furniture, items: moving),
            truck: VolumeEstimator.estimate(items: moving, boxes: boxes),
            schedule: schedule(numbered)
        )
    }

    // MARK: What moves, and how

    /// Kept items plus undecided sentimental ones, in id order.
    static func movingItems(_ items: [Item]) -> [Item] {
        items.filter { $0.disposition == .keep || ($0.disposition == .undecided && $0.maybeSentimental) }
            .sorted { $0.id < $1.id }
    }

    enum Handling {
        case boxed(PackUnit)
        /// On the truck, not in a box.
        case furniture([String])
        /// Base on the truck as furniture, shade in a box.
        case floorLamp(shade: PackUnit, steps: [String])
        /// Sentimental and too big for a box: rides in your car.
        case car([String])
        /// A bulk item ("Box of paperbacks") too big or heavy for one box, unpacked into typical contents.
        case expanded([PackUnit])

        /// Counts toward truck volume as a loose piece.
        var onTruckLoose: Bool {
            switch self {
            case .furniture, .floorLamp: return true
            case .boxed, .car, .expanded: return false
            }
        }
    }

    static func handling(of item: Item, room: String) -> Handling {
        if isLargeFurniture(item) { return .furniture(furnitureSteps(item)) }
        let kind = PackKind(category: item.category)
        let dims = [item.widthM, item.heightM, item.depthM].sorted(by: >)
        if item.maybeSentimental {
            var unit = PackUnit(item: item, kind: .keepWithYou, room: keepWithYouRoom, density: kind.density)
            unit.sizes = PackKind.keepWithYou.sizes + [.picture]
            if unit.bestSize != nil { return .boxed(unit) }
            return .car([
                "Too big for a box, so it rides in your car, not the truck",
                "Wrap it in a moving blanket or a thick quilt",
                "Load it last and take it in first",
            ])
        }
        if kind == .lamps && (item.heightM > 1.2 || dims[0] > 1.22 || item.name.lowercased().contains("floor")) {
            let side = max(0.25, min(0.5, max(item.widthM, item.depthM)))
            var shade = PackUnit(itemId: item.id, name: "\(item.name) shade", quantity: 1, litres: side * side * 0.3 * 1100,
                                 kg: 0.4, room: room, kind: .lamps, fragile: true, dims: [side, side, 0.3])
            shade.lightOnly = true
            return .floorLamp(shade: shade, steps: [
                "Take off the bulb and shade; the shade goes in a box on its own",
                "Wrap the base and pole in a moving blanket",
                "Tape the cord to the pole so it can't snag",
            ])
        }
        var unit = PackUnit(item: item, kind: kind, room: room, density: kind.density)
        if unit.fragile, dims[2] <= 0.1 { unit.sizes.append(.picture) }
        if unit.bestSize != nil { return .boxed(unit) }
        unit.sizes = [.medium, .large, .small, .tote, .dishPack, .wardrobe, .picture]
        if unit.bestSize != nil { return .boxed(unit) }
        if let parts = expand(item, kind: kind, room: room, litres: unit.litres) { return .expanded(parts) }
        return .furniture(furnitureSteps(item))
    }

    /// Bulk books, kitchenware, clothes, bedding or decor as the typical pieces of that
    /// kind, scaled to the item's volume. Lines keep the item's id; fragility comes from
    /// the piece (plates are fragile, pans aren't).
    static func expand(_ item: Item, kind: PackKind, room: String, litres: Double) -> [PackUnit]? {
        guard [.books, .kitchen, .clothes, .shoes, .bedding, .decor, .bathroom].contains(kind) else { return nil }
        let templates = [PackingTemplates.bedroom, PackingTemplates.kitchen, PackingTemplates.living, PackingTemplates.bathroom]
        guard let lines = templates.lazy.map({ $0.filter { $0.kind == kind } }).first(where: { !$0.isEmpty }) else { return nil }
        let perSet = lines.reduce(0) { $0 + $1.litres * Double($1.quantity) }
        let sets = max(1, Int((litres / perSet).rounded()))
        return lines.map { line in
            var unit = PackUnit(typical: line, room: room)
            unit.itemId = item.id
            unit.quantity = line.quantity * sets
            return unit
        }
    }

    static func isLargeFurniture(_ item: Item) -> Bool {
        let v = item.volumeM3
        switch item.category.lowercased() {
        case "bed", "mattress", "sofa", "couch", "table", "desk", "dresser", "wardrobe", "chair", "tv", "television":
            return true
        case "storage", "bookshelf", "cabinet", "shelf":
            return v > 0.25
        case "appliance", "refrigerator", "washer", "dryer":
            return v > 0.1
        default:
            return false
        }
    }

    static func furnitureSteps(_ item: Item) -> [String] {
        let n = item.name.lowercased()
        let c = item.category.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if c == "mattress" || has("mattress") {
            return ["Seal it in a mattress bag", "Carry it on its side and stand it against the truck wall"]
        }
        if c == "bed" || has("bed frame") {
            return [
                "Strip the bedding and seal the mattress in a mattress bag",
                "Take off the headboard and side rails; bag and label the bolts",
                "Bundle the slats with stretch wrap",
                "Wrap rails in a moving blanket",
            ]
        }
        if c == "sofa" || c == "couch" {
            return [
                "Take off the cushions and bag them",
                "Unscrew the legs; bag and label the hardware",
                "Wrap it in moving blankets and stretch wrap",
                "Measure the doorways; carry it on end",
            ]
        }
        if has("nightstand", "bedside", "night stand") {
            return [
                "Empty the drawer and tape it shut with painter's tape",
                "Wrap it in a moving blanket",
            ]
        }
        if c == "dresser" || has("dresser", "chest of drawers") {
            return [
                "Lighten the drawers; soft clothes can stay in",
                "Hold the drawers shut with stretch wrap, not tape",
                "Wrap it in moving blankets and carry it upright",
            ]
        }
        if c == "table" || c == "desk" || has("desk", "table") {
            return [
                "Empty the drawers",
                "Unscrew the legs; bag the bolts and tape the bag under the top",
                "Wrap the top in a moving blanket with cardboard corners",
            ]
        }
        if c == "chair" {
            if has("office", "mesh", "swivel", "aeron") {
                return ["Lower the seat and lock the tilt", "Wrap it in a moving blanket; tape the armrests"]
            }
            return ["Wrap it in a moving blanket", "Load it legs-up on top of sturdy boxes"]
        }
        if c == "tv" || c == "television" {
            return [
                "Photograph the cable setup, then unplug and bag the cables",
                "Pack it upright in a TV box or wrap it in a moving blanket",
                "Never lay a screen flat; load it between mattresses",
            ]
        }
        if c == "appliance" || c == "refrigerator" {
            if has("fridge", "refrigerator", "freezer") || c == "refrigerator" {
                return [
                    "Empty, unplug and defrost it a day before",
                    "Tape the doors shut and the cord to the back",
                    "Keep it upright on the truck",
                ]
            }
            return ["Unplug it and tape the cord to it", "Wrap it in a moving blanket"]
        }
        if c == "storage" || c == "bookshelf" || c == "shelf" || c == "cabinet" {
            return [
                "Empty it; take out the shelves and bag the shelf pins",
                "Wrap the frame in a moving blanket",
                "Carry it upright, back against the truck wall",
            ]
        }
        return ["Wrap it in a moving blanket and stretch wrap", "Bag and label any loose parts"]
    }

    // MARK: Packing

    /// First-fit packing per (room, kind, fragility) group, splitting quantities across boxes.
    /// A group shares one box size when one fits every unit (so a lamp shade doesn't
    /// push the whole group into bigger boxes); otherwise each unit gets its own best size.
    static func pack(_ units: [PackUnit]) -> [DraftBox] {
        struct Key: Hashable { var room: String; var kind: PackKind; var fragile: Bool; var lightOnly: Bool }
        var order: [Key] = []
        var groups: [Key: [PackUnit]] = [:]
        for unit in units where unit.quantity > 0 && unit.bestSize != nil { // handling() guarantees a size
            let key = Key(room: unit.room, kind: unit.kind, fragile: unit.fragile, lightOnly: unit.lightOnly)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(unit)
        }
        var boxes: [DraftBox] = []
        for key in order {
            let us = groups[key] ?? []
            var candidates: [BoxSize] = []
            for size in us.flatMap(\.sizes) where !candidates.contains(size) { candidates.append(size) }
            let shared = candidates.first { size in us.allSatisfy { $0.fits(size) } }
            var bySize: [(BoxSize, [PackUnit])] = []
            for unit in us {
                let size = shared ?? unit.bestSize!
                if let i = bySize.firstIndex(where: { $0.0 == size }) { bySize[i].1.append(unit) } else { bySize.append((size, [unit])) }
            }
            for (size, sized) in bySize {
                boxes += fill(sized, size: size, room: key.room, kind: key.kind, fragile: key.fragile, lightOnly: key.lightOnly)
            }
        }
        return boxes
    }

    static func fill(_ units: [PackUnit], size: BoxSize, room: String, kind: PackKind, fragile: Bool, lightOnly: Bool) -> [DraftBox] {
        var group: [DraftBox] = []
        for unit in units {
            var left = unit.quantity
            while left > 0 {
                if let i = group.firstIndex(where: { $0.capacity(for: unit) >= 1 }) {
                    let n = min(left, group[i].capacity(for: unit))
                    group[i].add(unit, quantity: n)
                    left -= n
                } else {
                    group.append(DraftBox(size: size, room: room, kinds: [kind], fragile: fragile, lightOnly: lightOnly))
                }
            }
        }
        return group
    }

    /// Combines boxes that are mostly empty: same room, size and fragility, at most two kinds.
    static func merge(_ boxes: [DraftBox]) -> [DraftBox] {
        var out: [DraftBox] = []
        let sorted = boxes.enumerated().sorted { a, b in
            (a.element.room, a.element.kinds[0], a.offset) < (b.element.room, b.element.kinds[0], b.offset)
        }.map(\.element)
        for box in sorted {
            if !box.special, let i = out.firstIndex(where: { $0.canMerge(box) }) {
                out[i].absorb(box)
            } else {
                out.append(box)
            }
        }
        return out
    }

    /// Orders boxes by schedule, then room and kind; numbers and titles them.
    static func finalize(_ drafts: [DraftBox]) -> [(box: MovingBox, days: Int)] {
        let sorted = drafts.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if x.daysBeforeMove != y.daysBeforeMove { return x.daysBeforeMove > y.daysBeforeMove }
            if x.specialRank != y.specialRank { return x.specialRank < y.specialRank }
            if x.room != y.room { return x.room < y.room }
            if x.kinds != y.kinds { return x.kinds.lexicographicallyPrecedes(y.kinds) }
            if x.fragile != y.fragile { return !x.fragile }
            return a.offset < b.offset
        }.map(\.element)

        var boxes: [MovingBox] = sorted.enumerated().map { i, d in
            let title: String
            if d.kinds == [.openFirst] {
                title = "Open first · first-night essentials"
            } else if d.kinds == [.keepWithYou] {
                title = "Keep with you · photos and valuables"
            } else {
                title = "\(d.room) · \(d.kinds.map(\.label).joined(separator: " and "))"
            }
            return MovingBox(
                id: i + 1, size: d.size, room: d.room, title: title,
                contents: d.lines.map { BoxContent(name: $0.name, quantity: $0.quantity, itemId: $0.itemId) },
                weightKg: (d.kg * 10).rounded() / 10,
                fragile: d.fragile,
                openFirst: d.kinds == [.openFirst],
                keepWithYou: d.kinds == [.keepWithYou],
                thisSideUp: d.fragile || [.dishPack, .picture, .wardrobe].contains(d.size)
                    || d.kinds.contains(.electronics) || d.kinds == [.openFirst]
            )
        }
        // "Bedroom · books (1 of 2)" when a title repeats.
        let counts = Dictionary(boxes.map { ($0.title, 1) }, uniquingKeysWith: +)
        var seen: [String: Int] = [:]
        for i in boxes.indices {
            let t = boxes[i].title
            guard let total = counts[t], total > 1 else { continue }
            seen[t, default: 0] += 1
            boxes[i].title = "\(t) (\(seen[t]!) of \(total))"
        }
        return zip(boxes, sorted).map { ($0, $1.daysBeforeMove) }
    }

    // MARK: Supplies and schedule

    static func supplies(boxes: [MovingBox], furniture: [FurnitureNote], items: [Item]) -> [SupplyLine] {
        guard !boxes.isEmpty || !furniture.isEmpty else { return [] }
        var out: [SupplyLine] = []
        for size in BoxSize.allCases {
            let n = boxes.filter { $0.size == size }.count
            if n > 0 { out.append(SupplyLine(name: size.label, quantity: n)) }
        }
        if !boxes.isEmpty {
            out.append(SupplyLine(name: "Packing tape rolls", quantity: (boxes.count + 7) / 8))
            let fragile = boxes.filter(\.fragile).count
            out.append(SupplyLine(name: "Packing paper sheets", quantity: fragile * 20 + (boxes.count - fragile) * 5))
        }
        if !furniture.isEmpty {
            out.append(SupplyLine(name: "Moving blankets", quantity: furniture.count))
            out.append(SupplyLine(name: "Stretch wrap roll", quantity: 1))
            out.append(SupplyLine(name: "Zip bags for screws and bolts", quantity: max(4, furniture.count * 2)))
        }
        let beds = items.filter { item in
            let c = item.category.lowercased()
            return c == "bed" || c == "mattress" || item.name.lowercased().contains("mattress")
        }.count
        if beds > 0 { out.append(SupplyLine(name: "Mattress bag", quantity: beds)) }
        out.append(SupplyLine(name: "Permanent markers", quantity: max(1, (boxes.count + 14) / 15)))
        return out
    }

    static let stages: [(days: Int, title: String)] = [
        (14, "Two weeks out: books, decor and things you rarely use"),
        (7, "One week out: most of each room"),
        (2, "Two days out: kitchen and bathroom basics, hanging clothes, take furniture apart"),
        (0, "Moving day: the open-first tote and the keep-with-you box"),
    ]

    static func schedule(_ boxes: [(box: MovingBox, days: Int)]) -> [PackingStep] {
        guard !boxes.isEmpty else { return [] }
        return stages.enumerated().map { i, stage in
            PackingStep(id: i + 1, title: stage.title, daysBeforeMove: stage.days,
                        boxIds: boxes.filter { $0.days == stage.days }.map(\.box.id))
        }
    }
}

// MARK: - Internal packing types

struct PackUnit: Sendable {
    var itemId: UInt64?
    var name: String
    var quantity: Int
    /// Per piece, wrapped.
    var litres: Double
    var kg: Double
    var room: String
    var kind: PackKind
    var fragile: Bool
    /// Sorted largest first; nil for typical contents (they're small).
    var dims: [Double]?
    /// A lampshade: only light things share its box.
    var lightOnly = false
    var sizes: [BoxSize]

    init(itemId: UInt64?, name: String, quantity: Int, litres: Double, kg: Double, room: String, kind: PackKind,
         fragile: Bool, dims: [Double]? = nil) {
        self.itemId = itemId
        self.name = name
        self.quantity = quantity
        self.litres = litres
        self.kg = kg
        self.room = room
        self.kind = kind
        self.fragile = fragile
        self.dims = dims?.sorted(by: >)
        // Dish packs are for breakables; pots and pans go in medium boxes.
        self.sizes = kind == .kitchen && !fragile ? [.medium, .large, .small] : kind.sizes
    }

    init(item: Item, kind: PackKind, room: String, density: Double) {
        let fragile = item.fragile || kind == .electronics
        let v = item.volumeM3
        self.init(itemId: item.id, name: item.name, quantity: 1, litres: v * 1000 * (fragile ? 1.5 : 1.1),
                  kg: max(0.1, v * density), room: room, kind: kind, fragile: fragile,
                  dims: [item.widthM, item.heightM, item.depthM])
    }

    init(typical: TypicalLine, room: String) {
        self.init(itemId: nil, name: typical.name, quantity: typical.quantity, litres: typical.litres, kg: typical.kg,
                  room: room, kind: typical.kind, fragile: typical.fragile)
    }

    func fits(_ size: BoxSize) -> Bool {
        if let dims {
            let box = size.sortedDims
            for (a, b) in zip(dims, box) where a > b + 1e-9 { return false }
        }
        return litres <= size.usableLitres + 1e-9 && kg <= DraftBox.capKg(size, fragile: fragile) + 1e-9
    }

    var bestSize: BoxSize? { sizes.first(where: fits) }
}

struct DraftLine: Sendable {
    var name: String
    var quantity: Int
    var itemId: UInt64?
    var litres: Double
    var kg: Double
}

struct DraftBox: Sendable {
    var size: BoxSize
    var room: String
    var kinds: [PackKind]
    var fragile: Bool
    var lightOnly: Bool
    var lines: [DraftLine] = []

    init(size: BoxSize, room: String, kinds: [PackKind], fragile: Bool, lightOnly: Bool) {
        self.size = size
        self.room = room
        self.kinds = kinds
        self.fragile = fragile
        self.lightOnly = lightOnly
    }

    static func capKg(_ size: BoxSize, fragile: Bool) -> Double {
        fragile ? min(size.maxKg, PackingPlanner.fragileMaxKg) : size.maxKg
    }

    var capKg: Double { Self.capKg(size, fragile: fragile) }
    var litres: Double { lines.reduce(0) { $0 + $1.litres * Double($1.quantity) } }
    var kg: Double { lines.reduce(0) { $0 + $1.kg * Double($1.quantity) } }
    var fill: Double { litres / size.usableLitres }
    var special: Bool { kinds.contains(.openFirst) || kinds.contains(.keepWithYou) }
    var specialRank: Int { kinds == [.openFirst] ? 1 : kinds == [.keepWithYou] ? 2 : 0 }
    /// The later of its kinds' stages: you can't pack it until everything in it is ready.
    var daysBeforeMove: Int { kinds.map(\.daysBeforeMove).min() ?? 7 }

    /// How many more of `unit` fit.
    func capacity(for unit: PackUnit) -> Int {
        let byVolume = Int(((size.usableLitres - litres) / unit.litres + 1e-9).rounded(.down))
        let byWeight = Int(((capKg - kg) / unit.kg + 1e-9).rounded(.down))
        return max(0, min(byVolume, byWeight))
    }

    mutating func add(_ unit: PackUnit, quantity: Int) {
        if let i = lines.firstIndex(where: { $0.itemId == unit.itemId && $0.name == unit.name }) {
            lines[i].quantity += quantity
        } else {
            lines.append(DraftLine(name: unit.name, quantity: quantity, itemId: unit.itemId, litres: unit.litres, kg: unit.kg))
        }
    }

    func canMerge(_ other: DraftBox) -> Bool {
        guard !special, !other.special, room == other.room, size == other.size, fragile == other.fragile else { return false }
        let merged = kinds + other.kinds.filter { !kinds.contains($0) }
        guard merged.count <= 2, fill < 0.5 || other.fill < 0.5 else { return false }
        guard litres + other.litres <= size.usableLitres * 0.95, kg + other.kg <= capKg + 1e-9 else { return false }
        if lightOnly && other.lines.contains(where: { $0.kg > 1.0 }) { return false }
        if other.lightOnly && lines.contains(where: { $0.kg > 1.0 }) { return false }
        return true
    }

    mutating func absorb(_ other: DraftBox) {
        for kind in other.kinds where !kinds.contains(kind) { kinds.append(kind) }
        kinds.sort()
        lightOnly = lightOnly || other.lightOnly
        for line in other.lines {
            if let i = lines.firstIndex(where: { $0.itemId == line.itemId && $0.name == line.name }) {
                lines[i].quantity += line.quantity
            } else {
                lines.append(line)
            }
        }
    }
}

/// Destination rooms: the saved layout's, else a guess from the category that
/// prefers rooms already in use (so a lamp lands in the bedroom of a one-room move).
struct RoomGuesser {
    let mapped: [UInt64: String]
    let known: [String]

    init(items: [Item], mapped: [UInt64: String]) {
        let clean = mapped.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        self.mapped = clean
        var known = Set(items.compactMap { clean[$0.id] })
        // Categories with one obvious room (a bed goes in a bedroom) anchor the guesses.
        for item in items where clean[item.id] == nil {
            let kinds = LayoutSolver.preferredKinds(for: item.category)
            if kinds.count == 1, let k = kinds.first { known.insert(k.label) }
        }
        self.known = known.sorted()
    }

    func room(for item: Item) -> String {
        if let r = mapped[item.id] { return r }
        let kinds = LayoutSolver.preferredKinds(for: item.category)
        for kind in kinds {
            if let r = known.first(where: { roomKind(named: $0) == kind }) { return r }
        }
        return kinds.first?.label ?? RoomKind.other.label
    }
}
