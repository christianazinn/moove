import SwiftUI
import MooveKit

@main
struct MooveApp: App {
    @State private var auth = AuthService()
    @State private var store = MooveStore()

    init() {
        #if DEBUG
        // UI tests: start from a fresh install's defaults (signed out, first tab).
        // Launch arguments (`-moove.backendKind fixture`) still apply on top.
        if ProcessInfo.processInfo.environment["MOOVE_UI_TEST_RESET"] != nil, let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MOOVE_ROOM_PREVIEW"] != nil {
                // Screenshot harness: the demo bedroom, no login.
                NavigationStack {
                    RoomVisualizationView(
                        geometry: DemoFixtures.roomGeometry(),
                        items: Dictionary(uniqueKeysWithValues: DemoFixtures.inventory(owner: "me").items.map { ($0.scanObjectId!, $0) })
                    )
                }
            } else {
                gate
            }
            #else
            gate
            #endif
        }
    }

    private var gate: some View {
        AuthGate()
            .environment(auth)
            .environment(store)
    }
}
