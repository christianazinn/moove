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

    var tint: Color {
        switch self {
        case .keep: .blue
        case .sell: .green
        case .donate: .purple
        case .trash: .gray
        case .undecided: .orange
        }
    }

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
        .clipShape(.rect(cornerRadius: size / 6))
    }

    private var placeholder: some View {
        Image(systemName: Self.icon(for: item.category))
            .font(.system(size: size * 0.45))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary)
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
        case "bicycle": "bicycle"
        case "motorcycle": "motorcycle"
        case "suitcase": "suitcase"
        case "plant": "leaf"
        case "microwave": "microwave"
        case "laptop": "laptopcomputer"
        case "backpack": "backpack"
        case "bench": "chair.lounge"
        case "teddy bear": "teddybear"
        case "skateboard": "skateboard"
        case "surfboard", "skis", "snowboard": "figure.skiing.downhill"
        default: "shippingbox"
        }
    }
}

struct DispositionChip: View {
    let disposition: Disposition

    var body: some View {
        Label(disposition.label, systemImage: disposition.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(disposition.tint)
            .background(disposition.tint.opacity(0.12), in: .capsule)
    }
}
