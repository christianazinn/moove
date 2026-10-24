import SwiftUI
import MooveKit

/// Thin status strip: shows offline-demo mode, reconnects and write errors.
struct ConnectionBanner: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if store.backendKind == .fixture {
                strip("Offline demo: fixture data, nothing is synced", systemImage: "externaldrive", tint: Theme.ochreInk)
            }
            switch store.status {
            case .connecting:
                strip("Connecting…", systemImage: "antenna.radiowaves.left.and.right", tint: Theme.muted)
            case .reconnecting(let attempt):
                strip("Reconnecting (attempt \(attempt))…", systemImage: "arrow.clockwise", tint: Theme.ochreInk)
            case .failed(let why):
                strip("Offline: \(why)", systemImage: "wifi.exclamationmark", tint: Theme.danger)
            case .connected, .disconnected:
                EmptyView()
            }
            if let error = store.lastError {
                strip(error, systemImage: "exclamationmark.triangle", tint: Theme.danger)
                    .onTapGesture { store.lastError = nil }
            }
        }
    }

    /// A quiet notice strip: mono text on the raised surface, a colored edge, a rule below.
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
        .background(Theme.surface)
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .ruled()
        .accessibilityElement(children: .combine)
    }
}
