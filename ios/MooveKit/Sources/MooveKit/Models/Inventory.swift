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

    public init(identity: IdentityHex, auth0Sub: String? = nil, name: String, email: String? = nil, approvalThresholdCents: Int64 = 10_000) {
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
    /// 6-character code a second phone enters to join this room (#10).
    public var joinCode: String?

    public init(id: UInt64, owner: IdentityHex, name: String, home: Home = .old, joinCode: String? = nil) {
        self.id = id
        self.owner = owner
        self.name = name
        self.home = home
        self.joinCode = joinCode
    }

    /// Join codes are matched trimmed and uppercased, as the `join_room` reducer does.
    public static func normalizeJoinCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

public struct Scan: Codable, Sendable, Hashable, Identifiable {
    /// The worker's room photo sweep (#92) for this scan.
    public enum SweepStatus: String, Codable, Sendable {
        case none, pending, running, done, failed

        /// Photos are in and the worker hasn't finished with them yet.
        public var isActive: Bool { self == .pending || self == .running }
    }

    public var id: UInt64
    public var owner: IdentityHex
    public var roomId: UInt64
    public var usdzUrl: String?
    public var capturedRoomJsonUrl: String?
    public var createdAt: Date
    /// nil = `none` (also what older encoded scans decode to).
    public var sweepStatus: SweepStatus?

    public init(id: UInt64, owner: IdentityHex, roomId: UInt64, usdzUrl: String? = nil, capturedRoomJsonUrl: String? = nil,
                createdAt: Date = .now, sweepStatus: SweepStatus? = nil) {
        self.id = id
        self.owner = owner
        self.roomId = roomId
        self.usdzUrl = usdzUrl
        self.capturedRoomJsonUrl = capturedRoomJsonUrl
        self.createdAt = createdAt
        self.sweepStatus = sweepStatus
    }
}

extension SyncSnapshot {
    /// The newest scan of a room, i.e. the one whose sweep the room's items reflect.
    public func latestScan(ofRoom roomId: UInt64) -> Scan? {
        scans.filter { $0.roomId == roomId }.max { $0.id < $1.id }
    }
}

/// A worker stage on an item (`details_status`, `pricing_status`, `model_status`).
public enum AgentStage: String, Codable, Sendable {
    case pending, running, done, failed
}

/// How exactly vision identified an item (`identify_confidence`, #276): the exact product,
/// the brand or product line, or only the generic type.
public enum IdentifyConfidence: String, Codable, Sendable {
    case high, medium, low
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
    /// The pricing agent's low/high for the estimate (`est_low_cents`/`est_high_cents`). nil when
    /// the backend doesn't say (fixtures, older rows). Not shown: every screen shows the one estimate.
    public var estLowCents: Int64?
    public var estHighCents: Int64?
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
    /// Where the vision and pricing agents are with this item (`details_status`,
    /// `pricing_status`). nil when the backend doesn't say (fixtures, older encodings).
    public var detailsStatus: AgentStage?
    public var pricingStatus: AgentStage?
    /// Vision's confidence in the exact product and the one close-up photo that would pin it
    /// down, e.g. "model sticker on the back" (#276). nil until vision reports them.
    public var identifyConfidence: IdentifyConfidence?
    public var closeupHint: String?

    public init(
        id: UInt64, owner: IdentityHex, roomId: UInt64, scanObjectId: String? = nil,
        name: String, category: String, widthM: Double, heightM: Double, depthM: Double,
        photoUrls: [String] = [], material: String? = nil, brand: String? = nil, condition: Int? = nil,
        estValueCents: Int64? = nil, disposition: Disposition = .undecided, dispositionSource: DispositionSource = .auto,
        dispositionReason: String? = nil, fragile: Bool = false, maybeSentimental: Bool = false, updatedAt: Date = .now,
        attributes: [String] = [], colors: ItemColors? = nil,
        detailsStatus: AgentStage? = nil, pricingStatus: AgentStage? = nil,
        identifyConfidence: IdentifyConfidence? = nil, closeupHint: String? = nil,
        estLowCents: Int64? = nil, estHighCents: Int64? = nil
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
        self.estLowCents = estLowCents
        self.estHighCents = estHighCents
        self.disposition = disposition
        self.dispositionSource = dispositionSource
        self.dispositionReason = dispositionReason
        self.fragile = fragile
        self.maybeSentimental = maybeSentimental
        self.updatedAt = updatedAt
        self.attributes = attributes
        self.colors = colors
        self.detailsStatus = detailsStatus
        self.pricingStatus = pricingStatus
        self.identifyConfidence = identifyConfidence
        self.closeupHint = closeupHint
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

extension Item {
    /// What to show where the price goes. Mirrors the worker's gating: pricing waits
    /// for vision on items with a photo (`agents/src/agents/pricing.ts`).
    public enum PriceState: Equatable, Sendable {
        case priced(Int64)
        /// Vision hasn't finished with the photo yet, so pricing hasn't started.
        case identifying
        case pricing
        /// A catch-all name ("storage", "other") and no photo: vision can't name it and pricing
        /// can't look it up, so a photo (or a rename) is what it needs.
        case needsPhoto
        /// The pricing agent gave up (no comparable listings, or a lookup error).
        case unpriced
        /// A toilet, tub, sink or radiator: part of the building, never sold or priced.
        case builtIn
    }

    public var priceState: PriceState {
        if isBuiltInFixture { return .builtIn }
        if let estValueCents { return .priced(estValueCents) }
        if photoUrls.isEmpty, brand == nil, Self.genericNames.contains((name.isEmpty ? category : name).trimmingCharacters(in: .whitespaces).lowercased()) {
            return .needsPhoto
        }
        if pricingStatus == .failed { return .unpriced }
        if !photoUrls.isEmpty, detailsStatus == .pending || detailsStatus == .running { return .identifying }
        return .pricing
    }

    /// Names too generic to price (the worker's `GENERIC_NAMES` in `agents/src/agents/pricing.ts`).
    static let genericNames: Set<String> = ["", "other", "unknown", "object", "item", "storage"]
}

extension Item {
    /// Fixtures that belong to the building (mirrors the worker's `agents/src/builtins.ts`): never
    /// priced, and left out of sale totals even if an older worker priced them (Rio's hotel
    /// bathroom: a $48 toilet, a $64 tub, a $32 radiator; a door, a ceiling fan). A sink caddy, a door mat
    /// or a window fan is an item.
    public var isBuiltInFixture: Bool {
        let text = "\(name) \(category)"
        if Self.matches(Self.alwaysFixture, text) { return true }
        // Accessory words only count in the head noun phrase, as on the worker: "bathtub with
        // shower curtain" is a tub, "shower curtain with rod" is a curtain.
        let head = Self.headSplit.firstMatch(in: name, range: NSRange(name.startIndex..., in: name))
            .flatMap { Range($0.range, in: name) }.map { String(name[..<$0.lowerBound]) } ?? name
        return Self.matches(Self.fixture, text) && !Self.matches(Self.accessory, "\(head) \(category)")
    }

    // The same patterns as `agents/src/builtins.ts`; keep the two in sync.
    private static let fixture = regex(#"\b(toilets?|bathtubs?|bath tubs?|sinks?|washbasins?|fireplaces?|stairs?|staircases?|radiators?|showers?|shower stalls?|built-?ins?|doors?|windows?|blinds?|shutters?|outlets?|vents?|countertops?)\b"#)
    private static let alwaysFixture = regex(#"\b(ceiling (fans?|lights?)|light fixtures?|recessed lights?|curtain rods?|smoke detectors?|thermostats?|grab bars?)\b|\bwall[- ]mounted\b[^,;(]*\b(towel (bars?|racks?)|hair ?dryers?|soap dispensers?)\b"#)
    private static let accessory = regex(#"\b(caddy|caddies|mats?|organizers?|strainers?|stoppers?|paper|brush(es)?|plungers?|cleaners?|towels?|racks?|shelf|shelves|curtains?|heads?|heaters?|portable|oil|covers?|seats? covers?|tools?|screens?|gates?|fans?|ac|air conditioners?|hangers?|hooks?|stops?|wedges?|knobs?|locks?)\b"#)
    private static let headSplit = regex(#"\b(?:with|and|plus)\b|[,;(]"#)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// What the item adds to "expected sales" and other totals: nothing for a built-in fixture.
    public var saleValueCents: Int64? { isBuiltInFixture ? nil : estValueCents }

    /// An estimate from only one or two comparable listings is a rough guess, not a market price.
    /// Zero means none are recorded (seeded or demo rows), which isn't flagged.
    public static func isRoughEstimate(compCount: Int) -> Bool { (1...2).contains(compCount) }
}

extension SyncSnapshot {
    /// How many comparable listings priced each item.
    public var compCounts: [UInt64: Int] { comps.reduce(into: [:]) { $0[$1.itemId, default: 0] += 1 } }
}

extension Item {
    /// How the item got into the inventory, which says how much to trust its size.
    public enum Origin: Equatable, Sendable {
        /// A box from the LiDAR scan (RoomPlan or the extra detector): measured.
        case scan
        /// Added by the room photo sweep (`scan_object_id = "photo:<scan id>"`, #92): size estimated.
        case roomPhotos
        /// Added by its photo during the scan review: no size at all.
        case photo
        /// Added by hand in Inventory (`add_item`, no scan object): its kind's typical size.
        case manual
    }

    public var origin: Origin {
        if scanObjectId?.hasPrefix("photo:") == true { return .roomPhotos }
        if widthM <= 0 && heightM <= 0 && depthM <= 0 { return .photo }
        if scanObjectId == nil { return .manual }
        return .scan
    }
}
