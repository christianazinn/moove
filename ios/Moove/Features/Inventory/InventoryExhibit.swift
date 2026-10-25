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
    static let spotlight = Color(uiColor: Theme.dynamicUIColor(0xFFFBF2, 0x463B2E))
    /// The plinth's top face and its front.
    static let plinthTop = Color(uiColor: Theme.dynamicUIColor(0xF7F2E9, 0x3A3229))
    static let plinthFront = Color(uiColor: Theme.dynamicUIColor(0xDDD4C4, 0x2B241D))
}

/// What one exhibit shows, worked out once by the screen.
struct ExhibitInfo {
    var item: Item
    var roomName: String
    var story: String?
    var autoStory: String
    var catalog: String
    var acquired: String
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
        // Items added by photo have no size, so no model: show the photo, framed.
        if item.origin == .photo, let url = item.photoUrls.first.flatMap(URL.init(string:)) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.surface2 }
                .frame(width: size * 0.7, height: size * 0.7)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tag))
                .padding(5)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.tag + 2))
                .mooveShadow(.paper)
                .accessibilityHidden(true)
        } else {
            VoxelThumbnail(item, size: size, tile: false)
                .mooveShadow(.lifted)
        }
    }
}

/// The placard under an exhibit: name, a short size line, the story, and price + origin.
struct ExhibitPlacard: View {
    let info: ExhibitInfo
    var onEditStory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(info.item.name)
                .serifType(16, weight: .semibold)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            // Name, story, price: the catalog line, origin tag and the agents' note are read by
            // VoiceOver only (Lisa: less on screen).
            Button(action: onEditStory) {
                Text(info.story.map { "“\($0)”" } ?? "Add a story")
                    .serifType(13, italic: true)
                    .foregroundStyle(info.story == nil ? Theme.muted : Theme.text)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(info.story.map { "Story: \($0)" } ?? "\(info.autoStory). Add a story")
            .accessibilityHint(info.story == nil ? "Add your own story" : "Edit your story")
            .accessibilityIdentifier("inventory.story.\(info.item.id)")
            price
                .padding(.top, 2)
                .accessibilityLabel("\(info.price), \(info.catalog), \(info.tag.accessibilityLabel)")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var price: some View {
        Text(info.price).monoText(13, weight: .bold, maxScale: 1.8).foregroundStyle(info.priceTint).lineLimit(1)
    }

}

/// Edit the one-line story on a placard ("Grandma's, 1974"). Kept on this device only.
struct StoryEditor: View {
    let item: Item
    var current: String?
    var onSave: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(item.name).serifType(20, weight: .semibold).foregroundStyle(Theme.text)
                TextField("Grandma's, 1974", text: $text)
                    .serifType(17, italic: true)
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip))
                    .submitLabel(.done)
                    .onSubmit(save)
                    .accessibilityIdentifier("inventory.story.field")
                Text("A year in it becomes the “Acquired” date. Saved on this phone.")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                if current != nil {
                    Button("Remove story", role: .destructive) {
                        onSave("")
                        dismiss()
                    }
                    .buttonStyle(.pill(.danger, compact: true))
                }
                Spacer()
            }
            .padding(Theme.gutter)
            .navigationTitle("Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).accessibilityIdentifier("inventory.story.save")
                }
            }
            .mooveScreen()
        }
        .presentationDetents([.medium])
        .onAppear { text = current ?? "" }
    }

    private func save() {
        onSave(String(text.prefix(ItemStories.maxLength)))
        dismiss()
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
