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
        List {
            if !listings.isEmpty {
                Section { totals(listings) }
            }
            ForEach(Self.groups, id: \.title) { group in
                let rows = listings.filter { group.statuses.contains($0.status) }
                if !rows.isEmpty {
                    Section("\(group.title) · \(rows.count)") {
                        ForEach(rows) { listing in
                            NavigationLink(value: listing.id) { ListingRow(listing: listing, item: item(for: listing)) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Listings")
        .navigationDestination(for: UInt64.self) { ListingDetailView(listingId: $0) }
        .overlay {
            if listings.isEmpty {
                ContentUnavailableView("No listings yet", systemImage: "tag",
                                       description: Text("Items sorted to Sell show up here once the listing agent writes them."))
            }
        }
        .animation(.default, value: listings)
    }

    private func item(for listing: Listing) -> Item? {
        store.items.first { $0.id == listing.itemId }
    }

    private func totals(_ listings: [Listing]) -> some View {
        let live = listings.filter { $0.status == .posted }
        let sold = listings.filter { $0.status == .sold }
        return HStack {
            stat("\(live.count)", "live")
            Divider()
            stat(live.map(\.priceCents).reduce(0, +).usd, "listed")
            Divider()
            stat(sold.map(\.priceCents).reduce(0, +).usd, "sold", tint: .green)
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

struct ListingRow: View {
    let listing: Listing
    let item: Item?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let item { ItemThumbnail(item: item, size: 56) }
            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 6) {
                    Text(listing.priceCents.usd).font(.headline.monospacedDigit())
                    Spacer()
                    if listing.simulated { SimulatedTag() }
                }
                ListingStatusChip(status: listing.status)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { ListingsView() }.environment(MooveStore.preview())
}
