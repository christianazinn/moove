import Foundation

/// Everything the app currently sees, as plain MooveKit models.
/// Other lanes add their tables (payments, listings, approvals, ...) here.
public struct SyncSnapshot: Sendable, Equatable {
    public var me: IdentityHex?
    public var users: [User] = []
    public var rooms: [Room] = []
    public var scans: [Scan] = []
    public var items: [Item] = []
    public var comps: [Comp] = []
    public var newHomes: [NewHome] = []
    public var layouts: [Layout] = []
    public var listings: [Listing] = []
    public var approvals: [Approval] = []
    public var payments: [Payment] = []
    public var agentEvents: [AgentEvent] = []
    public var shoppingItems: [ShoppingItem] = []
    public var deals: [Deal] = []
    /// Worker announcements (#122): upload URL, worker version and start time.
    public var serviceConfig = ServiceConfig()

    public init(me: IdentityHex? = nil) { self.me = me }

    public func comps(for itemId: UInt64) -> [Comp] { comps.filter { $0.itemId == itemId } }

    /// The user's current new home: the most recently created one they own.
    public var myNewHome: NewHome? {
        newHomes.filter { $0.owner == me }.max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public func layouts(for newHomeId: UInt64) -> [Layout] { layouts.filter { $0.newHomeId == newHomeId } }

    /// The item's newest listing, if the listing agent has written one.
    public func listing(for itemId: UInt64) -> Listing? { listings.filter { $0.itemId == itemId }.max { $0.id < $1.id } }

    /// Payments plus refusals, newest first, with per-agent budgets (#7).
    public func spendingLog(capPerAgentUsdMicros: Int64 = UsdMicros.defaultAgentCap) -> SpendingLog {
        SpendingLog(payments: payments, events: agentEvents, capPerAgentUsdMicros: capPerAgentUsdMicros)
    }

    /// Agent steps, newest first, optionally only those about one row (e.g. "item", 11).
    public func agentEvents(refTable: String? = nil, refId: UInt64? = nil) -> [AgentEvent] {
        agentEvents
            .filter { e in (refTable == nil || e.refTable == refTable) && (refId == nil || e.refId == refId) }
            .sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
    }
}

/// One object from a RoomPlan scan, ready to become an `items` row.
public struct ScanObject: Codable, Sendable, Hashable {
    public var scanObjectId: String
    public var category: String
    public var widthM: Double
    public var heightM: Double
    public var depthM: Double
    public var photoUrl: String?
    /// RoomPlan (iOS 17) attributes, type-prefixed raw values like "ChairLegType.star" (#110).
    /// [] for objects RoomPlan didn't classify (manual / extra detections).
    public var attributes: [String]

    public init(scanObjectId: String, category: String, widthM: Double, heightM: Double, depthM: Double,
                photoUrl: String? = nil, attributes: [String] = []) {
        self.scanObjectId = scanObjectId
        self.category = category
        self.widthM = widthM
        self.heightM = heightM
        self.depthM = depthM
        self.photoUrl = photoUrl
        self.attributes = attributes
    }

    /// The module's rule for one attribute (`import_scan_v2`): `Type.value`, letters and digits.
    public static func isValidAttribute(_ a: String) -> Bool {
        let parts = a.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let type = parts.first, let value = parts.last,
              (1...41).contains(type.count), (1...40).contains(value.count),
              let first = type.first, first.isASCII, first.isLetter else { return false }
        func ascii(_ c: Character, underscore: Bool) -> Bool {
            c.isASCII && (c.isLetter || c.isNumber || (underscore && c == "_"))
        }
        return type.allSatisfy { ascii($0, underscore: false) } && value.allSatisfy { ascii($0, underscore: true) }
    }

    /// At most this many attributes per object (`import_scan_v2`).
    public static let maxAttributes = 32
}

/// A whole scan, imported in one reducer call so the room, scan and items
/// land in one transaction (reducers can't hand back the new room id).
public struct ScanImport: Codable, Sendable, Hashable {
    public var roomName: String
    public var usdzUrl: String?
    public var capturedRoomJsonUrl: String?
    public var objects: [ScanObject]

    public init(roomName: String, usdzUrl: String? = nil, capturedRoomJsonUrl: String? = nil, objects: [ScanObject]) {
        self.roomName = roomName
        self.usdzUrl = usdzUrl
        self.capturedRoomJsonUrl = capturedRoomJsonUrl
        self.objects = objects
    }
}

public enum SyncStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(String)
}

/// The one seam between screens and the backend. The app has a SpacetimeDB
/// implementation; `FixtureBackend` is the offline/demo/preview one.
public protocol SyncBackend: AnyObject, Sendable {
    /// Connects and returns the identity plus a token to persist for reconnects.
    func connect(token: String?) async throws -> (identity: IdentityHex, token: String)
    func disconnect() async

    /// Emits a fresh snapshot after every change, starting with the current state.
    func snapshots() -> AsyncStream<SyncSnapshot>
    func statusUpdates() -> AsyncStream<SyncStatus>

    func registerUser(name: String, email: String?, auth0Sub: String?) async throws
    func importScan(_ scan: ScanImport) async throws
    func addItemPhoto(itemId: UInt64, url: String) async throws
    func setDisposition(itemId: UInt64, disposition: Disposition) async throws
    func setSentimental(itemId: UInt64, maybeSentimental: Bool) async throws
    /// `set_item_colors` (#110): colors sampled from the scan's frames. nil clears them.
    func setItemColors(itemId: UInt64, colors: ItemColors?) async throws

    /// Joins someone else's room by its join code (#10). Its scans and items then
    /// stream in like the user's own. Joining a room you already have is a no-op.
    func joinRoom(code: String) async throws

    /// Shopping list (#15): the user's edit step on the list the shopping agent generated.
    func addShoppingItem(name: String, category: String, reason: String) async throws
    func removeShoppingItem(shoppingItemId: UInt64) async throws
    /// Pick which of an item's deals the buy agent should check out.
    func chooseDeal(shoppingItemId: UInt64, dealId: UInt64) async throws

    func createNewHome(name: String, source: NewHomeSource, floorPlanJson: String) async throws
    func saveLayout(newHomeId: UInt64, name: String, placementsJson: String) async throws

    /// Owner decision on a pending approval (#12): `.approved` or `.denied`.
    func decideApproval(approvalId: UInt64, status: ApprovalStatus) async throws
}
