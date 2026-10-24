import SwiftUI
import MooveKit

/// App shell. Each lane adds its tab here and keeps the screen itself in
/// `Features/<Feature>/`.
struct RootView: View {
    @Environment(MooveStore.self) private var store
    @State private var showSettings = false
    @AppStorage("moove.tab") private var tab = "scan"

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { screen(ScanHomeView()) }
                .tag("scan")
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
            NavigationStack { screen(InventoryView()) }
                .tag("inventory")
                .tabItem { Label("Inventory", systemImage: "shippingbox") }
            NavigationStack { screen(ReviewView()) }
                .tag("review")
                .tabItem { Label("Review", systemImage: "checklist") }
            NavigationStack { screen(NewHomeView()) }
                .tabItem { Label("New Home", systemImage: "house") }
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
