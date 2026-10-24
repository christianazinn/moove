import Foundation

/// One rectangle the user typed in on the manual-entry screen.
public struct ManualRoom: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: RoomKind
    public var widthM: Double
    public var depthM: Double

    public init(id: UUID = UUID(), name: String, kind: RoomKind, widthM: Double, depthM: Double) {
        self.id = id
        self.name = name
        self.kind = kind
        self.widthM = widthM
        self.depthM = depthM
    }
}

/// Turns typed-in room sizes into a plausible plan: rooms in two rows facing a
/// central hallway, each with a door onto it. Not architecture, just enough
/// for the 3D view and the layout solver.
public enum ManualFloorPlan {
    public static let hallwayDepthM = 1.2
    public static let doorWidthM = 0.9

    public static func build(_ input: [ManualRoom]) -> FloorPlan {
        let rooms = input.filter { $0.widthM > 0 && $0.depthM > 0 }
        guard !rooms.isEmpty else { return FloorPlan(rooms: []) }

        // Balance the two rows by total width, keeping the user's order within each row.
        var front: [ManualRoom] = [], back: [ManualRoom] = []
        var frontW = 0.0, backW = 0.0
        for r in rooms {
            if frontW <= backW { front.append(r); frontW += r.widthM } else { back.append(r); backW += r.widthM }
        }
        let frontDepth = front.map(\.depthM).max() ?? 0
        let hallY = frontDepth
        let backY = hallY + hallwayDepthM
        let length = max(frontW, backW)

        var planRooms: [FloorPlanRoom] = []
        var doors: [WallOpening] = []
        var names = NameDeduper()

        // Front row hangs down from the hallway so every room's hallway wall is flush.
        var x = 0.0
        for r in front {
            let y = hallY - r.depthM
            planRooms.append(.rectangle(names.unique(r.name), kind: r.kind, x: x, y: y, width: r.widthM, depth: r.depthM))
            doors.append(door(centerX: x + r.widthM / 2, y: hallY, roomWidth: r.widthM))
            x += r.widthM
        }
        x = 0
        for r in back {
            planRooms.append(.rectangle(names.unique(r.name), kind: r.kind, x: x, y: backY, width: r.widthM, depth: r.depthM))
            doors.append(door(centerX: x + r.widthM / 2, y: backY, roomWidth: r.widthM))
            x += r.widthM
        }
        if !back.isEmpty {
            planRooms.append(.rectangle(names.unique("Hallway"), kind: .hallway, x: 0, y: hallY, width: length, depth: hallwayDepthM))
        }
        return FloorPlan(rooms: planRooms, doors: back.isEmpty ? [] : doors)
    }

    private static func door(centerX: Double, y: Double, roomWidth: Double) -> WallOpening {
        let w = min(doorWidthM, roomWidth * 0.6)
        return WallOpening(from: PlanPoint(centerX - w / 2, y), to: PlanPoint(centerX + w / 2, y))
    }

    /// A reasonable starting list for the editor.
    public static let starter: [ManualRoom] = [
        ManualRoom(name: "Living room", kind: .living, widthM: 5, depthM: 4),
        ManualRoom(name: "Bedroom", kind: .bedroom, widthM: 4, depthM: 3.5),
        ManualRoom(name: "Kitchen", kind: .kitchen, widthM: 3.5, depthM: 3),
        ManualRoom(name: "Bathroom", kind: .bathroom, widthM: 2.5, depthM: 2),
    ]
}

/// Room names are the join key for placements, so they must be unique.
private struct NameDeduper {
    private var counts: [String: Int] = [:]

    mutating func unique(_ raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespaces).isEmpty ? "Room" : raw.trimmingCharacters(in: .whitespaces)
        let n = (counts[base] ?? 0) + 1
        counts[base] = n
        return n == 1 ? base : "\(base) \(n)"
    }
}
