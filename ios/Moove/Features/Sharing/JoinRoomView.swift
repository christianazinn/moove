import SwiftUI
import MooveKit

/// Joins someone else's room by its 6-character code (#10). The room and its
/// items then arrive through the `room_member` subscription.
struct JoinRoomView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var joining = false
    @State private var error: String?
    @State private var joined = false
    @FocusState private var focused: Bool

    private static let length = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: "Join a room.")
                    // The offline demo's code is the placeholder, so there's nothing to read.
                    TextField(store.backendKind == .fixture ? DemoFixtures.roommateJoinCode : "ABC123", text: $code)
                        .monoText(32, weight: .bold, maxScale: 1.4)
                        .kerning(6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .focused($focused)
                        .onSubmit(join)
                        .onChange(of: code) { _, new in
                            let clean = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(Self.length))
                            if clean != new { code = clean }
                            error = nil
                        }
                        .frame(minHeight: 56)
                        .ruled()
                        .padding(.top, 28)
                        .accessibilityLabel("Room code")
                        .accessibilityHint(store.backendKind == .fixture
                            ? "Six letters and numbers. Offline demo: try \(DemoFixtures.roommateJoinCode)"
                            : "Six letters and numbers, from Share in the owner's Inventory")
                        .accessibilityIdentifier("join.code")

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .monoText(13.5)
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 14)
                            .accessibilityIdentifier("join.error")
                    }
                    if joined {
                        Label("Joined", systemImage: "checkmark.circle")
                            .monoText(13.5)
                            .foregroundStyle(Theme.text)
                            .padding(.top, 14)
                    }

                    Button(action: join) {
                        HStack(spacing: 8) {
                            Text(joining ? "Joining…" : "Join")
                            if joining { ProgressView().controlSize(.small) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pill(.primary))
                    .disabled(code.count != Self.length || joining || joined)
                    .accessibilityIdentifier("join.submit")
                    .padding(.top, 24)
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Join")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .mooveScreen()
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func join() {
        guard code.count == Self.length, !joining else { return }
        joining = true
        error = nil
        Task {
            let ok = await store.joinRoom(code: code)
            joining = false
            if ok {
                joined = true
                try? await Task.sleep(for: .milliseconds(700))
                dismiss()
            } else {
                // Show it here instead of in the app-wide banner.
                let detail = store.lastError ?? ""
                store.lastError = nil
                error = detail.localizedCaseInsensitiveContains("no room") || detail.contains("noSuchRoomCode")
                    ? "No room has that code. Check it and try again."
                    : detail.hasPrefix("Not saved: ")
                        ? "Couldn't join: " + detail.dropFirst("Not saved: ".count)  // offline (MooveStore.describe)
                        : "Couldn't join: \(detail)"
            }
        }
    }
}

#Preview {
    JoinRoomView().environment(MooveStore.preview())
}
