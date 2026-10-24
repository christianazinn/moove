import SwiftUI

@main
struct MooveApp: App {
    @State private var auth = AuthService()
    @State private var store = MooveStore()

    var body: some Scene {
        WindowGroup {
            AuthGate()
                .environment(auth)
                .environment(store)
        }
    }
}
