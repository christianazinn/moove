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
                .foregroundStyle(Theme.muted)
                .mooveScreen()
        }
    }

    private func content(_ listing: Listing, item: Item?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("04 — Sell · Listing").eyebrow().padding(.bottom, 16)
                if listing.simulated {
                    notice("Simulated post. Not live on eBay.", systemImage: "info.circle", tint: Theme.ochre)
                        .padding(.bottom, 20)
                }
                if let item {
                    ItemThumbnail(item: item, size: 320)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 24)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(listing.title)
                        .monoText(20, weight: .bold, maxScale: 1.6)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(listing.priceCents.usd)
                        .monoText(32, weight: .bold, maxScale: 1.6)
                        .tracking(-0.3)
                        .foregroundStyle(Theme.text)
                    HStack(spacing: 10) {
                        ListingStatusChip(status: listing.status)
                        if listing.simulated { SimulatedTag() }
                        if let number = listing.externalId {
                            Text("eBay #\(number)").monoMeta()
                        }
                    }
                }
                if listing.status == .awaitingApproval {
                    notice("Over your approval limit. Approve it on your phone to post.", systemImage: "hand.raised", tint: Theme.ochre)
                        .padding(.top, 20)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let url = listing.url.flatMap(URL.init(string:)) {
                        Button { openURL(url) } label: {
                            Label("View listing page", systemImage: "safari").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pill(.primary))
                    }
                    HStack(spacing: 10) {
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
                    .buttonStyle(.pill(.outline))
                    Text("Copy the text to post on FB Marketplace or Craigslist.").monoMeta()
                }
                .padding(.top, 28)

                ListHeader(title: "About this item").padding(.top, 40)
                Text(listing.description)
                    .sansText(15.5)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                if let item {
                    ListHeader(title: "Details").padding(.top, 40)
                    detail("Category", item.category)
                    if let brand = item.brand { detail("Brand", brand) }
                    if let value = item.estValueCents { detail("Moove estimate", value.usd) }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Listing")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .sensoryFeedback(.success, trigger: listing.status) { _, new in new == .posted || new == .sold }
    }

    /// Demo/attention notice: mono text on the raised surface with a colored left edge.
    private func notice(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .accessibilityHidden(true)
            Text(text)
                .monoText(13)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: UnevenRoundedRectangle(bottomTrailingRadius: Theme.radiusSmall, topTrailingRadius: Theme.radiusSmall))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
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
}

#Preview {
    NavigationStack { ListingDetailView(listingId: 201) }.environment(MooveStore.preview())
}
