import SwiftUI
import MooveKit

// Inventory as a tabbed binder (Lisa, #335): each function hall is a page behind a colored
// index tab, and each page is a wall of chunky voxel-style wooden shelves the items stand
// on, each with a hanging tag. Packing and tab order come from MooveKit `InventoryBinder`.

enum BinderColors {
    static func tint(_ t: BinderTint) -> Color {
        switch t {
        case .sage: dynamic(0x5E6D50, 0x9AAA89)
        case .ochre: dynamic(0x96701F, 0xCFA45A)
        case .slate: dynamic(0x55687A, 0x93A3B1)
        case .clay: dynamic(0xA24D35, 0xD27A5E)
        case .plum: dynamic(0x77506B, 0xB993AF)
        case .stone: dynamic(0x7A6F60, 0xA39887)
        case .teal: dynamic(0x3F7570, 0x86B5AE)
        }
    }

    /// Text on a picked (solid) tab.
    static let tabInk = dynamic(0xFFFFFF, 0x1C1814)
    /// The page: warm paper by day, a deep wall by night.
    static let wall = dynamic(0xF6F0E6, 0x211C17)
    static let wallShade = dynamic(0xEDE4D5, 0x1A1612)
    /// Oak by day, walnut by night: top face, front, grain bands, brackets.
    static let woodTop = dynamic(0xD6B385, 0x7A5638)
    static let woodFront = dynamic(0xB98C5A, 0x5C3E29)
    static let woodGrain = dynamic(0xA57A4B, 0x4C3322)
    static let woodLight = dynamic(0xC69A67, 0x684731)
    static let bracket = dynamic(0x8E6841, 0x3F2A1C)
    static let floor = dynamic(0xCDB28A, 0x3B2C20)
    static let floorSeam = dynamic(0xB39670, 0x2C2118)
    static let tag = Theme.Paper.cream
    static let string = dynamic(0x9C9383, 0x7A7163)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color { Color(uiColor: Theme.dynamicUIColor(light, dark)) }
}

// MARK: Tabs

/// A folder tab: rounded on the side that sticks out, slanted shoulders.
struct BinderTabShape: Shape {
    /// The edge it sticks out from: `.top` (iPhone, over the page) or `.trailing` (iPad).
    var edge: Edge = .top

    func path(in r: CGRect) -> Path {
        var p = Path()
        let s: CGFloat = 6, c: CGFloat = 7
        if edge == .trailing {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY + s))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + s + c), control: CGPoint(x: r.maxX, y: r.minY + s))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - s - c))
            p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY - s), control: CGPoint(x: r.maxX, y: r.maxY - s))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + c))
            p.addQuadCurve(to: CGPoint(x: r.minX + s + c, y: r.minY), control: CGPoint(x: r.minX + s, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - s - c, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX - s, y: r.minY + c), control: CGPoint(x: r.maxX - s, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// One index tab: the hall's name and count; solid when it's the open page.
struct BinderTabButton: View {
    let tab: BinderTab
    let selected: Bool
    var edge: Edge = .top
    var action: () -> Void

    var body: some View {
        // Neutral paper tabs; only the open one takes the accent (Lisa: less color).
        Button(action: action) {
            // Name only; the count is in the VoiceOver label.
            Text(tab.hall.name).sansText(13, weight: .semibold, maxScale: 1.6).lineLimit(1)
            .foregroundStyle(selected ? Theme.accentInk : Theme.text)
            .padding(.horizontal, edge == .top ? 16 : 12)
            .padding(.vertical, edge == .top ? 9 : 12)
            .frame(minHeight: 44)
            .frame(maxWidth: edge == .trailing ? .infinity : nil, alignment: .leading)
            .background(BinderTabShape(edge: edge).fill(selected ? Theme.accentFill : Theme.surface))
            .contentShape(BinderTabShape(edge: edge))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("inventory.tab.\(tab.hall.rawValue)")
    }
}

// MARK: Shelves

/// A chunky wooden plank in 5 cm-ish blocks (like the voxel models): a light top face, a
/// grained front, and two brackets underneath.
struct ShelfPlank: View {
    static let height: CGFloat = 26

    var body: some View {
        Canvas { ctx, size in
            let top: CGFloat = 5, front: CGFloat = 11, block: CGFloat = 18
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: top)), with: .color(BinderColors.woodTop))
            ctx.fill(Path(CGRect(x: 0, y: top, width: size.width, height: front)), with: .color(BinderColors.woodFront))
            // Grain: a few blocks a shade darker or lighter, the same pattern every time.
            var x: CGFloat = 0, i = 0
            while x < size.width {
                let w = min(block, size.width - x)
                switch (i * 7 + 3) % 5 {
                case 0: ctx.fill(Path(CGRect(x: x, y: top + 3, width: w, height: 3)), with: .color(BinderColors.woodGrain))
                case 2: ctx.fill(Path(CGRect(x: x, y: top + 6, width: w, height: 2)), with: .color(BinderColors.woodLight))
                case 4: ctx.fill(Path(CGRect(x: x, y: top, width: w, height: front)), with: .color(BinderColors.woodLight))
                default: break
                }
                x += block
                i += 1
            }
            // Brackets: stepped blocks under each end.
            for bx in [size.width * 0.07, size.width * 0.93 - 8] {
                ctx.fill(Path(CGRect(x: bx, y: top + front, width: 8, height: 6)), with: .color(BinderColors.bracket))
                ctx.fill(Path(CGRect(x: bx, y: top + front + 6, width: 4, height: 4)), with: .color(BinderColors.bracket))
            }
        }
        .frame(height: Self.height)
        .mooveShadow(.paper)
        .accessibilityHidden(true)
    }
}

/// The floor row the big furniture stands on: boards with seams and a baseboard.
struct FloorBoards: View {
    static let height: CGFloat = 18

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: 4)), with: .color(BinderColors.woodFront))
            ctx.fill(Path(CGRect(x: 0, y: 4, width: size.width, height: size.height - 4)), with: .color(BinderColors.floor))
            var x: CGFloat = 24, row = 0
            while x < size.width {
                ctx.fill(Path(CGRect(x: x, y: 4, width: 2, height: size.height - 4)), with: .color(BinderColors.floorSeam))
                x += row % 2 == 0 ? 54 : 38
                row += 1
            }
            ctx.fill(Path(CGRect(x: 0, y: 10, width: size.width, height: 1)), with: .color(BinderColors.floorSeam))
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

/// How tall an item stands on each band.
enum ShelfMetrics {
    static func spriteHeight(_ tier: ShelfTier) -> CGFloat {
        switch tier {
        case .upper: 76
        case .lower: 104
        case .floor: 132
        }
    }
}

/// One plank (or the floor) with its items, each a column: the item standing on the wood
/// and its tag hanging below. `item` draws a column for an item.
struct ShelfRow<ItemView: View>: View {
    let shelf: Shelf
    @ViewBuilder var item: (Item) -> ItemView

    var body: some View {
        let standing = ShelfMetrics.spriteHeight(shelf.tier)
        let wood = shelf.tier == .floor ? FloorBoards.height : ShelfPlank.height
        HStack(alignment: .top, spacing: 8) {
            ForEach(shelf.items) { item($0).frame(maxWidth: .infinity) }
        }
        .padding(.horizontal, 10)
        .background(alignment: .top) {
            Group {
                if shelf.tier == .floor { FloorBoards() } else { ShelfPlank() }
            }
            .padding(.top, standing - 3)
        }
        .padding(.top, shelf.tier == .floor ? 18 : 10)
        // Keeps the wood where the sprites stand even before tags lay out.
        .frame(minHeight: standing + wood, alignment: .top)
    }
}

/// One item on a shelf: its voxel model (or framed photo) standing on the wood, and a
/// small hanging tag with the name and price.
struct ShelfItemColumn: View {
    let item: Item
    let tier: ShelfTier
    let price: String
    /// Alternates the tag's tilt along the plank.
    var tilt: Double = 0

    var body: some View {
        let standing = ShelfMetrics.spriteHeight(tier)
        let wood = tier == .floor ? FloorBoards.height : ShelfPlank.height
        // On a shared plank each piece keeps its own size (a monitor next to a desk stays smaller).
        let own = min(standing, ShelfMetrics.spriteHeight(ShelfSize.of(item).tier))
        VStack(spacing: 0) {
            ShelfSprite(item: item, size: own)
                .frame(height: standing, alignment: .bottom)
            Color.clear.frame(height: wood - 3)
            // The string and the tag.
            Rectangle().fill(BinderColors.string).frame(width: 1, height: 6)
            VStack(spacing: 2) {
                Text(item.name)
                    .sansText(11.5, weight: .semibold, maxScale: 1.6)
                    .foregroundStyle(Theme.Paper.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(price).monoText(11, weight: .bold, maxScale: 1.6).foregroundStyle(Theme.Paper.inkMuted).lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(maxWidth: 140)
            .background(BinderColors.tag, in: RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous).strokeBorder(Theme.Paper.rule, lineWidth: 1))
            .mooveShadow(.contact)
            .overlay(alignment: .topTrailing) {
                if item.maybeSentimental {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ochre)
                        .offset(x: -4, y: -3)
                }
            }
            .rotationEffect(.degrees(tilt), anchor: .top)
        }
        .contentShape(Rectangle())
    }
}

/// The voxel sprite, or the photo for items added by photo (they have no size, so no model).
struct ShelfSprite: View {
    let item: Item
    let size: CGFloat

    var body: some View {
        if item.origin == .photo, !item.photoUrls.isEmpty {
            ItemPhoto(urls: item.photoUrls) { $0.resizable().scaledToFill() }
                .background(Theme.surface2)
                .frame(width: size * 0.62, height: size * 0.62)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tag - 1))
                .padding(4)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.tag + 1))
                .mooveShadow(.paper)
                .accessibilityHidden(true)
        } else {
            // The sprite's canvas has an inset; nudge it down so the model sits on the wood.
            VoxelThumbnail(item, size: size, tile: false)
                .offset(y: size * 0.1)
                .mooveShadow(.paper)
        }
    }
}

/// Holes along the page's left edge, so it reads as a binder page.
struct BinderHoles: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                Spacer(minLength: 24)
                Circle()
                    .fill(Theme.bg)
                    .overlay(Circle().strokeBorder(Theme.lineStrong, lineWidth: 1))
                    .frame(width: 9, height: 9)
                Spacer(minLength: 24)
            }
        }
        .frame(width: 9)
        .accessibilityHidden(true)
    }
}

// MARK: Placard

/// Tap an item: its placard (the model on a plinth, name, size, story, price + origin) and
/// what you can do with it.
struct PlacardSheet: View {
    let info: ExhibitInfo
    var onEditStory: () -> Void
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ExhibitPlinth(item: info.item)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                    ExhibitPlacard(info: info, onEditStory: onEditStory)
                        .padding(.horizontal, -12)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { actions }
                        VStack(alignment: .leading, spacing: 8) { actions }
                    }
                    .padding(.top, 12)
                }
                .padding(Theme.gutter)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .mooveScreen()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var actions: some View {
        Button("Open details", systemImage: "info.circle", action: onOpen)
            .buttonStyle(.pill(.primary, compact: true))
            .accessibilityIdentifier("inventory.placard.open")
        Menu {
            ItemFixMenu(item: info.item, onRename: onRename)
        } label: {
            Label("Fix it", systemImage: "wrench.adjustable")
        }
        .buttonStyle(.pill(.outline, compact: true))
        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            .buttonStyle(.pill(.danger, compact: true))
            .accessibilityIdentifier("inventory.placard.delete")
    }
}
