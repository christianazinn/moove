import Foundation

// Mirrors of the `newHome` and `layouts` tables (docs/data-model.md).

public enum NewHomeSource: String, Codable, Sendable, CaseIterable {
    case demo, zillow, manual
}

public struct NewHome: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var name: String
    public var source: NewHomeSource
    public var floorPlanJson: String
    public var createdAt: Date

    public init(id: UInt64, owner: IdentityHex, name: String, source: NewHomeSource, floorPlanJson: String, createdAt: Date = .now) {
        self.id = id
        self.owner = owner
        self.name = name
        self.source = source
        self.floorPlanJson = floorPlanJson
        self.createdAt = createdAt
    }

    /// Nil if the stored JSON doesn't parse (e.g. a bad Zillow import).
    public var floorPlan: FloorPlan? { try? FloorPlan(json: floorPlanJson) }
}

/// Where one item sits in the new home. `x`/`y` are plan meters (world x/z), the item's center.
public struct Placement: Codable, Sendable, Hashable {
    public var itemId: UInt64
    public var room: String
    public var x: Double
    public var y: Double
    public var rotationDeg: Double

    public init(itemId: UInt64, room: String, x: Double, y: Double, rotationDeg: Double = 0) {
        self.itemId = itemId
        self.room = room
        self.x = x
        self.y = y
        self.rotationDeg = rotationDeg
    }
}

public struct Layout: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var newHomeId: UInt64
    public var name: String
    public var placementsJson: String
    public var createdAt: Date

    public init(id: UInt64, owner: IdentityHex, newHomeId: UInt64, name: String, placementsJson: String, createdAt: Date = .now) {
        self.id = id
        self.owner = owner
        self.newHomeId = newHomeId
        self.name = name
        self.placementsJson = placementsJson
        self.createdAt = createdAt
    }

    public var placements: [Placement] {
        (try? JSONDecoder().decode([Placement].self, from: Data(placementsJson.utf8))) ?? []
    }

    public static func encode(_ placements: [Placement]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(placements)) ?? Data("[]".utf8), as: UTF8.self)
    }
}
