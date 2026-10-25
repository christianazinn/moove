import SwiftUI
import MooveKit

/// One listing, laid out like the marketplace page a buyer would see.
struct ListingDetailView: View {
    @Environment(MooveStore.self) private var store
    @Environment(\.openURL) private var openURL
    let listingId: UInt64
    @State private var copied = false
    @State private var deciding = false

    var body: some View {
        if let listing = store.snapshot.listings.first(where: { $0.id == listingId }) {
            content(listing, item: store.items.first { $0.id == listing.itemId })
        } else {
            EmptyState(title: "Listing removed", detail: "")
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .mooveScreen()
        }
    }

    private func content(_ listing: Listing, item: Item?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The poster, up close (iOS 18 zooms into this page from the poster on the wall).
                ListingPosterHero(listing: listing, item: item,
                                  style: PosterWall.style(forListingId: listing.id, straight: true))
                    .padding(.top, 10)
                    .padding(.bottom, Theme.Space.xl)
                header(listing)
                if let problem = failureText(listing) {
                    Text(problem)
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Theme.Space.m)
                }
                if let approval = pendingApproval(for: listing) {
                    decideButtons(approval).padding(.top, Theme.Space.l)
                }
                actions(listing).padding(.top, 28)
                Text(listing.description)
                    .sansText(15.5)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.section)
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

    /// Title, price, one status and the SIMULATED tag. The eBay item number and the approval
    /// limit are in the VoiceOver label only.
    private func header(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(listing.title)
                .monoText(20, weight: .bold, maxScale: 1.6)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(listing.formattedPrice)
                .monoText(32, weight: .bold, maxScale: 1.6)
                .tracking(-0.3)
                .foregroundStyle(Theme.text)
                .amountText()
            AdaptiveLine(spacing: 10) {
                ListingStatusChip(status: listing.status, simulated: listing.simulated)
                if listing.simulated { SimulatedTag() }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerLabel(listing))
        .accessibilityAddTraits(.isHeader)
    }

    private func headerLabel(_ listing: Listing) -> String {
        var label = listing.accessibilitySummary + (listing.displayExternalId.map { ", eBay item \($0)" } ?? "")
        if listing.simulated { label += ". Simulated post, not live on eBay" }
        if listing.status == .awaitingApproval {
            let whose = store.snapshot.isShared(listing) ? "\(store.snapshot.ownerName(listing.owner))'s" : "your"
            label += ". Over \(whose) approval limit"
        }
        return label
    }

    /// Only for a post that didn't happen: the agent's reason, short.
    private func failureText(_ listing: Listing) -> String? {
        switch listing.status {
        case .rejected: store.snapshot.problem(for: listing) ?? "Not posted"
        case .failed: store.snapshot.problem(for: listing) ?? "Couldn't post"
        default: nil
        }
    }

    private func actions(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = listing.viewURL(uploadBase: store.uploadBaseURL) {
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
            .accessibilityHint("Copies the title, price and description, to post on FB Marketplace or Craigslist")
        }
    }

    private func pendingApproval(for listing: Listing) -> Approval? {
        guard listing.status == .awaitingApproval else { return nil }
        return store.pendingApprovals.first { $0.kind == .listing && $0.refId == listing.id && store.snapshot.canDecide($0) }
    }

    /// Approve or deny right here (the same `decide_approval` as the Agents inbox).
    private func decideButtons(_ approval: Approval) -> some View {
        HStack(spacing: 10) {
            Button {
                decide(approval, approve: true)
            } label: {
                Label(deciding ? "Posting…" : "Approve and post", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.primary))
            .accessibilityIdentifier("listing.approve.\(approval.refId)")
            Button(role: .destructive) {
                decide(approval, approve: false)
            } label: {
                Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill(.outline))
            .accessibilityIdentifier("listing.deny.\(approval.refId)")
        }
        .disabled(deciding)
    }

    private func decide(_ approval: Approval, approve: Bool) {
        deciding = true
        Task {
            _ = await store.decide(approval, approve: approve)
            deciding = false
        }
    }
}

#Preview {
    NavigationStack { ListingDetailView(listingId: 201) }.environment(MooveStore.preview())
}
