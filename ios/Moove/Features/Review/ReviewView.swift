import SwiftUI
import MooveKit

/// Every item grouped by disposition. "Needs you" (possibly sentimental or
/// undecided) is first. Any decision can be changed with a swipe or menu;
/// user decisions are never overwritten by the agents.
struct ReviewView: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        let sections = Review.sections(store.visibleItems)
        // A plain List (not a ScrollView) so rows keep their swipe actions; the theme comes from
        // clear row backgrounds, gutter insets and rule-colored separators.
        List {
            Section {
                PageHeader(
                    eyebrow: "03 — Review",
                    title: "Decide what goes.",
                    lede: "Keep, sell, donate or trash. Swipe a row to change it. Your calls always win over the agents'."
                )
                .padding(.top, 16)
                .padding(.bottom, store.visibleItems.isEmpty ? 28 : 24)
                .chromeRow()
                if store.visibleItems.isEmpty {
                    ReviewEmptyState().chromeRow()
                } else {
                    ReviewTotalsHeader(totals: Review.totals(store.visibleItems)).chromeRow()
                    if !sections.contains(where: { $0.section == .needsYou }) {
                        Label("All caught up: nothing needs you. Swipe any row to change it.", systemImage: "checkmark.circle")
                            .monoMeta()
                            .foregroundStyle(Theme.accentStrong)
                            .padding(.top, 16)
                            .chromeRow()
                    }
                }
            }
            .listSectionSeparator(.hidden)
            let closeups = Review.wantingCloseups(store.visibleItems)
            if !closeups.isEmpty {
                // #276: one more photo would pin down these items' exact model, and so their price
                Section {
                    ListHeader(title: "A photo would help", count: "\(closeups.count)")
                        .padding(.top, 40)
                        .chromeRow()
                    ForEach(closeups) { item in
                        NavigationLink(value: item.id) { ReviewRow(item: item) }
                            .ledgerListRow()
                    }
                    Text("Open one and tap Add another photo. Moove identifies and prices it again.")
                        .monoMeta()
                        .padding(.top, 12)
                        .chromeRow()
                }
                .listSectionSeparator(.hidden)
            }
            ForEach(sections, id: \.section) { group in
                Section {
                    ListHeader(title: group.section.title, count: "\(group.items.count)")
                        .padding(.top, 40)
                        .chromeRow()
                    ForEach(group.items) { item in
                        NavigationLink(value: item.id) { ReviewRow(item: item) }
                            .swipeActions(edge: .leading) { swipe(item, .keep); swipe(item, .sell) }
                            .swipeActions(edge: .trailing) { swipe(item, .trash); swipe(item, .donate) }
                            .contextMenu { DispositionMenu(item: item) }
                            .ledgerListRow()
                    }
                    if group.section == .needsYou {
                        Text("Moove never decides possibly sentimental items for you.")
                            .monoMeta()
                            .padding(.top, 12)
                            .chromeRow()
                    }
                }
                .listSectionSeparator(.hidden)
            }
            Color.clear.frame(height: 32).chromeRow()
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UInt64.self) { ItemDetailView(itemId: $0) }
        .mooveScreen()
        .animation(.default, value: store.visibleItems)
    }

    private func swipe(_ item: Item, _ disposition: Disposition) -> some View {
        Button(disposition.label, systemImage: disposition.systemImage) {
            Task { await store.setDisposition(disposition, for: item) }
        }
        .tint(ReviewPalette.swipe(disposition))
    }
}

/// Theme colors for dispositions on this screen (the shared `Disposition.tint` lives in ItemViews).
enum ReviewPalette {
    /// Swatch for the small dot beside a disposition, as in the summary's breakdown.
    static func dot(_ d: Disposition) -> Color {
        switch d {
        case .keep: Theme.accent
        case .sell: Theme.ochre
        case .donate: Theme.slate
        case .trash: Theme.stone
        case .undecided: Theme.danger
        }
    }

    /// Swipe buttons draw white labels in both modes, so these stay dark and fixed.
    static func swipe(_ d: Disposition) -> Color {
        switch d {
        case .keep: Theme.color(0x5E6D50)
        case .sell: Theme.color(0x86621F)
        case .donate: Theme.color(0x55657A)
        case .trash: Theme.color(0x665E52)
        case .undecided: Theme.color(0xA24D35)
        }
    }
}

private extension View {
    /// A non-interactive row (heading, note, stats): no separator, page background, gutter insets.
    func chromeRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.bg)
    }

    /// An item row: page background and a full-width rule-colored separator.
    func ledgerListRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: Theme.gutter, bottom: 0, trailing: Theme.gutter))
            .listRowBackground(Theme.bg)
            .listRowSeparatorTint(Theme.line)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

private struct ReviewEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing to review").blockTitle()
            Text("Scan a room first.").monoMeta()
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .combine)
    }
}

struct ReviewRow: View {
    let item: Item

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ItemThumbnail(item: item, size: 56)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name).blockTitle().lineLimit(2)
                    if item.maybeSentimental {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                            .accessibilityLabel("Possibly sentimental")
                    }
                    Spacer(minLength: 8)
                    Text(item.saleValueCents?.usd ?? "—").rowValue()
                }
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(ReviewPalette.dot(item.disposition)).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                        Text(item.disposition.label).monoText(12.5).foregroundStyle(Theme.text)
                    }
                    if item.dispositionSource == .user || item.disposition != .undecided {
                        Text("·").monoText(12.5).foregroundStyle(Theme.faint).accessibilityHidden(true)
                        Text(item.dispositionSource == .user ? "You decided" : "Auto").monoMeta()
                    }
                }
                if let reason = item.dispositionReason, item.dispositionSource == .auto {
                    Text(reason)
                        .sansText(14)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
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
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
            GridRow {
                StatFigure(label: "Expected sales", value: totals.expectedSaleCents.usd, tint: Theme.accentStrong)
                    .padding(.vertical, 18)
                StatFigure(label: "Items to move", value: "\(totals.itemsToMove)")
                    .padding(.vertical, 18)
            }
            Rectangle().fill(Theme.line).frame(height: 1).gridCellUnsizedAxes(.horizontal)
            GridRow {
                StatFigure(label: "Volume to move",
                           value: totals.volumeToMoveM3.formatted(.number.precision(.fractionLength(1))) + " m³")
                    .padding(.vertical, 18)
                if totals.needsYou > 0 {
                    StatFigure(label: "Need you", value: "\(totals.needsYou)", tint: Theme.danger)
                        .padding(.vertical, 18)
                } else {
                    StatFigure(label: "Need you", value: "0")
                        .padding(.vertical, 18)
                }
            }
        }
        .ruled(.top)
        .ruled()
    }
}

#Preview {
    NavigationStack { ReviewView() }.environment(MooveStore.preview())
}
