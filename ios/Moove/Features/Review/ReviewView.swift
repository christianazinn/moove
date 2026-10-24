import SwiftUI
import MooveKit

/// Every item grouped by disposition. "Needs you" (possibly sentimental or
/// undecided) is first. Any decision can be changed with a swipe or menu;
/// user decisions are never overwritten by the agents.
struct ReviewView: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        let sections = Review.sections(store.items)
        List {
            if !store.items.isEmpty {
                Section { ReviewTotalsHeader(totals: Review.totals(store.items)) }
            }
            ForEach(sections, id: \.section) { group in
                Section {
                    ForEach(group.items) { item in
                        NavigationLink(value: item.id) { ReviewRow(item: item) }
                            .swipeActions(edge: .leading) { swipe(item, .keep); swipe(item, .sell) }
                            .swipeActions(edge: .trailing) { swipe(item, .trash); swipe(item, .donate) }
                            .contextMenu { DispositionMenu(item: item) }
                    }
                } header: {
                    Text("\(group.section.title) · \(group.items.count)")
                } footer: {
                    if group.section == .needsYou {
                        Text("Moove never decides possibly sentimental items for you.")
                    }
                }
            }
        }
        .navigationTitle("Review")
        .navigationDestination(for: UInt64.self) { ItemDetailView(itemId: $0) }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView("Nothing to review", systemImage: "checklist", description: Text("Scan a room first."))
            }
        }
        .animation(.default, value: store.items)
    }

    private func swipe(_ item: Item, _ disposition: Disposition) -> some View {
        Button(disposition.label, systemImage: disposition.systemImage) {
            Task { await store.setDisposition(disposition, for: item) }
        }
        .tint(disposition.tint)
    }
}

struct ReviewRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ItemThumbnail(item: item)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name).font(.headline).lineLimit(1)
                    if item.maybeSentimental {
                        Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
                            .accessibilityLabel("Possibly sentimental")
                    }
                    Spacer()
                    Text(item.estValueCents?.usd ?? "—").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    DispositionChip(disposition: item.disposition)
                    if item.dispositionSource == .user || item.disposition != .undecided {
                        Text(item.dispositionSource == .user ? "You decided" : "Auto")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let reason = item.dispositionReason, item.dispositionSource == .auto {
                    Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct DispositionMenu: View {
    @Environment(MooveStore.self) private var store
    let item: Item

    var body: some View {
        ForEach(Disposition.choices, id: \.self) { d in
            Button(d.label, systemImage: d.systemImage) { Task { await store.setDisposition(d, for: item) } }
                .disabled(item.disposition == d && item.dispositionSource == .user)
        }
        Divider()
        Button(item.maybeSentimental ? "Not sentimental" : "Mark sentimental", systemImage: item.maybeSentimental ? "heart.slash" : "heart") {
            Task { await store.setSentimental(!item.maybeSentimental, for: item) }
        }
    }
}

struct ReviewTotalsHeader: View {
    let totals: ReviewTotals

    var body: some View {
        HStack {
            stat(totals.expectedSaleCents.usd, "expected sales")
            Divider()
            stat("\(totals.itemsToMove)", "items to move")
            Divider()
            stat(totals.volumeToMoveM3.formatted(.number.precision(.fractionLength(1))) + " m³", "to move")
            if totals.needsYou > 0 {
                Divider()
                stat("\(totals.needsYou)", "need you", tint: .orange)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack { ReviewView() }.environment(MooveStore.preview())
}
