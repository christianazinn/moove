import Network
import SwiftUI
import MooveKit

/// Shows login until the user signs in (or continues as a guest), then
/// connects to SpacetimeDB with the Auth0 ID token and registers the user.
struct AuthGate: View {
    @Environment(AuthService.self) private var auth
    @Environment(MooveStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var network = NetworkWatcher()
    /// The app's own reconnect loop (the SDK's auto-reconnect is off).
    @State private var reconnectTask: Task<Void, Never>?
    @State private var reconnectAttempt = 0

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                ProgressView().task { await auth.restore() }
            case .signedOut:
                LoginView()
            case .signedIn, .guest:
                RootView()
            }
        }
        .task(id: auth.state) { await sessionChanged() }
        // Register once the connection is up: after sign-in, and again after a
        // banner retry, since a write before that would only fail.
        // iOS kills the socket when the iPad locks or the app goes to the background. Coming back
        // (or the network returning) reconnects at once; while the app is open a dropped
        // connection retries after 1, 2, 4, 8, then every 15 s.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { reconnect(now: true) } else { reconnectTask?.cancel() }
        }
        .onChange(of: network.isOnline) { _, online in
            if online { reconnect(now: true) }
        }
        .onChange(of: store.status) { _, status in
            if status == .connected {
                reconnectAttempt = 0
                Task { await registerUser() }
            } else if status.needsReconnect {
                reconnect(now: false)
            }
            // The SDK retries with the token it started with; an expired ID token is
            // rejected every time, so start over with a renewed one.
            if case .reconnecting = status, case .signedIn = auth.state, auth.connectedTokenExpired {
                Task { await store.connect(token: await auth.spacetimeToken()) }
            }
        }
    }

    /// Reconnects a dropped live connection with a fresh one (renewed Auth0 token, or the guest
    /// token): `now` when the app becomes active or the network returns, else after the backoff.
    private func reconnect(now: Bool) {
        guard store.backendKind == .spacetime, store.status.needsReconnect, scenePhase == .active else { return }
        switch auth.state {
        case .signedIn, .guest: break
        case .checking, .signedOut: return
        }
        if now { reconnectAttempt = 0 } else if reconnectTask != nil { return }
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let delay = now ? 0 : SyncStatus.reconnectDelay(attempt: reconnectAttempt)
        reconnectTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, store.status.needsReconnect else { reconnectTask = nil; return }
            reconnectTask = nil
            switch auth.state {
            case .signedIn: await store.connect(token: await auth.spacetimeToken())
            case .guest: await store.connect(token: nil)
            case .checking, .signedOut: break
            }
        }
    }

    private func registerUser() async {
        switch auth.state {
        case .signedIn(let profile):
            await store.registerUser(name: profile.name, email: profile.email, auth0Sub: profile.sub)
        case .guest:
            if store.me == nil { await store.registerUser(name: "Guest", email: nil, auth0Sub: nil) }
        case .checking, .signedOut:
            break
        }
    }

    #if DEBUG
    @MainActor private static var importedDemo = false
    #endif

    private func sessionChanged() async {
        switch auth.state {
        case .checking:
            return
        case .signedOut:
            await store.disconnect()
        case .signedIn:
            await store.connect(token: await auth.spacetimeToken())
        case .guest:
            await store.connect(token: nil)
        }
        #if DEBUG
        // Test hook: import the demo scan through the live backend once connected.
        if ProcessInfo.processInfo.environment["MOOVE_DEBUG_IMPORT_DEMO"] != nil, !Self.importedDemo {
            Self.importedDemo = true
            try? await Task.sleep(for: .seconds(1))
            if store.items.isEmpty { await store.importScan(DemoFixtures.scanImport()) }
        }
        #endif
    }
}

/// Whether the device has a usable network path (Wi-Fi or cellular), for reconnecting.
@MainActor @Observable
final class NetworkWatcher {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "moove.network"))
    }

    deinit { monitor.cancel() }
}
