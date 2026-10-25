import SwiftUI
import UIKit
import MooveKit

/// "Where it goes": the four destinations as moving-box labels (a count, the figure that matters,
/// a fan of their items), with no item lists. 2×2 on iPhone, four across on iPad, one column at
/// accessibility sizes. A label opens its list (`ReviewPileScreen`), where items can be changed.
struct ReviewBoardView: View {
    let piles: [ReviewPile]
    let onMove: (UInt64, Disposition) -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : sizeClass == .regular ? 4 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 20) {
            ForEach(piles) { pile in
                NavigationLink(value: ReviewPileRoute(destination: pile.destination)) {
                    ReviewPileTile(pile: pile)
                }
                .buttonStyle(ReviewLabelButtonStyle(tilt: dynamicTypeSize.isAccessibilitySize ? 0 : ReviewPileTile.tilt(pile.destination)))
                .dropDestination(for: String.self) { ids, _ in
                    let moved = ids.compactMap(UInt64.init)
                    moved.forEach { onMove($0, pile.destination) }
                    return !moved.isEmpty
                }
                .accessibilityLabel(ReviewPileTile.accessibilityLabel(pile))
                .accessibilityIdentifier("review.pile.\(pile.destination.rawValue)")
            }
        }
        .padding(.top, 6)
    }
}

/// Opens one destination's list from the board.
struct ReviewPileRoute: Hashable {
    let destination: Disposition
}

/// A label stuck on a note: slightly tilted (deterministic, none at accessibility sizes); pressing
/// straightens it with a small spring, or just dims it under Reduce Motion.
private struct ReviewLabelButtonStyle: ButtonStyle {
    let tilt: Double

    func makeBody(configuration: Configuration) -> some View {
        Pressable(label: configuration.label, pressed: configuration.isPressed, tilt: tilt)
    }

    private struct Pressable<Label: View>: View {
        let label: Label
        let pressed: Bool
        let tilt: Double
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .rotationEffect(.degrees(pressed && !reduceMotion ? 0 : tilt))
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .opacity(pressed && reduceMotion ? 0.75 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55), value: pressed)
        }
    }
}

/// One destination as a moving-box label: a strip of tape, the destination printed in its color
/// ("KEEP → New home"), the count written big in marker, a fan of its items and its total.
struct ReviewPileTile: View {
    let pile: ReviewPile

    var body: some View {
        let d = pile.destination
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: d.systemImage).font(.system(size: 12, weight: .bold))
                Text(Self.heading(d))
                    .font(ReviewHand.font(17, relativeTo: .headline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.accentInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ReviewPalette.solid(d), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(pile.count)")
                    .font(ReviewHand.font(40, relativeTo: .largeTitle))
                    .foregroundStyle(Theme.text)
                Text(pile.count == 1 ? "item" : "items")
                    .font(ReviewHand.font(16, relativeTo: .body))
                    .foregroundStyle(Theme.muted)
            }
            ItemFan(items: Array(pile.items.prefix(3)), destination: d)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
            Text(Self.total(pile))
                .monoText(12.5, weight: .bold, maxScale: 1.6)
                .foregroundStyle(pile.items.isEmpty ? Theme.muted : Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(ReviewPalette.paper)
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(ReviewPalette.solid(d).opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .overlay(alignment: .top) {
            // A strip of packing tape holding the label on.
            Rectangle()
                .fill(ReviewPalette.tape)
                .overlay(Rectangle().strokeBorder(Theme.lineStrong.opacity(0.6), lineWidth: 0.5))
                .frame(width: 56, height: 16)
                .rotationEffect(.degrees(-4))
                .offset(y: -8)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    /// The tilt each label is stuck on with, in degrees (fixed, so the board never shuffles).
    static func tilt(_ d: Disposition) -> Double {
        switch d {
        case .keep: -1.5
        case .sell: 1.2
        case .donate: -1
        default: 1.6
        }
    }

    static func heading(_ d: Disposition) -> String {
        d == .keep ? "KEEP → New home" : d.label.uppercased()
    }

    /// The figure that matters: volume moving, expected sales, kg kept from landfill.
    static func total(_ pile: ReviewPile) -> String {
        if pile.items.isEmpty { return "Nothing here yet" }
        switch pile.destination {
        case .keep: return String(format: "%.1f m³ to move", pile.volumeM3)
        case .sell: return "\(pile.valueCents.usd) expected"
        case .donate: return "\(Int(pile.kg.rounded())) kg kept from landfill"
        default: return "To the curb"
        }
    }

    /// "Keep, 7 items, opens the list"; Sell and Donate add their total.
    static func accessibilityLabel(_ pile: ReviewPile) -> String {
        var parts = [pile.destination.label, pile.count == 1 ? "1 item" : "\(pile.count) items"]
        if !pile.items.isEmpty {
            switch pile.destination {
            case .sell: parts.append("\(pile.valueCents.usd) expected")
            case .donate: parts.append("about \(Int(pile.kg.rounded())) kilograms kept from landfill")
            default: break
            }
        }
        parts.append("opens the list")
        return parts.joined(separator: ", ")
    }
}

/// The board labels' marker lettering: Marker Felt, else the rounded system font. Scales with
/// Dynamic Type.
enum ReviewHand {
    static let name = "MarkerFelt-Wide"
    static let available = UIFont(name: name, size: 12) != nil

    static func font(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        available ? .custom(name, size: size, relativeTo: style) : .system(style, design: .rounded).weight(.bold)
    }
}

/// One destination's items, opened from its label: each row with its reason and the ⇄ change
/// menu (Keep grouped by the new home's rooms). On iPad, rows drag onto the other labels at the top.
struct ReviewPileScreen: View {
    let destination: Disposition
    @Environment(MooveStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let piles = Review.piles(store.visibleItems)
        let pile = piles.first { $0.destination == destination }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let pile {
                    Text(ReviewPileTile.total(pile)).monoMeta().padding(.bottom, 8)
                    if sizeClass == .regular { moveTargets(piles) }
                    list(pile, keepGroups: Review.keepByRoom(pile.items, layout: Review.savedLayout(in: store.snapshot)))
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle(destination.label)
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .animation(.default, value: store.visibleItems)
    }

    /// The other three destinations as small labels to drop a dragged row on.
    private func moveTargets(_ piles: [ReviewPile]) -> some View {
        HStack(spacing: 10) {
            Text("Drag a row to").monoMeta()
            ForEach(piles.filter { $0.destination != destination }) { other in
                let d = other.destination
                Label(d.label, systemImage: d.systemImage)
                    .font(ReviewHand.font(15, relativeTo: .subheadline))
                    .foregroundStyle(Theme.accentInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ReviewPalette.solid(d), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .rotationEffect(.degrees(ReviewPileTile.tilt(d)))
                    .dropDestination(for: String.self) { ids, _ in
                        let moved = ids.compactMap(UInt64.init)
                        for id in moved {
                            guard let item = store.items.first(where: { $0.id == id }) else { continue }
                            Task { await store.setDisposition(d, for: item) }
                        }
                        return !moved.isEmpty
                    }
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func list(_ pile: ReviewPile, keepGroups: [ReviewKeepGroup]) -> some View {
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
                    rows(group.items)
                }
            } else {
                rows(pile.items)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.list.\(pile.destination.rawValue)")
    }

    private func rows(_ items: [Item]) -> some View {
        ForEach(items) { item in
            ReviewBoardRow(item: item)
                .modifier(DraggableItem(id: item.id, enabled: sizeClass == .regular))
        }
    }
}

/// Rows drag onto the other labels on iPad (a long press on iPhone opens the change menu instead).
private struct DraggableItem: ViewModifier {
    let id: UInt64
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.draggable(String(id)) } else { content }
    }
}

/// Up to three voxel models fanned like a hand of cards.
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
                ItemArt(item: item, size: 60, photo: .none)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
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

    /// The board labels' paper and the tape holding them on.
    static let paper = Color(uiColor: Theme.dynamicUIColor(0xFBF7EF, 0x2C261F))
    static let tape = Color(uiColor: Theme.dynamicUIColor(0xE4D2AE, 0x5C4E37)).opacity(0.85)

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
