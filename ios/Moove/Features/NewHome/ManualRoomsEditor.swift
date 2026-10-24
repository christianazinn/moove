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
                    .font(.system(size: 17, weight: .semibold))
            } header: {
                Text("Home").eyebrow()
            }
            .listRowBackground(Theme.surface)
            Section {
                FloorPlanSketch(plan: plan)
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            } footer: {
                Text("\(plan.rooms.count) rooms · \(plan.totalAreaM2, format: .number.precision(.fractionLength(0))) m² · laid out around a hallway; only the sizes matter")
                    .monoMeta()
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
                Text("Rooms · meters").eyebrow()
            }
            .listRowBackground(Theme.surface)
        }
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
                    .font(.mono(14.5, weight: .bold))
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
                Text("×").font(.mono(13)).foregroundStyle(Theme.faint)
                dimension("D", value: $room.depthM)
            }
        }
        .padding(.vertical, 2)
    }

    private func dimension(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.mono(11.5)).foregroundStyle(Theme.faint)
            TextField(label, value: value, format: .number.precision(.fractionLength(1)))
                .font(.mono(14))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 52, height: 30)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            Stepper(label, value: value, in: 0.5...30, step: 0.5).labelsHidden()
        }
    }
}

#Preview {
    NavigationStack { ManualRoomsEditor { _, _ in } }
}
