import SwiftUI
import MooveKit

// The Shopping storefront's pieces: hero banner, bento item cards and deal shelves. Layout
// decisions (who gets the big card, which deals go on which shelf) come from MooveKit
// `SyncSnapshot.storefront()`; these views only draw them. At accessibility text sizes the grid
// and the shelves turn into one column.

/// Soft backdrop colors for item imagery, picked by id so a card keeps its color.
enum StorefrontTint {
    static func color(for id: UInt64) -> Color {
        switch id % 4 {
        case 0: Theme.accentSoft
        case 1: Theme.ochre.opacity(0.2)
        case 2: Theme.slate.opacity(0.2)
        default: Theme.surface2
        }
    }
}

extension StorefrontBadge.Tone {
    var color: Color {
        switch self {
        case .neutral: Theme.muted
        case .working: Theme.text
        case .attention: Theme.ochreInk
        case .good: Theme.accentStrong
        case .danger: Theme.danger
        }
    }
}

/// A big voxel drawing on a soft colored tile, filling the space it's given.
struct StorefrontImage: View {
    let spec: VoxelItemSpec
    let tint: Color
    var height: CGFloat
    var bought = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous).fill(tint)
            VoxelThumbnail(spec: spec, size: height * 0.92, tile: false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay(alignment: .bottomTrailing) {
            if bought {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accentStrong)
                    .background(Circle().fill(Theme.bg))
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Best deal" / "Lowest price" / "Local pickup", as a filled corner ribbon.
struct RibbonTag: View {
    let ribbon: StorefrontRibbon

    var body: some View {
        Label {
            Text(ribbon.label).monoText(11, weight: .bold, maxScale: 1.6).tracking(0.3)
        } icon: {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(ribbon == .bestDeal ? Theme.accentInk : Theme.text)
        .background(ribbon == .bestDeal ? Theme.accentFill : Theme.bg, in: Capsule())
        .accessibilityHidden(true)
    }

    private var icon: String {
        switch ribbon {
        case .bestDeal: "star.fill"
        case .lowestPrice: "arrow.down"
        case .localPickup: "mappin"
        }
    }
}

/// A price on a chip, like a shelf tag.
struct PriceChip: View {
    let text: String
    var large = false

    var body: some View {
        Text(text)
            .monoText(large ? 20 : 15, weight: .bold, maxScale: 1.6)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, large ? 12 : 9)
            .padding(.vertical, large ? 6 : 4)
            .foregroundStyle(Theme.text)
            .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous).strokeBorder(Theme.line))
            .accessibilityHidden(true)
    }
}

/// The card's status in words, with a dot that pulses while an agent works (unless Reduce Motion).
struct StorefrontBadgeView: View {
    let badge: StorefrontBadge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .symbolEffect(.pulse, isActive: badge.tone == .working && !reduceMotion)
                .accessibilityHidden(true)
            Text(badge.label).monoText(12.5).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(badge.tone.color)
    }
}

// MARK: Hero

/// The banner at the top: how much is left, and the best saving with a big picture and a CTA.
struct StorefrontHeroBanner: View {
    let hero: StorefrontHero
    let item: ShoppingItem?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let large = dynamicTypeSize.isAccessibilitySize
        let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                           : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 10) {
                Text(hero.pick == nil ? "Your list" : "Biggest saving").eyebrow()
                Text(hero.headline)
                    .monoText(21, weight: .bold, maxScale: 1.6)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let pick = hero.pick {
                    Text("\(pick.itemName) · \(pick.deal.formattedPrice) · \(pick.savingsPercent)% under the priciest deal found")
                        .sansText(14.5)
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Label("See deals", systemImage: "arrow.right")
                        .labelStyle(.titleAndIcon)
                        .monoText(13, weight: .bold, maxScale: 1.5)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .foregroundStyle(Theme.accentInk)
                        .background(Theme.accentFill, in: Capsule())
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let pick = hero.pick {
                VoxelThumbnail(spec: ShoppingThumbnails.spec(for: pick.deal, item: item), size: large ? 200 : 150, tile: false)
                    .overlay(alignment: .topTrailing) {
                        Text("-\(pick.savingsPercent)%")
                            .monoText(15, weight: .heavy, maxScale: 1.4)
                            .foregroundStyle(Theme.accentInk)
                            .padding(10)
                            .background(Circle().fill(Theme.ochreInk))
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: large ? .infinity : nil)
            } else if let item {
                VoxelThumbnail(spec: ShoppingThumbnails.spec(for: item), size: large ? 180 : 130, tile: false)
                    .frame(maxWidth: large ? .infinity : nil)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
                .fill(LinearGradient(colors: [Theme.accentSoft, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let pick = hero.pick else { return hero.headline }
        return "\(hero.headline). Biggest saving: \(pick.itemName), \(pick.deal.formattedPrice) from \(pick.deal.source), "
            + "\(pick.savingsPercent) percent under the priciest deal found. See deals."
    }
}

// MARK: Bento

/// The item cards in asymmetric rows; one column at accessibility text sizes.
struct StorefrontBento: View {
    let rows: [StorefrontRow]
    var onRemove: (ShoppingItem) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let gap: CGFloat = 12

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: gap) {
                ForEach(rows.flatMap(\.tiles)) { card($0, size: .feature) }
            }
        } else {
            VStack(spacing: gap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in rowView(row) }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: StorefrontRow) -> some View {
        switch row {
        case .single(let t):
            card(t, size: t.size)
        case .pair(let a, let b):
            // Staggered by a few points so the pair doesn't read as a spreadsheet.
            HStack(alignment: .top, spacing: gap) {
                card(a, size: .small).frame(maxHeight: .infinity).padding(.bottom, 14)
                card(b, size: .small).frame(maxHeight: .infinity).padding(.top, 14)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .tall(let t, let stack, let tallLeading):
            HStack(alignment: .top, spacing: gap) {
                if tallLeading { card(t, size: .tall).frame(maxHeight: .infinity) }
                VStack(spacing: gap) {
                    ForEach(stack) { card($0, size: .small).frame(maxHeight: .infinity) }
                }
                .padding(.top, 18)
                if !tallLeading { card(t, size: .tall).frame(maxHeight: .infinity) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card(_ tile: StorefrontTile, size: StorefrontCardSize) -> some View {
        NavigationLink(value: ShoppingRoute(itemId: tile.item.id)) {
            StorefrontItemCard(tile: tile, size: size)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shopping.item.\(tile.item.id)")
        .contextMenu {
            Button("Remove from list", systemImage: "trash", role: .destructive) { onRemove(tile.item) }
        }
        .accessibilityAction(named: "Remove from list") { onRemove(tile.item) }
    }
}

/// One shopping-list item as a product card. `size` decides the image size and arrangement.
struct StorefrontItemCard: View {
    @Environment(MooveStore.self) private var store
    let tile: StorefrontTile
    let size: StorefrontCardSize

    var body: some View {
        let item = tile.item
        let payment = tile.featured.flatMap { store.snapshot.visaPayment(for: $0.deal.id) }
        let spec = tile.featured.map { ShoppingThumbnails.spec(for: $0.deal, item: item) } ?? ShoppingThumbnails.spec(for: item)
        let tint = StorefrontTint.color(for: item.id)
        Group {
            if size == .wide {
                HStack(alignment: .center, spacing: 14) {
                    image(spec, tint: tint, height: 120).frame(width: 130)
                    details(payment: payment)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    image(spec, tint: tint, height: imageHeight)
                    details(payment: payment)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous).strokeBorder(Theme.line))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(payment: payment))
        .accessibilityHint("Opens the deals")
    }

    private var imageHeight: CGFloat {
        switch size {
        case .feature: 210
        case .tall: 190
        case .wide: 120
        case .small: 96
        }
    }

    private func image(_ spec: VoxelItemSpec, tint: Color, height: CGFloat) -> some View {
        StorefrontImage(spec: spec, tint: tint, height: height, bought: tile.item.status == .bought)
            .overlay(alignment: .topLeading) {
                if let ribbon = tile.ribbon { RibbonTag(ribbon: ribbon).padding(8) }
            }
            .overlay(alignment: .bottomLeading) {
                if let featured = tile.featured, size != .small {
                    PriceChip(text: featured.deal.formattedPrice, large: size == .feature).padding(8)
                }
            }
    }

    private func details(payment: Payment?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tile.item.name)
                    .monoText(size == .feature ? 19 : 15, weight: .bold, maxScale: 1.6)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if size == .small, let featured = tile.featured {
                    Text(featured.deal.formattedPrice).rowValue().fontWeight(.bold).amountText()
                }
            }
            StorefrontBadgeView(badge: tile.badge)
            if let featured = tile.featured, size == .feature || size == .wide || size == .tall {
                Text(featured.deal.title)
                    .sansText(13.5)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(size == .tall ? 3 : 2)
                Text(featured.deal.source.uppercased()).monoText(11, weight: .bold).foregroundStyle(Theme.faint)
            }
            if let payment {
                VisaRailBadge(badge: VisaPaymentBadge(payment))
                if payment.status == .failed {
                    Text("Nothing was charged. Pick another deal.")
                        .monoText(12)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spoken(payment: Payment?) -> String {
        var parts = [tile.item.name, tile.badge.label]
        if let ribbon = tile.ribbon { parts.append(ribbon.label) }
        if let f = tile.featured { parts.append("\(f.deal.formattedPrice) from \(f.deal.source)") }
        if let payment { parts.append(VisaPaymentBadge(payment).accessibilitySummary(amount: payment.formattedAmount)) }
        if payment?.status == .failed { parts.append("checkout failed, nothing was charged") }
        return parts.joined(separator: ", ")
    }
}

// MARK: Shelves

/// A headline over a sideways row of deal cards; a vertical list at accessibility text sizes.
struct StorefrontShelfView: View {
    @Environment(MooveStore.self) private var store
    let shelf: StorefrontShelf
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if shelf.kind == .blocked {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.danger).accessibilityHidden(true)
                }
                Text(shelf.title).listHeading().accessibilityAddTraits(.isHeader)
                Text("\(shelf.deals.count)").monoText(13.5).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, Theme.gutter)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(shelf.deals) { card($0).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, Theme.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(shelf.deals) { card($0).frame(width: 196) }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .padding(.bottom, 4)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func card(_ d: StorefrontDeal) -> some View {
        NavigationLink(value: ShoppingRoute(itemId: d.itemId)) {
            StorefrontDealCard(deal: d, blocked: shelf.kind == .blocked,
                               item: store.snapshot.shoppingItems.first { $0.id == d.itemId })
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shelf.\(shelf.kind.rawValue).deal.\(d.id)")
    }
}

/// One deal as a product card: big picture, title, price, source and seller, saving, fraud check.
struct StorefrontDealCard: View {
    let deal: StorefrontDeal
    let blocked: Bool
    let item: ShoppingItem?

    var body: some View {
        let d = deal.deal
        VStack(alignment: .leading, spacing: 8) {
            StorefrontImage(spec: ShoppingThumbnails.spec(for: d, item: item),
                            tint: blocked ? Theme.dangerSoft : StorefrontTint.color(for: deal.itemId), height: 130)
                .overlay(alignment: .topLeading) {
                    if blocked {
                        Label("Blocked", systemImage: "xmark.octagon.fill")
                            .labelStyle(.titleAndIcon)
                            .monoText(11, weight: .bold, maxScale: 1.6)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .foregroundStyle(Theme.bg)
                            .background(Theme.danger, in: Capsule())
                            .padding(8)
                    } else if deal.isLocalPickup, let distance = deal.distanceText {
                        Label(distance, systemImage: "mappin")
                            .labelStyle(.titleAndIcon)
                            .monoText(11, weight: .bold, maxScale: 1.6)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Theme.bg, in: Capsule())
                            .padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if d.isSample { ReplayBadge(sample: true).padding(8) } else if d.isReplay { ReplayBadge().padding(8) }
                }
            Text(deal.itemName.uppercased()).monoText(11, weight: .bold).foregroundStyle(Theme.faint).lineLimit(1)
            Text(d.title)
                .sansText(14, weight: .medium)
                .foregroundStyle(Theme.text)
                .lineLimit(2, reservesSpace: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(d.formattedPrice)
                    .monoText(18, weight: .bold, maxScale: 1.6)
                    .foregroundStyle(blocked ? Theme.muted : Theme.text)
                    .strikethrough(blocked)
                    .amountText()
                Text(d.source).monoMeta().lineLimit(1)
            }
            if !d.sellerDetails.isEmpty {
                Text(d.sellerDetails).monoText(11.5).foregroundStyle(Theme.muted).lineLimit(2)
            }
            if blocked {
                if let level = d.fraudLevel, let score = d.fraudScore { FraudChip(level: level, score: score) }
                if let reason = d.fraudReasons.first {
                    Text(reason).monoText(11.5).foregroundStyle(Theme.danger).lineLimit(2)
                }
            } else if let savings = deal.savingsText {
                Text(savings)
                    .monoText(12, weight: .bold)
                    .foregroundStyle(Theme.accentStrong)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(blocked ? Theme.dangerSoft.opacity(0.5) : Theme.surface.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous)
            .strokeBorder(blocked ? Theme.danger : Theme.line, lineWidth: blocked ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let d = deal.deal
        var parts = ["For \(deal.itemName)", d.accessibilitySummary]
        if blocked {
            parts.insert("Blocked, likely fraud. The agent won't buy this deal", at: 0)
            parts += d.fraudReasons
        } else if let savings = deal.savingsText {
            parts.append(savings)
        }
        if deal.isLocalPickup, let distance = deal.distanceText { parts.append("local pickup, \(distance)") }
        return parts.joined(separator: ". ")
    }
}
