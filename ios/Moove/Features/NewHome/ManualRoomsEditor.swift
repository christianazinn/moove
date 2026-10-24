import SwiftUI
import MooveKit

/// Type in each room as a rectangle; Moove arranges them around a hallway.
struct ManualRoomsEditor: View {
    var onSave: (_ name: String, _ plan: FloorPlan) -> Void

    @State private var homeName = "My new place"
    @State private var rooms = ManualFloorPlan.starter

    private var plan: FloorPlan { ManualFloorPlan.build(rooms) }
    private var canSave: Bool { !plan.rooms.isEmpty && plan.issues().isEmpty }

    var body: some View {
        Form {
            Section {
                TextField("Home name", text: $homeName)
            }
            Section {
                FloorPlanSketch(plan: plan)
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } footer: {
                Text("\(plan.rooms.count) rooms · \(plan.totalAreaM2, format: .number.precision(.fractionLength(0))) m². Rooms are laid out around a hallway; only the sizes matter.")
            }
            Section("Rooms (meters)") {
                ForEach($rooms) { $room in
                    RoomRow(room: $room)
                }
                .onDelete { rooms.remove(atOffsets: $0) }
                Button("Add room", systemImage: "plus") {
                    rooms.append(ManualRoom(name: "Bedroom", kind: .bedroom, widthM: 3.5, depthM: 3.5))
                }
            }
        }
        .navigationTitle("Room sizes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(homeName.isEmpty ? "My new place" : homeName, plan) }
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
                    .font(.body.weight(.medium))
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
                Text("×").foregroundStyle(.secondary)
                dimension("D", value: $room.depthM)
            }
        }
        .padding(.vertical, 2)
    }

    private func dimension(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(1)))
                .keyboardType(.decimalPad)
                .frame(width: 52)
                .textFieldStyle(.roundedBorder)
            Stepper(label, value: value, in: 0.5...30, step: 0.5).labelsHidden()
        }
    }
}

#Preview {
    NavigationStack { ManualRoomsEditor { _, _ in } }
}
