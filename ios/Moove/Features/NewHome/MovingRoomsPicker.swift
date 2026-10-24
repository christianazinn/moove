import SwiftUI
import MooveKit

// "Moving from": which scanned rooms move. One set of picks (MooveStore `movingRoomPicks`,
// UserDefaults `moove.newHome.rooms`) drives both New Home and Pack, so the layout, the boxes,
// the furniture notes and the truck all agree on what's moving.

/// The "Moving from" summary: the room picks and how many kept items they bring.
struct MovingFrom: Equatable {
    var choices: [MovingRooms.Choice]
    var itemCount: Int

    var noneSelected: Bool { !choices.contains { $0.included } }
}

/// Multi-select list of the scanned rooms whose kept items move to the new home.
struct MovingRoomsPicker: View {
    var choices: [MovingRooms.Choice]
    var snapshot: SyncSnapshot
    var onToggle: (UInt64) -> Void
    var onAll: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(eyebrow: "Moving from", title: "Which rooms are moving?")
                    .padding(.bottom, 12)
                Text("Only kept items from the rooms you pick go into the new home. Older scans of a room are left out by default.")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                HStack(spacing: 10) {
                    Button("Select all") { onAll(true) }
                        .buttonStyle(.pill(.outline, compact: true))
                        .disabled(choices.allSatisfy { $0.included })
                    Button("None") { onAll(false) }
                        .buttonStyle(.pill(.outline, compact: true))
                        .disabled(!choices.contains { $0.included })
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 12)
                ForEach(choices) { c in
                    Button { onToggle(c.id) } label: {
                        LedgerRow(title: c.room.name, meta: meta(c), tag: snapshot.isDemoRoom(c.id) ? "Demo" : nil) {
                            Image(systemName: c.included ? "checkmark.square.fill" : "square")
                                .font(.system(size: 24))
                                .foregroundStyle(c.included ? Theme.accent : Theme.faint)
                                .frame(width: 44, height: 44)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(c.room.name), \(meta(c))")
                    .accessibilityAddTraits(c.included ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(c.included ? "Leaves this room's items behind" : "Moves this room's kept items")
                    .accessibilityIdentifier("movingRoom.\(c.id)")
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .mooveScreen()
        .navigationTitle("Moving from")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func meta(_ c: MovingRooms.Choice) -> String {
        let items = "\(c.itemCount) kept item\(c.itemCount == 1 ? "" : "s")"
        return [c.meta(), items].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The picker in a sheet, reading and saving the store's picks, with Done.
struct MovingRoomsSheet: View {
    @Environment(MooveStore.self) private var store
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            let choices = store.movingChoices
            MovingRoomsPicker(choices: choices, snapshot: store.visibleSnapshot,
                              onToggle: { store.setMovingRoomPicks(MovingRooms.toggle($0, in: choices, overrides: store.movingRoomPicks)) },
                              onAll: { store.setMovingRoomPicks(MovingRooms.setAll($0, in: choices)) })
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone).monoText(13, weight: .bold, maxScale: 1.4)
                    }
                }
        }
    }
}

/// "Moving from 2 rooms · 14 items ›" (opens the picker), or the empty state when no room is
/// picked. `idPrefix`: "newHome" or "pack", for the accessibility identifiers.
struct MovingFromRow: View {
    var movingFrom: MovingFrom
    var idPrefix: String
    var onChoose: () -> Void

    var body: some View {
        if movingFrom.noneSelected {
            VStack(alignment: .leading, spacing: 10) {
                Text("No rooms selected").blockTitle()
                Text("Pick the scanned rooms whose kept items are moving.").monoMeta()
                Button("Choose rooms", action: onChoose)
                    .buttonStyle(.pill(.primary, compact: true))
                    .accessibilityIdentifier("\(idPrefix).chooseRooms")
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ruled()
        } else {
            Button(action: onChoose) {
                LedgerRow(title: MovingRooms.summary(movingFrom.choices, items: movingFrom.itemCount),
                          meta: movingFrom.choices.filter(\.included).map(\.room.name).joined(separator: " · "), chevron: true) {
                    IconTile(systemName: "shippingbox")
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose which scanned rooms are moving")
            .accessibilityIdentifier("\(idPrefix).movingFrom")
        }
    }
}
