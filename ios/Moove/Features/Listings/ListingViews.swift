import SwiftUI
import MooveKit

extension ListingStatus {
    /// Real-listing label; use `displayLabel(simulated:)` (MooveKit) when the listing may be simulated.
    var label: String { displayLabel(simulated: false) }

    var systemImage: String {
        switch self {
        case .draft: "pencil.line"
        case .awaitingApproval: "hand.raised.fill"
        case .rejected: "xmark.circle.fill"
        case .posting: "arrow.up.circle"
        case .posted: "dot.radiowaves.left.and.right"
        case .sold: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .draft, .posting: Theme.muted
        case .awaitingApproval: Theme.ochreInk
        case .rejected, .failed: Theme.danger
        case .posted: Theme.accentStrong
        case .sold: Theme.text
        }
    }
}

/// Status as a colored dot and mono label (the prototype's `.tag`). The dot pulses while drafting or posting.
/// A simulated listing never says "Live on eBay".
struct ListingStatusChip: View {
    let status: ListingStatus
    var simulated = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .symbolEffect(.pulse, isActive: status == .draft || status == .posting)
                .accessibilityHidden(true)
            Text(status.displayLabel(simulated: simulated)).monoText(12.5)
        }
        .foregroundStyle(status.tint)
        .lineLimit(1)
    }
}

/// CLAUDE.md hard rule: anything simulated says so in the UI, in the shared SIMULATED pill.
struct SimulatedTag: View {
    var body: some View { SimulatedBadge(spoken: "Simulated listing, not posted to eBay") }
}
