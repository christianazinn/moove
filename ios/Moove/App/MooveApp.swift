import SwiftUI
import MooveKit

@main
struct MooveApp: App {
    @State private var auth = AuthService()
    @State private var store = MooveStore()

    init() {
        #if DEBUG
        // UI tests: start from a fresh install's state (signed out, Scan tab).
        // Values are written rather than removed so they also shadow a
        // simulator-wide `simctl spawn defaults write`. Launch arguments
        // (`-moove.backendKind fixture -moove.auth.guest YES`) still win.
        if ProcessInfo.processInfo.environment["MOOVE_UI_TEST_RESET"] != nil {
            let defaults = UserDefaults.standard
            defaults.set("scan", forKey: "moove.tab")
            defaults.set(false, forKey: AuthService.guestKey)
            defaults.set(MooveStore.BackendKind.spacetime.rawValue, forKey: MooveStore.backendKindKey)
            defaults.removeObject(forKey: HiddenRooms.defaultsKey)
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
                        items: Dictionary(uniqueKeysWithValues: DemoFixtures.inventory(owner: "me").items.map { ($0.scanObjectId!, $0) }),
                        roomName: "Bedroom", roomItems: DemoFixtures.inventory(owner: "me").items
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
