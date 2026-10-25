import SwiftUI
import MooveKit

/// Everything the listing agent (#11) is selling, as posters on a wall: drafting, waiting on the
/// user's approval, live, sold, and what didn't post (with the agent's reason). Each poster's
/// colors, type treatment and tilt come from MooveKit `PosterWall` (colors: `PosterPalette`).
struct ListingsView: View {
    @Environment(MooveStore.self) private var store
    @Environment(AuthService.self) private var auth: AuthService?
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom
    /// Posters already pinned up this visit (each one animates in once; pull to refresh re-pins).
    @State private var pinned: Set<UInt64> = []
    @State private var copied: UInt64?

    private static let groups: [(title: String, statuses: [ListingStatus])] = [
        ("Needs approval", [.awaitingApproval]),
        ("Live", [.posted]),
        ("Drafting", [.draft, .posting]), // `posting` lasts seconds, so it stays with the work in progress (#144)
        ("Sold", [.sold]),
        ("Not posted", [.rejected, .failed]),
    ]

    var body: some View {
        // A listing an older worker drafted for a built-in fixture (a toilet) isn't a real sale.
        let listings = store.snapshot.listings.filter { item(for: $0)?.isBuiltInFixture != true }.sorted { $0.updatedAt > $1.updatedAt }
        let state = store.commerceState(hasRows: !listings.isEmpty)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if state != .content {
                    CommercePlaceholder(
                        state: state,
                        emptyTitle: "No listings yet",
                        emptyDetail: "Sort an item to Sell in Review. Once it's priced, its eBay listing shows up here."
                    )
                    .padding(.top, 32)
                } else {
                    FlyerTotals(totals: PosterWall.totals(listings)).padding(.top, 24)
                }
                ForEach(Self.groups, id: \.title) { group in
                    let rows = listings.filter { group.statuses.contains($0.status) }
                    if !rows.isEmpty {
                        Text(group.title)
                            .listHeading()
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel("\(group.title), \(rows.count)")
                            .padding(.top, Theme.Space.section)
                        // Own stack per group, so a listing that changes group (awaiting approval ->
                        // posted) can't collide with its old poster in the LazyVStack (same bug as Approvals).
                        wall(rows).padding(.top, 22)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .background(PosterWallBackground())
        .refreshable { await refresh(listings) }
        .navigationTitle("Listings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ListingRoute.self) { route in
            ListingDetailView(listingId: route.listingId).zoomDestination(id: route.listingId, in: zoom)
        }
        .mooveScreen()
        .animation(.default, value: listings)
        .sensoryFeedback(.success, trigger: copied) { _, new in new != nil }
    }

    // MARK: Wall

    private func wall(_ rows: [Listing]) -> some View {
        let columns = PosterWall.columns(regularWidth: sizeClass == .regular,
                                         accessibilitySize: dynamicTypeSize.isAccessibilitySize)
        let order = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
        // A poster with a reason under its price runs taller.
        let dealt = PosterWall.deal(rows, columns: columns) { store.snapshot.problem(for: $0) == nil ? 1 : 1.3 }
        return HStack(alignment: .top, spacing: 18) {
            ForEach(dealt.indices, id: \.self) { c in
                VStack(spacing: 30) {
                    ForEach(dealt[c]) { listing in
                        poster(listing, order: order[listing.id] ?? 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func poster(_ listing: Listing, order: Int) -> some View {
        let style = PosterWall.style(forListingId: listing.id, straight: dynamicTypeSize.isAccessibilitySize)
        let problem = store.snapshot.problem(for: listing)
        let approval = pendingApproval(for: listing)
        return NavigationLink(value: ListingRoute(listingId: listing.id)) {
            ListingPoster(listing: listing, item: item(for: listing), problem: problem, style: style)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(listing.accessibilitySummary + (problem.map { ". \($0)" } ?? ""))
                .accessibilityHint("Opens the listing")
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("listing.\(listing.id)")
                .accessibilityAction(named: "Copy listing text") { copy(listing) }
        }
        .buttonStyle(PosterPressStyle(tilt: style.tiltDegrees))
        .zoomSource(id: listing.id, in: zoom)
        .modifier(PinIn(pinned: reduceMotion || pinned.contains(listing.id), tilt: style.tiltDegrees))
        .onAppear { pin(listing.id, order: order) }
        // Quick actions (long press).
        .contextMenu {
            Button(copied == listing.id ? "Copied" : "Copy listing text", systemImage: "doc.on.doc") { copy(listing) }
            ShareLink(item: listing.copyText) { Label("Cross-post", systemImage: "square.and.arrow.up") }
            if let url = listing.viewURL(uploadBase: store.uploadBaseURL) {
                Button(listing.simulated ? "View simulated listing page" : "View on eBay", systemImage: "safari") { openURL(url) }
            }
            if let approval, store.snapshot.canDecide(approval) {
                Divider()
                Button("Approve and post", systemImage: "checkmark") { Task { await store.decide(approval, approve: true) } }
                Button("Deny", systemImage: "xmark", role: .destructive) { Task { await store.decide(approval, approve: false) } }
            }
        }
    }

    private func pendingApproval(for listing: Listing) -> Approval? {
        guard listing.status == .awaitingApproval else { return nil }
        return store.pendingApprovals.first { $0.kind == .listing && $0.refId == listing.id }
    }

    private func item(for listing: Listing) -> Item? {
        store.items.first { $0.id == listing.itemId }
    }

    private func copy(_ listing: Listing) {
        UIPasteboard.general.string = listing.copyText
        copied = listing.id
    }

    // MARK: Pinning up

    private func pin(_ id: UInt64, order: Int) {
        guard !pinned.contains(id) else { return }
        if reduceMotion {
            pinned.insert(id)
            return
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72).delay(min(Double(order) * 0.07, 0.42))) {
            _ = pinned.insert(id)
        }
    }

    /// Pull to refresh: reconnect if the live backend dropped, then pin the wall up again.
    private func refresh(_ listings: [Listing]) async {
        if store.backendKind != .fixture, store.status != .connected, let auth {
            await store.connect(token: await auth.spacetimeToken())
        } else {
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard !reduceMotion else { return }
        pinned = []
        for (i, listing) in listings.enumerated() { pin(listing.id, order: i % 6) }
    }
}

/// Its own route type, so it can't collide with another screen's `UInt64` destination when the
/// commerce screens share one navigation stack (proposal #129).
struct ListingRoute: Hashable {
    let listingId: UInt64
}

extension View {
    /// iOS 18+: the poster is the source of a zoom into the listing. iOS 17 pushes as usual.
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// iOS 18+: the listing zooms out of its poster (and back into it on the way back).
    @ViewBuilder
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

#Preview {
    NavigationStack { ListingsView() }.environment(MooveStore.preview())
}
