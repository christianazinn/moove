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
            ContentUnavailableView("Listing removed", systemImage: "tag",
                                   description: Text("This listing is no longer synced. Go back to see the rest."))
                .foregroundStyle(Theme.muted)
                .mooveScreen()
        }
    }

    private func content(_ listing: Listing, item: Item?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("04 — Sell · Listing").eyebrow().padding(.bottom, 16)
                if listing.simulated {
                    notice("Simulated post. Not live on eBay, and no buyer can see it.", systemImage: "info.circle", tint: Theme.ochre)
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
                    Text(listing.formattedPrice)
                        .monoText(32, weight: .bold, maxScale: 1.6)
                        .tracking(-0.3)
                        .foregroundStyle(Theme.text)
                        .amountText()
                    AdaptiveLine(spacing: 10) {
                        ListingStatusChip(status: listing.status, simulated: listing.simulated)
                        if listing.simulated { SimulatedTag() }
                        // A simulated listing's item number is made up, so only real posts show one.
                        if let number = listing.displayExternalId {
                            Text("eBay #\(number)").monoMeta()
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(listing.accessibilitySummary + (listing.displayExternalId.map { ", eBay item \($0)" } ?? ""))
                .accessibilityAddTraits(.isHeader)
                switch listing.status {
                case .awaitingApproval where store.snapshot.isShared(listing):
                    // Shared-room item someone else owns (#195): any room member may decide it (#200).
                    notice("Over \(store.snapshot.ownerName(listing.owner))'s approval limit. Anyone in the room can approve it in Approvals to post it.",
                           systemImage: "hourglass", tint: Theme.ochre)
                        .padding(.top, 20)
                case .awaitingApproval:
                    notice("Over your approval limit. Approve it in Approvals, or on your phone if Auth0 Guardian is set up, to post it.",
                           systemImage: "hand.raised", tint: Theme.ochre)
                        .padding(.top, 20)
                case .rejected:
                    notice(store.snapshot.problem(for: listing).map { "\($0). Nothing was posted to eBay." } ?? "Not posted: the request was denied or the price changed.",
                           systemImage: "xmark.circle", tint: Theme.danger)
                        .padding(.top, 20)
                case .failed:
                    notice("Couldn't post this listing. \(store.snapshot.problem(for: listing) ?? "The listing agent hit an error"). You can still copy the text and post it yourself.",
                           systemImage: "exclamationmark.triangle", tint: Theme.danger)
                        .padding(.top, 20)
                case .draft:
                    notice("The listing agent is still drafting this. It posts once it's ready, or asks you first if it's over your limit.",
                           systemImage: "pencil.line", tint: Theme.muted)
                        .padding(.top, 20)
                case .posting:
                    notice(listing.simulated ? "The listing agent is posting this now. It's a simulated post, so nothing goes to eBay." : "The listing agent is posting this to eBay now.",
                           systemImage: "arrow.up.circle", tint: Theme.muted)
                        .padding(.top, 20)
                case .posted, .sold:
                    EmptyView()
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let url = listing.url.flatMap(URL.init(string:)) {
                        Button { openURL(url) } label: {
                            Label(listing.simulated ? "View simulated listing page" : "View on eBay", systemImage: "safari")
                                .frame(maxWidth: .infinity)
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
                    .accessibilityHint("Copies the title, price and description")
                    Text("Copy the text to post on FB Marketplace or Craigslist.").monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
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
