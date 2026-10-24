import SwiftUI
import UIKit

/// Warm, quiet look: cream paper, warm black ink, sage accent, monospace for
/// headings and numbers, thin dividers instead of cards. Every color has a
/// light and a dark value. Opt in per screen with `.mooveScreen()`.
enum Theme {
    // Surfaces
    static let bg = dynamic(0xF3EEE5, 0x1C1814)
    static let surface = dynamic(0xEAE3D7, 0x26211B)
    static let surface2 = dynamic(0xE1D9CB, 0x302921)
    static let line = dynamic(0xDAD1C1, 0x352E26)
    static let lineStrong = dynamic(0xC9BFAE, 0x4A4136)
    // Ink
    static let text = dynamic(0x1E1B16, 0xF1EADD)
    static let muted = dynamic(0x6E665A, 0xA89F8F)
    static let faint = dynamic(0x9C9383, 0x7A7163)
    // Accents
    static let accent = dynamic(0x8B9A7B, 0x9AAA89)
    static let accentStrong = dynamic(0x6E7E5F, 0xB2C1A0)
    static let accentSoft = dynamic(0xDCE0D0, 0x343A2C)
    static let accentInk = dynamic(0xFFFFFF, 0x1C1814)
    static let danger = dynamic(0xB0563D, 0xD27A5E)
    static let dangerSoft = dynamic(0xEFD9CD, 0x3D2A22)
    static let ochre = dynamic(0xB48A3E, 0xCFA45A)
    static let slate = dynamic(0x7B8B99, 0x93A3B1)
    static let stone = dynamic(0x8F8577, 0xA39887)
    // Floor plans
    static let planFloor = dynamic(0xEFE8DC, 0x2A241E)
    static let planWall = dynamic(0x1E1B16, 0xF1EADD)

    static let radiusLarge: CGFloat = 20
    static let radiusMedium: CGFloat = 14
    static let radiusSmall: CGFloat = 10

    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static func dynamicUIColor(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) }
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color { Color(uiColor: dynamicUIColor(light, dark)) }
}

// MARK: Type

extension Font {
    /// Monospace, for headings, labels and numbers.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Small monospace label above a section ("NEW HOME · 6 ROOMS").
    func eyebrow() -> some View {
        font(.mono(11.5)).tracking(0.5).textCase(.uppercase).foregroundStyle(Theme.faint)
    }

    /// Bold monospace title for a block or row.
    func blockTitle() -> some View {
        font(.mono(14.5, weight: .bold)).foregroundStyle(Theme.text)
    }

    /// Monospace secondary line ("4.5 × 4.0 m · 2 doors").
    func monoMeta() -> some View {
        font(.mono(12.5)).foregroundStyle(Theme.muted)
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

    /// A 1 pt rule under the view, like a row in a ledger.
    func ruled(_ edge: VerticalEdge = .bottom) -> some View {
        overlay(alignment: edge == .bottom ? .bottom : .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

// MARK: Components

/// Pill-shaped button: sage fill, ink outline, or bare text.
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
                .font(.mono(compact ? 12.5 : 13.5, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, kind == .text ? 4 : (compact ? 12 : 18))
                .frame(minHeight: compact ? 30 : 40)
                .foregroundStyle(foreground)
                .background {
                    if kind == .primary {
                        Capsule().fill(configuration.isPressed ? Theme.accentStrong : Theme.accent)
                    } else if kind != .text {
                        Capsule().strokeBorder(kind == .danger ? Theme.danger : Theme.text, lineWidth: 1)
                            .background(Capsule().fill(configuration.isPressed ? Theme.surface : .clear))
                    }
                }
                .contentShape(Capsule())
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
            .font(.mono(10.5, weight: .bold))
            .tracking(0.5)
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(tone)
            .overlay(Capsule().strokeBorder(tone.opacity(0.6), lineWidth: 1))
    }
}

/// Horizontal set of mono pill choices with an underline-free selected state.
struct PillPicker<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button(label(option)) { selection = option }
                    .font(.mono(12.5, weight: selected ? .bold : .regular))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .foregroundStyle(selected ? Theme.accentInk : Theme.muted)
                    .background(Capsule().fill(selected ? Theme.text : .clear))
                    .overlay(Capsule().strokeBorder(selected ? .clear : Theme.line, lineWidth: 1))
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
