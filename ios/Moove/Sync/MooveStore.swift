import Foundation
import Observation
import MooveKit

/// The single app-wide store. Screens read `snapshot` and call intents here;
/// they never touch the SpacetimeDB SDK directly, so swapping the backend
/// (SpacetimeDB, offline fixture) is invisible to them.
@MainActor
@Observable
final class MooveStore {
    enum BackendKind: String, CaseIterable, Identifiable {
        case spacetime, fixture
        var id: String { rawValue }
        var label: String { self == .spacetime ? "SpacetimeDB (live)" : "Offline demo (fixtures)" }
    }

    private(set) var snapshot = SyncSnapshot()
    private(set) var status: SyncStatus = .disconnected
    private(set) var backendKind: BackendKind
    /// Last write error, shown as a banner. Cleared by the UI.
    var lastError: String?

    private var backend: SyncBackend
    private var listeners: [Task<Void, Never>] = []
    private let config: AppConfig

    static let backendKindKey = "moove.backendKind"
    /// Optional database-name override (Settings → Database), e.g. "moove-demo".
    static let databaseKey = "moove.database"

    /// The database to connect to: the Settings override, else the build's.
    static func databaseName(config: AppConfig) -> String {
        let override = UserDefaults.standard.string(forKey: databaseKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return override.isEmpty ? config.spacetimeDB : override
    }

    var databaseName: String { Self.databaseName(config: config) }

    /// Where photos and scan files go: the URL the worker announces in
    /// `service_config` (#122, it changes whenever the tunnel restarts), else the
    /// build's `MOOVE_UPLOAD_BASE_URL`. Nil in offline demo mode (files stay local).
    var uploadBaseURL: URL? {
        guard backendKind == .spacetime else { return nil }
        return snapshot.serviceConfig.uploadBaseURL(fallback: config.uploadBaseURL)
    }

    /// True when the upload URL came from the worker rather than the build.
    var uploadURLIsLive: Bool { snapshot.serviceConfig.uploadBaseURL != nil }

    init(config: AppConfig = .current, kind: BackendKind? = nil) {
        self.config = config
        let stored = UserDefaults.standard.string(forKey: Self.backendKindKey).flatMap(BackendKind.init(rawValue:))
        let kind = kind ?? stored ?? .spacetime
        self.backendKind = kind
        self.backend = Self.makeBackend(kind, config: config)
    }

    /// Preview/test store backed by the demo fixture, already connected.
    static func preview() -> MooveStore {
        let store = MooveStore(kind: .fixture)
        Task { await store.connect(token: nil) }
        return store
    }

    private static func makeBackend(_ kind: BackendKind, config: AppConfig) -> SyncBackend {
        switch kind {
        case .spacetime: SpacetimeBackend(host: config.spacetimeHost, db: databaseName(config: config))
        case .fixture: FixtureBackend.demo()
        }
    }

    var items: [Item] { snapshot.items }
    var me: User? { snapshot.users.first { $0.identity == snapshot.me } }

    // MARK: Hidden rooms (#267)

    /// Rooms hidden on this device (Inventory > room header > Hide room), e.g. old
    /// test scans. Local only: nothing is deleted from the database.
    private(set) var hiddenRoomIds: Set<UInt64> =
        HiddenRooms.decode(UserDefaults.standard.stringArray(forKey: HiddenRooms.defaultsKey))

    func setRoom(_ roomId: UInt64, hidden: Bool) {
        if hidden { hiddenRoomIds.insert(roomId) } else { hiddenRoomIds.remove(roomId) }
        UserDefaults.standard.set(HiddenRooms.encode(hiddenRoomIds), forKey: HiddenRooms.defaultsKey)
    }

    /// The snapshot without hidden rooms and their items. Inventory, Review, Scan home,
    /// New Home, Pack and Summary read this so they agree on what's there.
    var visibleSnapshot: SyncSnapshot { snapshot.hidingRooms(hiddenRoomIds) }
    var visibleItems: [Item] { hiddenRoomIds.isEmpty ? snapshot.items : snapshot.items.filter { !hiddenRoomIds.contains($0.roomId) } }
    var visibleRooms: [Room] { hiddenRoomIds.isEmpty ? snapshot.rooms : snapshot.rooms.filter { !hiddenRoomIds.contains($0.id) } }
    /// Hidden rooms that still exist, for Inventory's "Show hidden rooms (N)".
    var hiddenRooms: [Room] { snapshot.rooms.filter { hiddenRoomIds.contains($0.id) } }

    // MARK: Connection

    /// Connects with an Auth0 ID token when signed in, or the saved anonymous
    /// SpacetimeDB token otherwise (demo fallback from task #1).
    func connect(token: String?) async {
        startListening()
        status = .connecting
        let saved = token ?? Keychain.string(for: .spacetimeToken)
        do {
            let result = try await backend.connect(token: saved)
            if token == nil { Keychain.set(result.token, for: .spacetimeToken) }
        } catch is CancellationError {
            // Superseded by a newer connect: its status wins.
        } catch where token == nil && saved != nil && Self.isAuthRejection(error) {
            // The saved guest token was signed by another server (a local `spacetime start`,
            // the other database) or is no longer accepted, and the SDK would retry it forever.
            // Start over with a new anonymous identity.
            Keychain.set(nil, for: .spacetimeToken)
            await connect(token: nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// The server refused the WebSocket upgrade with 401 (the token's signature or claims).
    static func isAuthRejection(_ error: Error) -> Bool {
        String(describing: error).contains(" 401")
    }

    func disconnect() async {
        await backend.disconnect()
        listeners.forEach { $0.cancel() }
        listeners = []
        snapshot = SyncSnapshot()
        AppConfig.runtimeUploadBaseURL = nil
        status = .disconnected
    }

    func switchBackend(to kind: BackendKind, token: String?) async {
        guard kind != backendKind else { return }
        await disconnect()
        UserDefaults.standard.set(kind.rawValue, forKey: Self.backendKindKey)
        backendKind = kind
        backend = Self.makeBackend(kind, config: config)
        await connect(token: token)
    }

    /// Switches the live backend to another database on the same host (nil = build default).
    func switchDatabase(to name: String?, token: String?) async {
        let current = databaseName
        if let name, !name.isEmpty { UserDefaults.standard.set(name, forKey: Self.databaseKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.databaseKey) }
        guard databaseName != current || backendKind != .spacetime else { return }
        await disconnect()
        UserDefaults.standard.set(BackendKind.spacetime.rawValue, forKey: Self.backendKindKey)
        backendKind = .spacetime
        backend = Self.makeBackend(.spacetime, config: config)
        await connect(token: token)
    }

    private func startListening() {
        listeners.forEach { $0.cancel() }
        let snapshots = backend.snapshots()
        let statuses = backend.statusUpdates()
        listeners = [
            Task { [weak self] in
                for await snap in snapshots {
                    self?.snapshot = snap
                    // Same rule as `uploadBaseURL` (a loopback announcement loses to the build's
                    // URL on a device), so the uploader and listing import agree with Settings.
                    AppConfig.runtimeUploadBaseURL = self?.uploadBaseURL
                }
            },
            Task { [weak self] in
                for await status in statuses { self?.status = status }
            },
        ]
    }

    // MARK: Intents

    func registerUser(name: String, email: String?, auth0Sub: String?) async {
        await run { try await $0.registerUser(name: name, email: email, auth0Sub: auth0Sub) }
    }

    /// Returns whether the import landed. Don't infer success from `lastError`:
    /// it's only cleared when the banner is tapped, so an older error lingers.
    @discardableResult
    func importScan(_ scan: ScanImport) async -> Bool {
        await run { try await $0.importScan(scan) }
    }

    @discardableResult
    func addItemPhoto(itemId: UInt64, url: String) async -> Bool {
        await run { try await $0.addItemPhoto(itemId: itemId, url: url) }
    }

    /// The scan just imported into room `roomName`, once it reaches the snapshot
    /// (waits up to ~5 s, like `saveScanColors`).
    func newestScan(inRoomNamed roomName: String) async -> Scan? {
        for attempt in 0..<20 {
            if let room = newestRoom(named: roomName),
               let scan = snapshot.scans.filter({ $0.roomId == room.id }).max(by: { $0.id < $1.id }) { return scan }
            if attempt < 19 { try? await Task.sleep(for: .milliseconds(250)) }
        }
        return nil
    }

    /// Offline demo only (#181): plays the photo sweep on the newest scan of `roomName`,
    /// since there's no worker. A no-op on the live backend, where the real sweep runs.
    func simulateSweep(roomName: String) async {
        guard let fixture = backend as? FixtureBackend, let scan = await newestScan(inRoomNamed: roomName) else { return }
        await run { _ in try await fixture.simulateSweep(scanId: scan.id) }
    }

    @discardableResult
    func addScanPhoto(scanId: UInt64, url: String) async -> Bool {
        await run { try await $0.addScanPhoto(scanId: scanId, url: url) }
    }

    @discardableResult
    func setDisposition(_ disposition: Disposition, for item: Item) async -> Bool {
        await run { try await $0.setDisposition(itemId: item.id, disposition: disposition) }
    }

    func setSentimental(_ value: Bool, for item: Item) async {
        await run { try await $0.setSentimental(itemId: item.id, maybeSentimental: value) }
    }

    // MARK: Fix-it (correct a misread scan item; `ItemFix` builds the attributes)

    @discardableResult
    func renameItem(_ item: Item, to name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != item.name else { return true }
        guard await run({ try await $0.renameItem(itemId: item.id, name: name) }) else { return false }
        // The voxel model follows the new name, even over RoomPlan's own attributes.
        return await setItemAttributes(ItemFix.renamed(to: name, attributes: currentAttributes(item)), for: item)
    }

    /// "What is it?": the chip's kind wins in every 3D view; a generic name ("Storage") becomes its word.
    @discardableResult
    func setQuickKind(_ kind: ItemFix.QuickKind, for item: Item) async -> Bool {
        let change = ItemFix.apply(kind, name: item.name, category: item.category, attributes: currentAttributes(item))
        if let name = change.name, !(await run({ try await $0.renameItem(itemId: item.id, name: name) })) { return false }
        return await setItemAttributes(change.attributes, for: item)
    }

    /// Turn around (180°) or, with `by90`, the next quarter turn.
    @discardableResult
    func turn(_ item: Item, by90: Bool = false) async -> Bool {
        let attrs = currentAttributes(item)
        return await setItemAttributes(by90 ? ItemFix.rotating90(attrs) : ItemFix.turningAround(attrs), for: item)
    }

    /// Adds an item by hand to one of the user's rooms (`add_item`). With a photo, vision names
    /// and prices it; without one, pricing uses the name.
    @discardableResult
    func addItem(roomId: UInt64, name: String, category: String, size: (w: Double, h: Double, d: Double), photoUrl: String?) async -> Bool {
        await run { try await $0.addItem(roomId: roomId, name: name, category: category, widthM: size.w, heightM: size.h, depthM: size.d, photoUrl: photoUrl) }
    }

    /// "Not a real item": `delete_item`.
    @discardableResult
    func deleteItem(_ item: Item) async -> Bool {
        await run { try await $0.deleteItem(itemId: item.id) }
    }

    @discardableResult
    func setItemAttributes(_ attributes: [String], for item: Item) async -> Bool {
        guard attributes != currentAttributes(item) else { return true }
        return await run { try await $0.setItemAttributes(itemId: item.id, attributes: attributes) }
    }

    /// The item's attributes as synced now (a view's copy can be a write behind).
    private func currentAttributes(_ item: Item) -> [String] {
        snapshot.items.first { $0.id == item.id }?.attributes ?? item.attributes
    }

    /// `set_item_colors`. Quiet: a failed color write only loses the real color (the model
    /// falls back to its palette), so it doesn't raise the error banner.
    @discardableResult
    func setItemColors(_ colors: ItemColors?, forItemId itemId: UInt64) async -> Bool {
        do {
            try await backend.setItemColors(itemId: itemId, colors: colors)
            return true
        } catch {
            return false
        }
    }

    /// The newest old-home room named `roomName`: the one a scan import just created.
    func newestRoom(named roomName: String) -> Room? {
        snapshot.rooms.filter { $0.name == roomName && $0.home == .old }.max { $0.id < $1.id }
    }

    /// Persists a scan's sampled colors onto the items just imported into room `roomName`
    /// (matched by scan object id), one `set_item_colors` each. The imported rows reach the
    /// snapshot a moment after the reducer returns, so this waits up to ~5 s for them.
    /// Returns how many items were written.
    @discardableResult
    func saveScanColors(_ colors: ScanColors, roomName: String) async -> Int {
        guard !colors.objectColors.isEmpty else { return 0 }
        var updates: [ItemColorUpdate] = []
        for attempt in 0..<20 {
            if let room = newestRoom(named: roomName) {
                updates = colors.itemColorUpdates(for: items.filter { $0.roomId == room.id })
                if !updates.isEmpty { break }
            }
            if attempt < 19 { try? await Task.sleep(for: .milliseconds(250)) }
        }
        var written = 0
        for u in updates {
            if await setItemColors(u.colors, forItemId: u.itemId) { written += 1 }
        }
        return written
    }

    // MARK: Sharing (#10)

    /// Joins another person's room by its 6-character code. Its items then stream in
    /// through the `room_member` subscription. Returns false if the write failed
    /// (the error is in `lastError`).
    @discardableResult
    func joinRoom(code: String) async -> Bool {
        await run { try await $0.joinRoom(code: code) }
    }

    // MARK: Shopping (#15)

    var shoppingItems: [ShoppingItem] { snapshot.myShoppingItems }

    @discardableResult
    func addShoppingItem(name: String, category: String, reason: String) async -> Bool {
        await run { try await $0.addShoppingItem(name: name, category: category, reason: reason) }
    }

    @discardableResult
    func removeShoppingItem(_ item: ShoppingItem) async -> Bool {
        await run { try await $0.removeShoppingItem(shoppingItemId: item.id) }
    }

    /// The buy agent checks out the chosen deal (asking for approval above the threshold).
    @discardableResult
    func choose(_ deal: Deal, for item: ShoppingItem) async -> Bool {
        await run { try await $0.chooseDeal(shoppingItemId: item.id, dealId: deal.id) }
    }

    // MARK: New home (#13, #14)

    var newHome: NewHome? { snapshot.myNewHome }

    /// Returns false if the write failed (the error is in `lastError`).
    @discardableResult
    func createNewHome(name: String, source: NewHomeSource, plan: FloorPlan) async -> Bool {
        guard let json = try? plan.jsonString() else {
            lastError = "Couldn't encode the floor plan"
            return false
        }
        return await run { try await $0.createNewHome(name: name, source: source, floorPlanJson: json) }
    }

    @discardableResult
    func saveLayout(_ placements: [Placement], name: String, for home: NewHome) async -> Bool {
        await run { try await $0.saveLayout(newHomeId: home.id, name: name, placementsJson: Layout.encode(placements)) }
    }

    // MARK: Approvals (#12)

    /// The signed-in user's undecided approvals, oldest first.
    var pendingApprovals: [Approval] { snapshot.actionableApprovals } // own + shared-room listing ones (#195)

    /// Approve or deny through `decide_approval`. The listing agent posts or
    /// rejects once it sees the decision. Returns false if the write failed.
    @discardableResult
    func decide(_ approval: Approval, approve: Bool) async -> Bool {
        await run { try await $0.decideApproval(approvalId: approval.id, status: approve ? .approved : .denied) }
    }

    @discardableResult
    private func run(_ op: (SyncBackend) async throws -> Void) async -> Bool {
        do {
            try await op(backend)
            return true
        } catch {
            lastError = Self.describe(error, status: status)
            return false
        }
    }

    /// Write errors as a person would say them. A write while the connection is down
    /// fails with a bare "disconnected"; module errors (`SenderError`) are already sentences.
    static func describe(_ error: Error, status: SyncStatus) -> String {
        let raw = String(describing: error)
        switch status {
        case .connected: return raw
        case .connecting, .reconnecting: return "Not saved: still connecting to the server. Try again in a moment."
        case .disconnected, .failed: return "Not saved: not connected to the server."
        }
    }
}
