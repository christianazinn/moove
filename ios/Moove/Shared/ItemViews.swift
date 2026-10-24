import SwiftUI
import MooveKit

extension Disposition {
    var label: String { self == .undecided ? "Undecided" : rawValue.capitalized }

    var systemImage: String {
        switch self {
        case .keep: "shippingbox.fill"
        case .sell: "tag.fill"
        case .donate: "gift.fill"
        case .trash: "trash.fill"
        case .undecided: "questionmark.circle.fill"
        }
    }

    /// Theme color for text and icons about this disposition (at least 4.5:1 on `bg` and `surface`).
    var tint: Color {
        switch self {
        case .keep: Theme.accentStrong
        case .sell: Theme.ochreInk
        case .donate: Self.slateInk
        case .trash: Theme.muted
        case .undecided: Theme.danger
        }
    }

    /// Swatch for the small dot beside a disposition (fills only, not text).
    var swatch: Color {
        switch self {
        case .keep: Theme.accent
        case .sell: Theme.ochre
        case .donate: Theme.slate
        case .trash: Theme.stone
        case .undecided: Theme.danger
        }
    }

    /// Darker slate that reads as text in light mode.
    private static let slateInk = Color(uiColor: Theme.dynamicUIColor(0x55657A, 0x93A3B1))

    static let choices: [Disposition] = [.keep, .sell, .donate, .trash]
}

/// Photo if we have one, otherwise an icon for the RoomPlan category.
struct ItemThumbnail: View {
    let item: Item
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let url = item.photoUrls.first.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size >= 120 ? Theme.radiusLarge : Theme.radiusMedium, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: Self.icon(for: item.category))
            .font(.system(size: size * 0.32, weight: .light))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.surface)
    }

    static func icon(for category: String) -> String {
        switch category.lowercased() {
        case "bed": "bed.double"
        case "chair": "chair"
        case "sofa": "sofa"
        case "table": "table.furniture"
        case "storage": "cabinet"
        case "lamp": "lamp.floor"
        case "appliance", "refrigerator": "refrigerator"
        case "television": "tv"
        case "decor": "photo.artframe"
        default: "shippingbox"
        }
    }
}

/// Disposition as a colored dot and a mono label on a quiet capsule.
struct DispositionChip: View {
    let disposition: Disposition

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(disposition.swatch).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(disposition.label).monoText(12, weight: .bold, maxScale: 1.6)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(Theme.text)
        .background(Capsule().fill(Theme.surface))
        .accessibilityElement(children: .combine)
    }
}
