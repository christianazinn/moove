import SwiftUI
import MooveKit

/// "Where it goes": the four destinations as tiles with their items fanned on top. On iPhone a
/// 2×2 grid (tap a tile to open its list under the grid); on iPad four columns side by side,
/// each with its list, and items can be dragged between them.
struct ReviewBoardView: View {
    let piles: [ReviewPile]
    let keepGroups: [ReviewKeepGroup]
    @Binding var selected: Disposition?
    let onMove: (UInt64, Disposition) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 14) {
                ForEach(piles) { pile in
                    VStack(alignment: .leading, spacing: 10) {
                        tile(pile, expandable: false)
                        list(pile, compact: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                         count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(piles) { tile($0, expandable: true) }
                }
                if let selected, let pile = piles.first(where: { $0.destination == selected }) {
                    list(pile, compact: false)
                        .padding(.top, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    // MARK: Tile

    private func tile(_ pile: ReviewPile, expandable: Bool) -> some View {
        Button {
            guard expandable else { return }
            selected = selected == pile.destination ? nil : pile.destination
        } label: {
            ReviewPileTile(pile: pile, selected: expandable && selected == pile.destination)
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { ids, _ in
            let moved = ids.compactMap(UInt64.init)
            moved.forEach { onMove($0, pile.destination) }
            return !moved.isEmpty
        }
        .accessibilityLabel(ReviewPileTile.accessibilityLabel(pile))
        .accessibilityAddTraits(expandable && selected == pile.destination ? .isSelected : [])
        .accessibilityHint(Text(expandable ? "Shows its items." as String : ""))
        .accessibilityIdentifier("review.pile.\(pile.destination.rawValue)")
    }

    // MARK: List

    @ViewBuilder
    private func list(_ pile: ReviewPile, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if pile.items.isEmpty {
                Text("Nothing here yet.")
                    .monoMeta()
                    .padding(.vertical, 14)
            } else if pile.destination == .keep, keepGroups.contains(where: { $0.room != nil }) {
                ForEach(keepGroups, id: \.room) { group in
                    Text(group.room.map { "→ \($0)" } ?? "Not placed yet")
                        .monoText(12.5, weight: .bold)
                        .foregroundStyle(Theme.accentStrong)
                        .padding(.top, 14)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    rows(group.items, compact: compact)
                }
            } else {
                rows(pile.items, compact: compact)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.list.\(pile.destination.rawValue)")
    }

    private func rows(_ items: [Item], compact: Bool) -> some View {
        ForEach(items) { item in
            ReviewBoardRow(item: item, compact: compact)
                .modifier(DraggableItem(id: item.id, enabled: sizeClass == .regular))
        }
    }
}

/// Rows drag between the iPad columns (a long press on iPhone opens the change menu instead).
private struct DraggableItem: ViewModifier {
    let id: UInt64
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.draggable(String(id)) } else { content }
    }
}

/// One destination: its color, name, a fan of its items and the figure that matters for it.
struct ReviewPileTile: View {
    let pile: ReviewPile
    var selected = false

    var body: some View {
        let d = pile.destination
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: d.systemImage).font(.system(size: 13, weight: .semibold)).foregroundStyle(d.tint)
                Text(d.label).monoText(15, weight: .bold).foregroundStyle(Theme.text)
                Spacer(minLength: 4)
                Text("\(pile.count)").monoText(13.5).foregroundStyle(Theme.muted)
            }
            ItemFan(items: Array(pile.items.prefix(3)), destination: d)
                .frame(maxWidth: .infinity)
                .frame(height: 74)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.figure(pile))
                    .monoText(22, weight: .bold, maxScale: 1.5)
                    .foregroundStyle(pile.items.isEmpty ? Theme.muted : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(Self.caption(d)).monoText(12.5, maxScale: 1.6).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReviewPalette.soft(d), in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .strokeBorder(selected ? ReviewPalette.solid(d) : Theme.line, lineWidth: selected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
    }

    /// The tile's big number: items moving, expected sales, kg kept from landfill, items to toss.
    static func figure(_ pile: ReviewPile) -> String {
        switch pile.destination {
        case .sell: pile.valueCents.usd
        case .donate: "\(Int(pile.kg.rounded())) kg"
        default: pile.count == 1 ? "1 item" : "\(pile.count) items"
        }
    }

    static func caption(_ d: Disposition) -> String {
        switch d {
        case .keep: "→ new home"
        case .sell: "expected sales"
        case .donate: "kept from landfill"
        default: "to the curb"
        }
    }

    static func accessibilityLabel(_ pile: ReviewPile) -> String {
        let count = pile.count == 1 ? "1 item" : "\(pile.count) items"
        switch pile.destination {
        case .keep: return "Keep, \(count), moving to the new home"
        case .sell: return "Sell, \(count), \(pile.valueCents.usd) expected"
        case .donate: return "Donate, \(count), about \(Int(pile.kg.rounded())) kilograms kept from landfill"
        default: return "Trash, \(count)"
        }
    }
}

/// Up to three voxel models (or photos) fanned like a hand of cards.
private struct ItemFan: View {
    let items: [Item]
    let destination: Disposition

    var body: some View {
        ZStack {
            if items.isEmpty {
                RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous)
                    .strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: destination.systemImage).foregroundStyle(Theme.faint))
            }
            ForEach(Array(items.enumerated().reversed()), id: \.element.id) { index, item in
                let spread = Self.spread(index, of: items.count)
                ItemArt(item: item, size: 60)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                    .rotationEffect(.degrees(spread * 9))
                    .offset(x: spread * 30, y: abs(spread) * 5)
            }
        }
        .accessibilityHidden(true)
    }

    /// -1, 0, 1 across the fan; the first (most valuable) item sits in front, in the middle.
    private static func spread(_ index: Int, of count: Int) -> CGFloat {
        switch (count, index) {
        case (1, _): 0
        case (2, 0): -0.5
        case (2, _): 0.5
        case (_, 0): 0
        case (_, 1): -1
        default: 1
        }
    }
}

/// An item on the board: model, name, why it's here, value, and a quick change menu.
struct ReviewBoardRow: View {
    let item: Item
    var compact = false

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: item.id) {
                HStack(spacing: 12) {
                    ItemArt(item: item, size: compact ? 40 : 48)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(item.name).monoText(compact ? 13.5 : 14.5, weight: .bold).foregroundStyle(Theme.text).lineLimit(2)
                            if item.maybeSentimental {
                                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(Theme.danger)
                                    .accessibilityLabel("Possibly sentimental")
                            }
                        }
                        if let why = Self.why(item) {
                            Text(why).monoText(12, maxScale: 1.8).foregroundStyle(Theme.muted).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(item.saleValueCents?.usd ?? "—").monoText(13.5).foregroundStyle(Theme.text).lineLimit(1).layoutPriority(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("review.item.\(item.id)")
            Menu {
                DispositionMenu(item: item)
            } label: {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Change where \(item.name) goes")
            .accessibilityIdentifier("review.change.\(item.id)")
        }
        .padding(.vertical, 10)
        .ruled()
        .contextMenu { DispositionMenu(item: item) }
    }

    /// "You decided", or the sort agent's one-line reason.
    static func why(_ item: Item) -> String? {
        if item.dispositionSource == .user { return "You decided" }
        return item.dispositionReason?.capitalizedFirst
    }
}

struct DispositionMenu: View {
    @Environment(MooveStore.self) private var store
    let item: Item

    var body: some View {
        ForEach(Disposition.choices, id: \.self) { d in
            Button(d.label, systemImage: d.systemImage) { Task { await store.setDisposition(d, for: item) } }
                .disabled(item.disposition == d && item.dispositionSource == .user)
        }
        Divider()
        Button(item.maybeSentimental ? "Not sentimental" : "Mark sentimental", systemImage: item.maybeSentimental ? "heart.slash" : "heart") {
            Task { await store.setSentimental(!item.maybeSentimental, for: item) }
        }
    }
}

/// Theme colors for dispositions on this screen (the shared `Disposition.tint` lives in ItemViews).
enum ReviewPalette {
    /// Strong fill: swipe stamps, suggested buttons, the selected tile's border.
    static func solid(_ d: Disposition) -> Color {
        switch d {
        case .keep: Theme.accentFill
        case .sell: Theme.ochreInk
        case .donate: Theme.color(0x55657A)
        case .trash: Theme.stone
        case .undecided: Theme.danger
        }
    }

    /// Edge glow while a card is dragged that way.
    static func glow(_ d: Disposition) -> Color {
        switch d {
        case .keep: Theme.accent
        case .sell: Theme.ochre
        case .donate: Theme.slate
        case .trash: Theme.stone
        case .undecided: Theme.danger
        }
    }

    /// Tile background, a whisper of the destination's color over the page.
    static func soft(_ d: Disposition) -> Color {
        switch d {
        case .keep: Theme.accentSoft
        case .sell: Theme.ochre.opacity(0.16)
        case .donate: Theme.slate.opacity(0.16)
        case .trash: Theme.surface
        case .undecided: Theme.dangerSoft
        }
    }

    /// The deck's swipe direction for each choice.
    static func arrow(_ d: Disposition) -> String {
        switch d {
        case .keep: "arrow.right"
        case .sell: "arrow.left"
        case .donate: "arrow.up"
        case .trash: "arrow.down"
        case .undecided: "questionmark"
        }
    }
}
