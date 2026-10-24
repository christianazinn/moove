import SwiftUI
import MooveKit

extension ApprovalStatus {
    var label: String {
        switch self {
        case .pending: "Waiting on you"
        case .approved: "Approved"
        case .denied: "Denied"
        case .expired: "Expired"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "hourglass"
        case .approved: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .expired: "clock.badge.xmark"
        }
    }

    var tint: Color {
        switch self {
        case .pending: .orange
        case .approved: .green
        case .denied: .red
        case .expired: .secondary
        }
    }
}

extension ApprovalKind {
    var label: String { self == .listing ? "Sell" : "Buy" }
    var systemImage: String { self == .listing ? "tag" : "cart" }
}

struct ApprovalStatusChip: View {
    let status: ApprovalStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(status.tint)
            .background(status.tint.opacity(0.12), in: .capsule)
    }
}

struct ApprovalKindTag: View {
    let kind: ApprovalKind

    var body: some View {
        Label(kind.label, systemImage: kind.systemImage)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Thumbnail for the thing being approved: the listed item's photo, or a kind icon.
struct ApprovalThumbnail: View {
    let approval: Approval
    let item: Item?
    var size: CGFloat = 56

    var body: some View {
        if let item {
            ItemThumbnail(item: item, size: size)
        } else {
            Image(systemName: approval.kind.systemImage)
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(.quaternary, in: .rect(cornerRadius: 8))
        }
    }
}
