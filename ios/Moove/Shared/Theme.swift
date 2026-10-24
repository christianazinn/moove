import SwiftUI
import UIKit

/// Warm, quiet look (after the MoveWise prototype): cream paper, warm black
/// ink, sage accent, monospace for headings and numbers, thin rules instead
/// of cards. Every color has a light and a dark value. Opt in per screen
/// with `.mooveScreen()`.
///
/// Text colors are picked for at least 4.5:1 contrast on `bg` and `surface`
/// in both modes. `faint` and `accent` are for rules, dots and fills only.
enum Theme {
    // Surfaces
    static let bg = dynamic(0xF3EEE5, 0x1C1814)
    static let surface = dynamic(0xEAE3D7, 0x26211B)
    static let surface2 = dynamic(0xE1D9CB, 0x302921)
    static let line = dynamic(0xDAD1C1, 0x352E26)
    static let lineStrong = dynamic(0xC9BFAE, 0x4A4136)
    // Ink
    static let text = dynamic(0x1E1B16, 0xF1EADD)
    static let muted = dynamic(0x665E52, 0xA89F8F)
    /// Decorative only (chevrons, separators in meta lines); too light for body text.
    static let faint = dynamic(0x9C9383, 0x7A7163)
    // Accents
    /// Sage for dots, bars and swatches.
    static let accent = dynamic(0x8B9A7B, 0x9AAA89)
    /// Sage that reads as text on `bg` / `surface`.
    static let accentStrong = dynamic(0x5E6D50, 0xB2C1A0)
    static let accentSoft = dynamic(0xDCE0D0, 0x343A2C)
    /// Fill for primary buttons; `accentInk` on top passes 4.5:1 in both modes.
    static let accentFill = dynamic(0x5E6D50, 0x9AAA89)
    static let accentFillPressed = dynamic(0x4F5D43, 0x8A9A79)
    static let accentInk = dynamic(0xFFFFFF, 0x1C1814)
    static let danger = dynamic(0xA24D35, 0xD27A5E)
    static let dangerSoft = dynamic(0xEFD9CD, 0x3D2A22)
    /// Ochre for swatches; use `ochreInk` for ochre text.
    static let ochre = dynamic(0xB48A3E, 0xCFA45A)
    static let ochreInk = dynamic(0x86621F, 0xCFA45A)
    static let slate = dynamic(0x7B8B99, 0x93A3B1)
    static let stone = dynamic(0x8F8577, 0xA39887)
    // Floor plans
    static let planFloor = dynamic(0xEFE8DC, 0x2A241E)
    static let planWall = dynamic(0x1E1B16, 0xF1EADD)

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
    /// Monospace, for headings, labels and numbers. Fixed size; prefer `.monoText(...)`, which follows Dynamic Type.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
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
        content.font(.system(size: s, weight: weight, design: monospaced ? .monospaced : .default))
    }
}

extension View {
    /// Monospace at a design size, scaled for Dynamic Type.
    func monoText(_ size: CGFloat, weight: Font.Weight = .regular, maxScale: CGFloat = 2.2) -> some View {
        modifier(ScaledFont(size: size, weight: weight, monospaced: true, maxScale: maxScale))
    }

    /// Sans (system) at a design size, scaled for Dynamic Type.
    func sansText(_ size: CGFloat, weight: Font.Weight = .regular, maxScale: CGFloat = 2.2) -> some View {
        modifier(ScaledFont(size: size, weight: weight, monospaced: false, maxScale: maxScale))
    }

    /// Small monospace label above a heading or section ("06 — New home").
    func eyebrow() -> some View {
        monoText(13).tracking(0.4).foregroundStyle(Theme.muted)
    }

    /// Large monospace page heading ("Your current room").
    func pageTitle() -> some View {
        monoText(28, weight: .bold, maxScale: 1.6).tracking(-0.3).foregroundStyle(Theme.text)
    }

    /// Short sans paragraph under a page heading.
    func lede() -> some View {
        sansText(15.5).foregroundStyle(Theme.muted).lineSpacing(4)
    }

    /// Bold monospace section heading ("Pieces").
    func listHeading() -> some View {
        monoText(16, weight: .bold).foregroundStyle(Theme.text)
    }

    /// Bold monospace title for a block or row.
    func blockTitle() -> some View {
        monoText(15.5, weight: .bold).foregroundStyle(Theme.text).lineSpacing(2)
    }

    /// Monospace secondary line ("4.5 × 4.0 m · 2 doors").
    func monoMeta() -> some View {
        monoText(13.5).foregroundStyle(Theme.muted).lineSpacing(2.5)
    }

    /// Right-aligned monospace figure in a row ("$80–$140").
    func rowValue() -> some View {
        monoText(14).foregroundStyle(Theme.text).lineLimit(1)
    }

    /// Cream background, sage tint, warm ink. Lists and forms drop their gray background.
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
        overlay(alignment: edge == .bottom ? .bottom : .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: Components

/// Eyebrow, big mono heading, and an optional sans paragraph, like the top of each prototype panel.
struct PageHeader: View {
    var eyebrow: String
    var title: String
    var lede: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow).eyebrow().padding(.bottom, 12)
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
            .monoText(11, weight: .bold, maxScale: 1.6)
            .tracking(0.5)
            .textCase(.uppercase)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(tone)
            .overlay(Capsule().strokeBorder(tone.opacity(0.55), lineWidth: 1))
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
