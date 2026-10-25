import SwiftUI
import MooveKit

/// Thin status strip: shows offline-demo mode, reconnects and write errors.
struct ConnectionBanner: View {
    @Environment(MooveStore.self) private var store
    @Environment(AuthService.self) private var auth
    @State private var retrying = false

    var body: some View {
        VStack(spacing: 0) {
            if store.backendKind == .fixture {
                strip("Offline demo", systemImage: "externaldrive", tint: Theme.muted)
                    .accessibilityLabel("Offline demo: fixture data, nothing is synced")
            }
            switch store.status {
            case .connecting:
                strip("Connecting…", systemImage: "antenna.radiowaves.left.and.right", tint: Theme.muted)
            case .reconnecting(let attempt):
                strip("Reconnecting…", systemImage: "arrow.clockwise", tint: Theme.muted)
                    .accessibilityLabel("Reconnecting, attempt \(attempt)")
            case .failed(let why):
                // Dropped: the app retries by itself (`AuthGate`); a tap retries right away.
                strip(retrying ? "Connecting…" : "Reconnecting…", systemImage: "wifi.exclamationmark", tint: Theme.muted)
                    .accessibilityLabel(retrying ? "Connecting" : "Reconnecting: \(why). Tap to retry now.")
                    .onTapGesture { retry() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Reconnects to the server")
            case .connected, .disconnected:
                EmptyView()
            }
            if let error = store.lastError {
                strip(error, systemImage: "exclamationmark.triangle", tint: Theme.danger)
                    .onTapGesture { store.lastError = nil }
            }
        }
    }

    private func retry() {
        guard !retrying else { return }
        retrying = true
        Task {
            await store.connect(token: await auth.spacetimeToken())
            retrying = false
        }
    }

    /// A quiet notice strip: one short mono line on the page color (red only for a failed write).
    private func strip(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .regular))
                .accessibilityHidden(true)
            Text(text)
                .monoText(12.5, maxScale: 1.6)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(tint)
        .padding(.vertical, 8)
        .padding(.horizontal, Theme.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
        .accessibilityElement(children: .combine)
    }
}
