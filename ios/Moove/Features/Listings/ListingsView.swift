import SwiftUI
import MooveKit

/// Everything the listing agent (#11) is selling: drafting, waiting on the
/// user's approval, live, and sold.
struct ListingsView: View {
    @Environment(MooveStore.self) private var store

    private static let groups: [(title: String, statuses: [ListingStatus])] = [
        ("Needs you", [.awaitingApproval]),
        ("Live", [.posted]),
        ("Drafting", [.draft]),
        ("Sold", [.sold]),
        ("Not posted", [.rejected, .failed]),
    ]

    var body: some View {
        let listings = store.snapshot.listings.sorted { $0.updatedAt > $1.updatedAt }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "04 — Sell",
                    title: "Your listings.",
                    lede: "What the listing agent is selling for you: drafting, waiting on your OK, live and sold."
                )
                if listings.isEmpty {
                    emptyState.padding(.top, 32)
                } else {
                    totals(listings).padding(.top, 28)
                }
                ForEach(Self.groups, id: \.title) { group in
                    let rows = listings.filter { group.statuses.contains($0.status) }
                    if !rows.isEmpty {
                        ListHeader(title: group.title, count: "\(rows.count)")
                            .padding(.top, 40)
                        ForEach(rows) { listing in
                            NavigationLink(value: listing.id) { ListingRow(listing: listing, item: item(for: listing)) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Listings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UInt64.self) { ListingDetailView(listingId: $0) }
        .mooveScreen()
        .animation(.default, value: listings)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No listings yet").blockTitle()
            Text("Items sorted to Sell show up here once the listing agent writes them.").monoMeta()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .combine)
    }

    private func item(for listing: Listing) -> Item? {
        store.items.first { $0.id == listing.itemId }
    }

    /// Three headline figures between rules, split by hairlines.
    private func totals(_ listings: [Listing]) -> some View {
        let live = listings.filter { $0.status == .posted }
        let sold = listings.filter { $0.status == .sold }
        return HStack(spacing: 0) {
            StatFigure(label: "Live", value: "\(live.count)")
                .padding(.vertical, 18).padding(.trailing, 14)
            Rectangle().fill(Theme.line).frame(width: 1)
            StatFigure(label: "Listed", value: live.map(\.priceCents).reduce(0, +).usd)
                .padding(.vertical, 18).padding(.horizontal, 14)
            Rectangle().fill(Theme.line).frame(width: 1)
            StatFigure(label: "Sold", value: sold.map(\.priceCents).reduce(0, +).usd, tint: Theme.accentStrong)
                .padding(.vertical, 18).padding(.leading, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
        .ruled(.top)
        .ruled()
    }
}

/// A ledger row: photo, bold mono title, status, price and simulated tag on the right.
struct ListingRow: View {
    let listing: Listing
    let item: Item?

    var body: some View {
        HStack(spacing: 16) {
            if let item { ItemThumbnail(item: item, size: 56) } else { IconTile(systemName: "tag") }
            VStack(alignment: .leading, spacing: 5) {
                Text(listing.title).blockTitle().lineLimit(2)
                ListingStatusChip(status: listing.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                Text(listing.priceCents.usd).rowValue()
                if listing.simulated { SimulatedTag() }
            }
            .layoutPriority(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Theme.faint)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .ruled()
    }
}

#Preview {
    NavigationStack { ListingsView() }.environment(MooveStore.preview())
}
