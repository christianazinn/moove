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

/// Where an item's 3D model came from: Object Capture on the phone (beats
/// everything) or SAM 3D from a photo (worker).
public enum ModelSource: String, Codable, Sendable {
    case capture, sam3d
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
    /// 3D model (#65): a USDZ from Object Capture or a GLB from SAM 3D.
    public var modelUrl: String?
    public var modelSource: ModelSource?

    public init(
        id: UInt64, owner: IdentityHex, roomId: UInt64, scanObjectId: String? = nil,
        name: String, category: String, widthM: Double, heightM: Double, depthM: Double,
        photoUrls: [String] = [], material: String? = nil, brand: String? = nil, condition: Int? = nil,
        estValueCents: Int64? = nil, disposition: Disposition = .undecided, dispositionSource: DispositionSource = .auto,
        dispositionReason: String? = nil, fragile: Bool = false, maybeSentimental: Bool = false, updatedAt: Date = .now,
        modelUrl: String? = nil, modelSource: ModelSource? = nil
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
        self.modelUrl = modelUrl
        self.modelSource = modelSource
    }

    public var volumeM3: Double { widthM * heightM * depthM }

    /// Sentimental or undecided items go in the review screen's "Needs you" section.
    public var needsUser: Bool { maybeSentimental || disposition == .undecided }
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
