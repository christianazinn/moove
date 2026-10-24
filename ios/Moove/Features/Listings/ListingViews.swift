import SwiftUI
import MooveKit

extension ListingStatus {
    var label: String {
        switch self {
        case .draft: "Drafting"
        case .awaitingApproval: "Needs approval"
        case .rejected: "Not posted"
        case .posted: "Live on eBay"
        case .sold: "Sold"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .draft: "pencil.line"
        case .awaitingApproval: "hand.raised.fill"
        case .rejected: "xmark.circle.fill"
        case .posted: "dot.radiowaves.left.and.right"
        case .sold: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .draft: Theme.muted
        case .awaitingApproval: Theme.ochreInk
        case .rejected, .failed: Theme.danger
        case .posted: Theme.accentStrong
        case .sold: Theme.text
        }
    }
}

/// Status as a colored dot and mono label (the prototype's `.tag`). The dot pulses while drafting.
struct ListingStatusChip: View {
    let status: ListingStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .symbolEffect(.pulse, isActive: status == .draft)
                .accessibilityHidden(true)
            Text(status.label).monoText(12.5)
        }
        .foregroundStyle(status.tint)
        .lineLimit(1)
    }
}

/// CLAUDE.md hard rule: anything simulated says so in the UI.
struct SimulatedTag: View {
    var body: some View {
        MonoTag(text: "Simulated", tone: Theme.ochreInk)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Simulated listing, not posted to eBay")
    }
}
