import SwiftUI
import MooveKit

/// Colors for the cardboard boxes (after the MoveWise prototype's Pack step). Kraft is a warm tan in
/// light mode and a deep kraft in dark mode. Ink and stamp colors pass 4.5:1 on the kraft face in both
/// modes; the label sticker is always cream paper with warm black ink.
enum BoxPalette {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color { Color(uiColor: Theme.dynamicUIColor(light, dark)) }

    static let kraft = Theme.Paper.kraft
    static let kraftFlap = dynamic(0xE5C89F, 0x634E38)
    static let kraftEdge = dynamic(0xB08A5A, 0x3E3022)
    static let kraftSeam = dynamic(0xB38D5B, 0x45362A)
    /// Printed ink on cardboard (arrows, handle slot).
    static let kraftInk = dynamic(0x4A3119, 0xF1E3CC)
    static let stampRed = dynamic(0x7E2F1B, 0xF5B39C)
    static let stampGreen = dynamic(0x3D4B30, 0xC9D7B4)

    // Plastic tote: grey-blue, ink-colored stamps.
    static let toteFace = dynamic(0xA3AFB8, 0x46525B)
    static let toteLid = dynamic(0x8E9BA5, 0x3B464E)
    static let toteEdge = dynamic(0x7A8790, 0x2E363C)
    static let toteInk = dynamic(0x2A3138, 0xE4ECF2)

    /// Clear-ish packing tape that seals the flaps.
    static let sealTape = dynamic(0xEEDFC2, 0x8C7656)
    static let sealTapeEdge = dynamic(0xC9B38A, 0x6F5C42)

    static let paper = dynamic(0xFBF7EF, 0xEDE4D2)
    static let paperInk = Theme.color(0x1E1B16)
    static let paperMuted = Theme.color(0x5E564A)

    /// A stable tape color per destination room, from MooveKit's shared `PackingPalette` (the printed
    /// labels and the 3D truck use the same one). Fixed, not adaptive, and light enough that
    /// `paperInk` on it passes 4.5:1, so the number badges read in both modes.
    static func tape(for room: String) -> Color { Theme.color(PackingPalette.color(forRoom: room)) }

    /// An SF Symbol for what a box mostly holds.
    static func symbol(for box: MovingBox) -> String {
        if box.keepWithYou { return "heart.fill" }
        if box.openFirst { return "moon.stars.fill" }
        switch box.kinds.first ?? "" {
        case "books": return "books.vertical.fill"
        case "decor": return "photo.artframe"
        case "lamps": return "lamp.table.fill"
        case "desk": return "pencil.and.ruler.fill"
        case "electronics": return "headphones"
        case "clothes": return "tshirt.fill"
        case "shoes": return "shoeprints.fill"
        case "bedding": return "bed.double.fill"
        case "kitchen": return "fork.knife"
        case "bathroom": return "shower.fill"
        case "hanging": return "hanger"
        default: return "shippingbox.fill"
        }
    }
}

extension MovingBox {
    /// "04"
    var numberText: String { id < 10 ? "0\(id)" : "\(id)" }
    /// Destination room, or "Any room" when the plan has none.
    var roomName: String { room.isEmpty ? "Any room" : room }
    var tapeColor: Color { BoxPalette.tape(for: room) }
    var symbol: String { BoxPalette.symbol(for: self) }

    /// Stamp texts in priority order.
    var stamps: [BoxStamp] {
        var out: [BoxStamp] = []
        if keepWithYou { out.append(.keepWithYou) }
        if openFirst && !keepWithYou { out.append(.openFirst) }
        if fragile { out.append(.fragile) }
        if thisSideUp { out.append(.thisSideUp) }
        return out
    }
}

enum BoxStamp: String, CaseIterable {
    case keepWithYou = "Keep with you"
    case openFirst = "Open first"
    case fragile = "Fragile"
    case thisSideUp = "This side up"

    var isWarning: Bool { self == .fragile || self == .thisSideUp }
}

// MARK: Card

/// One box in the grid: the drawn cardboard box, then a one-line mono meta under it. Tapping opens
/// its contents.
struct MovingBoxCard: View {
    var box: MovingBox
    /// How many content lines are checked off.
    var packed: Int
    var action: () -> Void

    private var sealed: Bool { !box.contents.isEmpty && packed >= box.contents.count }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                BoxArt(box: box, sealed: sealed)
                HStack(alignment: .center, spacing: 6) {
                    Circle().fill(box.tapeColor).frame(width: 9, height: 9).accessibilityHidden(true)
                    Text(meta)
                        .monoText(11.5, maxScale: 1.6)
                        .foregroundStyle(sealed ? Theme.accentStrong : Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(box.tapeColor.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .top) {
                // A band of the room's color across the top of the card.
                UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.card, topTrailingRadius: Theme.Radius.card, style: .continuous)
                    .fill(box.tapeColor)
                    .frame(height: 5)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(BoxPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens the box's contents")
        .accessibilityAddTraits(.isButton)
    }

    /// One short line, no figures (the box's label already carries its number): sealed, or its size.
    private var meta: String { sealed ? "Sealed" : box.size.label }

    private var accessibilityText: String {
        var parts = ["Box \(box.id)", box.title, box.roomName, box.size.label, "\(Int(box.weightKg.rounded())) kilograms"]
        if !box.reason.isEmpty { parts.append(box.reason) }
        if box.estimatedOnly && !box.openFirst && !box.keepWithYou { parts.append("everyday stuff, an estimate") }
        parts += box.stamps.map(\.rawValue)
        parts.append(sealed ? "sealed" : "\(packed) of \(box.contents.count) packed")
        return parts.joined(separator: ", ")
    }
}

/// Small press-down for the box cards (none with Reduce Motion).
private struct BoxPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: Art

/// The front face of a kraft moving box: flaps with seams on top, a strip of room-colored tape, a
/// paper label ("BOX 04" and the title), outlined stamps, and packing tape plus a "Sealed" stamp
/// once every line is checked. Totes are drawn as grey-blue plastic with a lid.
struct BoxArt: View {
    var box: MovingBox
    var sealed: Bool
    /// The bigger version in the box detail; shows every stamp.
    var large = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTote: Bool { box.size == .tote }
    private var face: Color { isTote ? BoxPalette.toteFace : BoxPalette.kraft }
    private var flap: Color { isTote ? BoxPalette.toteLid : BoxPalette.kraftFlap }
    private var edge: Color { isTote ? BoxPalette.toteEdge : BoxPalette.kraftEdge }
    private var ink: Color { isTote ? BoxPalette.toteInk : BoxPalette.kraftInk }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let flapH = h * (isTote ? 0.18 : 0.24)
            let tapeW = max(10, w * 0.11)
            let tapeX = w * 0.1
            let shape = RoundedRectangle(cornerRadius: isTote ? 10 : 5, style: .continuous)

            ZStack(alignment: .topLeading) {
                shape.fill(face)
                // A wash of the room's color, so boxes for different rooms differ at a glance.
                if !isTote { shape.fill(box.tapeColor.opacity(0.28)) }
                // Flaps (or the tote's lid) and their seams.
                Rectangle().fill(flap).frame(width: w, height: flapH)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: flapH))
                    p.addLine(to: CGPoint(x: w, y: flapH))
                    if !isTote {
                        p.move(to: CGPoint(x: w / 2, y: 0))
                        p.addLine(to: CGPoint(x: w / 2, y: flapH))
                    }
                }
                .stroke(isTote ? BoxPalette.toteEdge : BoxPalette.kraftSeam, lineWidth: 1)
                if isTote {
                    Capsule().fill(ink.opacity(0.55))
                        .frame(width: w * 0.3, height: max(5, h * 0.035))
                        .offset(x: w * 0.35, y: flapH * 0.4)
                }
                // Room tape down the left of the face.
                Rectangle()
                    .fill(box.tapeColor)
                    .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.22)).frame(width: tapeW * 0.3) }
                    .frame(width: tapeW, height: h)
                    .offset(x: tapeX)
                // Paper label.
                label(width: w * 0.58, height: h)
                    .rotationEffect(.degrees(-1.6))
                    .offset(x: w * 0.34, y: flapH + h * 0.07)
                // Packing tape across the top seals the flaps.
                sealTape(width: w, height: max(12, h * 0.1))
                    .offset(y: flapH - max(12, h * 0.1) / 2)
                // "Sealed" stamped over the tape, on a patch of flap so it reads on the tape in both modes.
                sealedStamp(size: large ? 16 : 11.5)
                    .position(x: w * 0.56, y: flapH)
            }
            .overlay(alignment: .topTrailing) {
                sizeGlyph(size: large ? 30 : 22)
                    .padding(.top, flapH * 0.5 - (large ? 15 : 11))
                    .padding(.trailing, large ? 10 : 6)
            }
            .overlay(alignment: .bottomLeading) {
                stampStack(size: large ? 12 : 9.5)
                    .padding(.leading, tapeX + tapeW + (large ? 12 : 7))
                    .padding(.bottom, h * 0.08)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
        }
        .aspectRatio(large ? 1.3 : 1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// "M" in a circle: the box size at a glance.
    private func sizeGlyph(size: CGFloat) -> some View {
        Text(box.size.glyph)
            .font(.mono(size * 0.55, weight: .bold))
            .foregroundStyle(BoxPalette.paperInk)
            .frame(width: size, height: size)
            .background(Circle().fill(BoxPalette.paper))
            .overlay(Circle().strokeBorder(box.tapeColor, lineWidth: 2.5))
    }

    private func label(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(box.numberText)
                    .font(.mono(min(width * 0.3, large ? 40 : 24), weight: .bold))
                    .tracking(-0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: box.symbol)
                    .font(.system(size: large ? 15 : 11, weight: .semibold))
                    .foregroundStyle(BoxPalette.paperMuted)
            }
            Text(box.title)
                .font(.mono(large ? 13 : 10.5, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(box.roomName.uppercased())
                .font(.mono(large ? 10.5 : 8.5, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(BoxPalette.paperMuted)
                .lineLimit(1)
                .padding(.top, 1)
        }
        .foregroundStyle(BoxPalette.paperInk)
        .padding(.horizontal, large ? 10 : 7)
        .padding(.top, large ? 14 : 10)
        .padding(.bottom, large ? 8 : 6)
        .frame(width: width, alignment: .leading)
        .background(BoxPalette.paper)
        .overlay(alignment: .top) { Rectangle().fill(box.tapeColor).frame(height: large ? 8 : 6) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tag, style: .continuous))
        .mooveShadow(.contact)
    }

    private func stampStack(size: CGFloat) -> some View {
        // Small cards show the two most important stamps; the detail shows all of them.
        let shown = large ? box.stamps : Array(box.stamps.prefix(2))
        return VStack(alignment: .leading, spacing: large ? 7 : 5) {
            ForEach(Array(shown.enumerated()), id: \.element) { i, stamp in
                StampMark(
                    text: stamp.rawValue,
                    color: isTote ? BoxPalette.toteInk : (stamp.isWarning ? BoxPalette.stampRed : BoxPalette.stampGreen),
                    size: size,
                    arrows: stamp == .thisSideUp
                )
                .rotationEffect(.degrees(i.isMultiple(of: 2) ? -4 : 2.5))
            }
        }
    }

    private func sealTape(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(BoxPalette.sealTape)
            .overlay(alignment: .top) { Rectangle().fill(BoxPalette.sealTapeEdge).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(BoxPalette.sealTapeEdge).frame(height: 1) }
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.28)).frame(height: height * 0.28).padding(.top, 2) }
            .frame(width: width + 4, height: height)
            .offset(x: -2)
            .scaleEffect(x: sealed || reduceMotion ? 1 : 0.001, y: 1, anchor: .leading)
            .opacity(sealed ? 0.95 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.55), value: sealed)
    }

    private func sealedStamp(size: CGFloat) -> some View {
        Text("SEALED")
            .font(.mono(size, weight: .bold))
            .tracking(size * 0.16)
            .foregroundStyle(isTote ? BoxPalette.toteInk : BoxPalette.stampGreen)
            .padding(.horizontal, size * 0.5)
            .padding(.vertical, size * 0.25)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(isTote ? BoxPalette.toteInk : BoxPalette.stampGreen, lineWidth: 2))
            .padding(2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isTote ? BoxPalette.toteInk : BoxPalette.stampGreen, lineWidth: 1))
            .background(flap, in: RoundedRectangle(cornerRadius: 4))
            .rotationEffect(.degrees(-11))
            .scaleEffect(sealed || reduceMotion ? 1 : 1.5)
            .opacity(sealed ? 1 : 0)
            .animation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.55).delay(sealed ? 0.45 : 0),
                value: sealed
            )
    }
}

/// An outlined, uppercase mono stamp ("FRAGILE"), optionally with "this way up" arrows.
struct StampMark: View {
    var text: String
    var color: Color
    var size: CGFloat = 9.5
    var arrows = false

    var body: some View {
        HStack(spacing: size * 0.35) {
            if arrows {
                HStack(spacing: 0) {
                    Image(systemName: "arrow.up")
                    Image(systemName: "arrow.up")
                }
                .font(.system(size: size * 0.95, weight: .bold))
            }
            Text(text.uppercased())
                .font(.mono(size, weight: .bold))
                .tracking(size * 0.1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(color)
        .padding(.horizontal, size * 0.45)
        .padding(.vertical, size * 0.25)
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1.5))
    }
}

/// The box number on a chip of the box's room tape ("04"), as on the schedule.
struct BoxBadge: View {
    var box: MovingBox
    var sealed = false

    var body: some View {
        Text(box.numberText)
            .monoText(12, weight: .bold, maxScale: 1.5)
            .strikethrough(sealed)
            .foregroundStyle(BoxPalette.paperInk)
            .padding(.horizontal, 7)
            .frame(minWidth: 32, minHeight: 24)
            .background(box.tapeColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
