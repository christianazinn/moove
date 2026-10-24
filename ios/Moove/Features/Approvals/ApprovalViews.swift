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
        case .pending: Theme.ochreInk
        case .approved: Theme.accentStrong
        case .denied: Theme.danger
        case .expired: Theme.muted
        }
    }
}

extension ApprovalKind {
    var label: String { self == .listing ? "Sell" : "Buy" }
    var systemImage: String { self == .listing ? "tag" : "cart" }
}

/// Status as a colored dot and mono label; the dot pulses while it waits on you.
struct ApprovalStatusChip: View {
    let status: ApprovalStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .symbolEffect(.pulse, isActive: status == .pending)
                .accessibilityHidden(true)
            Text(status.label).monoText(12.5)
        }
        .foregroundStyle(status.tint)
        .lineLimit(1)
    }
}

struct ApprovalKindTag: View {
    let kind: ApprovalKind

    var body: some View {
        Label {
            Text(kind.label).monoText(11.5, weight: .bold, maxScale: 1.6).tracking(0.5)
        } icon: {
            Image(systemName: kind.systemImage).font(.system(size: 10))
        }
        .labelStyle(.titleAndIcon)
        .textCase(.uppercase)
        .foregroundStyle(Theme.muted)
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
            IconTile(systemName: approval.kind.systemImage, size: size)
        }
    }
}
