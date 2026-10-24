import SwiftUI
import MooveKit

/// Everything the listing agent (#11) is selling: drafting, waiting on the
/// user's approval, live, sold, and what didn't post (with the agent's reason).
struct ListingsView: View {
    @Environment(MooveStore.self) private var store

    private static let groups: [(title: String, statuses: [ListingStatus])] = [
        ("Needs approval", [.awaitingApproval]),
        ("Live", [.posted]),
        ("Drafting", [.draft, .posting]), // `posting` lasts seconds, so it stays with the work in progress (#144)
        ("Sold", [.sold]),
        ("Not posted", [.rejected, .failed]),
    ]

    var body: some View {
        let listings = store.snapshot.listings.sorted { $0.updatedAt > $1.updatedAt }
        let state = store.commerceState(hasRows: !listings.isEmpty)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if state != .content {
                    CommercePlaceholder(
                        state: state,
                        emptyTitle: "No listings yet",
                        emptyDetail: "Sort an item to Sell in Review. Once it's priced, the listing agent drafts an eBay listing and it shows up here."
                    )
                    .padding(.top, 32)
                } else {
                    totals(listings).padding(.top, 28)
                }
                ForEach(Self.groups, id: \.title) { group in
                    let rows = listings.filter { group.statuses.contains($0.status) }
                    if !rows.isEmpty {
                        ListHeader(title: group.title, count: "\(rows.count)")
                            .padding(.top, 40)
                        // Own VStack per group, so a listing that changes group (awaiting approval ->
                        // posted) can't collide with its old row in the LazyVStack (same bug as Approvals).
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { listing in
                                NavigationLink(value: ListingRoute(listingId: listing.id)) {
                                    ListingRow(listing: listing, item: item(for: listing),
                                               problem: store.snapshot.problem(for: listing))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if listings.contains(where: \.simulated) {
                    Text("SIMULATED listings were never sent to eBay. The demo's eBay poster is simulated unless sandbox keys are set.")
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Listings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ListingRoute.self) { ListingDetailView(listingId: $0.listingId) }
        .mooveScreen()
        .animation(.default, value: listings)
    }

    private func item(for listing: Listing) -> Item? {
        store.items.first { $0.id == listing.itemId }
    }

    /// Three headline figures between rules, split by hairlines.
    private func totals(_ listings: [Listing]) -> some View {
        let live = listings.filter { $0.status == .posted }
        let sold = listings.filter { $0.status == .sold }
        let listed = live.map(\.priceCents).reduce(0, +)
        let soldCents = sold.map(\.priceCents).reduce(0, +)
        return StatStrip(figures: [
            .init(label: "Live", value: "\(live.count)", spoken: "\(live.count) posted"),
            .init(label: "Listed", value: CentsFormat.usd(listed), spoken: "Listed, \(CentsFormat.usd(listed))"),
            .init(label: "Sold", value: CentsFormat.usd(soldCents), tint: Theme.accentStrong,
                  spoken: "Sold, \(CentsFormat.usd(soldCents))"),
        ])
    }
}

/// Its own route type, so it can't collide with another screen's `UInt64` destination when the
/// commerce screens share one navigation stack (proposal #129).
struct ListingRoute: Hashable {
    let listingId: UInt64
}

/// A ledger row: photo, bold mono title, status, price and simulated tag on the right.
struct ListingRow: View {
    let listing: Listing
    let item: Item?
    var problem: String? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the price and SIMULATED pill move under the title, which otherwise
        // gets a third of the row and breaks mid-word ("Lamina / te").
        let stacked = dynamicTypeSize.isAccessibilitySize
        HStack(spacing: 16) {
            if let item { ItemThumbnail(item: item, size: 56) } else { IconTile(systemName: "tag") }
            VStack(alignment: .leading, spacing: 5) {
                Text(listing.title).blockTitle().lineLimit(stacked ? 6 : 3).fixedSize(horizontal: false, vertical: true)
                ListingStatusChip(status: listing.status, simulated: listing.simulated)
                if let problem {
                    Text(problem).monoMeta().lineLimit(stacked ? 6 : 3)
                }
                if stacked {
                    Text(listing.formattedPrice).rowValue().amountText()
                    if listing.simulated { SimulatedTag() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(listing.formattedPrice).rowValue().amountText()
                    if listing.simulated { SimulatedTag() }
                }
                .layoutPriority(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .ruled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(listing.accessibilitySummary + (problem.map { ". \($0)" } ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("listing.\(listing.id)")
    }
}

#Preview {
    NavigationStack { ListingsView() }.environment(MooveStore.preview())
}
