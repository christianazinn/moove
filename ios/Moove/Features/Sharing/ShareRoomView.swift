import SwiftUI
import UIKit
import MooveKit

/// Shows a room's join code so a second phone can join it (#10).
struct ShareRoomView: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: "Share \(room.name).")
                        .accessibilityHint("On the other phone, open Inventory, Join a room, and enter this code")
                    if let code = room.joinCode {
                        Text(code)
                            .monoText(44, weight: .bold, maxScale: 1.4)
                            .kerning(8)
                            .foregroundStyle(Theme.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .padding(.top, Theme.Space.l)
                            .accessibilityLabel("Join code " + code.map(String.init).joined(separator: " "))
                            .accessibilityIdentifier("share.code")
                        HStack(spacing: 12) {
                            Button {
                                UIPasteboard.general.string = code
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.pill(.outline))
                            ShareLink(item: "Join my room in Moove: \(code)") {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.pill(.primary))
                        }
                        .padding(.top, 20)
                    } else {
                        Text("No code yet")
                            .blockTitle()
                            .padding(.vertical, 28)
                            .padding(.top, Theme.Space.l)
                            .accessibilityHint("Try again in a moment")
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .mooveScreen()
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ShareRoomView(room: Room(id: 1, owner: "me", name: "Bedroom", joinCode: "ABC234"))
}
