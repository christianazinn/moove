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
                        if store.backendKind == .spacetime {
                            Text("Database").monoMeta().padding(.top, 18)
                            ForEach(DatabaseChoice.allCases) { databaseChoice($0) }
                        }
                        row("Status", statusText)
                        row("Server", "\(AppConfig.current.spacetimeHost) / \(store.databaseName)")
                        if let me = store.snapshot.me {
                            row("Identity", String(me.prefix(16)) + "…")
                        }
                    }

                    if store.backendKind == .spacetime {
                        section("Worker") {
                            row("Agents", workerText)
                            row("Uploads", uploadsText)
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

    /// Where the live backend points. "Demo" is a separate, seeded database for a clean
    /// stage run; the morning plan is to keep `moove` for real data (#122).
    enum DatabaseChoice: String, CaseIterable, Identifiable {
        case live = "moove", demo = "moove-demo"
        var id: String { rawValue }
        var label: String { self == .live ? "Live (moove)" : "Demo (moove-demo)" }
    }

    private func databaseChoice(_ choice: DatabaseChoice) -> some View {
        let selected = store.databaseName == choice.rawValue
        return Button {
            guard !selected else { return }
            Task { await store.switchDatabase(to: choice == .live ? nil : choice.rawValue, token: await auth.spacetimeToken()) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(selected ? Theme.accentStrong : Theme.faint)
                    .accessibilityHidden(true)
                Text(choice.label)
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

    /// "online · started 12 min ago · 878eead", from the worker's announcement.
    private var workerText: String {
        let c = store.snapshot.serviceConfig
        guard c.workerVersion != nil || c.workerStartedAt != nil else {
            return store.status == .connected ? "No announcement yet" : "Unknown (not connected)"
        }
        var parts = ["online"]
        if let started = c.workerStartedAt {
            parts.append("started " + started.formatted(.relative(presentation: .named)))
        }
        if let v = c.workerVersion { parts.append(v) }
        return parts.joined(separator: " · ")
    }

    private var uploadsText: String {
        guard let url = store.uploadBaseURL else { return "Not configured (photos stay on this device)" }
        return (url.host ?? url.absoluteString) + (store.uploadURLIsLive ? " (from worker)" : " (build default)")
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
        .accessibilityIdentifier("settings.dataSource.\(kind.rawValue)")
    }
}
