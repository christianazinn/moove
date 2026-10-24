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
        case .draft: .secondary
        case .awaitingApproval: .orange
        case .rejected, .failed: .red
        case .posted: .green
        case .sold: .blue
        }
    }
}

struct ListingStatusChip: View {
    let status: ListingStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.12), in: .capsule)
            .symbolEffect(.pulse, isActive: status == .draft)
    }
}

/// CLAUDE.md hard rule: anything simulated says so in the UI.
struct SimulatedTag: View {
    var body: some View {
        Text("SIMULATED")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .overlay(Capsule().strokeBorder(.secondary.opacity(0.5)))
            .accessibilityLabel("Simulated listing, not posted to eBay")
    }
}
