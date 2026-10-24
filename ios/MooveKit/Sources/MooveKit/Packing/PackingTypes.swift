import Foundation

// Public result types for the packing plan (#19). Pure values: PackingPlanner
// builds them from the inventory, and the Logistics screen only renders them.

/// Standard moving carton sizes (U-Haul / Home Depot style).
public enum BoxSize: String, Sendable, CaseIterable {
    case small, medium, large, dishPack, picture, wardrobe, tote

    public var label: String {
        switch self {
        case .small: return "Small box"
        case .medium: return "Medium box"
        case .large: return "Large box"
        case .dishPack: return "Dish pack"
        case .picture: return "Picture box"
        case .wardrobe: return "Wardrobe box"
        case .tote: return "Clear tote"
        }
    }

    /// Outside dimensions in meters.
    public var dimsM: (w: Double, h: Double, d: Double) {
        switch self {
        case .small: return (0.41, 0.32, 0.32)
        case .medium: return (0.46, 0.41, 0.46)
        case .large: return (0.46, 0.61, 0.46)
        case .dishPack: return (0.46, 0.71, 0.46)
        case .picture: return (1.22, 0.91, 0.10)
        case .wardrobe: return (0.61, 1.22, 0.53)
        case .tote: return (0.60, 0.35, 0.40)
        }
    }

    /// The most a packed box of this size should weigh. Never over 20 kg,
    /// so one person can carry it.
    public var maxKg: Double {
        switch self {
        case .small, .medium, .dishPack: return 20
        case .large, .wardrobe, .tote: return 18
        case .picture: return 12
        }
    }

    public var volumeM3: Double {
        let d = dimsM
        return d.w * d.h * d.d
    }

    /// Litres you can actually fill once things are wrapped (about 70%).
    var usableLitres: Double { volumeM3 * 1000 * PackingPlanner.packingEfficiency }

    /// Dimensions sorted largest first, for "does it fit" checks.
    var sortedDims: [Double] {
        let d = dimsM
        return [d.w, d.h, d.d].sorted(by: >)
    }
}

/// One line on a box's contents list.
public struct BoxContent: Sendable, Hashable {
    public var name: String
    public var quantity: Int
    /// The inventory item this came from; nil for typical contents Moove adds
    /// (the UI labels those "typical for a bedroom" and so on).
    public var itemId: UInt64?

    public init(name: String, quantity: Int, itemId: UInt64? = nil) {
        self.name = name
        self.quantity = quantity
        self.itemId = itemId
    }
}

public struct MovingBox: Sendable, Hashable, Identifiable {
    /// Box number printed on the label, 1-based, in packing order.
    public var id: Int
    public var size: BoxSize
    /// Destination room ("Bedroom"), or "Open first" / "Keep with you".
    public var room: String
    /// "Bedroom · decor and lamps"
    public var title: String
    public var contents: [BoxContent]
    public var weightKg: Double
    public var fragile: Bool
    public var openFirst: Bool
    public var keepWithYou: Bool
    public var thisSideUp: Bool

    public init(id: Int, size: BoxSize, room: String, title: String, contents: [BoxContent], weightKg: Double,
                fragile: Bool = false, openFirst: Bool = false, keepWithYou: Bool = false, thisSideUp: Bool = false) {
        self.id = id
        self.size = size
        self.room = room
        self.title = title
        self.contents = contents
        self.weightKg = weightKg
        self.fragile = fragile
        self.openFirst = openFirst
        self.keepWithYou = keepWithYou
        self.thisSideUp = thisSideUp
    }
}

/// Something too big for a box: how to take it apart and wrap it.
public struct FurnitureNote: Sendable, Hashable, Identifiable {
    /// The item's id.
    public var id: UInt64
    public var name: String
    /// Destination room, or "Keep with you" for sentimental pieces that ride in the car.
    public var room: String
    public var steps: [String]

    public init(id: UInt64, name: String, room: String, steps: [String]) {
        self.id = id
        self.name = name
        self.room = room
        self.steps = steps
    }
}

public struct SupplyLine: Sendable, Hashable {
    public var name: String
    public var quantity: Int

    public init(name: String, quantity: Int) {
        self.name = name
        self.quantity = quantity
    }
}

public enum TruckSize: String, Sendable, CaseIterable {
    case cargoVan, ft10, ft15, ft20, ft26

    public var label: String {
        switch self {
        case .cargoVan: return "Cargo van"
        case .ft10: return "10 ft truck"
        case .ft15: return "15 ft truck"
        case .ft20: return "20 ft truck"
        case .ft26: return "26 ft truck"
        }
    }

    /// Cargo space in cubic meters.
    public var capacityM3: Double {
        switch self {
        case .cargoVan: return 7
        case .ft10: return 11
        case .ft15: return 21
        case .ft20: return 28
        case .ft26: return 45
        }
    }
}

public struct TruckEstimate: Sendable, Hashable {
    /// Truck space needed, after packing inefficiency.
    public var loadM3: Double
    public var truck: TruckSize
    public var trucks: Int
    public var moverHours: Double
    public var movers: Int
    public var costLowCents: Int64
    public var costHighCents: Int64

    public init(loadM3: Double, truck: TruckSize, trucks: Int, moverHours: Double, movers: Int,
                costLowCents: Int64, costHighCents: Int64) {
        self.loadM3 = loadM3
        self.truck = truck
        self.trucks = trucks
        self.moverHours = moverHours
        self.movers = movers
        self.costLowCents = costLowCents
        self.costHighCents = costHighCents
    }

    /// Nothing to move.
    public static let zero = TruckEstimate(loadM3: 0, truck: .cargoVan, trucks: 0, moverHours: 0, movers: 0,
                                           costLowCents: 0, costHighCents: 0)
}

public struct PackingStep: Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var daysBeforeMove: Int
    public var boxIds: [Int]

    public init(id: Int, title: String, daysBeforeMove: Int, boxIds: [Int]) {
        self.id = id
        self.title = title
        self.daysBeforeMove = daysBeforeMove
        self.boxIds = boxIds
    }
}

public struct PackingPlan: Sendable, Hashable {
    public var boxes: [MovingBox]
    public var furniture: [FurnitureNote]
    public var supplies: [SupplyLine]
    public var truck: TruckEstimate
    public var schedule: [PackingStep]

    public init(boxes: [MovingBox], furniture: [FurnitureNote], supplies: [SupplyLine], truck: TruckEstimate,
                schedule: [PackingStep]) {
        self.boxes = boxes
        self.furniture = furniture
        self.supplies = supplies
        self.truck = truck
        self.schedule = schedule
    }

    public static let empty = PackingPlan(boxes: [], furniture: [], supplies: [], truck: .zero, schedule: [])
}
