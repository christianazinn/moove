import SwiftUI
import MooveKit

/// "Needs you": the items only a person can decide (undecided, or possibly sentimental), as a
/// stack of cards. Swipe right = Keep, left = Sell, up = Donate, down = Trash (`ReviewSwipe`),
/// or use the buttons under the card. The parent owns the decisions and the undo stack.
struct ReviewDeckView: View {
    /// Cards still to decide, top first (`Review.deck`).
    let cards: [Item]
    let comps: [Comp]
    /// Decided on this visit, for "2 of 5".
    let decidedCount: Int
    let canUndo: Bool
    let onDecide: (Item, Disposition) -> Void
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var drag: CGSize = .zero
    /// Set while the top card flies off, so a second swipe can't hit it.
    @State private var leaving: Disposition?

    static let threshold: Double = 110

    var body: some View {
        VStack(spacing: 0) {
            header
            if let top = cards.first {
                ZStack {
                    // Up to two cards peek out behind the top one, fanned a little.
                    ForEach(Array(cards.dropFirst().prefix(2).enumerated().reversed()), id: \.element.id) { index, item in
                        ReviewCardBack(item: item)
                            .scaleEffect(1 - 0.05 * CGFloat(index + 1))
                            .offset(y: 12 * CGFloat(index + 1))
                            .rotationEffect(.degrees(reduceMotion ? 0 : (index == 0 ? 2.5 : -2.5)))
                            .accessibilityHidden(true)
                    }
                    card(top)
                        .id(top.id)
                        .transition(.identity)
                }
                .padding(.top, 20)
                .padding(.bottom, 24 + 12 * CGFloat(min(cards.count - 1, 2)))
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                actions(top)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.deck")
    }

    // MARK: Header

    private var header: some View {
        let total = cards.count + decidedCount
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Needs you").listHeading().accessibilityAddTraits(.isHeader)
                Text("\(min(decidedCount + 1, total)) of \(total)")
                    .monoText(13.5)
                    .foregroundStyle(Theme.muted)
                    .accessibilityLabel("Card \(min(decidedCount + 1, total)) of \(total)")
                    .accessibilityIdentifier("review.deck.progress")
                Spacer(minLength: 8)
                if canUndo { UndoButton(action: onUndo) }
            }
            GeometryReader { geo in
                Capsule().fill(Theme.surface2)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent)
                            .frame(width: total == 0 ? 0 : geo.size.width * CGFloat(decidedCount) / CGFloat(total))
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
        return ReviewCardFace(item: item, range: Review.valueRange(item, comps: comps))
            .overlay {
                if let pointing {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(ReviewPalette.glow(pointing), lineWidth: 3 + 3 * progress)
                        .opacity(progress)
                        .shadow(color: ReviewPalette.glow(pointing).opacity(0.6 * progress), radius: 14)
                        .allowsHitTesting(false)
                    SwipeStamp(disposition: pointing)
                        .opacity(progress)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: stampAlignment(pointing))
                        .padding(22)
                        .allowsHitTesting(false)
                }
            }
            .offset(drag)
            .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width) / 18), anchor: .bottom)
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
            .accessibilityLabel(Self.spoken(item))
            .accessibilityIdentifier("review.card.\(item.id)")
            .accessibilityHint("Swipe right to keep, left to sell. Donate and Trash are buttons below.")
            .accessibilityActions {
                ForEach(Disposition.choices, id: \.self) { d in
                    Button(d.label) { fly(item, d) }
                }
            }
            .overlay(alignment: .topTrailing) {
                NavigationLink(value: item.id) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Details for \(item.name)")
                .accessibilityIdentifier("review.card.details")
                .opacity(drag == .zero ? 1 : 0)
                .padding(6)
            }
    }

    /// "Yamaha acoustic guitar, $109, possibly sentimental, Moove says keep. <reason>"
    private static func spoken(_ item: Item) -> String {
        var parts = [item.name, item.priceText]
        if item.maybeSentimental { parts.append("possibly sentimental") }
        if let s = Review.suggestion(item) { parts.append("Moove says \(s.label.lowercased())") }
        if let reason = item.dispositionReason, item.dispositionSource == .auto { parts.append(reason) }
        return parts.joined(separator: ", ")
    }

    private func stampAlignment(_ d: Disposition) -> Alignment {
        switch d {
        case .keep: .topLeading
        case .sell: .topTrailing
        case .donate: .bottom
        default: .top
        }
    }

    /// Throws the card off in its direction, then hands the decision to the parent.
    private func fly(_ item: Item, _ d: Disposition) {
        guard leaving == nil else { return }
        leaving = d
        let far = Self.offscreen(d, from: drag)
        if reduceMotion {
            finish(item, d)
            return
        }
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
        withTransaction(t) { drag = .zero }
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

/// The face of a deck card: the item big, its name, size and value, and what Moove thinks.
private struct ReviewCardFace: View {
    let item: Item
    let range: ClosedRange<Int64>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The voxel model is the card's picture (the same piece that flies into the new
            // home, and never blank); the photo, once it loads, is a snapshot pinned in the corner.
            ItemArt(item: item, size: 190, photo: .none)
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    ItemPhoto(urls: item.photoUrls) { image in
                        image.resizable().scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(5)
                            .background(Theme.bg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                            .rotationEffect(.degrees(4))
                            .padding(12)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if item.maybeSentimental {
                        Label("Sentimental", systemImage: "heart.fill")
                            .labelStyle(.titleAndIcon)
                            .monoText(11, weight: .bold, maxScale: 1.6)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Theme.dangerSoft))
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .monoText(20, weight: .bold, maxScale: 1.6)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(valueText).monoText(15, weight: .bold).foregroundStyle(Theme.text)
                    Text("·").monoText(13).foregroundStyle(Theme.faint).accessibilityHidden(true)
                    Text(sizeText).monoMeta().lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            if let suggestion = Review.suggestion(item) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(suggestion.tint).accessibilityHidden(true)
                    Text("Moove says \(suggestion.label.lowercased())").monoText(13, weight: .bold).foregroundStyle(suggestion.tint)
                }
            }
            if let reason = item.dispositionReason, item.dispositionSource == .auto {
                Text(reason.capitalizedFirst)
                    .sansText(14.5)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReviewCardBackground())
    }

    private var valueText: String {
        if let range { return "\(range.lowerBound.usd)–\(range.upperBound.usd)" }
        return item.priceText
    }

    private var sizeText: String {
        func cm(_ m: Double) -> String { "\(Int((m * 100).rounded()))" }
        return "\(cm(item.widthM))×\(cm(item.depthM))×\(cm(item.heightM)) cm"
    }
}

/// A card further down the stack: just the paper, with a hint of the item.
private struct ReviewCardBack: View {
    let item: Item

    var body: some View {
        ReviewCardBackground()
            .overlay(alignment: .top) {
                ItemArt(item: item, size: 120, photo: .none).opacity(0.35).padding(.top, 40)
            }
    }
}

private struct ReviewCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Theme.bg)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.lineStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
    }
}

/// "KEEP" / "SELL" / … stamped on the card while it's dragged that way.
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

/// "All decided": shown once the deck is empty on this visit, with what it added up to.
struct ReviewAllDecided: View {
    let totals: ReviewTotals
    let canUndo: Bool
    let onUndo: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = 0

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accentStrong)
                .symbolEffect(.bounce, value: bounce)
                .accessibilityHidden(true)
            Text("All decided.").monoText(22, weight: .bold, maxScale: 1.6).foregroundStyle(Theme.text)
            HStack(spacing: 0) {
                figure("\(totals.itemsToMove)", "moving")
                figure(totals.expectedSaleCents.usd, "to sell")
                figure("\(Int(totals.divertedKg.rounded())) kg", "saved")
            }
            if canUndo { UndoButton(action: onUndo) }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onAppear { if !reduceMotion { bounce += 1 } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.allDecided")
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).monoText(20, weight: .bold, maxScale: 1.5).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).monoText(12.5, maxScale: 1.5).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
