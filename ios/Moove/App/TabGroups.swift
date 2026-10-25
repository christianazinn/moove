import SwiftUI
import MooveKit

/// The four tabs (decision on #129; Summary was removed in an addendum). Each tab groups
/// existing screens behind a segmented picker; the screens stay in their feature folders.
///
/// `@AppStorage("moove.tab")` stores the *screen* key ("inventory", "agents"...),
/// so any screen can still jump with `tab = "<screen>"` and lands on the right
/// tab and segment. The old "approvals" and "spending" keys are aliases of
/// "agents" (Sell & Buy went from four segments to three, decision 0129 addendum),
/// and the old "summary" key lands on Review, where the kg kept from landfill now lives.
enum TabGroup: String, CaseIterable {
    case scan, items, sellBuy, move

    /// Screen keys in picker order. The first one is the default segment.
    var screens: [String] {
        switch self {
        case .scan: ["scan"]
        case .items: ["inventory", "review"]
        case .sellBuy: ["listings", "shopping", "agents"]
        case .move: ["newhome", "pack"]
        }
    }

    var title: String {
        switch self {
        case .scan: "Scan"
        case .items: "Items"
        case .sellBuy: "Sell & Buy"
        case .move: "Move"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: "camera.viewfinder"
        case .items: "shippingbox"
        case .sellBuy: "tag"
        case .move: "house"
        }
    }

    /// The segment a screen key shows: itself, "agents" for the merged approvals/spending keys,
    /// or "review" for the removed Summary tab.
    static func segment(for screen: String) -> String {
        switch screen {
        case "approvals", "spending": "agents"
        case "summary": "review"
        default: screen
        }
    }

    static func containing(_ screen: String) -> TabGroup {
        let segment = segment(for: screen)
        return allCases.first { $0.screens.contains(segment) } ?? .scan
    }

    static func screenTitle(_ screen: String) -> String {
        switch screen {
        case "inventory": "Inventory"
        case "review": "Review"
        case "listings": "Listings"
        case "shopping": "Shopping"
        case "agents": "Agents"
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
                        PillPicker(options: group.screens, selection: segment, label: label)
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Theme.bg)
                }
            }
    }

    /// The selected pill; "approvals"/"spending" select Agents (it scrolls to the section itself).
    private var segment: Binding<String> {
        Binding(get: { TabGroup.segment(for: screen) }, set: { screen = $0 })
    }

    @ViewBuilder private var content: some View {
        let segment = TabGroup.segment(for: screen)
        switch group.screens.contains(segment) ? segment : group.screens[0] {
        case "inventory": InventoryView()
        case "review": ReviewView()
        case "listings": ListingsView()
        case "shopping": ShoppingView()
        case "agents": AgentsView()
        case "newhome": NewHomeView()
        case "pack": PackView()
        default: ScanHomeView()
        }
    }

    private func label(_ screen: String) -> String {
        let title = TabGroup.screenTitle(screen)
        let pending = store.pendingApprovals.count
        return screen == "agents" && pending > 0 ? "\(title) · \(pending)" : title
    }
}
