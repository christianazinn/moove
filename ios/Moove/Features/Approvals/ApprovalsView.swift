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
        List {
            if !pending.isEmpty {
                Section {
                    ForEach(pending) { approval in
                        PendingApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                           item: item(for: approval))
                    }
                } header: {
                    Text("Needs you · \(pending.count)")
                } footer: {
                    Label("Also sent to your phone via Auth0 Guardian when set up. Approving here works too.",
                          systemImage: "iphone.radiowaves.left.and.right")
                }
            }
            if !decided.isEmpty {
                Section("History") {
                    ForEach(decided) { approval in
                        DecidedApprovalRow(approval: approval, listing: store.snapshot.listing(for: approval),
                                           item: item(for: approval))
                    }
                }
            }
        }
        .navigationTitle("Approvals")
        .overlay {
            if pending.isEmpty && decided.isEmpty {
                ContentUnavailableView("Nothing to approve", systemImage: "checkmark.shield",
                                       description: Text("When an agent wants to sell or buy something over your limit, it asks here first."))
            }
        }
        .animation(.default, value: pending)
        .animation(.default, value: decided)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ApprovalThumbnail(approval: approval, item: item)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ApprovalKindTag(kind: approval.kind)
                        Spacer()
                        if listing?.simulated == true { SimulatedTag() }
                    }
                    Text(listing?.title ?? approval.summary)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(3)
                    HStack {
                        Text(approval.amountCents.usd).font(.title3.weight(.bold).monospacedDigit())
                        Spacer()
                        Text(approval.requestedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let listing, listing.priceCents != approval.amountCents {
                Label("Price changed to \(listing.priceCents.usd) since this was requested. Approving won't post it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(role: .destructive) { confirmDeny = true } label: {
                    Label("Deny", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button { decide(approve: true) } label: {
                    Label("Approve", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .disabled(working)
        }
        .padding(.vertical, 4)
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
        HStack(alignment: .top, spacing: 12) {
            ApprovalThumbnail(approval: approval, item: item, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(listing?.title ?? approval.summary)
                    .font(.subheadline)
                    .lineLimit(2)
                HStack {
                    ApprovalStatusChip(status: approval.status)
                    Spacer()
                    Text(approval.amountCents.usd).font(.subheadline.monospacedDigit())
                }
                Text(approval.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack { ApprovalsView() }.environment(MooveStore.preview())
}
