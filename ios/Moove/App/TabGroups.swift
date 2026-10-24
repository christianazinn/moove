import SwiftUI
import MooveKit

/// The five tabs (decision on #129). Each tab groups existing screens behind a
/// segmented picker; the screens themselves stay in their feature folders.
///
/// `@AppStorage("moove.tab")` stores the *screen* key ("inventory", "approvals"...),
/// so any screen can still jump with `tab = "<screen>"` and lands on the right
/// tab and segment.
enum TabGroup: String, CaseIterable {
    case scan, items, sellBuy, move, summary

    /// Screen keys in picker order. The first one is the default segment.
    var screens: [String] {
        switch self {
        case .scan: ["scan"]
        case .items: ["inventory", "review"]
        case .sellBuy: ["listings", "shopping", "approvals", "spending"]
        case .move: ["newhome", "pack"]
        case .summary: ["summary"]
        }
    }

    var title: String {
        switch self {
        case .scan: "Scan"
        case .items: "Items"
        case .sellBuy: "Sell & Buy"
        case .move: "Move"
        case .summary: "Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: "camera.viewfinder"
        case .items: "shippingbox"
        case .sellBuy: "tag"
        case .move: "house"
        case .summary: "chart.bar.doc.horizontal"
        }
    }

    static func containing(_ screen: String) -> TabGroup {
        allCases.first { $0.screens.contains(screen) } ?? .scan
    }

    static func screenTitle(_ screen: String) -> String {
        switch screen {
        case "inventory": "Inventory"
        case "review": "Review"
        case "listings": "Listings"
        case "shopping": "Shopping"
        case "approvals": "Approvals"
        case "spending": "Spending"
        case "newhome": "New Home"
        case "pack": "Pack"
        default: screen.capitalized
        }
    }
}

/// One tab: a segmented picker over its screens (hidden when there is only one).
struct TabGroupView: View {
    @Environment(MooveStore.self) private var store
    let group: TabGroup
    @Binding var screen: String

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if group.screens.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        PillPicker(options: group.screens, selection: $screen, label: label)
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Theme.bg)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch group.screens.contains(screen) ? screen : group.screens[0] {
        case "inventory": InventoryView()
        case "review": ReviewView()
        case "listings": ListingsView()
        case "shopping": ShoppingView()
        case "approvals": ApprovalsView()
        case "spending": SpendingView()
        case "newhome": NewHomeView()
        case "pack": PackView()
        case "summary": SummaryView()
        default: ScanHomeView()
        }
    }

    private func label(_ screen: String) -> String {
        let title = TabGroup.screenTitle(screen)
        let pending = store.pendingApprovals.count
        return screen == "approvals" && pending > 0 ? "\(title) · \(pending)" : title
    }
}
