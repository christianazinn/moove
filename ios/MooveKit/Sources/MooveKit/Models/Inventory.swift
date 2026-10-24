import Foundation

// Plain mirrors of the SpacetimeDB tables in docs/data-model.md.
// The app maps generated SDK rows into these, so screens and tests never
// depend on the SDK. Identities are hex strings here.

public typealias IdentityHex = String

public enum Home: String, Codable, Sendable, CaseIterable {
    case old, new
}

public enum Disposition: String, Codable, Sendable, CaseIterable {
    case keep, sell, donate, trash, undecided
}

public enum DispositionSource: String, Codable, Sendable {
    case auto, user
}

public struct User: Codable, Sendable, Hashable, Identifiable {
    public var identity: IdentityHex
    public var auth0Sub: String?
    public var name: String
    public var email: String?
    public var approvalThresholdCents: Int64

    public var id: IdentityHex { identity }

    public init(identity: IdentityHex, auth0Sub: String? = nil, name: String, email: String? = nil, approvalThresholdCents: Int64 = 20_000) {
        self.identity = identity
        self.auth0Sub = auth0Sub
        self.name = name
        self.email = email
        self.approvalThresholdCents = approvalThresholdCents
    }
}

public struct Room: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var name: String
    public var home: Home

    public init(id: UInt64, owner: IdentityHex, name: String, home: Home = .old) {
        self.id = id
        self.owner = owner
        self.name = name
        self.home = home
    }
}

public struct Scan: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var roomId: UInt64
    public var usdzUrl: String?
    public var capturedRoomJsonUrl: String?
    public var createdAt: Date

    public init(id: UInt64, owner: IdentityHex, roomId: UInt64, usdzUrl: String? = nil, capturedRoomJsonUrl: String? = nil, createdAt: Date = .now) {
        self.id = id
        self.owner = owner
        self.roomId = roomId
        self.usdzUrl = usdzUrl
        self.capturedRoomJsonUrl = capturedRoomJsonUrl
        self.createdAt = createdAt
    }
}

public struct Item: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var owner: IdentityHex
    public var roomId: UInt64
    public var scanObjectId: String?
    public var name: String
    public var category: String
    public var widthM: Double
    public var heightM: Double
    public var depthM: Double
    public var photoUrls: [String]
    public var material: String?
    public var brand: String?
    /// 1 (broken) to 5 (like new), set by the vision agent.
    public var condition: Int?
    public var estValueCents: Int64?
    public var disposition: Disposition
    public var dispositionSource: DispositionSource
    public var dispositionReason: String?
    public var fragile: Bool
    public var maybeSentimental: Bool
    public var updatedAt: Date
    /// RoomPlan (iOS 17) object attributes, type-prefixed raw values like "ChairType.swivel",
    /// "ChairLegType.star", "TableShapeType.circularElliptic" (`attributes_json`, #110). [] if none.
    public var attributes: [String]
    /// Main / accent colors measured from scan photos (`colors_json`, #110). nil until sampled.
    public var colors: ItemColors?

    public init(
        id: UInt64, owner: IdentityHex, roomId: UInt64, scanObjectId: String? = nil,
        name: String, category: String, widthM: Double, heightM: Double, depthM: Double,
        photoUrls: [String] = [], material: String? = nil, brand: String? = nil, condition: Int? = nil,
        estValueCents: Int64? = nil, disposition: Disposition = .undecided, dispositionSource: DispositionSource = .auto,
        dispositionReason: String? = nil, fragile: Bool = false, maybeSentimental: Bool = false, updatedAt: Date = .now,
        attributes: [String] = [], colors: ItemColors? = nil
    ) {
        self.id = id
        self.owner = owner
        self.roomId = roomId
        self.scanObjectId = scanObjectId
        self.name = name
        self.category = category
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
        self.photoUrls = photoUrls
        self.material = material
        self.brand = brand
        self.condition = condition
        self.estValueCents = estValueCents
        self.disposition = disposition
        self.dispositionSource = dispositionSource
        self.dispositionReason = dispositionReason
        self.fragile = fragile
        self.maybeSentimental = maybeSentimental
        self.updatedAt = updatedAt
        self.attributes = attributes
        self.colors = colors
    }

    public var volumeM3: Double { widthM * heightM * depthM }

    /// Sentimental or undecided items go in the review screen's "Needs you" section.
    public var needsUser: Bool { maybeSentimental || disposition == .undecided }

    /// Parses `attributes_json` (a JSON array of strings). [] for '' or anything malformed;
    /// non-string entries are skipped.
    public static func attributes(json: String) -> [String] {
        guard let array = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any] else { return [] }
        return array.compactMap { $0 as? String }
    }
}

/// An item's measured colors (`item.colors_json`, #110): `{"primary":"#RRGGBB","secondary":"#RRGGBB"}`,
/// either key optional. Colors are packed 0xRRGGBB like `VoxelColor`.
public struct ItemColors: Codable, Sendable, Hashable {
    public var primary: VoxelColor?
    public var secondary: VoxelColor?

    public init(primary: VoxelColor? = nil, secondary: VoxelColor? = nil) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Parses `colors_json`. nil for '' (unknown), bad JSON, or no valid color; a bad
    /// entry is dropped rather than failing the whole value.
    public init?(json: String) {
        guard !json.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        let primary = (object["primary"] as? String).flatMap(Self.color(hex:))
        let secondary = (object["secondary"] as? String).flatMap(Self.color(hex:))
        guard primary != nil || secondary != nil else { return nil }
        self.init(primary: primary, secondary: secondary)
    }

    /// The `colors_json` wire form, keys in a fixed order; '' when both colors are unknown.
    public var json: String {
        let parts = [("primary", primary), ("secondary", secondary)].compactMap { key, c in
            c.map { "\"\(key)\":\"\(Self.hex($0))\"" }
        }
        return parts.isEmpty ? "" : "{" + parts.joined(separator: ",") + "}"
    }

    /// "#RRGGBB" (case-insensitive, '#' required) → 0xRRGGBB; nil for anything else.
    public static func color(hex: String) -> VoxelColor? {
        guard hex.count == 7, hex.first == "#" else { return nil }
        let digits = hex.dropFirst()
        guard digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        return value
    }

    /// The module's `colorsJsonOf` (`set_item_colors`): '' stays '' (clears); otherwise a JSON
    /// object whose only keys are `primary` / `secondary`, each a "#RRGGBB" string, stored
    /// uppercase. nil when the module would reject it.
    public static func normalizedJson(_ json: String) -> String? {
        if json.isEmpty { return "" }
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        var out: [String: String] = [:]
        for (key, value) in object {
            guard key == "primary" || key == "secondary", let hex = value as? String, color(hex: hex) != nil else { return nil }
            out[key] = hex.uppercased()
        }
        let parts = ["primary", "secondary"].compactMap { key in out[key].map { "\"\(key)\":\"\($0)\"" } }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// Both colors fit in 24 bits (a `VoxelColor` above 0xFFFFFF has no "#RRGGBB" form).
    public var isValid: Bool { [primary, secondary].allSatisfy { ($0 ?? 0) <= 0xFFFFFF } }

    /// 0xRRGGBB → "#RRGGBB" (uppercase, as the module stores it).
    public static func hex(_ color: VoxelColor) -> String {
        let v = color & 0xFFFFFF
        let digits = String(v, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: 6 - digits.count) + digits
    }
}

public struct Comp: Codable, Sendable, Hashable, Identifiable {
    public var id: UInt64
    public var itemId: UInt64
    public var source: String
    public var title: String
    public var priceCents: Int64
    public var url: String

    public init(id: UInt64, itemId: UInt64, source: String, title: String, priceCents: Int64, url: String) {
        self.id = id
        self.itemId = itemId
        self.source = source
        self.title = title
        self.priceCents = priceCents
        self.url = url
    }
}
