import SwiftUI
import MooveKit

/// App shell. Each lane adds its tab here and keeps the screen itself in
/// `Features/<Feature>/`.
struct RootView: View {
    @Environment(MooveStore.self) private var store
    @State private var showSettings = false

    var body: some View {
        TabView {
            NavigationStack { screen(ScanHomeView()) }
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
            NavigationStack { screen(InventoryView()) }
                .tabItem { Label("Inventory", systemImage: "shippingbox") }
            NavigationStack { screen(ReviewView()) }
                .tabItem { Label("Review", systemImage: "checklist") }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { await store.connect(token: nil) }
    }

    private func screen(_ content: some View) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { ConnectionBanner() }
            .toolbar { settingsButton }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
    }
}

#Preview {
    RootView().environment(MooveStore.preview())
}
