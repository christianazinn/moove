import Foundation

/// Where the new-home fly-in starts each piece: its scanned spot in the old room, with that
/// room's dollhouse footprint moved to just left of the new house (so it's in view), instead
/// of the generic pile. Items with no scanned position aren't in the result; the caller piles them.
public struct FlyInStarts: Sendable, Hashable {
    /// One old room: its dollhouse plan (`RoomGeometry.dollhouse`) and the scanned placements in it.
    public struct OldRoom: Sendable, Hashable {
        public var plan: FloorPlan
        public var placements: [Placement]

        public init(plan: FloorPlan, placements: [Placement]) {
            self.plan = plan
            self.placements = placements
        }
    }

    /// Start placement per item id, in new-home plan coordinates (rotation and height as scanned).
    public var placements: [UInt64: Placement]
    /// The old rooms' plans, moved to where the starts are, for drawing their footprints.
    public var rooms: [FloorPlan]

    public init(placements: [UInt64: Placement] = [:], rooms: [FloorPlan] = []) {
        self.placements = placements
        self.rooms = rooms
    }

    /// Gap between the old room(s) and the new house's left edge.
    public static let gapM = 1.0
    /// Gap between old rooms stacked beside each other.
    public static let stackGapM = 0.8

    /// Bounds of every old room as moved, nil if there are none.
    public var bounds: PlanBounds? {
        let points = rooms.flatMap { $0.rooms.flatMap(\.polygon) }
        return points.isEmpty ? nil : PlanBounds(points)
    }

    /// One old room's starts beside the new house's bounds `beside`.
    public static func compute(oldPlan: FloorPlan, oldPlacements: [Placement], beside: PlanBounds) -> [UInt64: Placement] {
        layout(oldRooms: [OldRoom(plan: oldPlan, placements: oldPlacements)], beside: beside).placements
    }

    /// Several old rooms, stacked front to back (plan y) and centered on the house's depth, each
    /// right-aligned `gapM` left of `beside.minX`. Rooms with no plan outline or no placements are
    /// skipped; an item placed in two rooms keeps its first start.
    public static func layout(oldRooms: [OldRoom], beside b: PlanBounds) -> FlyInStarts {
        let rooms = oldRooms.filter { !$0.placements.isEmpty && !$0.plan.rooms.flatMap(\.polygon).isEmpty }
        guard !rooms.isEmpty else { return FlyInStarts() }
        let depths = rooms.map { $0.plan.bounds.depth }
        let total = depths.reduce(0, +) + stackGapM * Double(rooms.count - 1)
        var cursorY = b.center.y - total / 2
        var out = FlyInStarts()
        for (room, depth) in zip(rooms, depths) {
            let rb = room.plan.bounds
            let offset = PlanPoint(b.minX - gapM - rb.maxX, cursorY - rb.minY)
            out.rooms.append(room.plan.translated(by: offset))
            for p in room.placements where out.placements[p.itemId] == nil {
                var start = p
                start.x = p.x + offset.x
                start.y = p.y + offset.y
                out.placements[p.itemId] = start
            }
            cursorY += depth + stackGapM
        }
        return out
    }
}

extension FloorPlan {
    /// The same plan moved by `offset` (rooms, doors and windows).
    public func translated(by offset: PlanPoint) -> FloorPlan {
        func move(_ o: WallOpening) -> WallOpening { WallOpening(from: o.from + offset, to: o.to + offset) }
        return FloorPlan(
            rooms: rooms.map { FloorPlanRoom(name: $0.name, kind: $0.kind, polygon: $0.polygon.map { $0 + offset }) },
            doors: doors.map(move), windows: windows.map(move), wallHeightM: wallHeightM
        )
    }
}
