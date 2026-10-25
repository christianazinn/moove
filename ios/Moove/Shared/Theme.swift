import SwiftUI
import UIKit

/// Quiet coastal look: cream paper, deep harbor ink, slate and sage accents (Lisa's palette:
/// #121F26 · #4F7889 · #7FA8A3 · #D1D6C8 · #F4F0D7), one sans family (SF Pro) with tabular
/// figures, thin rules instead of cards. Every color has a light and a dark value. Opt in per
/// screen with `.mooveScreen()`.
///
/// Text colors are picked for at least 4.5:1 contrast on `bg` and `surface`
/// in both modes. `faint` and `accent` are for rules, dots and fills only.
enum Theme {
    // Surfaces
    static let bg = dynamic(0xF4F0D7, 0x121F26)
    static let surface = dynamic(0xE9E8D2, 0x1A2A32)
    static let surface2 = dynamic(0xDDE0CF, 0x22343D)
    static let line = dynamic(0xD1D6C8, 0x2A3D46)
    static let lineStrong = dynamic(0xB4BEB4, 0x3B525C)
    // Ink
    static let text = dynamic(0x121F26, 0xF4F0D7)
    static let muted = dynamic(0x45626E, 0xA9B8B4)
    /// Decorative only (chevrons, separators in meta lines); too light for body text.
    static let faint = dynamic(0x8FA3A3, 0x5F7A80)
    // Accents
    /// Sage for dots, bars and swatches.
    static let accent = dynamic(0x7FA8A3, 0x7FA8A3)
    /// Slate that reads as text on `bg` / `surface`.
    static let accentStrong = dynamic(0x3E6474, 0x9CC4BE)
    static let accentSoft = dynamic(0xDCE4D8, 0x1F3A3E)
    /// Fill for primary buttons; `accentInk` on top passes 4.5:1 in both modes.
    static let accentFill = dynamic(0x46707F, 0x7FA8A3)
    static let accentFillPressed = dynamic(0x3B6170, 0x6F9893)
    static let accentInk = dynamic(0xF4F0D7, 0x121F26)
    static let danger = dynamic(0xA24D35, 0xD27A5E)
    static let dangerSoft = dynamic(0xEFDCCD, 0x3A2A26)
    /// Ochre for swatches; use `ochreInk` for ochre text.
    static let ochre = dynamic(0xB48A3E, 0xCFA45A)
    static let ochreInk = dynamic(0x7E5C1C, 0xCFA45A)
    static let slate = dynamic(0x4F7889, 0x8FB0BF)
    static let stone = dynamic(0x8C9690, 0xA0AAA4)
    // Floor plans
    static let planFloor = dynamic(0xEEEBD4, 0x1A2A32)
    static let planWall = dynamic(0x121F26, 0xF4F0D7)

    static let radiusLarge: CGFloat = 20
    static let radiusMedium: CGFloat = 14
    static let radiusSmall: CGFloat = 10

    /// Side margin for every screen.
    static let gutter: CGFloat = 20

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func dynamicUIColor(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) }
    }

    /// A fixed (non-adaptive) color from 0xRRGGBB.
    static func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color { Color(uiColor: dynamicUIColor(light, dark)) }
}

// MARK: Type

extension Font {
    /// The app's label face (SF Pro with tabular figures; it was monospace before the 2026-10-25 restyle).
    /// Fixed size; prefer `.monoText(...)`, which follows Dynamic Type.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: Font.Weight.softened(weight)).monospacedDigit()
    }
}

extension Font.Weight {
    /// Bold reads heavy in SF Pro at label sizes; the restyle sets it a step lighter.
    static func softened(_ weight: Font.Weight) -> Font.Weight { weight == .black ? .bold : (weight == .bold || weight == .heavy ? .semibold : weight) }
}

extension DynamicTypeSize {
    /// How much to scale a size designed at the default (`.large`) setting.
    var textScale: CGFloat {
        switch self {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.1
        case .xxLarge: 1.2
        case .xxxLarge: 1.3
        case .accessibility1: 1.55
        case .accessibility2: 1.8
        case .accessibility3: 2.1
        case .accessibility4: 2.4
        case .accessibility5: 2.7
        @unknown default: 1
        }
    }
}

/// A fixed design size that scales with the reader's Dynamic Type setting.
private struct ScaledFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight
    var monospaced: Bool
    /// Upper bound on the scale, for display sizes that would otherwise swamp the screen.
    var maxScale: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let s = size * min(dynamicTypeSize.textScale, maxScale)
        // One family: "mono" text is SF Pro with tabular figures, so numbers still line up.
        let font = Font.system(size: s, weight: monospaced ? Font.Weight.softened(weight) : weight)
        content.font(monospaced ? font.monospacedDigit() : font)
    }
}

extension View {
    /// The label face (SF Pro, tabular figures) at a design size, scaled for Dynamic Type.
    func monoText(_ size: CGFloat, weight: Font.Weight = .regular, maxScale: CGFloat = 2.2) -> some View {
        modifier(ScaledFont(size: size, weight: weight, monospaced: true, maxScale: maxScale))
    }

    /// Sans (system) at a design size, scaled for Dynamic Type.
    func sansText(_ size: CGFloat, weight: Font.Weight = .regular, maxScale: CGFloat = 2.2) -> some View {
        modifier(ScaledFont(size: size, weight: weight, monospaced: false, maxScale: maxScale))
    }

    /// Small monospace label above a heading or section ("06 — New home").
    func eyebrow() -> some View {
        monoText(12, weight: .medium).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.muted)
    }

    /// Large monospace page heading ("Your current room").
    func pageTitle() -> some View {
        sansText(30, weight: .semibold, maxScale: 1.6).tracking(-0.6).foregroundStyle(Theme.text)
    }

    /// Short sans paragraph under a page heading.
    func lede() -> some View {
        sansText(15.5).foregroundStyle(Theme.muted).lineSpacing(4)
    }

    /// Bold monospace section heading ("Pieces").
    func listHeading() -> some View {
        sansText(17, weight: .semibold).tracking(-0.2).foregroundStyle(Theme.text)
    }

    /// Bold monospace title for a block or row.
    func blockTitle() -> some View {
        sansText(16, weight: .medium).foregroundStyle(Theme.text).lineSpacing(2)
    }

    /// Monospace secondary line ("4.5 × 4.0 m · 2 doors").
    func monoMeta() -> some View {
        monoText(13.5).foregroundStyle(Theme.muted).lineSpacing(2)
    }

    /// Right-aligned monospace figure in a row ("$80–$140").
    func rowValue() -> some View {
        monoText(15, weight: .medium).foregroundStyle(Theme.text).lineLimit(1)
    }

    /// Cream background, slate tint, harbor ink. Lists and forms drop their gray background.
    func mooveScreen() -> some View {
        self
            .foregroundStyle(Theme.text)
            .tint(Theme.accentStrong)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbarBackground(Theme.bg, for: .navigationBar)
    }

    /// A 1 pt rule under (or over) the view, like a row in a ledger.
    func ruled(_ edge: VerticalEdge = .bottom) -> some View {
        overlay(alignment: edge == .bottom ? .bottom : .top) { Rectangle().fill(Theme.line).frame(height: 0.75) }
    }
}

// MARK: Components

/// Eyebrow, big mono heading, and an optional sans paragraph, like the top of each prototype panel.
/// A screen's big title and optional one-line instruction. No "02 — Inventory" eyebrow: the
/// navigation bar already names the screen (Rio: "unnecessary text").
struct PageHeader: View {
    var title: String
    var lede: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .pageTitle()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let lede {
                Text(lede)
                    .lede()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// Section heading with an optional count and trailing accessory, over a rule.
struct ListHeader<Trailing: View>: View {
    var title: String
    var count: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).listHeading().accessibilityAddTraits(.isHeader)
            if let count { Text(count).monoText(13.5).foregroundStyle(Theme.muted) }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
    }
}

extension ListHeader where Trailing == EmptyView {
    init(title: String, count: String? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

/// One inventory-style row: thumbnail, bold mono title, mono meta, a right-aligned value and an
/// optional chevron, over a thin rule.
struct LedgerRow<Leading: View, Trailing: View>: View {
    var title: String
    var meta: String?
    var value: String?
    var valueTint: Color = Theme.text
    var chevron = false
    /// Optional short chip under the meta line (Inventory's item origin, #267).
    var tag: String? = nil
    var tagAccessibilityLabel: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            leading
            VStack(alignment: .leading, spacing: 4) {
                Text(title).blockTitle().fixedSize(horizontal: false, vertical: true)
                if let meta { Text(meta).monoMeta().fixedSize(horizontal: false, vertical: true) }
                if let tag {
                    MonoTag(text: tag)
                        .accessibilityLabel(tagAccessibilityLabel ?? tag)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                trailing
                if let value { Text(value).rowValue().foregroundStyle(valueTint) }
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.faint)
                        .accessibilityHidden(true)
                }
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 16)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .ruled()
    }
}

extension LedgerRow where Trailing == EmptyView {
    init(title: String, meta: String? = nil, value: String? = nil, valueTint: Color = Theme.text, chevron: Bool = false,
         tag: String? = nil, tagAccessibilityLabel: String? = nil, @ViewBuilder leading: () -> Leading) {
        self.init(title: title, meta: meta, value: value, valueTint: valueTint, chevron: chevron, tag: tag,
                  tagAccessibilityLabel: tagAccessibilityLabel, leading: leading) { EmptyView() }
    }
}

/// A 56 pt rounded tile with an SF Symbol, the same size as a voxel thumbnail.
struct IconTile: View {
    var systemName: String
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.32, weight: .light))
            .foregroundStyle(Theme.muted)
            .frame(width: size, height: size)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A label and a large mono figure, as in the prototype's stat strip.
struct StatFigure: View {
    var label: String
    var value: String
    var tint: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).monoText(13.5).foregroundStyle(Theme.muted)
            Text(value)
                .monoText(24, weight: .bold, maxScale: 1.6)
                .tracking(-0.2)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Pill-shaped button: sage fill, ink outline, or bare text. Always at least 44 pt tall to tap.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, outline, text, danger }
    var kind: Kind = .primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(kind: kind, compact: compact, configuration: configuration)
    }

    private struct PillBody: View {
        let kind: Kind
        let compact: Bool
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .monoText(compact ? 13 : 14, weight: .bold, maxScale: 1.5)
                .lineLimit(1)
                .padding(.horizontal, kind == .text ? 4 : (compact ? 16 : 22))
                .frame(minHeight: compact ? 36 : 44)
                .foregroundStyle(foreground)
                .background {
                    switch kind {
                    case .primary:
                        Capsule().fill(configuration.isPressed ? Theme.accentFillPressed : Theme.accentFill)
                    case .outline, .danger:
                        Capsule()
                            .fill(configuration.isPressed ? Theme.surface : .clear)
                            .overlay(Capsule().strokeBorder(kind == .danger ? Theme.danger : Theme.text, lineWidth: 1))
                    case .text:
                        EmptyView()
                    }
                }
                .padding(.vertical, compact ? 4 : 0)
                .contentShape(Rectangle())
                .opacity(isEnabled ? 1 : 0.4)
        }

        private var foreground: Color {
            switch kind {
            case .primary: Theme.accentInk
            case .outline: Theme.text
            case .text: configuration.isPressed ? Theme.text : Theme.muted
            case .danger: Theme.danger
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ kind: PillButtonStyle.Kind, compact: Bool = false) -> PillButtonStyle { PillButtonStyle(kind: kind, compact: compact) }
}

/// A small monospace tag, e.g. "SIMULATED" or "DEMO HOUSE".
struct MonoTag: View {
    var text: String
    var tone: Color = Theme.muted

    var body: some View {
        Text(text)
            .monoText(10.5, weight: .semibold, maxScale: 1.6)
            .tracking(0.7)
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tone)
            .background(Capsule().fill(tone.opacity(0.10)))
    }
}

/// Segmented set of mono choices on a quiet track; the selected one sits raised on the page color.
struct PillPicker<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button(label(option)) { selection = option }
                    .monoText(13, weight: selected ? .bold : .regular, maxScale: 1.5)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .foregroundStyle(selected ? Theme.text : Theme.muted)
                    .background {
                        if selected {
                            Capsule().fill(Theme.bg).overlay(Capsule().strokeBorder(Theme.lineStrong, lineWidth: 1))
                        }
                    }
                    .contentShape(Capsule())
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface))
    }
}

/// Compact selectable capsule (room focus and similar).
struct ChoiceChip: View {
    var title: String
    var meta: String?
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).monoText(13, weight: selected ? .bold : .regular, maxScale: 1.5)
                if let meta {
                    Text(meta).monoText(12, maxScale: 1.5)
                        .foregroundStyle(selected ? Theme.accentInk.opacity(0.85) : Theme.muted)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(selected ? Theme.accentInk : Theme.text)
            .background(Capsule().fill(selected ? Theme.accentFill : Theme.surface))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Shared tokens (#335)
//
// One visual language across the redesigned screens: each keeps its metaphor (museum, deck, storefront,
// receipts, posters, boxes), but corners, shadows, paper, spacing and display titles come from here.

extension Theme {
    /// Corner radii. Paper things (labels, stamps, tape, photo mats) are nearly square; cards round more.
    enum Radius {
        /// Labels, stamps, tape, photo mats.
        static let tag: CGFloat = 4
        /// Chips, small tiles, price tags.
        static let chip: CGFloat = Theme.radiusSmall
        /// Cards and tiles.
        static let card: CGFloat = Theme.radiusMedium
        /// Large panels, banners, sheets.
        static let panel: CGFloat = Theme.radiusLarge
        /// The one hero card on a screen (Review's deck).
        static let hero: CGFloat = 28
    }

    /// Spacing scale. `gutter` (20) stays the side margin.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        /// Above a section header.
        static let section: CGFloat = 40
        /// Between a screen's top edge and its first block.
        static let screenTop: CGFloat = 16
    }

    /// Three shadow levels, for things lying on the page.
    enum Shadow {
        /// Paper flat on paper (a box label on kraft, a sticky note).
        case contact
        /// A sheet resting on the page (receipts, photo mats, box labels).
        case paper
        /// Something lifted off the page (cards, voxel models on a plinth).
        case lifted

        var opacity: Double { self == .lifted ? 0.07 : 0.08 }
        var radius: CGFloat {
            switch self {
            case .contact: return 1.5
            case .paper: return 4
            case .lifted: return 8
            }
        }
        var y: CGFloat {
            switch self {
            case .contact: return 1
            case .paper: return 2
            case .lifted: return 4
            }
        }
    }

    /// Printed-paper materials shared by the paper metaphors (box labels, receipts, sticky notes, posters).
    /// Text colors are at least 4.5:1 on `cream`.
    enum Paper {
        /// Cream paper a shade lighter than the page (deep slate in dark mode).
        static let cream = Color(uiColor: Theme.dynamicUIColor(0xFAF7E6, 0x1C2C34))
        /// Printed ink and its quieter line, on `cream`.
        static let ink = Color(uiColor: Theme.dynamicUIColor(0x121F26, 0xF4F0D7))
        static let inkMuted = Color(uiColor: Theme.dynamicUIColor(0x45626E, 0xAEB9B3))
        /// Rules, leaders and dashes printed on paper (decorative).
        static let rule = Color(uiColor: Theme.dynamicUIColor(0xB4BEB4, 0x3B525C))
        /// Cardboard.
        static let kraft = Color(uiColor: Theme.dynamicUIColor(0xDDBC8E, 0x5A4632))
        /// Paper tape.
        static let tape = Color(uiColor: Theme.dynamicUIColor(0xE6E2C6, 0x34474C))
    }
}

extension View {
    /// One of the theme's three shadow levels.
    func mooveShadow(_ level: Theme.Shadow) -> some View {
        shadow(color: Theme.color(0x121F26).opacity(level.opacity), radius: level.radius, y: level.y)
    }

    /// Display face for section and display titles (SF Pro, tight tracking; it was a serif before the restyle) (Inventory's halls, Shopping's categories),
    /// scaled for Dynamic Type up to 2×.
    func displayTitle(_ size: CGFloat = 24, weight: Font.Weight = .semibold) -> some View {
        serifType(size, weight: weight).foregroundStyle(Theme.text)
    }

    /// The same serif face without a color, for display figures (Review's counts) and placards.
    func serifType(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> some View {
        modifier(DisplaySerif(size: size, weight: weight, italic: italic))
    }
}

/// Serif at a design size, scaled for Dynamic Type up to 2×.
private struct DisplaySerif: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight
    var italic: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let font = Font.system(size: size * min(dynamicTypeSize.textScale, 2), weight: weight == .bold ? .semibold : weight)
        content.font(italic ? font.italic() : font).tracking(-0.3 * size / 24)
    }
}

/// A screen or section with nothing to show yet: a bold title and an optional next step (what to
/// do is spoken, not shown). Every screen's empty state uses it.
struct EmptyState<Action: View>: View {
    var title: String
    var detail: String
    /// `.combine` reads it as one line; `.contain` keeps an action button separately reachable.
    var children: AccessibilityChildBehavior = .combine
    /// Off right under a `ListHeader`, which already draws the top rule.
    var ruledTop = true
    @ViewBuilder var action: Action

    var body: some View {
        // Title only on screen (Lisa: "less overstimulating"); `detail` is the VoiceOver hint.
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).blockTitle().accessibilityHint(detail)
            action.padding(.top, Theme.Space.m)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: children)
    }
}

extension EmptyState where Action == EmptyView {
    init(title: String, detail: String, children: AccessibilityChildBehavior = .combine, ruledTop: Bool = true) {
        self.init(title: title, detail: detail, children: children, ruledTop: ruledTop) { EmptyView() }
    }
}

/// A quiet spinner with a mono line ("Planning…"), for anything still loading.
struct LoadingLine: View {
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.muted)
            Text(text).monoMeta()
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Show all N" / "Show fewer" under a list cut to its first few rows. `id` names it (`<id>.showAll`).
struct ShowAllButton: View {
    var count: Int
    @Binding var expanded: Bool
    var id: String

    /// Cut only when that hides at least two rows (hiding one row saves nothing).
    static func cuts(_ count: Int, limit: Int) -> Bool { count > limit + 1 }

    var body: some View {
        Button(expanded ? "Show fewer" : "Show all \(count)") {
            withAnimation(.default) { expanded.toggle() }
        }
        .buttonStyle(.pill(.text, compact: true))
        .padding(.top, Theme.Space.xs)
        .accessibilityIdentifier("\(id).showAll")
    }
}

/// A long list cut to its first few rows, with "Show all N" under it. Nothing is removed: every
/// row is one tap away.
struct CollapsedList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    var data: Data
    var limit = 5
    var id: String
    var row: (Data.Element) -> Row
    @State private var expanded = false

    init(data: Data, limit: Int = 5, id: String, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.limit = limit
        self.id = id
        self.row = row
    }

    var body: some View {
        let cuts = ShowAllButton.cuts(data.count, limit: limit)
        ForEach(expanded || !cuts ? Array(data) : Array(data.prefix(limit))) { row($0) }
        if cuts { ShowAllButton(count: data.count, expanded: $expanded, id: id) }
    }
}
