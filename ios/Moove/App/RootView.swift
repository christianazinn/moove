import SwiftUI
import MooveKit

/// App shell. Each lane adds its tab here and keeps the screen itself in
/// `Features/<Feature>/`.
struct RootView: View {
    @Environment(MooveStore.self) private var store
    @State private var showSettings = false
    @AppStorage("moove.tab") private var tab = "scan"
    @State private var lastScreen: [TabGroup: String] = [:]

    var body: some View {
        // Five tabs that follow the move (#129). `tab` holds the screen key,
        // so `tab = "inventory"` from any screen picks the tab and segment.
        TabView(selection: groupBinding) {
            ForEach(TabGroup.allCases, id: \.self) { group in
                NavigationStack { screen(TabGroupView(group: group, screen: $tab)) }
                    .tag(group)
                    .tabItem { Label(group.title, systemImage: group.systemImage) }
                    .badge(group == .sellBuy ? store.pendingApprovals.count : 0)
            }
        }
        .tint(Theme.accentStrong)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// Switching tabs returns to the last screen used in that tab.
    private var groupBinding: Binding<TabGroup> {
        Binding(
            get: { TabGroup.containing(tab) },
            set: { group in
                guard group != TabGroup.containing(tab) else { return }
                lastScreen[TabGroup.containing(tab)] = tab
                tab = lastScreen[group] ?? group.screens[0]
            }
        )
    }

    private func screen(_ content: some View) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) { ConnectionBanner() }
            .toolbar { settingsButton }
            // Tab bar styling has to be set from inside each tab.
            .toolbarBackground(Theme.bg, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
    }
}

#Preview {
    RootView().environment(MooveStore.preview()).environment(AuthService())
}
