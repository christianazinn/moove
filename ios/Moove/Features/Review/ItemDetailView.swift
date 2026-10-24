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
                .foregroundStyle(Theme.muted)
                .mooveScreen()
        }
    }

    private func content(_ item: Item) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("03 — Review · Item").eyebrow().padding(.bottom, 16)
                ItemThumbnail(item: item, size: 200)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.name)
                            .monoText(20, weight: .bold, maxScale: 1.6)
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if item.maybeSentimental {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.danger)
                                .accessibilityLabel("Possibly sentimental")
                        }
                    }
                    Text(item.estValueCents == nil ? item.priceText.capitalizedFirst : item.priceText)
                        .monoText(32, weight: .bold, maxScale: 1.6)
                        .tracking(-0.3)
                        .foregroundStyle(item.estValueCents == nil ? Theme.muted : Theme.text)
                        .accessibilityLabel("Estimated value: \(item.priceText)")
                    if item.priceState == .unpriced {
                        Text("The pricing agent couldn't price this one. It's still sorted by size, condition and category, and you can choose below.")
                            .monoMeta()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DispositionChip(disposition: item.disposition)
                }

                decision(item)
                details(item)
                comps(item)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
    }

    // MARK: Sections

    @ViewBuilder private func decision(_ item: Item) -> some View {
        ListHeader(title: "Decision").padding(.top, 40)
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { dispositionChoices(item) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 0) {
                    dispositionChoices(item)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Disposition")
            .accessibilityIdentifier("item.disposition")
            if item.disposition == .undecided {
                Text("Undecided. Pick one.").monoMeta()
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
        detail("Decided by", item.dispositionSource == .user ? "You" : "Moove (auto)")
        if let reason = item.dispositionReason {
            Text(reason)
                .sansText(15)
                .lineSpacing(3)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ruled()
        }
        Toggle(isOn: Binding(
            get: { item.maybeSentimental },
            set: { v in Task { await store.setSentimental(v, for: item) } }
        )) {
            Text("Possibly sentimental").monoText(13.5).foregroundStyle(Theme.text)
        }
        .tint(Theme.accentFill)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .ruled()
    }

    /// Same behavior as the old menu picker: choosing the current value does nothing.
    @ViewBuilder private func dispositionChoices(_ item: Item) -> some View {
        ForEach(Disposition.choices, id: \.self) { d in
            ChoiceChip(title: d.label, selected: item.disposition == d) {
                guard item.disposition != d else { return }
                Task { await store.setDisposition(d, for: item) }
            }
        }
    }

    @ViewBuilder private func details(_ item: Item) -> some View {
        ListHeader(title: "Details").padding(.top, 40)
        detail("Estimated value", item.estValueCents?.usd ?? "Pricing…")
        detail("Category", item.category)
        if let material = item.material { detail("Material", material) }
        if let brand = item.brand { detail("Brand", brand) }
        if let condition = item.condition { detail("Condition", "\(condition) / 5") }
        detail("Size", dims(item))
        if item.fragile {
            Label("Fragile", systemImage: "exclamationmark.triangle")
                .monoText(13.5, weight: .bold)
                .foregroundStyle(Theme.danger)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .ruled()
        }
    }

    @ViewBuilder private func comps(_ item: Item) -> some View {
        let comps = store.snapshot.comps(for: item.id)
        if !comps.isEmpty {
            ListHeader(title: "Comparable listings", count: "\(comps.count)").padding(.top, 40)
            ForEach(comps) { comp in
                if let url = URL(string: comp.url) {
                    Link(destination: url) { compRow(comp, linked: true) }
                        .buttonStyle(.plain)
                } else {
                    compRow(comp, linked: false)
                }
            }
        }
    }

    private func compRow(_ comp: Comp, linked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(comp.title).blockTitle().lineLimit(2)
                Text(comp.source.uppercased()).monoMeta()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(comp.priceCents.usd).rowValue().layoutPriority(1)
            if linked {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .ruled()
        .accessibilityElement(children: .combine)
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).monoText(13.5).foregroundStyle(Theme.muted)
            Spacer(minLength: 12)
            Text(value).rowValue()
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .ruled()
        .accessibilityElement(children: .combine)
    }

    private func dims(_ item: Item) -> String {
        let f = { (v: Double) in v.formatted(.number.precision(.fractionLength(2))) }
        return "\(f(item.widthM)) × \(f(item.depthM)) × \(f(item.heightM)) m"
    }
}

#Preview {
    NavigationStack { ItemDetailView(itemId: 11) }.environment(MooveStore.preview())
}
