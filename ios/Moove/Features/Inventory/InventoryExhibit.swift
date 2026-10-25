import SwiftUI
import MooveKit

// The museum look for Inventory: items as framed exhibits (a voxel model under a soft
// spotlight on a plinth) with a placard. Wording comes from MooveKit `MuseumLabel`.

extension View {
    /// Small caps catalog line ("OAK, IKEA · 140 × 195 CM").
    func catalogCaps() -> some View {
        monoText(10.5, weight: .medium, maxScale: 1.8).tracking(0.6).textCase(.uppercase).foregroundStyle(Theme.muted)
    }
}

enum MuseumColors {
    /// Warm light pooling on the gallery wall.
    static let spotlight = Color(uiColor: Theme.dynamicUIColor(0xFBF9EA, 0x3A5765))
    /// The plinth's top face and its front.
    static let plinthTop = Color(uiColor: Theme.dynamicUIColor(0xF6F3E0, 0x34505D))
    static let plinthFront = Color(uiColor: Theme.dynamicUIColor(0xD5E4E1, 0x2A424D))
}

/// What one exhibit shows, worked out once by the screen.
struct ExhibitInfo {
    var item: Item
    var roomName: String
    var catalog: String
    var price: String
    var priceTint: Color
    var tag: Item.OriginTag
    var featured: Bool
}

/// The picture half of an exhibit: the model on a plinth under a spotlight, a ribbon for
/// possibly sentimental pieces.
struct ExhibitPlinth: View {
    let item: Item
    var featured = false
    @ScaledMetric(relativeTo: .body) private var baseHeight: CGFloat = 132

    var body: some View {
        let height = featured ? baseHeight * 1.45 : baseHeight
        ZStack(alignment: .bottom) {
            Theme.surface
            RadialGradient(colors: [MuseumColors.spotlight, MuseumColors.spotlight.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.05), startRadius: 4, endRadius: height * 0.95)
            // Plinth: a light top edge over a darker front.
            VStack(spacing: 0) {
                Rectangle().fill(MuseumColors.plinthTop).frame(height: 5)
                Rectangle().fill(MuseumColors.plinthFront).frame(height: height * 0.12)
            }
            .padding(.horizontal, 18)
            model(size: height * 0.82)
                .padding(.bottom, height * 0.12 + 1)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .topTrailing) {
            if item.maybeSentimental {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.ochre)
                    .padding(.trailing, 12)
                    .offset(y: -2)
                    .accessibilityLabel("Possibly sentimental")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func model(size: CGFloat) -> some View {
        // Voxel for every item (Lisa); an item added by photo uses its kind's default size.
        VoxelThumbnail(item, size: size, tile: false)
            .mooveShadow(.lifted)
    }
}

/// The placard under an exhibit: name, a short size line, the story, and price + origin.
struct ExhibitPlacard: View {
    let info: ExhibitInfo

    /// Name, size line and price; the origin tag is read by VoiceOver.
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(info.item.name)
                .serifType(16, weight: .semibold)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(info.catalog)
                .catalogCaps()
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(info.price)
                .monoText(13, weight: .bold, maxScale: 1.8)
                .foregroundStyle(info.priceTint)
                .lineLimit(1)
                .padding(.top, 2)
                .accessibilityLabel("\(info.price), \(info.tag.accessibilityLabel)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Lays chips out left to right, wrapping to a new row when the next one doesn't fit.
struct ChipFlow: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(Int, CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, width)
            if !row.items.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
