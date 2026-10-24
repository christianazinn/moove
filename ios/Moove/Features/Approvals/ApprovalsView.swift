import SwiftUI
import MooveKit

/// In-app approvals inbox (#12). The worker also pushes each request to the
/// owner's phone via Auth0 Guardian (CIBA) when Auth0 is configured; this is
/// the always-available path. Both decide through `decide_approval`, and the
/// listing agent posts or rejects once it sees the decision.
struct ApprovalsView: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        let pending = store.snapshot.pendingApprovals
        let decided = store.snapshot.decidedApprovals
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "05 — Approvals",
                    title: "Your go-ahead.",
                    lede: "When an agent wants to sell or buy something over your limit, it asks here first."
                )
                if pending.isEmpty && decided.isEmpty {
                    emptyState.padding(.top, 32)
                }
                if !pending.isEmpty {
                    ListHeader(title: "Needs you", count: "\(pending.count)").padding(.top, 36)
                    ForEach(pending) { approval in
                        PendingApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                           item: item(for: approval))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 12))
                            .accessibilityHidden(true)
                        Text("Also sent to your phone via Auth0 Guardian when set up. Approving here works too.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .monoMeta()
                    .padding(.top, 12)
                }
                if !decided.isEmpty {
                    ListHeader(title: "History", count: "\(decided.count)").padding(.top, 40)
                    ForEach(decided) { approval in
                        DecidedApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                           item: item(for: approval))
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Approvals")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .animation(.default, value: pending)
        .animation(.default, value: decided)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing to approve").blockTitle()
            Text("Requests over your limit show up here.").monoMeta()
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .combine)
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
    let item: Item?
    @State private var confirmDeny = false
    @State private var working = false
    @State private var approvedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                ApprovalThumbnail(approval: approval, item: item)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ApprovalKindTag(kind: approval.kind)
                        Spacer(minLength: 8)
                        if listing?.simulated == true { SimulatedTag() }
                    }
                    Text(listing?.title ?? approval.summary)
                        .blockTitle()
                        .lineLimit(3)
                    HStack(alignment: .firstTextBaseline) {
                        Text(approval.amountCents.usd)
                            .monoText(22, weight: .bold, maxScale: 1.6)
                            .foregroundStyle(Theme.text)
                        Spacer(minLength: 8)
                        Text(approval.requestedAt, format: .relative(presentation: .named))
                            .monoMeta()
                    }
                }
            }
            if let listing, listing.priceCents != approval.amountCents {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 12)).accessibilityHidden(true)
                    Text("Price changed to \(listing.priceCents.usd) since this was requested. Approving won't post it.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .monoText(12.5)
                .foregroundStyle(Theme.ochreInk)
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 10) {
                Button(role: .destructive) { confirmDeny = true } label: {
                    Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.danger))
                Button { decide(approve: true) } label: {
                    Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.primary))
            }
            .disabled(working)
        }
        .padding(.vertical, 18)
        .ruled()
        .confirmationDialog("Deny this request?", isPresented: $confirmDeny, titleVisibility: .visible) {
            Button("Deny \(approval.amountCents.usd)", role: .destructive) { decide(approve: false) }
        } message: {
            Text(approval.kind == .listing ? "The listing won't be posted." : "The agent won't buy this.")
        }
        .sensoryFeedback(.success, trigger: approvedCount)
    }

    private func decide(approve: Bool) {
        working = true
        Task {
            if await store.decide(approval, approve: approve), approve { approvedCount += 1 }
            working = false
        }
    }
}

struct DecidedApprovalRow: View {
    let approval: Approval
    let listing: Listing?
    let item: Item?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ApprovalThumbnail(approval: approval, item: item, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(listing?.title ?? approval.summary)
                    .blockTitle()
                    .lineLimit(2)
                HStack(spacing: 8) {
                    ApprovalStatusChip(status: approval.status)
                    Text("·").monoText(12.5).foregroundStyle(Theme.faint).accessibilityHidden(true)
                    Text(approval.updatedAt, format: .relative(presentation: .named)).monoMeta()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(approval.amountCents.usd).rowValue().layoutPriority(1)
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .ruled()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { ApprovalsView() }.environment(MooveStore.preview())
}
