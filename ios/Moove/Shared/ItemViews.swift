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
        case "bed", "mattress": "bed.double"
        case "chair": "chair"
        case "sofa", "bench", "ottoman": "sofa"
        case "table", "desk": "table.furniture"
        case "storage", "dresser", "nightstand": "cabinet"
        case "bookshelf", "books": "books.vertical"
        case "lamp": "lamp.floor"
        case "appliance", "refrigerator": "refrigerator"
        case "stove", "oven": "stove"
        case "microwave": "microwave"
        case "dishwasher": "dishwasher"
        case "washerdryer": "washer"
        case "television", "tv": "tv"
        case "bike": "bicycle"
        case "suitcase": "suitcase"
        case "decor": "photo.artframe"
        // RoomPlan categories not covered above (RoomPlan's own names, lowercased)
        case "washerdryer": "washer"
        case "dishwasher": "dishwasher"
        case "oven": "oven"
        case "stove": "cooktop"
        case "sink": "sink"
        case "toilet": "toilet"
        case "bathtub": "bathtub"
        case "fireplace": "fireplace"
        case "stairs": "stairs"
        // Extra objects (#73, #82; see MooveKit ObjectVocabulary). SF Symbols ≤ 5 (iOS 17).
        case "scooter": "scooter"
        case "bicycle": "bicycle"
        case "motorcycle": "motorcycle"
        case "skateboard": "skateboard"
        case "surfboard": "figure.surfing"
        case "skis": "figure.skiing.downhill"
        case "snowboard": "figure.snowboarding"
        case "golf clubs": "figure.golf"
        case "racket": "tennis.racket"
        case "treadmill": "figure.run"
        case "exercise bike": "figure.indoor.cycle"
        case "rowing machine": "figure.rower"
        case "weight bench", "weights": "dumbbell"
        case "yoga mat": "figure.yoga"
        case "punching bag": "figure.boxing"
        case "stroller": "stroller"
        case "wheelchair": "figure.roll"
        case "helmet": "shield"
        case "ball": "basketball"
        case "guitar": "guitars"
        case "piano", "keyboard instrument": "pianokeys"
        case "drums", "violin", "cello", "saxophone", "trumpet": "music.quarternote.3"
        case "amplifier", "speaker": "hifispeaker"
        case "monitor": "display"
        case "computer": "desktopcomputer"
        case "laptop": "laptopcomputer"
        case "printer": "printer"
        case "game console": "gamecontroller"
        case "projector": "videoprojector"
        case "turntable": "record.circle"
        case "microwave": "microwave"
        case "coffee machine": "cup.and.saucer"
        case "toaster", "blender": "powerplug"
        case "vacuum", "fan": "fan.floor"
        case "air purifier": "air.purifier"
        case "heater": "heater.vertical"
        case "humidifier": "humidifier"
        case "air conditioner": "air.conditioner.horizontal"
        case "sewing machine": "scissors"
        case "ironing board", "clothes rack", "coat rack": "hanger"
        case "water dispenser": "drop"
        case "stool", "ottoman", "bean bag": "chair.lounge"
        case "mattress", "crib": "bed.double"
        case "bench": "chair.lounge"
        case "shoe rack": "shoe.2"
        case "shelf": "books.vertical"
        case "cart": "cart"
        case "ladder", "workbench": "hammer"
        case "room divider": "rectangle.split.3x1"
        case "trunk": "suitcase.cart"
        case "mirror": "oval.portrait"
        case "rug": "square.dashed"
        case "art": "photo.artframe"
        case "clock": "clock"
        case "vase", "plant stand": "camera.macro"
        case "plant": "leaf"
        case "toy", "teddy bear": "teddybear"
        case "box": "shippingbox"
        case "bin": "archivebox"
        case "suitcase": "suitcase"
        case "backpack": "backpack"
        case "bag": "bag"
        case "basket": "basket"
        case "trash can": "trash"
        case "toolbox": "wrench.and.screwdriver"
        case "lawn mower": "leaf"
        case "grill": "flame"
        case "pet crate", "pet bed": "pawprint"
        case "cat tree": "cat"
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
