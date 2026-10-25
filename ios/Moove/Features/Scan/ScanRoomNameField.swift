import SwiftUI
import MooveKit

/// The photo step's "Room" field (Lisa: "can you not call every room a bedroom? let the user
/// name the room"). Prefilled with a guess from what the scan found (MooveKit `RoomNames.guess`),
/// with quick chips and free text. When a visible room already has the name it offers the next
/// number ("Bedroom 2"), but keeping the same name is fine: that's how a re-scan replaces a room.
struct ScanRoomNameField: View {
    @Bindable var session: ScanSession
    @Environment(MooveStore.self) private var store
    @FocusState private var focused: Bool

    private var existing: [String] { store.visibleRoomNames }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Room").eyebrow()
            field
            chips
            duplicateHint
        }
        .onAppear { session.suggestRoomName(existing: existing) }
        .onChange(of: session.objects.count) { session.suggestRoomName(existing: existing) }
    }

    private var name: Binding<String> {
        Binding(
            get: { session.roomName },
            set: {
                session.roomName = String($0.prefix(RoomNames.maxLength))
                session.roomNameChosen = true
            }
        )
    }

    private var field: some View {
        TextField("Room name", text: name)
            .monoText(16, weight: .bold)
            .foregroundStyle(Theme.text)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($focused)
            .frame(minHeight: 44)
            .ruled()
            .accessibilityLabel("Room name")
            .accessibilityHint("What to call this room in your inventory")
            .accessibilityIdentifier("scan.roomName")
    }

    private var chips: some View {
        ChipFlow(spacing: 8) {
            ForEach(RoomNames.chips, id: \.self) { chip in
                ChoiceChip(title: chip, selected: RoomNames.baseName(session.roomName) == chip) { pick(chip) }
                    .accessibilityLabel("Call it \(chip)")
                    .accessibilityIdentifier("scan.roomName.chip.\(chip)")
            }
            ChoiceChip(title: "Other…", selected: false) {
                session.roomName = ""
                session.roomNameChosen = true
                focused = true
            }
            .accessibilityLabel("Other name")
            .accessibilityHint("Clears the field so you can type a name")
            .accessibilityIdentifier("scan.roomName.chip.Other")
        }
        .padding(.top, 6)
    }

    /// "You already have a Bedroom": offer "Bedroom 2", or keep it to replace that scan.
    @ViewBuilder private var duplicateHint: some View {
        if RoomNames.isTaken(session.roomName, in: existing) {
            let numbered = RoomNames.numbered(session.roomName, existing: existing)
            VStack(alignment: .leading, spacing: 6) {
                Text("Already taken")
                    .monoMeta()
                    .accessibilityLabel("You already have a room called \(session.roomName). Keep the name to replace that scan, or call it \(numbered).")
                Button("Use “\(numbered)”") {
                    session.roomName = numbered
                    session.roomNameChosen = true
                }
                .buttonStyle(.pill(.outline, compact: true))
                .accessibilityIdentifier("scan.roomName.useNumbered")
            }
            .padding(.top, 4)
        }
    }

    private func pick(_ chip: String) {
        session.roomName = RoomNames.numbered(chip, existing: existing)
        session.roomNameChosen = true
        focused = false
    }
}
