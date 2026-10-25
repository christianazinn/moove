import SwiftUI
import MooveKit

/// SwiftUI colors for the poster wall. Every hex comes from MooveKit `PosterPalette.current`
/// (`PosterPalette.swift`), so swapping the palette there restyles the whole wall.
enum PosterInk {
    static let palette = PosterPalette.current
    static func color(_ hex: UInt32) -> Color { Theme.color(hex) }
    static var paper: Color { color(palette.paper) }
    static var paperInk: Color { color(palette.paperInk) }
    static var tape: Color { color(palette.tape) }
    static let wall = Color(uiColor: Theme.dynamicUIColor(palette.wallLight, palette.wallDark))
    static let speckle = Color(uiColor: Theme.dynamicUIColor(palette.wallSpeckleLight, palette.wallSpeckleDark))
    static func stamp(_ kind: PosterStamp.Kind) -> Color { color(palette.ink(for: kind)) }
}

/// One listing as a poster pinned to the wall: banner, the item's voxel model (or photo) as the
/// art, a bold title, a giant price, the status as a rubber stamp, and blank tear-off tabs. Drafts are a pencil sketch, a failed post has a torn
/// corner and its reason, a denied one is crossed out.
struct ListingPoster: View {
    let listing: Listing
    let item: Item?
    var problem: String? = nil
    let style: PosterStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var artHeight: CGFloat = 112

    private var stamp: PosterStamp { PosterWall.stamp(for: listing.status, simulated: listing.simulated) }
    /// A sketch is drawn on plain paper, whatever its style.
    private var treatment: PosterTreatment { stamp.isSketch ? .paper : style.treatment }
    private var look: PosterStyle { var s = style; s.treatment = treatment; return s }

    var body: some View {
        let palette = PosterInk.palette
        let ink = PosterInk.color(look.ink(paperInk: palette.paperInk))
        let banner = look.banner(paper: palette.paper, paperInk: palette.paperInk)
        let ax = dynamicTypeSize.isAccessibilitySize
        VStack(spacing: 0) {
            Text(style.headline)
                .monoText(11, weight: .heavy, maxScale: 1.6)
                .tracking(1.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(PosterInk.color(banner.text))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(stamp.isSketch ? Color.clear : PosterInk.color(banner.fill))
                .overlay {
                    if stamp.isSketch {
                        Rectangle().strokeBorder(ink.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .padding([.horizontal, .top], 10)

            art
                .frame(height: ax ? artHeight * 1.4 : artHeight)
                .frame(maxWidth: .infinity)
                .background(PosterInk.color(look.artBackground(paper: palette.paper)).opacity(treatment == .split ? 1 : 0))
                .padding(.horizontal, treatment == .split ? 0 : 10)
                .padding(.top, 8)
                .overlay {
                    if stamp.isBig { BigStamp(stamp: stamp) }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(listing.title)
                    .monoText(13.5, weight: .bold, maxScale: 1.8)
                    // Always two lines tall, so every poster on the wall is the same size (Lisa).
                    .lineLimit(ax ? 8 : 2, reservesSpace: !ax)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(ink)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 6) {
                        price
                        Spacer(minLength: 0)
                        if !stamp.isBig { SmallStamp(stamp: stamp) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        price
                        if !stamp.isBig { SmallStamp(stamp: stamp) }
                    }
                }
                // The reason a post failed is in the VoiceOver label and on the listing's page.
                SimulatedTag().opacity(listing.simulated ? 1 : 0).accessibilityHidden(!listing.simulated)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 10)

            TearOffTabs(ink: ink, count: ax ? 5 : 3)
        }
        .background(sheet)
        .overlay { if stamp.isCrossedOut { CrossOut().stroke(PosterInk.stamp(.denied).opacity(0.75), lineWidth: 3) } }
        .overlay { if stamp.isSketch { Rectangle().strokeBorder(ink.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])) } }
        .clipShape(PosterSheetShape(torn: stamp.isTorn))
        .compositingGroup()
        .shadow(color: .black.opacity(stamp.isSketch ? 0.06 : 0.16), radius: 3, x: 0, y: 2)
        .overlay(alignment: .top) { fastener.offset(y: -7) }
    }

    @ViewBuilder private var sheet: some View {
        let palette = PosterInk.palette
        if stamp.isSketch {
            PosterInk.paper.opacity(0.8)
        } else {
            PosterInk.color(look.sheet(paper: palette.paper))
        }
    }

    private var price: some View {
        Text(listing.formattedPrice)
            .monoText(28, weight: .black, maxScale: 1.6)
            .tracking(-0.6)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(PosterInk.color(look.priceInk(paperInk: PosterInk.palette.paperInk)))
            .amountText()
    }

    @ViewBuilder private var art: some View {
        Group {
            if let item {
                VoxelThumbnail(item, size: artHeight, tile: false)
                    .mooveShadow(.lifted)
            } else {
                Image(systemName: "tag")
                    .font(.system(size: artHeight * 0.36, weight: .light))
                    .foregroundStyle(PosterInk.color(look.ink(paperInk: PosterInk.palette.paperInk)).opacity(0.6))
            }
        }
        .saturation(stamp.isSketch ? 0 : 1)
        .opacity(stamp.isSketch ? 0.5 : 1)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var fastener: some View {
        switch style.fastener {
        case .pin:
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.7), PosterInk.color(style.swatch.accent)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 8))
                .frame(width: 15, height: 15)
                .shadow(color: .black.opacity(0.35), radius: 1.5, x: 1, y: 2)
        case .tape:
            Rectangle()
                .fill(PosterInk.tape.opacity(0.82))
                .frame(width: 58, height: 17)
                .overlay(Rectangle().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
                .rotationEffect(.degrees(style.tiltDegrees > 0 ? -5 : 5))
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        }
    }
}

/// SOLD, across the art.
private struct BigStamp: View {
    let stamp: PosterStamp

    var body: some View {
        let ink = PosterInk.stamp(stamp.kind)
        Text(stamp.text)
            .monoText(30, weight: .black, maxScale: 1.4)
            .tracking(5)
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(PosterInk.paper.opacity(0.9))
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 3).padding(-4))
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 1).padding(1))
            .rotationEffect(.degrees(stamp.angleDegrees))
            .opacity(0.92)
    }
}

/// A small status stamp next to the price ("NEEDS YOUR OK", "POSTED").
private struct SmallStamp: View {
    let stamp: PosterStamp

    var body: some View {
        let ink = PosterInk.stamp(stamp.kind)
        Text(stamp.text)
            .monoText(9.5, weight: .heavy, maxScale: 1.6)
            .tracking(0.8)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(PosterInk.paper.opacity(0.92))
            .overlay(Rectangle().strokeBorder(ink, style: StrokeStyle(lineWidth: 1.5, dash: stamp.isSketch ? [3, 2] : [])))
            .rotationEffect(.degrees(stamp.angleDegrees))
    }
}

/// The strip of blank tear-off tabs at the bottom of a poster.
private struct TearOffTabs: View {
    let ink: Color
    var count = 3
    @ScaledMetric(relativeTo: .caption2) private var tabHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            Line().stroke(ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(height: 1)
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { i in
                    if i > 0 {
                        VLine().stroke(ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 1)
                    }
                    // Blank tabs (Lisa: no "eBay · simulated" text on them); the poster's own
                    // SIMULATED tag still labels simulated listings.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: tabHeight)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

private struct VLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
    }
}

/// Two strokes corner to corner, for a denied poster.
private struct CrossOut: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 14, dy: 14)
        return Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
    }
}

/// The poster sheet: a rectangle, or one with its top-right corner torn off in a jagged line.
struct PosterSheetShape: Shape {
    var torn = false

    func path(in rect: CGRect) -> Path {
        guard torn else { return Path(rect) }
        let tear: CGFloat = min(46, rect.width * 0.3)
        let jags: [(CGFloat, CGFloat)] = [(0, 0), (0.18, 0.12), (0.3, 0.34), (0.5, 0.42), (0.62, 0.66), (0.82, 0.74), (1, 1)]
        return Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - tear, y: rect.minY))
            for (t, s) in jags.dropFirst() {
                // Along the diagonal from (maxX - tear, minY) to (maxX, minY + tear), wobbling either side.
                let x = rect.maxX - tear + tear * t
                let y = rect.minY + tear * s
                p.addLine(to: CGPoint(x: x, y: y))
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// The wall: painted plaster with a faint speckle, a little darker at the top like it's lit from below a shelf.
struct PosterWallBackground: View {
    var body: some View {
        ZStack {
            PosterInk.wall
            Canvas { ctx, size in
                // A fixed speckle pattern (no randomness, so it doesn't shimmer between redraws).
                var x: CGFloat = 7
                var row = 0
                var y: CGFloat = 5
                while y < size.height {
                    while x < size.width {
                        let d: CGFloat = (row + Int(x)) % 3 == 0 ? 2 : 1.4
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)), with: .color(PosterInk.speckle))
                        x += 23 + CGFloat((row * 7 + Int(x)) % 11)
                    }
                    row += 1
                    y += 19
                    x = CGFloat((row * 13) % 23)
                }
            }
            LinearGradient(colors: [.black.opacity(0.05), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Lifts a poster off the wall while it's pressed: it straightens, grows a little and casts a
/// longer shadow. Without Reduce Motion it springs back.
struct PosterPressStyle: ButtonStyle {
    let tilt: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .rotationEffect(.degrees(pressed && !reduceMotion ? 0 : tilt))
            .scaleEffect(pressed && !reduceMotion ? 1.035 : 1)
            .shadow(color: .black.opacity(pressed ? 0.18 : 0), radius: pressed ? 14 : 0, y: pressed ? 10 : 0)
            .zIndex(pressed ? 1 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: pressed)
    }
}

/// Posters arrive like they're being pinned up: dropped in from slightly above, a bit bigger and
/// more tilted, then settled. With Reduce Motion they're simply there.
struct PinIn: ViewModifier {
    let pinned: Bool
    let tilt: Double

    func body(content: Content) -> some View {
        content
            .opacity(pinned ? 1 : 0)
            .scaleEffect(pinned ? 1 : 1.06)
            .offset(y: pinned ? 0 : -16)
            .rotationEffect(.degrees(pinned ? 0 : tilt * 2.5))
    }
}

/// The flyer at the top of the wall: one total (Sold, else Listed) on cream paper with tape at the corners.
struct FlyerTotals: View {
    let totals: PosterWall.Totals
    var tilt: Double = -0.6
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let ax = dynamicTypeSize.isAccessibilitySize
        // One key total: what sold, or what's listed before anything sells (the live count is on the posters).
        let figures: [(label: String, value: String, spoken: String, kind: PosterStamp.Kind?)] = totals.soldCents > 0
            ? [("SOLD", CentsFormat.usd(totals.soldCents), "Sold, \(CentsFormat.usd(totals.soldCents)). Listed, \(CentsFormat.usd(totals.listedCents)). \(totals.liveCount) posted", nil)]
            : [("LISTED", CentsFormat.usd(totals.listedCents), "Listed, \(CentsFormat.usd(totals.listedCents)). \(totals.liveCount) posted", nil)]
        VStack(alignment: .leading, spacing: 0) {
            let layout = ax ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            layout {
                ForEach(figures.indices, id: \.self) { i in
                    let f = figures[i]
                    if i > 0 && !ax {
                        VLine().stroke(PosterInk.paperInk.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.label)
                            .monoText(10.5, weight: .bold, maxScale: 1.6)
                            .tracking(1.2)
                            .foregroundStyle(PosterInk.paperInk.opacity(0.65))
                        Text(f.value)
                            .monoText(24, weight: .black, maxScale: 1.6)
                            .tracking(-0.5)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(f.kind.map(PosterInk.stamp) ?? PosterInk.paperInk)
                            .amountText()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ax ? 0 : 12)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(f.spoken)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, ax ? 16 : 4)
            .padding(.vertical, 12)
        }
        .background(PosterInk.paper)
        .compositingGroup()
        .mooveShadow(.paper)
        .overlay(alignment: .topLeading) { tape(-32).offset(x: -10, y: -6) }
        .overlay(alignment: .topTrailing) { tape(32).offset(x: 10, y: -6) }
        .rotationEffect(.degrees(ax ? 0 : tilt))
    }

    private func tape(_ angle: Double) -> some View {
        Rectangle().fill(PosterInk.tape.opacity(0.82)).frame(width: 44, height: 15).rotationEffect(.degrees(angle))
            .accessibilityHidden(true)
    }
}

/// The top of a listing's page: its poster's banner, colors and stamp around a big model, so
/// opening a poster feels like holding it up close.
struct ListingPosterHero: View {
    let listing: Listing
    let item: Item?
    let style: PosterStyle
    @ScaledMetric(relativeTo: .body) private var artSize: CGFloat = 230

    var body: some View {
        let palette = PosterInk.palette
        let stamp = PosterWall.stamp(for: listing.status, simulated: listing.simulated)
        let banner = style.banner(paper: palette.paper, paperInk: palette.paperInk)
        VStack(spacing: 0) {
            Text(style.headline)
                .monoText(13, weight: .heavy, maxScale: 1.6)
                .tracking(2.4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(PosterInk.color(banner.text))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(PosterInk.color(banner.fill))
                .padding([.horizontal, .top], 14)
            ZStack {
                if let item {
                    VoxelThumbnail(item, size: min(artSize, 300), tile: false)
                        .mooveShadow(.lifted)
                        .saturation(stamp.isSketch ? 0 : 1)
                        .opacity(stamp.isSketch ? 0.55 : 1)
                } else {
                    Image(systemName: "tag").font(.system(size: 64, weight: .light))
                        .foregroundStyle(PosterInk.color(style.ink(paperInk: palette.paperInk)).opacity(0.6))
                }
                if stamp.isBig { BigStamp(stamp: stamp).scaleEffect(1.3) }
            }
            .frame(height: min(artSize, 300) + 10)
            .frame(maxWidth: .infinity)
            .background(PosterInk.color(style.artBackground(paper: palette.paper)).opacity(style.treatment == .split ? 1 : 0))
            .padding(.top, style.treatment == .split ? 14 : 0)
            .overlay(alignment: .bottomTrailing) {
                if !stamp.isBig { SmallStamp(stamp: stamp).scaleEffect(1.25).padding(18) }
            }
        }
        .padding(.bottom, 8)
        .background(PosterInk.color(style.sheet(paper: palette.paper)))
        .overlay { if stamp.isCrossedOut { CrossOut().stroke(PosterInk.stamp(.denied).opacity(0.6), lineWidth: 3) } }
        .clipShape(PosterSheetShape(torn: stamp.isTorn))
        .compositingGroup()
        .mooveShadow(.paper)
        .overlay(alignment: .top) {
            Rectangle().fill(PosterInk.tape.opacity(0.82)).frame(width: 70, height: 20).rotationEffect(.degrees(-3)).offset(y: -9)
        }
        .accessibilityHidden(true)
    }
}
