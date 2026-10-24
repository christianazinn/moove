import SwiftUI
import MooveKit

/// Shows login until the user signs in (or continues as a guest), then
/// connects to SpacetimeDB with the Auth0 ID token and registers the user.
struct AuthGate: View {
    @Environment(AuthService.self) private var auth
    @Environment(MooveStore.self) private var store

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
        case .signedIn(let profile):
            await store.connect(token: await auth.spacetimeToken())
            await store.registerUser(name: profile.name, email: profile.email, auth0Sub: profile.sub)
        case .guest:
            await store.connect(token: nil)
            if store.me == nil {
                await store.registerUser(name: "Guest", email: nil, auth0Sub: nil)
            }
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
