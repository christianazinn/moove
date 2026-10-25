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

    /// One letter for the label: S, M, L, D (dish pack), P (picture), W (wardrobe), T (tote).
    public var glyph: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .dishPack: return "D"
        case .picture: return "P"
        case .wardrobe: return "W"
        case .tote: return "T"
        }
    }

    public var volumeM3: Double {
        let d = dimsM
        return d.w * d.h * d.d
    }

    /// Litres you can actually fill once things are wrapped (about 70%).
    var usableLitres: Double { volumeM3 * 1000 * PackingPlanner.packingEfficiency }

    /// Place in the nesting chain small < medium < large < dish pack < wardrobe, where each size
    /// holds the one before it in every dimension; nil for picture boxes and totes.
    var nestRank: Int? {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .large: return 2
        case .dishPack: return 3
        case .wardrobe: return 4
        case .picture, .tote: return nil
        }
    }

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
    /// Why it's in this box ("Kitchen → Box 7 · fragile, wrapped"); nil for typical contents.
    public var reason: String?
    /// A voxel builder category for a generic thumbnail ("books", "kitchenware", "clothes").
    public var category: String

    public init(name: String, quantity: Int, itemId: UInt64? = nil, reason: String? = nil, category: String = "decor") {
        self.name = name
        self.quantity = quantity
        self.itemId = itemId
        self.reason = reason
        self.category = category
    }

    /// An estimate: typical everyday contents Moove added, not something the user scanned.
    public var estimated: Bool { itemId == nil }

    /// A generic voxel model for this line (books, a stack of plates, folded clothes), for lines
    /// without a scanned item to draw.
    public var voxelSpec: VoxelItemSpec {
        VoxelItemSpec(category: category, name: name, widthM: 0, depthM: 0, heightM: 0, id: "box-line-\(name)")
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
    /// What it holds, as kind keys ("books", "kitchen", "openFirst"), for an icon.
    public var kinds: [String]
    /// Why these things share this box ("Fragile: wrapped, under 8 kg").
    public var reason: String
    /// Where it goes and how Moove knows ("Goes to Bedroom 2 (from your saved layout)").
    public var roomReason: String

    /// Only typical everyday contents (an estimate for the truck), nothing from the scan.
    /// The open-first tote and keep-with-you box count too; the Pack screen keeps those apart.
    public var estimatedOnly: Bool { !contents.isEmpty && contents.allSatisfy(\.estimated) }
    /// How many lines came from the scan.
    public var scannedLineCount: Int { contents.filter { !$0.estimated }.count }

    public init(id: Int, size: BoxSize, room: String, title: String, contents: [BoxContent], weightKg: Double,
                fragile: Bool = false, openFirst: Bool = false, keepWithYou: Bool = false, thisSideUp: Bool = false,
                kinds: [String] = [], reason: String = "", roomReason: String = "") {
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
        self.kinds = kinds
        self.reason = reason
        self.roomReason = roomReason
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
    /// Why it isn't boxed ("Too big for a box: legs off, wrap in blankets").
    public var reason: String
    /// Where it goes and how Moove knows.
    public var roomReason: String

    public init(id: UInt64, name: String, room: String, steps: [String], reason: String = "", roomReason: String = "") {
        self.id = id
        self.name = name
        self.room = room
        self.steps = steps
        self.reason = reason
        self.roomReason = roomReason
    }
}

/// Something bought for the new home (Sell & Buy): a purchased shopping item and its chosen deal.
public struct BoughtPiece: Sendable, Hashable {
    public var item: ShoppingItem
    public var deal: Deal?

    public init(item: ShoppingItem, deal: Deal? = nil) {
        self.item = item
        self.deal = deal
    }
}

/// A bought piece that ships straight to the new home, so nothing to pack.
public struct DeliveredItem: Sendable, Hashable, Identifiable {
    /// The shopping item's id.
    public var id: UInt64
    /// The shopping item's name ("Mattress").
    public var name: String
    /// The chosen deal's title, or the name without one.
    public var title: String
    /// Who sells it ("ikea", "Facebook Marketplace · Dana"), or "" without a deal.
    public var seller: String
    public var room: String
    public var reason: String
    public var roomReason: String
    /// The same voxel model the new-home layout draws for it.
    public var voxelSpec: VoxelItemSpec
    /// What the chosen deal cost, nil without one.
    public var priceCents: Int64?

    public init(id: UInt64, name: String, title: String, seller: String, room: String, reason: String, roomReason: String,
                voxelSpec: VoxelItemSpec, priceCents: Int64? = nil) {
        self.priceCents = priceCents
        self.id = id
        self.name = name
        self.title = title
        self.seller = seller
        self.room = room
        self.reason = reason
        self.roomReason = roomReason
        self.voxelSpec = voxelSpec
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
    /// Bought pieces delivered to the new home: not boxed, not on the truck.
    public var delivered: [DeliveredItem]

    public init(boxes: [MovingBox], furniture: [FurnitureNote], supplies: [SupplyLine], truck: TruckEstimate,
                schedule: [PackingStep], delivered: [DeliveredItem] = []) {
        self.boxes = boxes
        self.furniture = furniture
        self.supplies = supplies
        self.truck = truck
        self.schedule = schedule
        self.delivered = delivered
    }

    public static let empty = PackingPlan(boxes: [], furniture: [], supplies: [], truck: .zero, schedule: [])
}
