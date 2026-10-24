import SwiftUI
import MooveKit

/// Thin status strip: shows offline-demo mode, reconnects and write errors.
struct ConnectionBanner: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            if store.backendKind == .fixture {
                strip("Offline demo: fixture data, nothing is synced", systemImage: "externaldrive", tint: .orange)
            }
            switch store.status {
            case .connecting:
                strip("Connecting…", systemImage: "antenna.radiowaves.left.and.right", tint: .secondary)
            case .reconnecting(let attempt):
                strip("Reconnecting (attempt \(attempt))…", systemImage: "arrow.clockwise", tint: .orange)
            case .failed(let why):
                strip("Offline: \(why)", systemImage: "wifi.exclamationmark", tint: .red)
            case .connected, .disconnected:
                EmptyView()
            }
            if let error = store.lastError {
                strip(error, systemImage: "exclamationmark.triangle", tint: .red)
                    .onTapGesture { store.lastError = nil }
            }
        }
    }

    private func strip(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal)
            .foregroundStyle(tint)
            .background(.bar)
    }
}
