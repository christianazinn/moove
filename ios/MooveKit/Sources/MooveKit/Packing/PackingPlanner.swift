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
///   fragility. Each room also gets typical everyday contents (`itemId == nil`,
///   `BoxContent.estimated`): an estimate for the truck, not something scanned.
///   Typical books are counted once per scanned room (living room, office, then bedroom, where the estimate has books), so a
///   one-room scan doesn't get a bedroom's and a living room's worth of books.
/// - Then boxes are filled properly (`consolidate`): within a destination room,
///   boxes merge when the combined volume fits one box (moving up a size, small →
///   medium → large, rather than adding a box) under its weight limit, and the
///   kinds go together: books with desk papers and games, electronics with desk
///   cables and decor, soft with soft, kitchen with kitchen. Bedding, throws and
///   clothes pad fragile decor, lamps, electronics and dishes ("Throws pad the
///   vases"). Never books with fragile things, never kitchen or bathroom things
///   with anything else (except padding around dishes), and only soft things go
///   under the hangers in a wardrobe box. A box still under 40% full then joins
///   another box of its room if the safety rules allow, and then any two boxes of a
///   room the safety rules allow together share one box when it holds both.
/// - No box weighs over its size's `maxKg` (all are 20 kg or less). Fragile
///   boxes stay at or under 8 kg, so nothing heavy ever shares a box with them.
/// - There's always an open-first tote and a keep-with-you box (sentimental
///   items, documents, valuables) when anything is moving. Sentimental things
///   too big for a box get a note in "Keep with you" and ride in the car.
/// - Box numbers follow the schedule: what you pack first gets the lowest
///   numbers. Within a stage boxes go by room (A-Z), then kind.
/// - Bought pieces (Sell & Buy) ship straight to the new home: they're listed as
///   `delivered`, never boxed and not on the truck.
/// - Every decision carries a short reason: each box (`reason`: why these things
///   share it, `roomReason`: where it goes and how Moove knows), each scanned line
///   (`BoxContent.reason`), each furniture note and each delivered piece.
public enum PackingPlanner {
    /// Share of a box's volume you can fill once things are wrapped.
    static let packingEfficiency = 0.7
    /// Fragile boxes stay at or under this, so heavy things never ride with them.
    public static let fragileMaxKg = 8.0
    static let keepWithYouRoom = "Keep with you"
    static let openFirstRoom = "Open first"
    /// A box of small leftovers from several rooms (the box cap's last pass).
    public static let miscRoom = "Misc"
    /// About how many boxes Move shows for a typical move (Lisa, #335). Over it, `consolidate`
    /// merges harder (any kinds the safety rules allow in one room, then small leftovers across
    /// rooms into Misc boxes); weight and fragile limits still hold, so a big home can stay over.
    public static let boxCap = 12

    /// - Parameters:
    ///   - items: the inventory. Only `.keep` items move, plus undecided
    ///     sentimental items, which go in "Keep with you". Others are ignored,
    ///     so passing the whole inventory is fine.
    ///   - destinationRoom: item id -> room name in the new home (from the saved
    ///     layout). Missing items are guessed from their category.
    ///   - bought: purchased shopping items. Their destination is looked up under
    ///     `BoughtFurniture.layoutId(forShoppingItem:)`, as the saved layout stores it.
    public static func plan(items: [Item], destinationRoom: [UInt64: String] = [:], bought: [BoughtPiece] = []) -> PackingPlan {
        let moving = movingItems(items)
        let rooms = RoomGuesser(items: moving, mapped: destinationRoom)
        let delivered = deliveries(bought, rooms: rooms)
        guard !moving.isEmpty else {
            var plan = PackingPlan.empty
            plan.delivered = delivered
            return plan
        }

        var units: [PackUnit] = []
        var furniture: [FurnitureNote] = []
        var keepUnits: [PackUnit] = []
        for item in moving {
            let room = rooms.room(for: item)
            switch handling(of: item, room: room) {
            case let .boxed(unit):
                if unit.kind == .keepWithYou { keepUnits.append(unit) } else { units.append(unit) }
            case let .furniture(steps):
                furniture.append(FurnitureNote(id: item.id, name: item.name, room: room, steps: steps,
                                               reason: Reasons.furniture(item), roomReason: rooms.reason(room, mapped: rooms.isMapped(item.id))))
            case let .floorLamp(shade, steps):
                units.append(shade)
                furniture.append(FurnitureNote(id: item.id, name: "\(item.name): base and pole", room: room, steps: steps,
                                               reason: Reasons.floorLamp, roomReason: rooms.reason(room, mapped: rooms.isMapped(item.id))))
            case let .car(steps):
                furniture.append(FurnitureNote(id: item.id, name: item.name, room: keepWithYouRoom, steps: steps,
                                               reason: Reasons.sentimental, roomReason: Reasons.ridesWithYou))
            case let .expanded(parts):
                units += parts
            }
        }

        // Typical everyday contents per destination room, skipping kinds the scan already has there.
        // Books are counted once per scanned room, not once per destination room (see `typicalBookRooms`).
        let destinations = Set(furniture.map(\.room) + units.map(\.room)).subtracting([keepWithYouRoom]).sorted()
        let bookRooms = typicalBookRooms(destinations, units: units, scannedRooms: Set(moving.map(\.roomId)).count)
        for room in destinations {
            let scannedKinds = Set(units.filter { $0.room == room && $0.itemId != nil }.map(\.kind))
            for line in PackingTemplates.typical(for: roomKind(named: room))
            where !scannedKinds.contains(line.kind) && (line.kind != .books || bookRooms.contains(room)) {
                units.append(PackUnit(typical: line, room: room))
            }
        }
        units += PackingTemplates.openFirst.map { PackUnit(typical: $0, room: openFirstRoom) }
        keepUnits += PackingTemplates.keepWithYou.map { PackUnit(typical: $0, room: keepWithYouRoom) }
        // The keep-with-you box is one group: fragile if anything in it is.
        let keepFragile = keepUnits.contains(where: \.fragile)
        units += keepUnits.map { var u = $0; u.fragile = keepFragile; return u }

        var numbered = finalize(consolidate(pack(units)))
        for i in numbered.indices {
            let box = numbered[i].box
            let mapped = box.contents.contains { $0.itemId.map(rooms.isMapped) ?? false } || rooms.mappedRooms.contains(box.room)
            numbered[i].box.roomReason = box.keepWithYou ? Reasons.ridesWithYou
                : box.openFirst ? Reasons.openFirstRoom : box.room == miscRoom ? Reasons.misc : rooms.reason(box.room, mapped: mapped)
        }
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
            schedule: schedule(numbered),
            delivered: delivered
        )
    }

    /// Destination rooms that get typical books. A household's books are estimated once per scanned
    /// room, so a one-room scan headed for a bedroom and a living room doesn't get both rooms' books.
    /// Scanned books use up a set first; the rest go to the living room, else the office, else a bedroom.
    static func typicalBookRooms(_ destinations: [String], units: [PackUnit], scannedRooms: Int) -> Set<String> {
        let scanned = Set(units.filter { $0.kind == .books && $0.itemId != nil }.map(\.room))
        let sets = max(0, max(1, scannedRooms) - scanned.count)
        func rank(_ room: String) -> Int {
            switch roomKind(named: room) {
            case .living: return 0
            case .office: return 1
            case .bedroom: return 2
            default: return 3
            }
        }
        let wanting = destinations.filter { room in
            !scanned.contains(room) && PackingTemplates.typical(for: roomKind(named: room)).contains { $0.kind == .books }
        }
        return Set(wanting.sorted { (rank($0), $0) < (rank($1), $1) }.prefix(sets))
    }

    /// Bought pieces, with their destination room (the saved layout's, else a guess) and seller.
    static func deliveries(_ bought: [BoughtPiece], rooms: RoomGuesser) -> [DeliveredItem] {
        bought.sorted { $0.item.id < $1.item.id }.map { piece in
            let layout = LayoutItem(bought: piece.item, deal: piece.deal)
            let room = rooms.room(id: layout.id, category: layout.category)
            let title = piece.deal?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return DeliveredItem(
                id: piece.item.id, name: piece.item.name, title: title.isEmpty ? piece.item.name : title,
                seller: piece.deal.map(seller) ?? "", room: room, reason: Reasons.bought,
                roomReason: rooms.reason(room, mapped: rooms.isMapped(layout.id)), voxelSpec: VoxelItemSpec(layout),
                priceCents: piece.deal?.priceCents
            )
        }
    }

    /// "IKEA" or "Craigslist · Dana" (the deal's source, plus who from its seller info).
    static func seller(_ deal: Deal) -> String {
        let source = deal.source.count <= 4 ? deal.source.uppercased() : deal.source.prefix(1).uppercased() + deal.source.dropFirst()
        let who = deal.sellerInfo.split(separator: "·").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if who.isEmpty || who.lowercased() == deal.source.lowercased() { return source }
        return "\(source) · \(who)"
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
            unit.why = "sentimental, rides with you"
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
            shade.why = "shade off the floor lamp"
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
            unit.why = "too much for one box, split up"
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

    /// Boxes under this share of their usable volume get one last try at joining another box.
    static let sparseFill = 0.4

    /// Fills boxes properly once the first pass has grouped them by room, kind and fragility.
    /// Per destination room (never the open-first tote or the keep-with-you box):
    /// 1. Biggest box first, each box takes in the largest other box that fits with it: compatible
    ///    kinds (`DraftBox.combined`), the combined volume within one box's usable litres, the weight
    ///    within its `maxKg` (8 kg if anything in it is fragile). The result can move up a size
    ///    (small → medium → large), since one bigger box beats two half-empty ones.
    /// 2. Any box still under `sparseFill` joins another box of its room with looser kind rules
    ///    (the safety rules still hold: no books with fragile things, kitchen only with kitchen).
    /// 3. Fuller boxes: any two boxes of one room that the safety rules allow together and one box
    ///    holds share it (the smallest such box first), so big boxes fill before another is added.
    /// 4-5. Only over `cap`: towels join the bathroom box, then small leftovers share a Misc box.
    static func consolidate(_ boxes: [DraftBox], cap: Int = boxCap) -> [DraftBox] {
        var out = boxes
        func capacityOrder(_ ids: [Int]) -> [Int] {
            ids.sorted { a, b in
                let x = out[a], y = out[b]
                if x.size.usableLitres != y.size.usableLitres { return x.size.usableLitres > y.size.usableLitres }
                if abs(x.litres - y.litres) > 1e-9 { return x.litres > y.litres }
                return a < b
            }
        }
        // 1. Strict pass.
        var changed = true
        while changed {
            changed = false
            let open = out.indices.filter { !out[$0].special }
            hosts: for h in capacityOrder(open) {
                let guests = open.filter { $0 != h && out[$0].room == out[h].room }.sorted { a, b in
                    abs(out[a].litres - out[b].litres) > 1e-9 ? out[a].litres > out[b].litres : a < b
                }
                for g in guests {
                    if let merged = out[h].combined(with: out[g], relaxed: false) {
                        out[h] = merged
                        out.remove(at: g)
                        changed = true
                        break hosts
                    }
                }
            }
        }
        // 2. Absorb sparse boxes.
        changed = true
        while changed {
            changed = false
            let open = out.indices.filter { !out[$0].special }
            let sparse = open.filter { out[$0].fill < sparseFill }.sorted { a, b in
                abs(out[a].fill - out[b].fill) > 1e-9 ? out[a].fill < out[b].fill : a < b
            }
            outer: for g in sparse {
                for h in capacityOrder(open.filter { $0 != g && out[$0].room == out[g].room }) {
                    if let merged = out[h].combined(with: out[g], relaxed: true) {
                        out[h] = merged
                        out.remove(at: g)
                        changed = true
                        break outer
                    }
                }
            }
        }
        // 3. Fuller boxes: any two boxes of one room the safety rules allow together share the
        //    smallest box that holds both (up to large) instead of riding as two (Lisa: fewer boxes).
        mergeToCap(&out, cap: 0, acrossRooms: false, overCap: false)
        // 4-5. Over the cap: merge harder (towels join the bathroom box, then small leftovers across rooms).
        if out.count > cap { mergeToCap(&out, cap: cap, acrossRooms: false) }
        if out.count > cap { mergeToCap(&out, cap: cap, acrossRooms: true) }
        return out
    }

    /// While there are more than `cap` boxes, merges the pair that makes the smallest box: 3. any two
    /// boxes of one room the safety rules allow together (towels may join the bathroom box), up a
    /// size if needed; 4. (`acrossRooms`) a box under half full into one from another room, which
    /// becomes a Misc box whose lines remember their own room.
    /// `overCap` false (the always-on fill pass) keeps the usual kind rules: no towels in the bathroom box.
    static func mergeToCap(_ out: inout [DraftBox], cap: Int, acrossRooms: Bool, overCap: Bool = true) {
        while out.count > cap {
            var best: (h: Int, g: Int, box: DraftBox)?
            let open = out.indices.filter { !out[$0].special }
            for h in open {
                for g in open where g != h {
                    let sameRoom = out[h].room == out[g].room
                    guard acrossRooms ? (!sameRoom && out[g].fill < 0.5) : sameRoom else { continue }
                    guard let merged = out[h].combined(with: out[g], relaxed: true, cap: overCap, acrossRooms: acrossRooms) else { continue }
                    if let b = best, b.box.size.usableLitres < merged.size.usableLitres - 1e-9
                        || (abs(b.box.size.usableLitres - merged.size.usableLitres) < 1e-9 && b.box.litres <= merged.litres) { continue }
                    best = (h, g, merged)
                }
            }
            guard let best else { return }
            out[best.h] = best.box
            out.remove(at: best.g)
        }
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
                title = "\(d.room) · \(Reasons.list(d.kinds.map(\.label)))"
            }
            return MovingBox(
                id: i + 1, size: d.size, room: d.room, title: title,
                contents: d.lines.map { line in
                    BoxContent(name: line.name, quantity: line.quantity, itemId: line.itemId,
                               reason: line.itemId == nil ? nil : Reasons.line(room: line.room ?? d.room, box: i + 1, why: line.why),
                               category: line.category)
                },
                weightKg: (d.kg * 10).rounded() / 10,
                fragile: d.fragile,
                openFirst: d.kinds == [.openFirst],
                keepWithYou: d.kinds == [.keepWithYou],
                thisSideUp: d.fragile || [.dishPack, .picture, .wardrobe].contains(d.size)
                    || d.kinds.contains(.electronics) || d.kinds == [.openFirst],
                kinds: d.kinds.map(\.key),
                reason: Reasons.box(d)
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
    /// Short detail for this line's reason ("fragile, wrapped"); nil uses the box's kind.
    var why: String?

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
        if fragile { why = "fragile, wrapped" }
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
    var why: String
    var category: String
    /// The room this line goes to when its box is a Misc box of several rooms' leftovers.
    var room: String? = nil
}

struct DraftBox: Sendable {
    var size: BoxSize
    var room: String
    var kinds: [PackKind]
    var fragile: Bool
    var lightOnly: Bool
    var lines: [DraftLine] = []
    /// Set when soft things were packed around fragile ones.
    var padding: Padding?

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
            lines.append(DraftLine(name: unit.name, quantity: quantity, itemId: unit.itemId, litres: unit.litres, kg: unit.kg,
                                   why: unit.why ?? unit.kind.label, category: unit.kind.voxelCategory))
        }
    }

    /// This box and `other` packed together, in the smallest box that holds both, or nil when they
    /// shouldn't or can't share. `relaxed` (the sparse-box pass) lets any kinds share except the
    /// safety rules: books never with fragile things, kitchen only with kitchen (or soft padding
    /// around fragile dishes), bathroom only with bathroom, a wardrobe box only takes soft things.
    /// `cap` (over the box cap) also lets towels and bedding join a bathroom box; `acrossRooms`
    /// merges boxes of different rooms into a Misc box.
    func combined(with other: DraftBox, relaxed: Bool, cap: Bool = false, acrossRooms: Bool = false) -> DraftBox? {
        guard !special, !other.special, room == other.room || acrossRooms else { return nil }
        let fragileResult = fragile || other.fragile
        guard Self.kindsShare(self, other, fragileResult: fragileResult, relaxed: relaxed, cap: cap) else { return nil }
        if lightOnly && other.lines.contains(where: { $0.kg > 1.0 }) { return nil }
        if other.lightOnly && lines.contains(where: { $0.kg > 1.0 }) { return nil }
        guard let rankA = size.nestRank, let rankB = other.size.nestRank else { return nil }
        // Only up the nesting chain (each size holds the one before it), so whatever fit still fits.
        // Dish packs and wardrobe boxes are only used when one side already is one.
        let allowed: Set<BoxSize> = [.small, .medium, .large, size, other.size]
        let totalLitres = litres + other.litres, totalKg = kg + other.kg
        let target = BoxSize.allCases
            .filter { allowed.contains($0) && ($0.nestRank ?? -1) >= max(rankA, rankB) }
            .sorted { ($0.nestRank ?? 0) < ($1.nestRank ?? 0) }
            .first { totalLitres <= $0.usableLitres + 1e-9 && totalKg <= Self.capKg($0, fragile: fragileResult) + 1e-9 }
        guard let target else { return nil }

        var out = self
        if room != other.room {
            for i in out.lines.indices where out.lines[i].room == nil { out.lines[i].room = room }
            out.room = PackingPlanner.miscRoom
        }
        out.size = target
        out.fragile = fragileResult
        out.lightOnly = lightOnly || other.lightOnly
        for kind in other.kinds where !out.kinds.contains(kind) { out.kinds.append(kind) }
        out.kinds.sort()
        for var line in other.lines {
            if other.room != out.room, line.room == nil { line.room = other.room }
            if let i = out.lines.firstIndex(where: { $0.itemId == line.itemId && $0.name == line.name && $0.room == line.room }) {
                out.lines[i].quantity += line.quantity
            } else {
                out.lines.append(line)
            }
        }
        out.padding = padding ?? other.padding ?? Self.paddingNote(self, other)
        return out
    }

    /// Soft things that pad fragile ones: folded clothes, bedding, throws.
    static let paddingKinds: Set<PackKind> = [.clothes, .bedding]
    static let softKinds: Set<PackKind> = [.clothes, .shoes, .bedding, .hanging]

    /// Kinds that pack well together (beyond the same kind): books with desk papers and games,
    /// cables and electronics with desk things, decor with lamps and electronics, soft with soft.
    static let sharingPairs: Set<Set<PackKind>> = [
        [.books, .desk], [.books, .misc], [.desk, .electronics], [.desk, .misc],
        [.electronics, .decor], [.electronics, .lamps], [.electronics, .misc],
        [.decor, .lamps], [.decor, .misc], [.lamps, .misc],
    ]

    static func kindsShare(_ a: DraftBox, _ b: DraftBox, fragileResult: Bool, relaxed: Bool, cap: Bool = false) -> Bool {
        let ka = Set(a.kinds), kb = Set(b.kinds), all = ka.union(kb)
        // Never heavy books with fragile things.
        if fragileResult && all.contains(.books) { return false }
        // A wardrobe box keeps its hangers; only soft things go in under them.
        if (a.size == .wardrobe || b.size == .wardrobe) && !all.isSubset(of: softKinds) { return false }
        // Kitchen only with kitchen, or soft padding around fragile dishes.
        if all.contains(.kitchen) && !all.isSubset(of: [.kitchen]) {
            let (kitchenSide, otherSide, kitchenFragile) = ka.contains(.kitchen) ? (ka, kb, a.fragile) : (kb, ka, b.fragile)
            return kitchenSide == [.kitchen] && kitchenFragile && otherSide.isSubset(of: paddingKinds)
        }
        if all.contains(.bathroom) && all != [.bathroom] && !(cap && all.subtracting([.bathroom]).isSubset(of: paddingKinds)) { return false }
        if relaxed { return true }
        for x in ka {
            for y in kb where x != y {
                if softKinds.contains(x) && softKinds.contains(y) { continue }
                let pair: Set<PackKind> = [x, y]
                if sharingPairs.contains(pair) { continue }
                // Soft things pad decor, lamps and electronics.
                if !pair.isDisjoint(with: paddingKinds) && !pair.isDisjoint(with: [.decor, .lamps, .electronics]) { continue }
                return false
            }
        }
        return true
    }

    /// "Throws" and "vases" when one side is all padding and the other holds the fragile things.
    static func paddingNote(_ a: DraftBox, _ b: DraftBox) -> Padding? {
        func soft(_ d: DraftBox) -> Bool { Set(d.kinds).isSubset(of: paddingKinds) }
        let pair: (DraftBox, DraftBox)? = soft(a) && b.fragile && !soft(b) ? (a, b) : soft(b) && a.fragile && !soft(a) ? (b, a) : nil
        guard let (pad, held) = pair else { return nil }
        func biggest(_ lines: [DraftLine]) -> DraftLine? {
            lines.enumerated().max { x, y in
                let lx = x.element.litres * Double(x.element.quantity), ly = y.element.litres * Double(y.element.quantity)
                return abs(lx - ly) > 1e-9 ? lx < ly : x.offset > y.offset
            }?.element
        }
        guard let p = biggest(pad.lines), let f = biggest(held.lines.filter { $0.itemId != nil }) ?? biggest(held.lines) else { return nil }
        return Padding(soft: Padding.short(p.name), fragile: Padding.short(f.name))
    }

    /// Soft things padding fragile ones in the same box, for the box's reason.
    struct Padding: Sendable, Hashable {
        var soft: String
        var fragile: String

        /// "Throws and cushions" -> "throws"; "Floor lamp shade" -> "floor lamp shade".
        static func short(_ name: String) -> String {
            var head = name
            for sep in [" and ", ",", " (", " ·"] {
                if let r = head.range(of: sep) { head = String(head[..<r.lowerBound]) }
            }
            head = head.trimmingCharacters(in: .whitespaces)
            guard let first = head.first else { return name }
            // Keep "IKEA" or "TV" as is; lowercase ordinary words.
            if head.dropFirst().first?.isUppercase == true { return head }
            return first.lowercased() + head.dropFirst()
        }

        /// "Throws pad the vases, under 8 kg"
        func reason(kg: Int) -> String {
            let verb = soft.hasSuffix("s") ? "pad" : "pads"
            let text = "\(soft.prefix(1).uppercased())\(soft.dropFirst()) \(verb) the \(fragile), under \(kg) kg"
            return text.count <= 60 ? text : "Soft things pad the fragile ones, under \(kg) kg"
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

    /// Rooms the saved layout uses.
    var mappedRooms: Set<String> { Set(mapped.values) }

    func isMapped(_ id: UInt64) -> Bool { mapped[id] != nil }

    func room(for item: Item) -> String { room(id: item.id, category: item.category) }

    func room(id: UInt64, category: String) -> String {
        if let r = mapped[id] { return r }
        let kinds = LayoutSolver.preferredKinds(for: category)
        for kind in kinds {
            if let r = known.first(where: { roomKind(named: $0) == kind }) { return r }
        }
        return kinds.first?.label ?? RoomKind.other.label
    }

    /// "Goes to Bedroom 2 (from your saved layout)" or "Room not set yet: best guess".
    func reason(_ room: String, mapped: Bool) -> String {
        mapped ? Reasons.fromLayout(room) : Reasons.guessed
    }
}

/// The short reasons behind each packing decision. Kept to a few words: they show under rows.
enum Reasons {
    static let sentimental = "Sentimental: rides with you"
    static let ridesWithYou = "Rides with you, not on the truck"
    static let openFirstRoom = "Load it last, open it first"
    static let floorLamp = "Too tall for a box: shade boxed, base wrapped"
    static let bought = "Bought: ships straight to the new place, nothing to pack"
    static let guessed = "Room not set yet: best guess from what it is"
    static let misc = "Small leftovers from a few rooms: each line says where it goes"

    static func fromLayout(_ room: String) -> String { "Goes to \(room) (from your saved layout)" }

    /// "Kitchen → Box 7 · fragile, wrapped"
    static func line(room: String, box: Int, why: String) -> String {
        room == PackingPlanner.keepWithYouRoom ? "Box \(box) · \(why)" : "\(room) → Box \(box) · \(why)"
    }

    /// "books", "books and desk supplies", "decor, lamps and electronics"
    static func list(_ words: [String]) -> String {
        guard words.count > 2 else { return words.joined(separator: " and ") }
        return words.dropLast().joined(separator: ", ") + " and " + words.last!
    }

    /// Why these things share a box.
    static func box(_ d: DraftBox) -> String {
        let kg = Int(d.capKg.rounded())
        if d.kinds == [.openFirst] { return "First-night things, all in one place" }
        if d.kinds == [.keepWithYou] { return "Valuables and keepsakes: never on the truck" }
        if let padding = d.padding { return padding.reason(kg: kg) }
        if d.lightOnly { return "Lamp shade: light things only, under \(kg) kg" }
        if d.fragile { return "Fragile: wrapped, nothing heavy, under \(kg) kg" }
        if d.size == .wardrobe {
            return d.kinds == [.hanging] ? "Hanging clothes stay on their hangers" : "On hangers, soft things packed below"
        }
        let heavy = d.kinds.contains(.books) || d.kinds.contains(.desk)
        if heavy && d.size == .small { return "Heavy: small box, under \(kg) kg" }
        if d.kinds.allSatisfy({ [.clothes, .shoes, .bedding].contains($0) }) { return "Light and soft: big box, under \(kg) kg" }
        if d.kinds.count > 1 {
            let text = "Shared: \(list(d.kinds.map(\.label))), under \(kg) kg"
            return text.count <= 60 ? text : "Shared to fill the box, under \(kg) kg"
        }
        if heavy { return "Heavy: packed tight, under \(kg) kg" }
        if d.kinds == [.kitchen] { return "Pots and pans: sturdy, under \(kg) kg" }
        return "Same room, same kind, under \(kg) kg"
    }

    /// Why a piece isn't boxed, with the one step that matters most.
    static func furniture(_ item: Item) -> String {
        let c = item.category.lowercased(), n = item.name.lowercased()
        let lead = "Too big for a box: "
        if c == "mattress" || n.contains("mattress") { return lead + "bag it, carry it on its side" }
        if c == "bed" { return lead + "take it apart, bag the bolts" }
        if c == "sofa" || c == "couch" { return lead + "legs off, wrap in blankets" }
        if c == "table" || c == "desk" { return lead + "take the legs off, wrap the top" }
        if c == "dresser" || c == "wardrobe" { return lead + "drawers shut, wrap in a blanket" }
        if c == "tv" || c == "television" { return lead + "keep the screen upright" }
        if c == "chair" { return lead + "wrap in a blanket" }
        if ["appliance", "refrigerator", "washer", "dryer"].contains(c) { return lead + "unplug, keep it upright" }
        return lead + "wrap in a blanket"
    }
}

extension SyncSnapshot {
    /// What the user bought for the new home, for `PackingPlanner.plan(bought:)`: purchased shopping
    /// items only (still-shopping ones aren't coming), each with its chosen deal.
    public var boughtPieces: [BoughtPiece] {
        purchasedShoppingItems.map { BoughtPiece(item: $0, deal: chosenDeal(for: $0)) }
    }
}
