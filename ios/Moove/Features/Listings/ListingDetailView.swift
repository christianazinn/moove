import SwiftUI
import MooveKit

/// One listing, laid out like the marketplace page a buyer would see.
struct ListingDetailView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.openURL) private var openURL
    let listingId: UInt64
    @State private var copied = false

    var body: some View {
        if let listing = store.snapshot.listings.first(where: { $0.id == listingId }) {
            content(listing, item: store.items.first { $0.id == listing.itemId })
        } else {
            ContentUnavailableView("Listing removed", systemImage: "tag")
        }
    }

    private func content(_ listing: Listing, item: Item?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if listing.simulated {
                    Label("Simulated post. Not live on eBay.", systemImage: "info.circle")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(.yellow.opacity(0.18), in: .rect(cornerRadius: 8))
                }
                if let item {
                    ItemThumbnail(item: item, size: 320)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(listing.title).font(.title3.weight(.semibold))
                    Text(listing.priceCents.usd).font(.largeTitle.weight(.bold).monospacedDigit())
                    HStack {
                        ListingStatusChip(status: listing.status)
                        if let number = listing.externalId {
                            Text("eBay #\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                if listing.status == .awaitingApproval {
                    Label("Over your approval limit. Approve it on your phone to post.", systemImage: "hand.raised")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                VStack(spacing: 10) {
                    if let url = listing.url.flatMap(URL.init(string:)) {
                        Button { openURL(url) } label: {
                            Label("View listing page", systemImage: "safari").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    HStack {
                        Button {
                            UIPasteboard.general.string = listing.copyText
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        ShareLink(item: listing.copyText) {
                            Label("Cross-post", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    Text("Copy the text to post on FB Marketplace or Craigslist.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text("About this item").font(.headline)
                Text(listing.description).font(.body)
                if let item {
                    Divider()
                    LabeledContent("Category", value: item.category)
                    if let brand = item.brand { LabeledContent("Brand", value: brand) }
                    if let value = item.estValueCents { LabeledContent("Moove estimate", value: value.usd) }
                }
            }
            .padding()
        }
        .navigationTitle("Listing")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: listing.status) { _, new in new == .posted || new == .sold }
    }
}

#Preview {
    NavigationStack { ListingDetailView(listingId: 201) }.environment(MooveStore.preview())
}
