import SwiftUI
import UIKit
import MooveKit

// Paper-receipt pieces for the Spending screen: Courier type, cream paper with torn zig-zag
// edges, dashed rules, dotted leaders and a decorative barcode. Grouping and wording live in
// MooveKit `SpendingReceipts`; this file only draws.

/// Receipt paper and ink. Light: cream paper a shade lighter than the page. Dark: a warm gray
/// a shade lighter than the page. Text colors are at least 4.5:1 on `paper` in both modes.
enum ReceiptPalette {
    static let paper = Theme.Paper.cream
    static let ink = Theme.Paper.ink
    static let muted = Theme.Paper.inkMuted
    /// Rules, leaders and the barcode (decorative).
    static let rule = Theme.Paper.rule
}

// MARK: Type

/// Courier New at a design size, scaled for Dynamic Type like the app's `monoText`. Falls back to
/// Courier, then to the system monospaced font.
private struct CourierText: ViewModifier {
    var size: CGFloat
    var bold: Bool
    var maxScale: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        content.font(Self.font(size * min(dynamicTypeSize.textScale, maxScale), bold: bold))
    }

    static func font(_ size: CGFloat, bold: Bool) -> Font {
        let names = bold ? ["CourierNewPS-BoldMT", "Courier-Bold"] : ["CourierNewPSMT", "Courier"]
        if let name = names.first(where: { UIFont(name: $0, size: size) != nil }) {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
    }
}

extension View {
    /// Receipt type: Courier at a design size, following Dynamic Type.
    func courier(_ size: CGFloat, bold: Bool = false, maxScale: CGFloat = 2.2) -> some View {
        modifier(CourierText(size: size, bold: bold, maxScale: maxScale))
    }
}

// MARK: Paper

/// A strip of paper torn along the top and bottom in small zig-zag teeth.
struct ReceiptPaper: Shape {
    var tooth: CGFloat = 9
    var depth: CGFloat = 5

    func path(in r: CGRect) -> Path {
        var p = Path()
        let n = max(1, Int((r.width / tooth).rounded()))
        let w = r.width / CGFloat(n)
        p.move(to: CGPoint(x: r.minX, y: r.minY + depth))
        for i in 0..<n {
            let x = r.minX + CGFloat(i) * w
            p.addLine(to: CGPoint(x: x + w / 2, y: r.minY))
            p.addLine(to: CGPoint(x: x + w, y: r.minY + depth))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - depth))
        for i in 0..<n {
            let x = r.maxX - CGFloat(i) * w
            p.addLine(to: CGPoint(x: x - w / 2, y: r.maxY))
            p.addLine(to: CGPoint(x: x - w, y: r.maxY - depth))
        }
        p.closeSubpath()
        return p
    }
}

extension View {
    /// Puts the view on a torn strip of receipt paper with a soft drop shadow.
    func onReceiptPaper() -> some View {
        padding(.horizontal, 18)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(ReceiptPalette.ink)
            .background(
                ReceiptPaper()
                    .fill(ReceiptPalette.paper)
                    .mooveShadow(.paper)
            )
    }
}

/// A dashed horizontal rule, like the separators a till prints.
struct DashedRule: View {
    var body: some View {
        HLine()
            .stroke(ReceiptPalette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(height: 1)
            .padding(.vertical, 10)
            .accessibilityHidden(true)
    }
}

private struct HLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// Dotted leader between a label and its amount; sits on the text baseline.
struct DottedLeader: View {
    var body: some View {
        HLine()
            .stroke(ReceiptPalette.rule, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.5, 4]))
            .frame(minWidth: 10, maxWidth: .infinity)
            .frame(height: 2)
            .accessibilityHidden(true)
    }
}

/// "LABEL ........ $0.01". At accessibility sizes, or when the two don't fit on a line, the
/// leader drops out and the value goes under the label.
struct LeaderRow: View {
    var label: String
    var value: String
    var size: CGFloat = 14
    var bold = false
    var tint: Color = ReceiptPalette.ink
    var struck = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stacked
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    labelText.lineLimit(1).fixedSize()
                    DottedLeader().alignmentGuide(.lastTextBaseline) { $0[.bottom] - 3 }
                    valueText.lineLimit(1).fixedSize()
                }
                stacked
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 2) {
            labelText.fixedSize(horizontal: false, vertical: true)
            valueText.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var labelText: some View { Text(label).courier(size, bold: bold).foregroundStyle(tint) }
    private var valueText: some View {
        Text(value).courier(size, bold: true).strikethrough(struck).foregroundStyle(tint)
    }
}

/// A small boxed rail tag printed on a line: "x402", "VISA".
struct RailStamp: View {
    var text: String

    var body: some View {
        Text(text)
            .courier(11.5, bold: true, maxScale: 1.6)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(ReceiptPalette.muted)
            .overlay(Rectangle().strokeBorder(ReceiptPalette.muted.opacity(0.7), lineWidth: 1))
    }
}

/// The filled ochre SIMULATED mark, in receipt type (same fill as `SimulatedBadge`, so it reads as
/// the app's simulated label). Paper on ochre ink is about 4.9:1 light, 6.8:1 dark.
struct SimStamp: View {
    var text = "SIMULATED"

    var body: some View {
        Text(text)
            .courier(11.5, bold: true, maxScale: 1.6)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(ReceiptPalette.paper)
            .background(Theme.ochreInk)
    }
}

/// The rubber stamp under a receipt with simulated lines, slightly askew.
struct NoMoneyMovedStamp: View {
    var text: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .courier(13, bold: true, maxScale: 1.8)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Theme.ochreInk)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.ochreInk, lineWidth: 2))
            .rotationEffect(.degrees(dynamicTypeSize.isAccessibilitySize ? 0 : -2.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

/// A row of bars from the receipt's widths (decorative).
struct ReceiptBarcode: View {
    var widths: [Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(widths.indices, id: \.self) { i in
                Rectangle()
                    .fill(ReceiptPalette.ink.opacity(0.85))
                    .frame(width: CGFloat(widths[i]) * 1.4, height: i % 9 == 0 ? 34 : 30)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }
}
