import SwiftUI
import MooveKit

/// Sell & Buy > Agents: what the agents asked for and what they paid, on one screen.
/// Approvals ("Needs your OK", then "Decided") on top, the spending receipts (#316) below.
///
/// The old "approvals" and "spending" screen keys still land here (`TabGroup.segment(for:)`), and
/// "spending" scrolls down to the receipts, so `tab = "spending"` keeps working.
struct AgentsView: View {
    @Environment(MooveStore.self) private var store
    @AppStorage("moove.tab") private var tab = "agents"

    static let approvalsAnchor = "agents.approvals"
    static let receiptsAnchor = "agents.receipts"

    var body: some View {
        let snapshot = store.snapshot
        let pending = store.pendingApprovals.count
        let decided = snapshot.decidedApprovals.count
        let payments = snapshot.myPayments.count
        let hasRows = pending + decided + payments > 0 || !snapshot.spendingSplit().isEmpty
        let state = store.commerceState(hasRows: hasRows)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if state != .content {
                        CommercePlaceholder(
                            state: state,
                            emptyTitle: "Nothing from your agents yet",
                            emptyDetail: "Agents ask here before they list or buy anything over your approval limit ($100 by default), and every payment they make prints a receipt here. Sort an item to Sell, or choose a deal in Shopping."
                        )
                        .padding(.top, 32)
                    } else {
                        StatStrip(figures: [
                            .init(label: "Waiting", value: "\(pending)", tint: pending > 0 ? Theme.ochreInk : Theme.text,
                                  spoken: "\(pending) waiting on you"),
                            .init(label: "Decided", value: "\(decided)", spoken: "\(decided) decided"),
                            .init(label: "Payments", value: "\(payments)", spoken: "\(payments) payments"),
                        ])
                        .padding(.top, 8)
                        ApprovalsSection()
                            .padding(.top, 32)
                            .id(Self.approvalsAnchor)
                        SpendingSection()
                            .padding(.top, 44)
                            .id(Self.receiptsAnchor)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 48)
            }
            .onAppear { jump(proxy) }
            .onChange(of: tab) { jump(proxy) }
        }
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
    }

    /// A deep link to "spending" scrolls to the receipts, "approvals" to the top; then the key
    /// becomes "agents" so coming back later doesn't jump again.
    private func jump(_ proxy: ScrollViewProxy) {
        guard tab == "spending" || tab == "approvals" else { return }
        let anchor = tab == "spending" ? Self.receiptsAnchor : Self.approvalsAnchor
        tab = "agents"
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))  // let the receipts lay out first
            withAnimation { proxy.scrollTo(anchor, anchor: .top) }
        }
    }
}

#Preview {
    NavigationStack { AgentsView() }.environment(MooveStore.preview())
}
