import SwiftUI
import UIKit
import MooveKit

/// The flip cards at the top of Review: the whole move as a stack (`Review.flipDeck`), the items
/// that need you first. The front is the item's photo; tap to flip to the voxel model and the
/// details. Swipe right = Keep, left = Sell (`ReviewSwipe`), on either side, or use the buttons
/// (Donate and Trash are buttons only, so a vertical scroll never decides). The parent owns the
/// decisions and the undo stack.
struct ReviewDeckView: View {
    /// Cards still to go, top first.
    let cards: [Item]
    let comps: [Comp]
    /// Cards done on this pass, for "4 of 12".
    let doneCount: Int
    let canUndo: Bool
    let onDecide: (Item, Disposition) -> Void
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drag: CGSize = .zero
    /// Showing the details side; `turn` is the card's rotation while it flips (0 at rest).
    @State private var flipped = false
    @State private var turn: Double = 0
    @State private var turning = false
    /// Set while the top card flies off, so a second swipe can't hit it.
    @State private var leaving: Disposition?

    static let threshold: Double = 110

    private var cardHeight: CGFloat { dynamicTypeSize.isAccessibilitySize ? 600 : 470 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let top = cards.first {
                ZStack {
                    // Up to two cards peek out behind the top one, fanned a little.
                    ForEach(Array(cards.dropFirst().prefix(2).enumerated().reversed()), id: \.element.id) { index, _ in
                        ReviewCardPaper()
                            .frame(height: cardHeight)
                            .scaleEffect(1 - 0.05 * CGFloat(index + 1))
                            .offset(y: 12 * CGFloat(index + 1))
                            .rotationEffect(.degrees(reduceMotion ? 0 : (index == 0 ? 2.5 : -2.5)))
                            .accessibilityHidden(true)
                    }
                    card(top)
                        .id(top.id)
                        .transition(.identity)
                }
                .padding(.top, 18)
                .padding(.bottom, 22 + 12 * CGFloat(min(cards.count - 1, 2)))
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .onChange(of: top.id) {
                    flipped = false
                    turn = 0
                }
                actions(top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.deck")
    }

    // MARK: Header

    private var header: some View {
        let total = cards.count + doneCount
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Flip through").listHeading().accessibilityAddTraits(.isHeader)
                Text("\(min(doneCount + 1, total)) of \(total)")
                    .monoText(13.5)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel("Card \(min(doneCount + 1, total)) of \(total)")
                    .accessibilityIdentifier("review.deck.progress")
                Spacer(minLength: 8)
                if canUndo { UndoButton(action: onUndo) }
            }
            GeometryReader { geo in
                Capsule().fill(Theme.surface2)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent)
                            .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(doneCount) / CGFloat(total))
                    }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
    }

    // MARK: Card

    private func card(_ item: Item) -> some View {
        let pointing = ReviewSwipe.pointing(dx: drag.width, dy: drag.height)
        let progress = ReviewSwipe.progress(dx: drag.width, dy: drag.height, threshold: Self.threshold)
        let armed = progress >= 1 ? pointing : nil
        let range = Review.valueRange(item, comps: comps)
        return ReviewFlipCard(flipped: flipped, turn: turn,
                              front: ReviewCardFront(item: item, range: range),
                              back: ReviewCardBack(item: item, range: range))
            .frame(height: cardHeight)
            .overlay {
                if let pointing {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .strokeBorder(ReviewPalette.glow(pointing), lineWidth: 3 + 3 * progress)
                        .opacity(progress)
                        .shadow(color: ReviewPalette.glow(pointing).opacity(0.6 * progress), radius: 14)
                        .allowsHitTesting(false)
                    SwipeStamp(disposition: pointing)
                        .opacity(progress)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pointing == .keep ? .topLeading : .topTrailing)
                        .padding(22)
                        .allowsHitTesting(false)
                }
            }
            .offset(drag)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width) / 18), anchor: .bottom)
            .contentShape(Rectangle())
            .onTapGesture { flip() }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard leaving == nil else { return }
                        drag = value.translation
                    }
                    .onEnded { value in
                        guard leaving == nil else { return }
                        if let d = ReviewSwipe.commit(dx: value.translation.width, dy: value.translation.height,
                                                      predictedDx: value.predictedEndTranslation.width,
                                                      predictedDy: value.predictedEndTranslation.height,
                                                      threshold: Self.threshold) {
                            fly(item, d)
                        } else {
                            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                        }
                    }
            )
            .sensoryFeedback(.selection, trigger: armed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.spoken(item, range: range))
            .accessibilityIdentifier("review.card.\(item.id)")
            .accessibilityHint("Swipe right to keep, left to sell. Double-tap to flip.")
            .accessibilityAction { flip() }
            .accessibilityActions {
                ForEach(Disposition.choices, id: \.self) { d in
                    Button(d.label) { fly(item, d) }
                }
            }
            .overlay(alignment: .topTrailing) {
                NavigationLink(value: item.id) {
                    Image(systemName: "info")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.bg.opacity(0.88)))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Details for \(item.name)")
                .accessibilityIdentifier("review.card.details")
                .opacity(drag == .zero ? 1 : 0)
                .padding(6)
            }
    }

    private func flip() {
        guard leaving == nil else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { flipped.toggle() }
            return
        }
        // Turn edge-on, swap sides out of sight, then turn the rest of the way.
        guard !turning else { return }
        turning = true
        let direction: Double = flipped ? -1 : 1
        withAnimation(.easeIn(duration: 0.16)) { turn = 90 * direction } completion: {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                flipped.toggle()
                turn = -90 * direction
            }
            withAnimation(.easeOut(duration: 0.2)) { turn = 0 } completion: { turning = false }
        }
    }

    /// "Yamaha acoustic guitar, needs you, possibly sentimental, $109. Moove says keep. <reason>"
    private static func spoken(_ item: Item, range: ClosedRange<Int64>?) -> String {
        var parts = [item.name]
        if ReviewSection.of(item) == .needsYou { parts.append("needs you") }
        if item.maybeSentimental { parts.append("possibly sentimental") }
        parts.append(range.map { "\($0.lowerBound.usd) to \($0.upperBound.usd)" } ?? item.priceText)
        if let verdict = Review.verdict(item) { parts.append("Moove says \(verdict)") }
        if item.dispositionSource == .user { parts.append("you chose \(item.disposition.label.lowercased())") }
        if let reason = item.dispositionReason, item.dispositionSource == .auto { parts.append(reason) }
        return parts.joined(separator: ", ")
    }

    /// Throws the card off in its direction, then hands the decision to the parent.
    private func fly(_ item: Item, _ d: Disposition) {
        guard leaving == nil else { return }
        leaving = d
        if reduceMotion {
            finish(item, d)
            return
        }
        let far = Self.offscreen(d, from: drag)
        withAnimation(.easeIn(duration: 0.22)) { drag = far } completion: { finish(item, d) }
    }

    private static func offscreen(_ d: Disposition, from drag: CGSize) -> CGSize {
        switch d {
        case .keep: CGSize(width: 700, height: drag.height)
        case .sell: CGSize(width: -700, height: drag.height)
        case .donate: CGSize(width: drag.width, height: -900)
        default: CGSize(width: drag.width, height: 900)
        }
    }

    private func finish(_ item: Item, _ d: Disposition) {
        onDecide(item, d)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            drag = .zero
            flipped = false
            turn = 0
        }
        leaving = nil
    }

    // MARK: Buttons

    @ViewBuilder
    private func actions(_ item: Item) -> some View {
        let order: [Disposition] = [.sell, .trash, .donate, .keep]
        if dynamicTypeSize.isAccessibilitySize {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { actionButton(.sell, item); actionButton(.keep, item) }
                GridRow { actionButton(.trash, item); actionButton(.donate, item) }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(order, id: \.self) { d in actionButton(d, item).frame(maxWidth: .infinity) }
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
    }

    private func actionButton(_ d: Disposition, _ item: Item) -> some View {
        let suggested = Review.suggestion(item) == d
        return Button { fly(item, d) } label: {
            VStack(spacing: 6) {
                Image(systemName: ReviewPalette.arrow(d))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(suggested ? Theme.accentInk : d.tint)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(suggested ? ReviewPalette.solid(d) : Theme.surface))
                    .overlay(Circle().strokeBorder(ReviewPalette.solid(d).opacity(0.5), lineWidth: 1))
                Text(d.label).monoText(12.5, weight: .bold, maxScale: 1.6).foregroundStyle(Theme.text).lineLimit(1)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(leaving != nil)
        .accessibilityLabel(suggested ? "\(d.label), suggested" : d.label)
        .accessibilityIdentifier("review.deck.\(d.rawValue)")
    }
}

/// Shows `front` or `back`, turned by `turn` degrees around the vertical axis. The deck turns it
/// edge-on, swaps sides, and turns it back (so the back never shows mirrored); under Reduce
/// Motion `turn` stays 0 and the sides crossfade.
private struct ReviewFlipCard<Front: View, Back: View>: View {
    let flipped: Bool
    let turn: Double
    let front: Front
    let back: Back

    var body: some View {
        ZStack {
            front.opacity(flipped ? 0 : 1)
            back.opacity(flipped ? 1 : 0)
        }
        .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}

/// Front: the item's photo, big. While it loads the paper shows; if none loads, the voxel model.
private struct ReviewCardFront: View {
    let item: Item
    let range: ClosedRange<Int64>?
    @State private var photo: UIImage?
    @State private var tried = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Theme.surface2
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().transition(.opacity)
                } else if tried {
                    ItemArt(item: item, size: 230, photo: .none).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) { ReviewCardBadge(item: item).padding(12) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name.capitalizedFirst)
                        .serifType(22, weight: .semibold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ReviewCardBack.value(item, range))
                        .monoText(14, weight: .bold)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                ReviewVerdict(item: item)
            }
            .padding(16)
        }
        .background(ReviewCardPaper())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .task(id: item.photoUrls) {
            let loaded = item.photoUrls.isEmpty ? nil : await ItemPhotoLoader.load(item.photoUrls)
            withAnimation(.easeOut(duration: 0.2)) {
                photo = loaded
                tried = true
            }
        }
    }
}

/// Back: the voxel model and the facts behind the call.
private struct ReviewCardBack: View {
    let item: Item
    let range: ClosedRange<Int64>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ItemArt(item: item, size: 150, photo: .none)
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(alignment: .topLeading) { ReviewCardBadge(item: item).padding(10) }
            Text(item.name.capitalizedFirst)
                .serifType(20, weight: .semibold)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                fact("Size", Self.size(item))
                fact("Value", Self.value(item, range))
                if let condition = item.condition { fact("Condition", "\(condition) / 5") }
            }
            if let reason = item.dispositionReason, item.dispositionSource == .auto {
                Text(reason.capitalizedFirst)
                    .sansText(14.5)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if item.maybeSentimental {
                Label("Possibly sentimental. Moove leaves it to you.", systemImage: "heart.fill")
                    .sansText(14)
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            ReviewVerdict(item: item)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ReviewCardPaper())
    }

    private func fact(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label.uppercased()).monoText(11, weight: .semibold, maxScale: 1.6).tracking(0.6).foregroundStyle(Theme.faint)
            Text(value).monoText(13.5).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    static func value(_ item: Item, _ range: ClosedRange<Int64>?) -> String {
        if let range { return "\(range.lowerBound.usd)–\(range.upperBound.usd)" }
        return item.priceText
    }

    static func size(_ item: Item) -> String {
        func cm(_ m: Double) -> String { "\(Int((m * 100).rounded()))" }
        return "\(cm(item.widthM))×\(cm(item.depthM))×\(cm(item.heightM)) cm"
    }
}

/// "Moove says: Sell · worth $30, costs ~$24 to move", or "You chose Keep" once it's yours.
private struct ReviewVerdict: View {
    let item: Item

    var body: some View {
        if let verdict = Review.verdict(item) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11)).accessibilityHidden(true)
                Text("Moove says: \(verdict)").monoText(12.5, weight: .semibold).lineLimit(2)
            }
            .foregroundStyle(item.disposition.tint)
        } else if item.dispositionSource == .user, item.disposition != .undecided {
            Text("You chose \(item.disposition.label)").monoText(12.5, weight: .semibold).foregroundStyle(Theme.muted)
        }
    }
}

/// "Needs you" on the cards only a person can decide (a heart when possibly sentimental).
private struct ReviewCardBadge: View {
    let item: Item

    var body: some View {
        if ReviewSection.of(item) == .needsYou {
            Label("Needs you", systemImage: item.maybeSentimental ? "heart.fill" : "hand.raised.fill")
                .labelStyle(.titleAndIcon)
                .monoText(11, weight: .bold, maxScale: 1.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.dangerSoft))
        }
    }
}

/// The card stock every deck card is printed on.
private struct ReviewCardPaper: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
            .fill(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
            .mooveShadow(.lifted)
    }
}

/// "KEEP" / "SELL" stamped on the card while it's dragged that way.
private struct SwipeStamp: View {
    let disposition: Disposition

    var body: some View {
        Text(disposition.label.uppercased())
            .monoText(24, weight: .heavy, maxScale: 1.4)
            .tracking(2)
            .foregroundStyle(ReviewPalette.solid(disposition))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ReviewPalette.solid(disposition), lineWidth: 3))
            .background(Theme.bg.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .rotationEffect(.degrees(disposition == .keep ? -12 : disposition == .sell ? 12 : 0))
            .accessibilityHidden(true)
    }
}

struct UndoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.pill(.outline, compact: true))
        .accessibilityIdentifier("review.undo")
    }
}

/// The end card once every card is through: what the move adds up to, and Start over.
struct ReviewAllDecided: View {
    let totals: ReviewTotals
    let canUndo: Bool
    let onUndo: () -> Void
    let onStartOver: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentStrong)
                .symbolEffect(.bounce, value: bounce)
                .accessibilityHidden(true)
            Text("All done").serifType(26, weight: .semibold).foregroundStyle(Theme.text)
            HStack(spacing: 0) {
                figure("\(totals.itemsToMove)", "moving")
                figure(totals.expectedSaleCents.usd, "to sell")
                figure("\(Int(totals.divertedKg.rounded())) kg", "saved")
            }
            HStack(spacing: 10) {
                if canUndo { UndoButton(action: onUndo) }
                Button(action: onStartOver) {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.pill(.outline, compact: true))
                .accessibilityIdentifier("review.startOver")
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .onAppear { if !reduceMotion { bounce += 1 } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.allDecided")
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).serifType(20, weight: .semibold).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).monoText(11, maxScale: 1.5).tracking(0.6).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
