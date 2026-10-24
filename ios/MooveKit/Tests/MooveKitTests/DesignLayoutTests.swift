import Foundation
import Testing
@testable import MooveKit

/// The designer layout (decision 0300): one bed per bedroom, furniture groups, clearances.
@Suite struct DesignLayoutTests {
    static let plans: [(String, FloorPlan)] = [("demo", DemoHouse.floorPlan), ("3b2b", LayoutFixtures.estimated3b2b)]
    static let inventories: [(String, [LayoutItem])] = [
        ("demo", LayoutFixtures.demoFurniture), ("scan9", LayoutFixtures.scan9), ("rescans", LayoutFixtures.rescannedBedroom),
        ("living", Self.livingSet), ("all", DemoFixtures.inventory(owner: "me").items.map(LayoutItem.init)),
    ]

    /// A furnished living room and study: sofa, coffee table, two armchairs, rug, floor lamp,
    /// TV stand + TV, desk + office chair.
    static let livingSet: [LayoutItem] = [
        LayoutItem(id: 1, name: "Sofa", category: "sofa", widthM: 2.1, depthM: 0.9, heightM: 0.85),
        LayoutItem(id: 2, name: "Coffee table", category: "table", widthM: 1.1, depthM: 0.6, heightM: 0.45),
        LayoutItem(id: 3, name: "Armchair", category: "sofa", widthM: 0.85, depthM: 0.85, heightM: 0.9),
        LayoutItem(id: 4, name: "Accent chair", category: "chair", widthM: 0.75, depthM: 0.75, heightM: 0.85),
        LayoutItem(id: 5, name: "Area rug", category: "rug", widthM: 2.4, depthM: 1.7, heightM: 0.02),
        LayoutItem(id: 6, name: "Floor lamp", category: "lamp", widthM: 0.35, depthM: 0.35, heightM: 1.6),
        LayoutItem(id: 7, name: "TV stand", category: "storage", widthM: 1.5, depthM: 0.45, heightM: 0.55),
        LayoutItem(id: 8, name: "Samsung 55 inch TV", category: "television", widthM: 1.23, depthM: 0.25, heightM: 0.78),
        LayoutItem(id: 9, name: "Writing desk", category: "desk", widthM: 1.2, depthM: 0.6, heightM: 0.75),
        LayoutItem(id: 10, name: "Office chair", category: "chair", widthM: 0.65, depthM: 0.65, heightM: 1.0),
        LayoutItem(id: 11, name: "Queen bed", category: "bed", widthM: 1.6, depthM: 2.1, heightM: 0.5),
        LayoutItem(id: 12, name: "Nightstand", category: "storage", widthM: 0.45, depthM: 0.4, heightM: 0.55),
        LayoutItem(id: 13, name: "Nightstand", category: "storage", widthM: 0.45, depthM: 0.4, heightM: 0.55),
        LayoutItem(id: 14, name: "Dresser", category: "storage", widthM: 1.2, depthM: 0.5, heightM: 0.9),
    ]

    func rect(_ p: Placement, _ items: [LayoutItem]) -> OrientedRect {
        let item = items.first { $0.id == p.itemId }!
        return OrientedRect(center: PlanPoint(p.x, p.y), halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: p.rotationDeg)
    }

    func role(_ id: UInt64, _ items: [LayoutItem]) -> DesignRole { DesignRole.of(items.first { $0.id == id }!) }

    /// Gap between two rectangles (0 when they touch or overlap), sampled along their edges.
    func gap(_ a: OrientedRect, _ b: OrientedRect) -> Double {
        if a.overlaps(b) { return 0 }
        func pts(_ r: OrientedRect) -> [PlanPoint] {
            let c = r.corners
            var out: [PlanPoint] = []
            for i in 0..<4 {
                let a = c[i], d = c[(i + 1) % 4] - c[i]
                for k in 0...10 { out.append(a + d * (Double(k) / 10)) }
            }
            return out
        }
        let pa = pts(a), pb = pts(b)
        var best = Double.infinity
        for p in pa { for q in pb { best = min(best, (p - q).length) } }
        return best
    }

    /// Every plan × inventory × style, solved once for all the tests.
    static let solved: [(String, FloorPlan, [LayoutItem], LayoutOption)] = plans.flatMap { pn, plan in
        inventories.flatMap { inv, items in
            LayoutSolver(plan: plan).solveAll(items).map { ("\(pn)/\(inv)/\($0.name)", plan, items, $0) }
        }
    }

    func each(_ body: (String, FloorPlan, [LayoutItem], LayoutOption) -> Void) {
        for (label, plan, items, option) in Self.solved { body(label, plan, items, option) }
    }

    // MARK: Guarantees

    @Test func noOverlapsInsideRoomsDoorsClear() {
        each { label, plan, items, option in
            let solver = LayoutSolver(plan: plan)
            let solid = option.placements.filter { role($0.itemId, items) != .rug && $0.onTopOf == nil }
            for (i, p) in solid.enumerated() {
                let r = rect(p, items)
                let room = plan.room(named: p.room)!
                #expect(LayoutSolver.inside(r, room), "\(label): \(p.itemId) pokes out of \(room.name)")
                #expect(room.kind != .hallway, "\(label): \(p.itemId) in the hallway")
                for q in solid[(i + 1)...] { #expect(!r.overlaps(rect(q, items)), "\(label): \(p.itemId) overlaps \(q.itemId)") }
                for d in solver.doorKeepOuts() { #expect(!r.overlaps(d), "\(label): \(p.itemId) blocks a door") }
            }
            #expect(Set(option.placements.map(\.itemId)).isDisjoint(with: option.unplaced), "\(label)")
        }
    }

    @Test func deterministic() {
        for (_, plan) in Self.plans {
            let solver = LayoutSolver(plan: plan)
            #expect(solver.solveAll(LayoutFixtures.scan9) == solver.solveAll(LayoutFixtures.scan9.reversed()))
            #expect(solver.solveAll(Self.livingSet) == solver.solveAll(Self.livingSet.reversed()))
        }
    }

    // MARK: Beds

    @Test func oneBedPerBedroomExtrasToStorage() {
        each { label, plan, items, option in
            var beds: [String: [UInt64]] = [:]
            for p in option.placements where role(p.itemId, items) == .bed { beds[p.room, default: []].append(p.itemId) }
            for (room, ids) in beds {
                #expect(plan.room(named: room)?.kind == .bedroom, "\(label): a bed in \(room)")
                let twins = ids.allSatisfy { id in items.first { $0.id == id }!.widthM <= DesignRole.twinWidthM }
                #expect(ids.count == 1 || (ids.count == 2 && twins), "\(label): \(ids.count) beds in \(room)")
            }
            let allBeds = items.filter { DesignRole.of($0) == .bed }
            let bedrooms = plan.rooms.filter { $0.kind == .bedroom }.count
            #expect(beds.values.map(\.count).reduce(0, +) == min(allBeds.count, bedrooms) || beds.values.contains { $0.count == 2 }, "\(label)")
            for id in option.stored { #expect(role(id, items) == .bed && option.unplaced.contains(id)) }
        }
        // The demo house has two bedrooms: of the three re-scanned beds, one is stored.
        let o = LayoutSolver(plan: DemoHouse.floorPlan).solve(LayoutFixtures.rescannedBedroom, style: .byFunction)
        #expect(o.stored.count == 1)
    }

    @Test func twinsShareTheKidsRoom() {
        let items = [
            LayoutItem(id: 1, name: "Queen bed", category: "bed", widthM: 1.6, depthM: 2.1, heightM: 0.5),
            LayoutItem(id: 2, name: "Twin bed", category: "bed", widthM: 1.0, depthM: 2.0, heightM: 0.5),
            LayoutItem(id: 3, name: "Twin bed", category: "bed", widthM: 1.0, depthM: 2.0, heightM: 0.5),
            LayoutItem(id: 4, name: "Nightstand", category: "storage", widthM: 0.45, depthM: 0.4, heightM: 0.55),
        ]
        let o = LayoutSolver(plan: DemoHouse.floorPlan).solve(items, style: .byFunction)
        let room = Dictionary(uniqueKeysWithValues: o.placements.map { ($0.itemId, $0.room) })
        #expect(room[1] == "Bedroom")
        #expect(room[2] == "Bedroom 2" && room[3] == "Bedroom 2")
        #expect(o.unplaced.isEmpty)
    }

    @Test func headboardOnASolidWallNotInLineWithTheDoor() {
        for (_, plan) in Self.plans {
            let o = LayoutSolver(plan: plan).solve(Self.livingSet, style: .byFunction)
            let bed = o.placements.first { $0.itemId == 11 }!
            let r = rect(bed, Self.livingSet)
            let head = r.center - r.axes.z * (r.halfDepth + LayoutSolver(plan: plan).wallGapM)
            // No window behind the headboard.
            for w in plan.windows {
                let mid = (w.from + w.to) * 0.5
                let along = abs((mid - head).dot(r.axes.x))
                let behind = abs((mid - head).dot(r.axes.z)) < 0.1
                #expect(!(behind && along < r.halfWidth + w.widthM / 2 - 0.05), "window behind the bed")
            }
            // No door straight off the foot of the bed.
            for d in plan.doors where plan.room(named: bed.room)!.edges.contains(where: { FloorPlan.span(of: d, onEdge: $0.0, $0.1) != nil }) {
                let v = (d.from + d.to) * 0.5 - r.center
                #expect(!(v.dot(r.axes.z) > 0 && abs(v.dot(r.axes.x)) < r.halfWidth), "door in line with the bed")
            }
        }
    }

    @Test func nightstandsFlankTheBed() {
        for (pn, plan) in Self.plans {
            for items in [Self.livingSet, LayoutFixtures.rescannedBedroom] {
                let o = LayoutSolver(plan: plan).solve(items, style: .byFunction)
                let beds = o.placements.filter { role($0.itemId, items) == .bed }.map { ($0.room, rect($0, items)) }
                let stands = o.placements.filter { role($0.itemId, items) == .nightstand }
                #expect(!stands.isEmpty)
                for s in stands {
                    let r = rect(s, items)
                    guard let bed = beds.first(where: { $0.0 == s.room })?.1 else { Issue.record("\(pn): nightstand without a bed"); continue }
                    #expect(gap(r, bed) <= 0.2, "\(pn): nightstand \(s.itemId) is \(gap(r, bed)) m from the bed")
                    // Beside the head, not the foot: same wall, same facing.
                    #expect(r.axes.z.dot(bed.axes.z) > 0.99)
                    let headLine = (bed.center - bed.axes.z * bed.halfDepth).dot(bed.axes.z)
                    #expect(abs((r.center - r.axes.z * r.halfDepth).dot(bed.axes.z) - headLine) < 0.02)
                }
            }
        }
    }

    @Test func bedSideAndDoorStayWalkable() {
        each { label, plan, items, option in
            let rules = LayoutSolver.rules(option.style)
            for room in plan.rooms {
                let here = option.placements.filter { $0.room == room.name && role($0.itemId, items) != .rug && $0.onTopOf == nil }
                let grid = WalkGrid(room: room, plan: plan, furniture: here.map { rect($0, items) }, radius: rules.walkMin / 2)
                #expect(grid.doorsConnected(), "\(label): \(room.name) cut in two")
                for p in here where role(p.itemId, items) == .bed {
                    let r = rect(p, items)
                    let sides = [r.center + r.axes.x * (r.halfWidth + 0.35), r.center - r.axes.x * (r.halfWidth + 0.35)]
                    #expect(grid.reachable(sides).contains(true), "\(label): can't get to the bed in \(room.name)")
                }
            }
        }
        // By function, the bedroom keeps a 0.8 m path from the door to the bed.
        for (_, plan) in Self.plans {
            let o = LayoutSolver(plan: plan).solve(Self.livingSet, style: .byFunction)
            let bed = o.placements.first { $0.itemId == 11 }!
            let room = plan.room(named: bed.room)!
            let here = o.placements.filter { $0.room == room.name && $0.onTopOf == nil && $0.itemId != 5 }.map { rect($0, Self.livingSet) }
            let r = rect(bed, Self.livingSet)
            let grid = WalkGrid(room: room, plan: plan, furniture: here, radius: 0.4)
            #expect(grid.reachable([r.center + r.axes.x * (r.halfWidth + 0.45), r.center - r.axes.x * (r.halfWidth + 0.45)], tolerance: 0.45).contains(true))
        }
    }

    // MARK: Living, dining, office

    @Test func sofaFacesTheTVAtViewingDistance() {
        for (pn, plan) in Self.plans {
            for (items, sofaId, tvId) in [(Self.livingSet, UInt64(1), UInt64(7)), (LayoutFixtures.scan9, 913, 909)] {
                let o = LayoutSolver(plan: plan).solve(items, style: .byFunction)
                let sofa = rect(o.placements.first { $0.itemId == sofaId }!, items)
                let tv = rect(o.placements.first { $0.itemId == tvId }!, items)
                #expect(plan.room(at: sofa.center)?.kind == .living, "\(pn): sofa in the living room")
                let v = tv.center - sofa.center
                #expect(sofa.axes.z.dot(v * (1 / v.length)) > 0.95, "\(pn): sofa faces the TV")
                #expect(tv.axes.z.dot(sofa.axes.z) < -0.95, "\(pn): TV faces the sofa")
                let screen = items.first { DesignRole.of($0) == .tv }!.widthM
                let diag = screen / 0.87
                let d = v.dot(sofa.axes.z) - sofa.halfDepth - tv.halfDepth
                #expect(d >= 1.3 && d <= 2.5 * diag + 0.05, "\(pn): \(d) m from a \(diag) m screen")
            }
        }
    }

    @Test func coffeeTableChairsLampAndRugMakeAGroup() {
        let items = Self.livingSet
        for (pn, plan) in Self.plans {
            let o = LayoutSolver(plan: plan).solve(items, style: .byFunction)
            let at = Dictionary(uniqueKeysWithValues: o.placements.map { ($0.itemId, $0) })
            let sofa = rect(at[1]!, items), ct = rect(at[2]!, items)
            let front = (ct.center - sofa.center).dot(sofa.axes.z) - sofa.halfDepth - ct.halfDepth
            #expect(front >= 0.35 - 1e-6 && front <= 0.45 + 1e-6, "\(pn): coffee table \(front) m from the sofa")
            // Both chairs in the living room; at least one pulled up to the coffee table facing it
            // (a 3.6 m deep room can't fit one at each end).
            var grouped = 0
            for id: UInt64 in [3, 4] {
                guard let p = at[id] else { Issue.record("\(pn): chair \(id) not placed"); continue }
                let c = rect(p, items)
                #expect(p.room == at[1]!.room)
                let toward = ct.center - c.center
                if toward.length < 2.5 && c.axes.z.dot(toward * (1 / toward.length)) > 0.5 { grouped += 1 }
            }
            #expect(grouped >= 1, "\(pn): no chair in the conversation group")
            let lamp = rect(at[6]!, items)
            #expect(gap(lamp, sofa) < 0.3 || gap(lamp, rect(at[3]!, items)) < 0.3, "\(pn): floor lamp beside the seating")
            let rug = rect(at[5]!, items)
            #expect((rug.center - ct.center).length < 0.3, "\(pn): rug under the coffee table")
        }
    }

    @Test func chairsAtTheirTableOrDeskFacingIt() {
        for (pn, plan) in Self.plans {
            for (items, tableRole, chairRole) in [(LayoutFixtures.scan9, DesignRole.diningTable, DesignRole.diningChair),
                                                  (Self.livingSet, .desk, .deskChair)] {
                let o = LayoutSolver(plan: plan).solve(items, style: .byFunction)
                let table = o.placements.first { role($0.itemId, items) == tableRole }!
                let t = rect(table, items)
                let chairs = o.placements.filter { role($0.itemId, items) == chairRole }
                #expect(!chairs.isEmpty)
                for ch in chairs {
                    let c = rect(ch, items)
                    #expect(ch.room == table.room)
                    #expect(gap(c, t) <= 0.6, "\(pn): chair \(ch.itemId) \(gap(c, t)) m from its \(tableRole)")
                    let toward = t.center - c.center
                    #expect(c.axes.z.dot(toward * (1 / toward.length)) > 0.7, "\(pn): chair \(ch.itemId) faces the \(tableRole)")
                }
            }
        }
    }

    @Test func bathroomFixturesInBathrooms() {
        each { label, plan, items, option in
            for p in option.placements where role(p.itemId, items).isBath {
                #expect(plan.room(named: p.room)?.kind == .bathroom, "\(label): \(p.itemId) in \(p.room)")
            }
        }
        #expect(DesignRole.of(LayoutItem(id: 1, name: "Toilet", category: "toilet", widthM: 0.4, depthM: 0.7, heightM: 0.75)) == .toilet)
        #expect(DesignRole.of(LayoutItem(id: 1, name: "Bathroom sink", category: "storage", widthM: 0.6, depthM: 0.5, heightM: 0.85)) == .sink)
        #expect(DesignRole.of(LayoutItem(id: 1, name: "Kitchen sink", category: "sink", widthM: 0.8, depthM: 0.6, heightM: 0.9)) == .kitchen)
        #expect(DesignRole.of(LayoutItem(id: 1, name: "Bathtub", category: "bathtub", widthM: 0.75, depthM: 1.6, heightM: 0.55)) == .bathtub)
    }

    @Test func propsSitOnTheirGroup() {
        let items = LayoutFixtures.scan9
        for (pn, plan) in Self.plans {
            let o = LayoutSolver(plan: plan).solve(items, style: .byFunction)
            let after = PropPlacer(plan: plan).place(o.placements, items: items)
            let lamp = after.first { $0.itemId == 908 }!
            let parent = lamp.onTopOf.map { role($0, items) }
            #expect(parent == .nightstand, "\(pn): the table lamp is on \(String(describing: parent))")
        }
    }

    @Test func stylesStayDistinctAndCompactUsesFewerRooms() {
        for (_, plan) in Self.plans {
            let options = LayoutSolver(plan: plan).solveAll(Self.livingSet)
            #expect(Set(options.map(\.placements)).count == 3)
        }
        let solver = LayoutSolver(plan: LayoutFixtures.estimated3b2b)
        let items = DemoFixtures.inventory(owner: "me").items.map(LayoutItem.init)
        #expect(Set(solver.solve(items, style: .compact).placements.map(\.room)).count < Set(solver.solve(items, style: .open).placements.map(\.room)).count)
    }

    @Test func aScannedRoomTakesAllItsBeds() {
        // One room (a scan's own dollhouse): the bunk room keeps both beds.
        let room = FloorPlan(rooms: [.rectangle("Bunk room", x: 0, y: 0, width: 4, depth: 3.6)],
                             doors: [WallOpening(from: PlanPoint(0.4, 3.6), to: PlanPoint(1.3, 3.6))])
        let beds = Array(LayoutFixtures.scan9.prefix(2))
        let o = LayoutSolver(plan: room).solve(beds, style: .byFunction)
        #expect(o.unplaced.isEmpty && o.placements.count == 2)
    }
}

@Suite struct MovingRoomsTests {
    static let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    func snapshot() -> (SyncSnapshot, [Item]) {
        var s = SyncSnapshot(me: "me")
        s.rooms = [Room(id: 1, owner: "me", name: "Bedroom"), Room(id: 2, owner: "me", name: "Bedroom"),
                   Room(id: 3, owner: "me", name: "Bunk room"), Room(id: 4, owner: "me", name: " bedroom ")]
        s.scans = [Scan(id: 11, owner: "me", roomId: 1, createdAt: Self.t0), Scan(id: 12, owner: "me", roomId: 2, createdAt: Self.t0 + 3600),
                   Scan(id: 13, owner: "me", roomId: 3, createdAt: Self.t0 + 7200), Scan(id: 14, owner: "me", roomId: 4, createdAt: Self.t0 + 60)]
        func bed(_ id: UInt64, _ room: UInt64, _ w: Double) -> Item {
            Item(id: id, owner: "me", roomId: room, name: "Bed", category: "bed", widthM: w, heightM: 0.57, depthM: 2.08, disposition: .keep)
        }
        let items = [bed(101, 1, 1.56), bed(102, 2, 1.58), bed(103, 3, 1.08), bed(104, 4, 1.6),
                     Item(id: 105, owner: "me", roomId: 1, name: "Lamp", category: "lamp", widthM: 0.3, heightM: 0.45, depthM: 0.3, disposition: .keep)]
        return (s, items)
    }

    @Test func newestScanOfEachNameMovesByDefault() {
        let (s, items) = snapshot()
        let choices = MovingRooms.choices(s, keptItems: items, overrides: [:])
        #expect(choices.map(\.id) == [3, 2, 4, 1]) // newest scan first
        #expect(choices.filter(\.included).map(\.id) == [3, 2])
        #expect(MovingRooms.items(items, choices: choices).map(\.id).sorted() == [102, 103])
    }

    @Test func togglingARoomInAndOutPersists() {
        let (s, items) = snapshot()
        var overrides: [UInt64: Bool] = [:]
        var choices = MovingRooms.choices(s, keptItems: items, overrides: overrides)
        overrides = MovingRooms.toggle(1, in: choices, overrides: overrides)
        #expect(overrides == [1: true])
        #expect(MovingRooms.decode(MovingRooms.encode(overrides)) == overrides)
        choices = MovingRooms.choices(s, keptItems: items, overrides: overrides)
        // Room 1's bed is a re-scan of room 2's (same name, same size): dropped; its lamp stays.
        #expect(MovingRooms.items(items, choices: choices).map(\.id).sorted() == [102, 103, 105])
        overrides = MovingRooms.toggle(1, in: choices, overrides: overrides)
        #expect(overrides.isEmpty) // back to the default
        overrides = MovingRooms.toggle(3, in: choices, overrides: overrides)
        #expect(MovingRooms.encode(overrides) == ["-3"])
        #expect(MovingRooms.decode(["+7", "-8", "junk", "9"]) == [7: true, 8: false])
    }

    @Test func selectAllNoneAndSummary() {
        var (s, items) = snapshot()
        s.rooms.append(Room(id: 5, owner: "me", name: "Garage")) // nothing kept there
        let choices = MovingRooms.choices(s, keptItems: items, overrides: [:])
        #expect(choices.count == 5)
        #expect(choices.contains { $0.id == 5 && $0.included })
        let none = MovingRooms.setAll(false, in: choices)
        let off = MovingRooms.choices(s, keptItems: items, overrides: none)
        #expect(off.allSatisfy { !$0.included })
        #expect(MovingRooms.items(items, choices: off).isEmpty)
        #expect(MovingRooms.summary(off, items: 0) == "No rooms selected")
        let all = MovingRooms.choices(s, keptItems: items, overrides: MovingRooms.setAll(true, in: choices))
        #expect(all.allSatisfy { $0.included })
        #expect(MovingRooms.summary(choices, items: 2) == "Moving from 3 rooms · 2 items")
        #expect(MovingRooms.pruned([1: true, 99: false], rooms: s.rooms) == [1: true])
    }

    @Test func differentRoomsKeepTheirTwinBeds() {
        let a = Item(id: 1, owner: "me", roomId: 1, name: "Twin bed", category: "bed", widthM: 1.0, heightM: 0.5, depthM: 2.0, disposition: .keep)
        var b = a
        b.id = 2; b.roomId = 2
        let names: [UInt64: String] = [1: "kids room", 2: "guest room"]
        #expect(MovingRooms.dedupe([a, b], roomName: { names[$0] }).count == 2)
        #expect(MovingRooms.dedupe([a, b], roomName: { _ in "bedroom" }).count == 1)
        var c = b
        c.widthM = 1.6 // a different bed
        #expect(MovingRooms.dedupe([a, c], roomName: { _ in "bedroom" }).count == 2)
    }
}
