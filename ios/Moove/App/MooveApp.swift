import SwiftUI
import MooveKit

@main
struct MooveApp: App {
    @State private var auth = AuthService()
    @State private var store = MooveStore()

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MOOVE_ROOM_PREVIEW"] != nil {
                // Screenshot harness: the demo bedroom, no login.
                NavigationStack {
                    RoomVisualizationView(
                        geometry: DemoFixtures.roomGeometry(),
                        items: Self.previewItems()
                    )
                }
                .environment(store)
            } else {
                gate
            }
            #else
            gate
            #endif
        }
    }

    #if DEBUG
    /// Harness items; MOOVE_PREVIEW_GLB=<url> gives the desk a synced SAM 3D model.
    private static func previewItems() -> [String: Item] {
        var items = DemoFixtures.inventory(owner: "me").items
        if let glb = ProcessInfo.processInfo.environment["MOOVE_PREVIEW_GLB"], let i = items.firstIndex(where: { $0.id == 12 }) {
            items[i].modelUrl = glb
            items[i].modelSource = .sam3d
        }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.scanObjectId!, $0) })
    }
    #endif

    private var gate: some View {
        AuthGate()
            .environment(auth)
            .environment(store)
    }
}
