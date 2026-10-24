import SwiftUI
import MooveKit

/// "Name it…" on a scan checklist row: a name and/or what it is, before the import. The name
/// goes in as the item's name (kept through vision), the kind as its `UserKind.*` and category,
/// so the 3D model is right from the start. Either part can be left empty.
struct ScanLabelSheet: View {
    let title: String
    let label: ItemLabels.Label?
    let onSave: (ItemLabels.Label?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: ItemFix.QuickKind?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Moove keeps your name.")
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 20)
                    Text("Name").eyebrow()
                    TextField("e.g. Grandma's rocking chair", text: $name)
                        .monoText(16, weight: .bold)
                        .foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(save)
                        .frame(minHeight: 44)
                        .ruled()
                        .accessibilityLabel("Item name")
                        .accessibilityIdentifier("scan.label.name")
                    Text("What is it?").eyebrow().padding(.top, 24).padding(.bottom, 6)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 0) {
                        ForEach(ItemFix.QuickKind.allCases) { k in
                            ChoiceChip(title: k.label, selected: k == kind) { kind = (kind == k) ? nil : k }
                                .accessibilityLabel(k == .other ? "Other, automatic" : "It's a \(k.label)")
                                .accessibilityIdentifier("scan.label.kind.\(k.rawValue)")
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .mooveScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).accessibilityIdentifier("scan.label.save")
                }
                if label != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Let Moove name it", role: .destructive) { onSave(nil); dismiss() }
                            .accessibilityIdentifier("scan.label.clear")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            name = label?.name ?? ""
            kind = label?.kind
            nameFocused = label == nil
        }
    }

    private func save() {
        onSave(ItemLabels.Label(name: name, kind: kind))
        dismiss()
    }
}
