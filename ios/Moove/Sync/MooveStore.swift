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
        case .spacetime: SpacetimeBackend(host: config.spacetimeHost, db: config.spacetimeDB)
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

    private func startListening() {
        listeners.forEach { $0.cancel() }
        let snapshots = backend.snapshots()
        let statuses = backend.statusUpdates()
        listeners = [
            Task { [weak self] in
                for await snap in snapshots { self?.snapshot = snap }
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

    func importScan(_ scan: ScanImport) async {
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
