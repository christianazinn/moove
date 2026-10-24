import SwiftUI
import MooveKit

/// Type in each room as a rectangle; Moove arranges them around a hallway.
struct ManualRoomsEditor: View {
    var onSave: (_ name: String, _ plan: FloorPlan) -> Void

    @State private var homeName = "My new place"
    @State private var rooms = ManualFloorPlan.starter

    private var plan: FloorPlan { ManualFloorPlan.build(rooms) }
    private var canSave: Bool { !plan.rooms.isEmpty && plan.issues().isEmpty }

    private var problem: String? {
        switch plan.issues().first {
        case nil: nil
        case .noRooms?: "Add a room to save."
        case let .tooFewPoints(room)?, let .zeroArea(room)?: "\(room) is too small."
        case let .duplicateName(room)?: "Two rooms are named \(room). Rename one."
        case let .overlap(a, b)?: "\(a) and \(b) overlap."
        }
    }

    var body: some View {
        Form {
            Section {
                PageHeader(
                    eyebrow: "06 — New home",
                    title: "Sketch your new place",
                    lede: "Width × depth, in meters."
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Home name", text: $homeName)
                    .monoText(15, weight: .bold)
                    .frame(minHeight: 44)
            } header: {
                Text("Home").eyebrow().textCase(nil)
            }
            .listRowBackground(Theme.surface)
            Section {
                FloorPlanSketch(plan: plan)
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(plan.rooms.count) rooms · \(plan.totalAreaM2, format: .number.precision(.fractionLength(0))) m²")
                        .monoMeta()
                        .accessibilityLabel("\(plan.rooms.count) rooms, \(Spoken.area(plan.totalAreaM2))")
                    // Why Save is off, in one line.
                    if let problem {
                        Text(problem)
                            .monoText(13.5)
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .listRowBackground(Theme.surface)
            Section {
                ForEach($rooms) { $room in
                    RoomRow(room: $room)
                }
                .onDelete { rooms.remove(atOffsets: $0) }
                Button {
                    rooms.append(ManualRoom(name: "Bedroom", kind: .bedroom, widthM: 3.5, depthM: 3.5))
                } label: {
                    Label("Add room", systemImage: "plus")
                }
                .buttonStyle(.pill(.outline, compact: true))
            } header: {
                Text("Rooms · meters").eyebrow().textCase(nil)
            }
            .listRowBackground(Theme.surface)
        }
        .listRowSeparatorTint(Theme.line)
        .navigationTitle("Room sizes")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(homeName.isEmpty ? "My new place" : homeName, plan) }
                    .buttonStyle(.pill(.primary, compact: true))
                    .disabled(!canSave)
            }
        }
    }
}

private struct RoomRow: View {
    @Binding var room: ManualRoom

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $room.name)
                    .monoText(14.5, weight: .bold)
                Picker("Type", selection: $room.kind) {
                    ForEach(RoomKind.allCases.filter { $0 != .hallway }, id: \.self) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .onChange(of: room.kind) { old, new in
                    // Keep custom names; only rename rooms still called after their old type.
                    if room.name == old.label { room.name = new.label }
                }
            }
            HStack(spacing: 16) {
                dimension("W", value: $room.widthM)
                Text("×").monoText(13).foregroundStyle(Theme.muted).accessibilityHidden(true)
                dimension("D", value: $room.depthM)
            }
        }
        .padding(.vertical, 6)
    }

    private func dimension(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).monoText(11.5).foregroundStyle(Theme.muted).accessibilityHidden(true)
            TextField(label, value: value, format: .number.precision(.fractionLength(1)))
                .monoText(14)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .accessibilityLabel(label == "W" ? "Width in meters" : "Depth in meters")
                .frame(minWidth: 56, minHeight: 36)
                .fixedSize()
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            Stepper(label, value: value, in: 0.5...30, step: 0.5)
                .labelsHidden()
                .accessibilityLabel(label == "W" ? "Width" : "Depth")
                .accessibilityValue("\(value.wrappedValue.formatted(.number.precision(.fractionLength(0...1)))) meters")
        }
    }
}

#Preview {
    NavigationStack { ManualRoomsEditor { _, _ in } }
}
