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
        } catch {
            status = .failed(error.localizedDescription)
        }
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
                    AppConfig.runtimeUploadBaseURL = snap.serviceConfig.uploadBaseURL
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

    func addItemPhoto(itemId: UInt64, url: String) async {
        await run { try await $0.addItemPhoto(itemId: itemId, url: url) }
    }

    func setDisposition(_ disposition: Disposition, for item: Item) async {
        await run { try await $0.setDisposition(itemId: item.id, disposition: disposition) }
    }

    func setSentimental(_ value: Bool, for item: Item) async {
        await run { try await $0.setSentimental(itemId: item.id, maybeSentimental: value) }
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
    var pendingApprovals: [Approval] { snapshot.pendingApprovals }

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
            lastError = String(describing: error)
            return false
        }
    }
}
