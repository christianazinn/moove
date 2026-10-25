import SwiftUI
import MooveKit

/// In-app approvals inbox (#12), the top of Sell & Buy > Agents. The worker also pushes each
/// request to the owner's phone via Auth0 Guardian (CIBA) when Auth0 is configured; this is the
/// always-available path. Both decide through `decide_approval`, and the listing agent posts or
/// rejects once it sees the decision.
///
/// "Needs your OK" lists pending requests (or one "Nothing waiting" line); "Decided" shows the
/// last few decisions with "Show all" for the rest.
struct ApprovalsSection: View {
    @Environment(MooveStore.self) private var store
    @State private var showAllDecided = false

    /// Decided rows shown before "Show all".
    static let decidedPreview = 3

    var body: some View {
        let pending = store.snapshot.pendingApprovals
        let decided = store.snapshot.decidedApprovals
        let shared = store.snapshot.sharedPendingApprovals
        VStack(alignment: .leading, spacing: 0) {
            if pending.isEmpty && shared.isEmpty {
                ListHeader(title: "Needs your OK", count: "0")
                Label("Nothing waiting", systemImage: "checkmark.circle")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ruled()
                    .accessibilityIdentifier("approvals.nothingWaiting")
            }
            if !pending.isEmpty {
                ListHeader(title: "Needs your OK", count: "\(pending.count)")
                // Each list in its own VStack: an approval's id is in `pending`, then in `decided`, and
                // sharing one LazyVStack's id space left the stale pending card showing under History.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(pending) { approval in
                        PendingApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                           deal: store.snapshot.deal(for: approval), item: item(for: approval))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                    Text("Also sent to your phone (Auth0 Guardian).")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .monoMeta()
                .padding(.top, 12)
            }
            if !shared.isEmpty {
                // Shared rooms (#195, #200): any room member may decide a listing approval.
                ListHeader(title: "Shared rooms", count: "\(shared.count)").padding(.top, pending.isEmpty ? 0 : Theme.Space.section)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shared) { approval in
                        PendingApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                           item: item(for: approval),
                                           sharedOwner: store.snapshot.ownerName(approval.owner))
                    }
                }
            }
            if !decided.isEmpty {
                let shown = showAllDecided ? decided : Array(decided.prefix(Self.decidedPreview))
                ListHeader(title: "Decided", count: "\(decided.count)").padding(.top, Theme.Space.section)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { approval in
                        DecidedApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                           deal: store.snapshot.deal(for: approval), item: item(for: approval))
                    }
                }
                if decided.count > Self.decidedPreview {
                    ShowAllButton(count: decided.count, expanded: $showAllDecided, id: "approvals.decided")
                }
            }
        }
        .animation(.default, value: pending)
        .animation(.default, value: decided)
        .animation(.default, value: shared)
    }

    private func item(for approval: Approval) -> Item? {
        guard let listing = store.snapshot.listing(for: approval) else { return nil }
        return store.items.first { $0.id == listing.itemId }
    }
}

struct PendingApprovalRow: View {
    @Environment(MooveStore.self) private var store
    let approval: Approval
    let listing: Listing?
    var deal: Deal? = nil
    let item: Item?
    /// Set for a shared-room item someone else owns (#200): their name, for the caption.
    var sharedOwner: String? = nil
    @State private var confirmDeny = false
    @State private var working = false
    @State private var approvedCount = 0
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                ApprovalThumbnail(approval: approval, item: item)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ApprovalKindTag(kind: approval.kind)
                        Spacer(minLength: 8)
                        if listing?.simulated == true { SimulatedTag() }
                        // #191: the worker's announced Visa mode; nothing when it didn't announce one.
                        switch railTag {
                        case .simulated?: SimulatedBadge(spoken: PurchaseRailTag.simulated.spoken)
                        case .sandbox?: MonoTag(text: PurchaseRailTag.sandbox.text, tone: Theme.muted)
                        case nil: EmptyView()
                        }
                    }
                    Text(listing?.title ?? deal?.title ?? approval.summary)
                        .blockTitle()
                        .fixedSize(horizontal: false, vertical: true)
                    AdaptiveLine {
                        Text(approval.formattedAmount)
                            .monoText(22, weight: .bold, maxScale: 1.6)
                            .foregroundStyle(Theme.text)
                            .amountText()
                        if let deal { Text("from \(deal.source)").monoMeta() }
                        Spacer(minLength: 8)
                        Text(approval.requestedAt, format: .relative(presentation: .named))
                            .monoMeta()
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary)
            .accessibilityIdentifier("approval.pending.\(approval.id)")
            // Re-asked after an expiry (#186): ties this card to the expired ask(s) in History.
            let asks = store.snapshot.asks(for: approval)
            if let caption = asks.pendingCaption {
                Label(caption, systemImage: "arrow.clockwise")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(asks.spokenPendingCaption ?? caption)
            }
            if let listing, listing.priceCents != approval.amountCents {
                CommerceProblem(text: "Price changed to \(listing.formattedPrice) since this was requested. Approving won't post it.",
                                tint: Theme.ochreInk)
            }
            if let deal, deal.priceCents != approval.amountCents {
                CommerceProblem(text: "Price changed to \(deal.formattedPrice) since this was requested. Approving won't buy it.",
                                tint: Theme.ochreInk)
            }
            if let deal, deal.isFraudBlocked {
                CommerceProblem(text: "The fraud screen flagged this deal. The agent won't buy it even if you approve.",
                                systemImage: "exclamationmark.shield")
            }
            if let sharedOwner {
                Label("Shared room: \(sharedOwner)'s item. Anyone in the room can decide.", systemImage: "person.2")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if failed {
                CommerceProblem(text: "Couldn't send your decision. Check the connection and try again.")
            }
            HStack(spacing: 10) {
                Button(role: .destructive) { confirmDeny = true } label: {
                    Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.danger))
                .accessibilityLabel("Deny \(approval.formattedAmount)")
                Button { decide(approve: true) } label: {
                    if working {
                        ProgressView().tint(Theme.accentInk).frame(maxWidth: .infinity)
                    } else {
                        Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.pill(.primary))
                .accessibilityLabel("Approve \(approval.formattedAmount)")
                .accessibilityIdentifier("approval.approve.\(approval.id)")
            }
            .disabled(working)
        }
        .padding(.vertical, 18)
        .ruled()
        .confirmationDialog("Deny this request?", isPresented: $confirmDeny, titleVisibility: .visible) {
            Button("Deny \(approval.formattedAmount)", role: .destructive) { decide(approve: false) }
        } message: {
            Text(approval.kind == .listing ? "The listing won't be posted." : "The agent won't buy this.")
        }
        .sensoryFeedback(.success, trigger: approvedCount)
    }

    private var spokenSummary: String {
        var s = approval.accessibilitySummary
        if listing?.simulated == true { s += ". Simulated listing, not posted to eBay" }
        if let railTag { s += ". \(railTag.spoken)" }
        return s
    }

    private var railTag: PurchaseRailTag? { approval.purchaseRailTag(store.snapshot.serviceConfig.visaCheckout) }

    private func decide(approve: Bool) {
        working = true
        failed = false
        Task {
            let ok = await store.decide(approval, approve: approve)
            if ok, approve { approvedCount += 1 }
            failed = !ok
            working = false
        }
    }
}

struct DecidedApprovalRow: View {
    @Environment(MooveStore.self) private var store
    let approval: Approval
    let listing: Listing?
    var deal: Deal? = nil
    let item: Item?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ApprovalThumbnail(approval: approval, item: item, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(listing?.title ?? deal?.title ?? approval.summary)
                    .blockTitle()
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if approval.status == .expired {
                        ExpiredBadge()
                    } else {
                        ApprovalStatusChip(status: approval.status)
                    }
                    Text("·").monoText(12.5).foregroundStyle(Theme.faint).accessibilityHidden(true)
                    Text(approval.updatedAt, format: .relative(presentation: .named)).monoMeta()
                }
                if let outcome = store.snapshot.historyOutcome(for: approval) {
                    Text(outcome).monoMeta().fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(approval.formattedAmount).rowValue().amountText()
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .ruled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.snapshot.historyAccessibilitySummary(for: approval))
        .accessibilityIdentifier("approval.decided.\(approval.id)")
    }
}

#Preview {
    ScrollView { ApprovalsSection().padding(.horizontal, Theme.gutter) }.environment(MooveStore.preview())
}
