import SwiftUI

@main
struct MooveApp: App {
    @State private var store = MooveStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
