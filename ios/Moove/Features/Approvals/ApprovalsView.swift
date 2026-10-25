import SwiftUI
import MooveKit

/// In-app approvals inbox (#12), the top of Sell & Buy > Agents. The worker also pushes each
/// request to the owner's phone via Auth0 Guardian (CIBA) when Auth0 is configured; this is the
/// always-available path. Both decide through `decide_approval`, and the listing agent posts or
/// rejects once it sees the decision.
///
/// "Needs your OK" lists pending requests (or one "Nothing waiting" line); "Decided" shows the
/// last few decisions with "Show all" for the rest. `parts` lets Agents show the two halves
/// separately (the safety card sits between them).
struct ApprovalsSection: View {
    enum Part: Hashable { case open, decided }

    @Environment(MooveStore.self) private var store
    @State private var showAllDecided = false
    var parts: Set<Part> = [.open, .decided]

    /// Decided rows shown before "Show all".
    static let decidedPreview = 3

    var body: some View {
        let pending = store.snapshot.pendingApprovals
        let decided = store.snapshot.decidedApprovals
        let shared = store.snapshot.sharedPendingApprovals
        VStack(alignment: .leading, spacing: 0) {
            if parts.contains(.open) { open(pending: pending, shared: shared) }
            if parts.contains(.decided) { decidedList(decided) }
        }
        .animation(.default, value: pending)
        .animation(.default, value: decided)
        .animation(.default, value: shared)
    }

    @ViewBuilder
    private func open(pending: [Approval], shared: [Approval]) -> some View {
        if pending.isEmpty && shared.isEmpty {
            heading("Needs your OK")
            Text("Nothing waiting")
                .monoMeta()
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("approvals.nothingWaiting")
        }
        if !pending.isEmpty {
            heading("Needs your OK")
            // Each list in its own VStack: an approval's id is in `pending`, then in `decided`, and
            // sharing one LazyVStack's id space left the stale pending card showing under History.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pending) { approval in
                    PendingApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                       deal: store.snapshot.deal(for: approval), item: item(for: approval))
                }
            }
        }
        if !shared.isEmpty {
            // Shared rooms (#195, #200): any room member may decide a listing approval.
            heading("Shared rooms").padding(.top, pending.isEmpty ? 0 : Theme.Space.section)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shared) { approval in
                    PendingApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                       item: item(for: approval),
                                       sharedOwner: store.snapshot.ownerName(approval.owner))
                }
            }
        }
    }

    @ViewBuilder
    private func decidedList(_ decided: [Approval]) -> some View {
        if !decided.isEmpty {
            let shown = showAllDecided ? decided : Array(decided.prefix(Self.decidedPreview))
            heading("Decided").padding(.top, parts.contains(.open) ? Theme.Space.section : 0)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { approval in
                    DecidedApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                       deal: store.snapshot.deal(for: approval), item: item(for: approval))
                }
            }
            if decided.count > Self.decidedPreview {
                Button(showAllDecided ? "Show fewer" : "Show all \(decided.count)") {
                    withAnimation { showAllDecided.toggle() }
                }
                .monoText(13.5, weight: .bold)
                .foregroundStyle(Theme.accentStrong)
                .frame(minHeight: 44)
                .accessibilityIdentifier("approvals.decided.showAll")
            }
        }
    }

    /// A section title alone: no count, no rule.
    private func heading(_ title: String) -> some View {
        Text(title)
            .listHeading()
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, Theme.Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            // Item + price (+ SIMULATED). Kind, source, time, re-asks and the Guardian push are spoken only.
            HStack(alignment: .center, spacing: 14) {
                ApprovalThumbnail(approval: approval, item: item, size: 44)
                Text(listing?.title ?? deal?.title ?? approval.summary)
                    .blockTitle()
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSimulated { SimulatedBadge(spoken: "Simulated") }
                Text(approval.formattedAmount)
                    .monoText(17, weight: .bold, maxScale: 1.6)
                    .foregroundStyle(Theme.text)
                    .amountText()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenSummary)
            .accessibilityIdentifier("approval.pending.\(approval.id)")
            if let warning {
                CommerceProblem(text: warning.text, systemImage: warning.icon, tint: warning.tint)
            }
            if failed {
                CommerceProblem(text: "Couldn't send your decision. Check the connection and try again.")
            }
            HStack(spacing: 10) {
                Button(role: .destructive) { confirmDeny = true } label: {
                    Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.outline))
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
        .confirmationDialog("Deny this request?", isPresented: $confirmDeny, titleVisibility: .visible) {
            Button("Deny \(approval.formattedAmount)", role: .destructive) { decide(approve: false) }
        } message: {
            Text(approval.kind == .listing ? "The listing won't be posted." : "The agent won't buy this.")
        }
        .sensoryFeedback(.success, trigger: approvedCount)
    }

    private var isSimulated: Bool { listing?.simulated == true || railTag == .simulated }

    /// The one thing that changes what Approve does, in a few words (the full sentence is spoken).
    private var warning: (text: String, icon: String, tint: Color)? {
        if let deal, deal.isFraudBlocked { return ("Flagged as fraud: won't buy", "exclamationmark.shield", Theme.danger) }
        if let listing, listing.priceCents != approval.amountCents { return ("Price changed: won't post", "exclamationmark.triangle", Theme.danger) }
        if let deal, deal.priceCents != approval.amountCents { return ("Price changed: won't buy", "exclamationmark.triangle", Theme.danger) }
        return nil
    }

    private var spokenSummary: String {
        var s = approval.accessibilitySummary
        if let deal { s += ", from \(deal.source)" }
        if listing?.simulated == true { s += ". Simulated listing, not posted to eBay" }
        if let railTag { s += ". \(railTag.spoken)" }
        if let sharedOwner { s += ". Shared room: \(sharedOwner)'s item. Anyone in the room can decide" }
        if let caption = store.snapshot.asks(for: approval).spokenPendingCaption { s += ". \(caption)" }
        if let listing, listing.priceCents != approval.amountCents { s += ". Price changed to \(listing.formattedPrice) since this was requested. Approving won't post it" }
        if let deal, deal.priceCents != approval.amountCents { s += ". Price changed to \(deal.formattedPrice) since this was requested. Approving won't buy it" }
        if let deal, deal.isFraudBlocked { s += ". The fraud screen flagged this deal. The agent won't buy it even if you approve" }
        if sharedOwner == nil { s += ". Also sent to your phone" }
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
        // One line: item and amount (status, time and outcome are spoken).
        HStack(spacing: 14) {
            ApprovalThumbnail(approval: approval, item: item, size: 44)
            Text(listing?.title ?? deal?.title ?? approval.summary)
                .blockTitle()
                .lineLimit(2)
                .strikethrough(approval.status == .denied)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(approval.formattedAmount).rowValue().amountText()
        }
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.snapshot.historyAccessibilitySummary(for: approval))
        .accessibilityIdentifier("approval.decided.\(approval.id)")
    }
}

#Preview {
    ScrollView { ApprovalsSection().padding(.horizontal, Theme.gutter) }.environment(MooveStore.preview())
}
