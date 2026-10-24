import SwiftUI
import MooveKit

/// One item: photo, what the vision agent saw, why it was sorted this way,
/// and the comps behind its price.
struct ItemDetailView: View {
    @Environment(MooveStore.self) private var store
    let itemId: UInt64

    var body: some View {
        if let item = store.items.first(where: { $0.id == itemId }) {
            content(item)
        } else {
            ContentUnavailableView("Item removed", systemImage: "shippingbox")
        }
    }

    private func content(_ item: Item) -> some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    ItemThumbnail(item: item, size: 160)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section("Decision") {
                Picker("Disposition", selection: Binding(
                    get: { item.disposition },
                    set: { d in Task { await store.setDisposition(d, for: item) } }
                )) {
                    ForEach(Disposition.choices, id: \.self) { Label($0.label, systemImage: $0.systemImage).tag($0) }
                    if item.disposition == .undecided { Text("Undecided").tag(Disposition.undecided) }
                }
                .pickerStyle(.menu)
                LabeledContent("Decided by", value: item.dispositionSource == .user ? "You" : "Moove (auto)")
                if let reason = item.dispositionReason {
                    Text(reason).font(.callout).foregroundStyle(.secondary)
                }
                Toggle("Possibly sentimental", isOn: Binding(
                    get: { item.maybeSentimental },
                    set: { v in Task { await store.setSentimental(v, for: item) } }
                ))
            }
            Section("Details") {
                LabeledContent("Estimated value", value: item.estValueCents?.usd ?? "Pricing…")
                LabeledContent("Category", value: item.category)
                if let material = item.material { LabeledContent("Material", value: material) }
                if let brand = item.brand { LabeledContent("Brand", value: brand) }
                if let condition = item.condition { LabeledContent("Condition", value: "\(condition) / 5") }
                LabeledContent("Size", value: dims(item))
                if item.fragile { Label("Fragile", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            let comps = store.snapshot.comps(for: item.id)
            if !comps.isEmpty {
                Section("Comparable listings") {
                    ForEach(comps) { comp in
                        if let url = URL(string: comp.url) {
                            Link(destination: url) {
                                LabeledContent(comp.title, value: comp.priceCents.usd)
                            }
                        }
                        Text(comp.source.uppercased()).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dims(_ item: Item) -> String {
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(2))) }
        return "\(f(item.widthM)) × \(f(item.depthM)) × \(f(item.heightM)) m"
    }
}
