import SwiftUI
import MooveKit

/// Sell & Buy > Agents: what the agents asked for and what they paid, on one screen.
/// "Needs your OK" on top, then "Agents kept you safe" (the guardrails, #225), "Decided", and the
/// spending receipts (#316) below.
///
/// The old "approvals" and "spending" screen keys still land here (`TabGroup.segment(for:)`), and
/// "spending" scrolls down to the receipts, so `tab = "spending"` keeps working.
struct AgentsView: View {
    @Environment(MooveStore.self) private var store
    @AppStorage("moove.tab") private var tab = "agents"

    static let approvalsAnchor = "agents.approvals"
    static let receiptsAnchor = "agents.receipts"
    static let safetyAnchor = "agents.safety"

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
                            emptyDetail: "Approvals over your limit and every payment's receipt land here. Sort an item to Sell, or choose a deal in Shopping."
                        )
                        .padding(.top, 32)
                    } else {
                        // No stat strip and no Decided list (Lisa): "Needs your OK" on top,
                        // then the guardrails card, then the receipts with their totals tape.
                        ApprovalsSection(parts: [.open])
                            .padding(.top, Theme.Space.l)
                            .id(Self.approvalsAnchor)
                        SafetyCard()
                            .padding(.top, Theme.Space.section)
                            .id(Self.safetyAnchor)
                        SpendingSection()
                            .padding(.top, Theme.Space.section)
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
