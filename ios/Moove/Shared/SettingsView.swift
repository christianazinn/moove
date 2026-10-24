import SwiftUI
import MooveKit

/// Debug/settings sheet: backend toggle (demo fallback) and connection info.
struct SettingsView: View {
    @Environment(MooveStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(eyebrow: "Moove — Settings", title: "Settings",
                               lede: "Your account, and where the app gets its data.")

                    section("Account") {
                        switch auth.state {
                        case .signedIn(let profile):
                            row("Signed in as", profile.email ?? profile.name)
                        case .guest:
                            row("Signed in as", "Guest (this device only)")
                        default:
                            EmptyView()
                        }
                        Button("Sign out", role: .destructive) {
                            Task {
                                await auth.signOut()
                                dismiss()
                            }
                        }
                        .buttonStyle(.pill(.danger))
                        .padding(.top, 16)
                    }

                    section("Backend") {
                        Text("Data source").monoMeta().padding(.top, 14)
                        ForEach(MooveStore.BackendKind.allCases) { kind in
                            backendChoice(kind)
                        }
                        row("Status", statusText)
                        row("Server", "\(AppConfig.current.spacetimeHost) / \(AppConfig.current.spacetimeDB)")
                        if let me = store.snapshot.me {
                            row("Identity", String(me.prefix(16)) + "…")
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .mooveScreen()
        }
    }

    private var statusText: String {
        switch store.status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting(let n): "Reconnecting (\(n))"
        case .failed(let why): "Failed: \(why)"
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: title)
            content()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Label on the left, mono value on the right, over a rule.
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).monoText(13.5).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value)
                .monoText(13.5)
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .ruled()
        .accessibilityElement(children: .combine)
    }

    /// One radio-style choice for the data source. Same setter as the old picker.
    private func backendChoice(_ kind: MooveStore.BackendKind) -> some View {
        let selected = store.backendKind == kind
        return Button {
            guard !selected else { return }
            Task { await store.switchBackend(to: kind, token: await auth.spacetimeToken()) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(selected ? Theme.accentStrong : Theme.faint)
                    .accessibilityHidden(true)
                Text(kind.label)
                    .monoText(13.5, weight: selected ? .bold : .regular)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .ruled()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
