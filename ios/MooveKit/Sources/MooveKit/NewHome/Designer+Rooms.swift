import Foundation

// Which room each group goes in, and the order everything is placed (decision 0300):
// beds one per bedroom (twin/bunk pairs may share), then the sleep, living, dining and office
// groups in their rooms, kitchen and bathroom fixtures on walls, the rest on free walls, and
// small things last, next to the furniture PropPlacer will set them on.

extension Designer {
    mutating func run(_ items: [LayoutItem], fixedBeds: [String: Int]) -> LayoutOption {
        let ordered = items.sorted { ($0.widthM * $0.depthM, $1.id) > ($1.widthM * $1.depthM, $0.id) }
        var pool: [DesignRole: [LayoutItem]] = [:]
        for item in ordered { pool[DesignRole.of(item), default: []].append(item) }
        func take(_ role: DesignRole) -> LayoutItem? {
            guard var list = pool[role], !list.isEmpty else { return nil }
            let first = list.removeFirst()
            pool[role] = list
            return first
        }
        func takeAll(_ role: DesignRole, max n: Int = .max) -> [LayoutItem] {
            let list = pool[role] ?? []
            pool[role] = Array(list.dropFirst(n))
            return Array(list.prefix(n))
        }
        var leftovers: [LayoutItem] = []
        let single = rooms.count == 1
        func byArea(_ rs: [FloorPlanRoom]) -> [FloorPlanRoom] { rs.sorted { ($0.areaM2, $1.name) > ($1.areaM2, $0.name) } }
        func ofKind(_ k: RoomKind...) -> [FloorPlanRoom] { byArea(rooms.filter { k.contains($0.kind) }) }

        // 1. Beds: one per bedroom, biggest bed in the biggest bedroom; a second twin or bunk
        //    may join a room that has one. A plan of one room (a scanned room) takes them all.
        let bedrooms = single ? rooms : (ofKind(.bedroom).isEmpty ? ofKind(.other, .living, .office) : ofKind(.bedroom))
        var bedsIn: [String: [LayoutItem]] = [:]
        var stored: [UInt64] = []
        let beds = takeAll(.bed)
        func count(_ r: FloorPlanRoom) -> Int { (bedsIn[r.name]?.count ?? 0) + (fixedBeds[r.name] ?? 0) }
        var waiting: [LayoutItem] = []
        for bed in beds {
            if let r = bedrooms.first(where: { single || count($0) == 0 }) { bedsIn[r.name, default: []].append(bed) } else { waiting.append(bed) }
        }
        for bed in waiting {
            let narrow = bed.widthM <= DesignRole.twinWidthM
            // Kids' rooms first: the smallest bedroom holding one narrow bed.
            if narrow, let r = bedrooms.reversed().first(where: { count($0) == 1 && (bedsIn[$0.name] ?? []).allSatisfy { $0.widthM <= DesignRole.twinWidthM } && fixedBeds[$0.name] == nil }) {
                bedsIn[r.name, default: []].append(bed)
            } else {
                stored.append(bed.id) // more beds than bedrooms: storage, never the living room
            }
        }
        let sleepRooms = bedrooms.filter { bedsIn[$0.name] != nil }
        let spare = single ? [] : ofKind(.bedroom).filter { bedsIn[$0.name] == nil && fixedBeds[$0.name] == nil }
        let primary = sleepRooms.first ?? ofKind(.bedroom).first

        // 2. Sleep groups: bed, nightstands either side, a dresser and a wardrobe.
        for room in sleepRooms {
            let here = bedsIn[room.name] ?? []
            let pair = here.count == 2 && here.allSatisfy { $0.widthM <= DesignRole.twinWidthM }
            let group = pair ? here : Array(here.prefix(1))
            let stands = takeAll(.nightstand, max: pair ? 1 : 2)
            leftovers += placeSleep(beds: group, stands: stands, in: room)
            // A scanned room with more beds: the others along free walls.
            for bed in here where !group.contains(where: { $0.id == bed.id }) {
                if !placeOnWall(bed, role: .bed, in: room, requireWalk: false) { stored.append(bed.id) }
            }
            if let d = take(.dresser), !placeCaseGood(d, role: .dresser, in: room) { leftovers.append(d) }
            if let w = take(.wardrobe), !placeCaseGood(w, role: .wardrobe, in: room) { leftovers.append(w) }
        }
        // Group placement may have failed for a bed: it goes on a free wall of its own room, else storage.
        for room in sleepRooms {
            for bed in bedsIn[room.name] ?? [] where !placements.contains(where: { $0.itemId == bed.id }) {
                leftovers.removeAll { $0.id == bed.id }
                if !placeOnWall(bed, role: .bed, in: room, requireWalk: false) { stored.append(bed.id) }
            }
        }

        // 3. Living group around the sofa (or the first armchair).
        let livingRooms = single ? rooms : dedupe(ofKind(.living) + ofKind(.other) + ofKind(.office) + (style == .compact ? [primary].compactMap { $0 } : [])
            + ofKind(.dining) + byArea(rooms.filter { $0.kind == .bedroom }) + ofKind(.kitchen))
        let sofa = take(.sofa) ?? take(.armchair)
        let tvStand = take(.tvStand)
        let floorTV = take(.tv)
        let media = tvStand ?? floorTV
        let screen = tvStand != nil ? floorTV : nil
        let propTV = (pool[.prop] ?? []).first { VoxelModels.kind(VoxelItemSpec($0)) == .tv }
        let tvWidth = floorTV?.widthM ?? propTV?.widthM
        if let sofa {
            let coffee = take(.coffeeTable)
            let chairs = takeAll(.sofa, max: 1) + takeAll(.armchair, max: 2)
            let side = take(.sideTable)
            let lamp = take(.floorLamp)
            let rug = take(.rug)
            var done = false
            for room in livingRooms {
                if let rest = placeLiving(sofa: sofa, media: media, screen: screen, tvWidth: tvWidth, coffee: coffee, chairs: Array(chairs.prefix(2)),
                                          side: side, lamp: lamp, rug: rug, in: room) {
                    leftovers += rest + chairs.dropFirst(2)
                    done = true
                    break
                }
            }
            if !done { leftovers += [sofa] + [media, screen, coffee, side, lamp, rug].compactMap { $0 } + chairs }
        } else if let media {
            if let screen { leftovers.append(screen) }
            // No seating: the TV piece on a wall of the living room (compact: the bedroom, facing the bed).
            let target = style == .compact ? ([primary].compactMap { $0 } + livingRooms) : livingRooms
            if !target.contains(where: { placeMedia(media, in: $0) }) { leftovers.append(media) }
        }

        // 4. Dining table with its chairs.
        let diningRooms = single ? rooms : dedupe(diningOrder(ofKind: ofKind))
        var diningChairs = takeAll(.diningChair)
        if let table = take(.diningTable) {
            var done = false
            for room in diningRooms {
                if let rest = placeDining(table: table, chairs: diningChairs, in: room) { leftovers += rest; done = true; break }
            }
            if !done { leftovers += [table] + diningChairs }
            diningChairs = []
        }

        // 5. Desk with its chair, then the bookshelf and a lamp near it.
        let officeRooms = single ? rooms : dedupe(officeOrder(spare: spare, primary: primary, ofKind: ofKind))
        if let desk = take(.desk) {
            let chair = take(.deskChair) ?? (diningChairs.isEmpty ? nil : diningChairs.removeFirst())
            var deskRoom: FloorPlanRoom?
            for room in officeRooms {
                if let rest = placeOffice(desk: desk, chair: chair, in: room) { leftovers += rest; deskRoom = room; break }
            }
            if let deskRoom, let d = placed.last(where: { $0.item.id == desk.id })?.rect {
                if let shelf = take(.bookshelf), !placeNear(shelf, role: .bookshelf, to: d, in: deskRoom) { leftovers.append(shelf) }
                if let lamp = take(.floorLamp), !placeNear(lamp, role: .floorLamp, to: d, in: deskRoom) { leftovers.append(lamp) }
            } else {
                leftovers += [desk] + [chair].compactMap { $0 }
            }
        }
        leftovers += diningChairs

        // 6. Kitchen and bathroom fixtures along their rooms' walls.
        for item in takeAll(.kitchen) {
            if !ofKind(.kitchen).contains(where: { placeFixture(item, role: .kitchen, in: $0) }) { leftovers.append(item) }
        }
        let baths = ofKind(.bathroom)
        var turn: [DesignRole: Int] = [:]
        for role in [DesignRole.bathtub, .toilet, .sink] {
            for item in takeAll(role) {
                let start = turn[role, default: 0]
                turn[role] = start + 1
                let order = baths.isEmpty ? [] : (0..<baths.count).map { baths[(start + $0) % baths.count] }
                if !order.contains(where: { placeFixture(item, role: role, in: $0) }) { leftovers.append(item) }
            }
        }

        // 7. Everything else on free walls (nightstands and dressers prefer bedrooms, plants the windows).
        let props = takeAll(.prop) + takeAll(.tableLamp) + takeAll(.wall)
        let rest = pool.values.flatMap { $0 } + leftovers
        for item in rest.sorted(by: { ($0.widthM * $0.depthM, $1.id) > ($1.widthM * $1.depthM, $0.id) }) where !stored.contains(item.id) {
            if DesignRole.of(item) == .bed { stored.append(item.id); continue }
            if !placeLeftover(item) { unplaced.append(item.id) }
        }

        // 8. Small things beside the piece they'll sit on; art by the sofa or bed.
        for item in props.sorted(by: { $0.id < $1.id }) where !placeProp(item) { unplaced.append(item.id) }

        placements.sort { $0.itemId < $1.itemId }
        return LayoutOption(style: style, placements: placements, unplaced: (unplaced + stored).sorted(), stored: stored.sorted())
    }

    func dedupe(_ rs: [FloorPlanRoom]) -> [FloorPlanRoom] {
        var seen = Set<String>()
        return rs.filter { seen.insert($0.name).inserted }
    }

    func diningOrder(ofKind: (RoomKind...) -> [FloorPlanRoom]) -> [FloorPlanRoom] {
        let bigKitchens = ofKind(.kitchen).filter { $0.areaM2 >= 10 }
        switch style {
        case .byFunction: return ofKind(.dining) + bigKitchens + ofKind(.living) + ofKind(.kitchen) + ofKind(.other)
        case .compact: return bigKitchens + ofKind(.living) + ofKind(.dining) + ofKind(.kitchen) + ofKind(.other)
        case .open: return ofKind(.dining) + bigKitchens + ofKind(.living) + ofKind(.kitchen) + ofKind(.other)
        }
    }

    func officeOrder(spare: [FloorPlanRoom], primary: FloorPlanRoom?, ofKind: (RoomKind...) -> [FloorPlanRoom]) -> [FloorPlanRoom] {
        let p = [primary].compactMap { $0 }
        let living = ofKind(.living), big = living.filter { $0.areaM2 >= 14 }
        let tail = ofKind(.other) + ofKind(.dining) + ofKind(.bedroom)
        switch style {
        case .byFunction: return ofKind(.office) + spare + big + p + living + tail
        case .compact: return ofKind(.office) + p + living + spare + tail
        case .open: return ofKind(.office) + spare + living + p + tail
        }
    }

    // MARK: Singles

    /// A TV stand or floor TV with no sofa: on the wall a bed or the room's middle faces.
    mutating func placeMedia(_ media: LayoutItem, in room: FloorPlanRoom) -> Bool {
        let bed = placed.first { $0.room == room.name && $0.role == .bed }?.rect
        let allWindows = plan.windows
        return placeOnWall(media, role: DesignRole.of(media), in: room) { w, t, r in
            let windows = w.spans(allWindows)
            var cost = abs(t - w.len / 2) / w.len
            if windows.contains(where: { min($0.1, t + r.halfWidth) - max($0.0, t - r.halfWidth) > 0.05 }) { cost += 1 }
            if let bed { cost += r.axes.z.dot(bed.axes.z) < -0.7 ? 0 : 1.5 } // across from the bed
            return cost
        }
    }

    /// Kitchen appliances cluster along the walls; a bathtub goes long side to the wall in a
    /// corner; the toilet isn't in line with the door; the sink is near the door.
    mutating func placeFixture(_ item: LayoutItem, role: DesignRole, in room: FloorPlanRoom) -> Bool {
        let doors = doorCenters(room)
        let mates = placed.filter { $0.room == room.name && ($0.role == .kitchen || $0.role.isBath) }.map(\.rect.center)
        let side = role == .bathtub && item.depthM > item.widthM
        let score: (RoomWall, Double, OrientedRect) -> Double = { w, t, r in
            var cost = mates.map { ($0 - r.center).length }.min().map { $0 * 0.3 } ?? 0
            switch role {
            case .bathtub:
                let half = (side ? item.depthM : item.widthM) / 2
                cost += min(t - half, w.len - t - half) * 0.6
            case .toilet:
                for d in doors {
                    let v = d - r.center
                    if v.dot(r.axes.z) > 0 && abs(v.dot(r.axes.x)) < r.halfWidth + 0.3 { cost += 1 }
                }
            case .sink:
                cost += (doors.map { ($0 - r.center).length }.min() ?? 0) * 0.1
            default:
                cost += (1 - w.len / max(room.widthM, room.depthM, 0.1)) * 0.3
            }
            return cost
        }
        return placeOnWall(item, role: role, in: room, side: side, score: score) || placeOnWall(item, role: role, in: room, side: side, requireWalk: false, score: score)
    }

    /// A piece with no group: on a free wall of the room it suits best (the old solver's room
    /// order), keeping the room walkable; then anywhere it fits.
    mutating func placeLeftover(_ item: LayoutItem) -> Bool {
        let role = DesignRole.of(item)
        var order = solver.roomOrder(for: item, rooms: rooms, style: style, used: used)
        if !role.isBath && rooms.count > 1 { order = order.filter { $0.kind != .bathroom } + order.filter { $0.kind == .bathroom } }
        // A group's extra pieces stay with the group: spare armchairs by the sofa, chairs by the
        // table or desk, nightstands and dressers in the bedrooms.
        let home: [DesignRole] = switch role {
        case .armchair, .sofa, .sideTable, .coffeeTable, .floorLamp, .rug, .tv, .tvStand: [.sofa]
        case .diningChair: [.diningTable, .desk]
        case .deskChair, .bookshelf: [.desk]
        case .nightstand, .dresser, .wardrobe: [.bed]
        default: []
        }
        let placedNow = placed
        let anchor = home.compactMap { r in placedNow.first { $0.role == r } }.first
        if let anchor, let i = order.firstIndex(where: { $0.name == anchor.room }) { order.insert(order.remove(at: i), at: 0) }
        let near = anchor?.rect.center
        let open = style == .open
        let windows = plan.windows
        for room in order {
            let ok = placeOnWall(item, role: role, in: room) { w, t, r in
                var cost = open ? abs(t - w.len / 2) / w.len : 0
                cost += (1 - w.len / max(room.widthM, room.depthM, 0.1)) * 0.2
                if let near { cost += (r.center - near).length * 0.3 }
                if role == .plant {
                    // Plants by a window.
                    cost += windows.map { ($0.from + $0.to) * 0.5 }.map { ($0 - r.center).length }.min().map { $0 * 0.5 } ?? 0
                }
                return cost
            }
            if ok { return true }
        }
        for room in order {
            if let spot = solver.fit(item, in: room, obstacles: doorBlocks + furniture + zones, style: style) {
                commit(item, spot, in: room, role: role)
                return true
            }
        }
        return false
    }

    // MARK: Props and wall pieces

    /// Where a small thing should end up: the room and the piece PropPlacer will put it on.
    func propTarget(_ item: LayoutItem) -> (room: String, at: PlanPoint)? {
        let spec = VoxelItemSpec(item)
        let kind = VoxelModels.kind(spec)
        let role = DesignRole.of(item)
        func first(_ roles: [DesignRole], skip: Set<UInt64> = []) -> (room: String, at: PlanPoint)? {
            for r in roles {
                if let p = placed.first(where: { $0.role == r && !skip.contains($0.item.id) }) { return (p.room, p.rect.center) }
            }
            return nil
        }
        if role == .wall {
            // Art over the sofa or the bed, a mirror over the dresser.
            let order: [DesignRole] = kind == .mirror ? [.dresser, .bed, .sofa] : [.sofa, .bed, .dresser, .desk]
            for r in order {
                if let p = placed.first(where: { $0.role == r }) {
                    return (p.room, p.rect.center - p.rect.axes.z * (p.rect.halfDepth - 0.1))
                }
            }
            return nil
        }
        if kind == .lamp {
            // One lamp per nightstand, then the desk, the dresser, the side table.
            let lit = Set(placements.compactMap { pl in
                placed.first { $0.item.id == pl.itemId && $0.role == .tableLamp }.flatMap { _ in nearestParent(pl) }
            })
            return first([.nightstand], skip: lit) ?? first([.desk, .dresser, .sideTable, .nightstand])
        }
        switch kind {
        case .tv: return first([.tvStand, .dresser, .bookshelf, .desk, .diningTable])
        case .monitor, .electronics, .keyboard: return first([.desk, .tvStand, .dresser])
        case .books, .photos, .framedPhotos, .binder: return first([.bookshelf, .dresser, .nightstand, .desk])
        default: return first([.dresser, .sideTable, .bookshelf, .coffeeTable, .desk, .nightstand])
        }
    }

    /// The placed parent piece nearest a prop's floor spot (for counting lamps per nightstand).
    func nearestParent(_ p: Placement) -> UInt64? {
        placed.filter { $0.room == p.room && $0.role == .nightstand }
            .min { ($0.rect.center - PlanPoint(p.x, p.y)).length < ($1.rect.center - PlanPoint(p.x, p.y)).length }?.item.id
    }

    /// A free floor spot as close as possible to the prop's target, so PropPlacer lifts it onto
    /// that piece (it only looks in the same room) and a hung piece goes on the nearest wall.
    mutating func placeProp(_ item: LayoutItem) -> Bool {
        let role = DesignRole.of(item)
        if let target = propTarget(item), let room = plan.room(named: target.room) {
            let b = room.bounds
            var best: (Double, OrientedRect)?
            for y in stride(from: b.minY + item.depthM / 2, through: b.maxY - item.depthM / 2, by: 0.1) {
                for x in stride(from: b.minX + item.widthM / 2, through: b.maxX - item.widthM / 2, by: 0.1) {
                    let c = PlanPoint(x, y)
                    let d = (c - target.at).length
                    if let bst = best, d >= bst.0 { continue }
                    let r = OrientedRect(center: c, halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: 0)
                    if free(r, in: room) { best = (d, r) }
                }
            }
            if let (_, r) = best {
                commit(item, r, in: room, role: role)
                return true
            }
        }
        return placeLeftover(item)
    }
}
