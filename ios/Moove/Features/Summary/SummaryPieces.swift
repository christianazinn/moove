import SwiftUI
import MooveKit

// The Summary screen's blocks (#335). Figures and wording come from MooveKit `MoveSummary`,
// `SummaryPayoff` and `SafetySummary`; these views only draw.

// MARK: Big figures

/// One headline figure on a soft card: label, big number, a thin meter and a short caption.
struct SummaryFigure: View {
    var label: String
    var value: String
    var tint: Color = Theme.text
    var size: CGFloat = 26
    /// 0...1 filled with `meterTint`, the rest with `meterRest`. nil: no meter.
    var meter: Double?
    var meterTint: Color = Theme.accent
    var meterRest: Color = Theme.line
    var caption: String?
    var tag: String?
    var spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(label).monoText(13.5).foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                if let tag { MonoTag(text: tag, tone: Theme.ochreInk) }
            }
            Text(value)
                .monoText(size, weight: .bold, maxScale: 1.6)
                .tracking(-0.4)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            if let meter {
                SummaryMeter(fraction: meter, tint: meterTint, rest: meterRest).padding(.vertical, 2)
            }
            if let caption {
                Text(caption).monoMeta().fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? ([label, value, tag, caption] as [String?]).compactMap { $0 }.joined(separator: ", "))
    }
}

/// A thin two-tone capsule (decorative; the caption says the same in words).
struct SummaryMeter: View {
    var fraction: Double
    var tint: Color
    var rest: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(rest)
                Capsule().fill(tint).frame(width: max(fraction > 0 ? 6 : 0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: Where everything went

/// One stacked bar of Keep / Sell / Donate / Trash / Needs you (Review's colors), and a legend
/// of the counts. Tapping a segment or its legend chip opens that list.
struct SummaryDispositionBar: View {
    let segments: [SummaryPayoff.Segment]
    let onOpen: (SummaryPayoff.Segment) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static func color(_ s: SummaryPayoff.Segment) -> Color {
        s.destination.map(ReviewPalette.solid) ?? Theme.danger
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geo in
                let gaps = CGFloat(max(segments.count - 1, 0)) * 3
                HStack(spacing: 3) {
                    ForEach(segments) { seg in
                        Button { onOpen(seg) } label: {
                            Rectangle()
                                .fill(Self.color(seg))
                                .frame(width: max(8, (geo.size.width - gaps) * seg.fraction))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: 30)
            .accessibilityHidden(true)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            ViewThatFits(in: .horizontal) {
                layout { chips }
                VStack(alignment: .leading, spacing: 8) { chips }
            }
        }
    }

    @ViewBuilder private var chips: some View {
        ForEach(segments) { seg in
            Button { onOpen(seg) } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(Self.color(seg)).frame(width: 12, height: 12)
                    Text(seg.label).monoText(13.5)
                    Text("\(seg.count)").monoText(13.5, weight: .bold)
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("\(seg.label), \(seg.count) item\(seg.count == 1 ? "" : "s")")
            .accessibilityHint(seg.destination == nil ? "Opens Review" : "Shows the list")
            .accessibilityIdentifier("summary.segment.\(seg.id)")
        }
    }
}

// MARK: Impact

/// "~49 kg kept out of landfill" next to a leaf meter (one leaf per ~5 kg) and the let-go
/// items stacked as voxel models.
struct SummaryImpact: View {
    let kg: Double
    let divertedItems: [Item]
    let divertedShare: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let leaves = SummaryPayoff.leaves(kg: kg)
        let kgText = Int(kg.rounded())
        VStack(alignment: .leading, spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
            layout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("~\(kgText) kg")
                        .monoText(34, weight: .bold, maxScale: 1.6)
                        .foregroundStyle(Theme.accentStrong)
                    Text("kept out of landfill").monoText(13.5).foregroundStyle(Theme.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("About \(kgText) kilograms kept out of landfill")
                Spacer(minLength: 0)
                if !divertedItems.isEmpty { stack }
            }
            if leaves > 0 { leafMeter(leaves) }
            Text(itemsLine)
                .sansText(15.5)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text("Each leaf ≈ \(Int(SummaryPayoff.kgPerLeaf)) kg · rough weights by type and size.")
                .monoMeta()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft.opacity(0.55), in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
    }

    private var itemsLine: String {
        let n = divertedItems.count
        var text = "\(n) \(n == 1 ? "item" : "items") sold or donated, not trashed."
        if let share = divertedShare {
            text += share >= 0.999 ? " Nothing you let go went to landfill." : " \(Int((share * 100).rounded()))% of what you let go skipped it."
        }
        return text
    }

    /// Up to four of the let-go pieces, overlapping like a pile.
    private var stack: some View {
        HStack(spacing: -18) {
            ForEach(Array(divertedItems.prefix(4).enumerated()), id: \.element.id) { i, item in
                VoxelThumbnail(item, size: 52)
                    .rotationEffect(.degrees(i.isMultiple(of: 2) ? -4 : 5))
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private func leafMeter(_ n: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<n, id: \.self) { i in
                Image(systemName: "leaf.fill")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(i.isMultiple(of: 3) ? Theme.accentStrong : Theme.accent)
                    .rotationEffect(.degrees(i.isMultiple(of: 2) ? -12 : 14))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Safety receipt

/// "Agents kept you safe" (#225) printed as a receipt, in the Agents receipts' paper and type:
/// one line per guardrail that fired, SIM marks on simulated money and the stamp under them.
struct SafetyReceipt: View {
    let safety: SafetySummary
    var printedAt: Date = .now

    var body: some View {
        let lines = safety.lines
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 3) {
                Text("MOOVE · GUARDRAILS").courier(14, bold: true)
                Text("\(ReceiptFormat.day(printedAt))  \(ReceiptFormat.time(printedAt))")
                    .courier(12.5).foregroundStyle(ReceiptPalette.muted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            DashedRule()
            if lines.isEmpty {
                Text(SafetySummary.emptyText.uppercased())
                    .courier(13.5)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines) { line in lineView(line) }
                }
                DashedRule()
                LeaderRow(label: "GUARDRAILS THAT FIRED", value: "\(lines.count)", size: 14, bold: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(lines.count) guardrail\(lines.count == 1 ? "" : "s") fired")
                if let stamp = SummaryPayoff.safetyStamp(lines) {
                    NoMoneyMovedStamp(text: stamp)
                        .padding(.top, 6)
                        .accessibilityLabel("Stamped: lines marked simulated moved no money")
                }
                ReceiptBarcode(widths: SummaryPayoff.safetyBarcode(lines)).padding(.top, 8)
            }
            Text("SAFE TRAVELS")
                .courier(13, bold: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityHidden(true)
        }
        .onReceiptPaper()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary.safety")
    }

    private func lineView(_ line: SafetySummary.Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: SummaryView.safetyIcon(line.kind))
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(ReceiptPalette.muted)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(line.text).courier(13.5, bold: true).fixedSize(horizontal: false, vertical: true)
                if let detail = line.detail {
                    Text(detail).courier(12.5).foregroundStyle(ReceiptPalette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if line.simulated { SimStamp(text: "SIM") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken + (line.simulated ? ", simulated" : ""))
    }
}

// MARK: What the agents did

/// The key agent steps as a short vertical timeline, the rest behind "Show all".
struct SummaryAgentTimeline: View {
    let key: [MoveSummary.Event]
    let rest: [MoveSummary.Event]
    @State private var showAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let shown = showAll ? (key + rest).sorted { $0.createdAt < $1.createdAt } : key
            ForEach(Array(shown.enumerated()), id: \.offset) { i, e in
                row(e, last: i == shown.count - 1)
            }
            if !rest.isEmpty {
                Button(showAll ? "Show fewer" : "Show all \(key.count + rest.count) steps") {
                    if reduceMotion { showAll.toggle() } else { withAnimation(.easeInOut(duration: 0.25)) { showAll.toggle() } }
                }
                .buttonStyle(.pill(.text, compact: true))
                .padding(.top, 4)
                .accessibilityIdentifier("summary.agents.showAll")
            }
        }
    }

    private func row(_ e: MoveSummary.Event, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Theme.accentSoft).frame(width: 28, height: 28)
                    Image(systemName: SummaryView.icon(e.kind))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentStrong)
                }
                if !last { Rectangle().fill(Theme.line).frame(width: 2).frame(maxHeight: .infinity) }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(e.message).sansText(15).fixedSize(horizontal: false, vertical: true)
                Text("\(e.agent) · \(e.createdAt, style: .relative) ago").monoMeta()
            }
            .padding(.top, 4)
            .padding(.bottom, last ? 4 : 18)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Share image

/// What "Share my move" renders to an image: the dollhouse still (or the floor plan), the
/// title, the story and the three figures, with the simulated note when it applies.
struct SummaryShareCard: View {
    var heroImage: UIImage?
    var plan: FloorPlan?
    var story: String?
    var made: String
    var spent: String
    var net: String
    var netTint: Color
    var simulated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MooveWordmark(height: 26, animated: false)
            if let heroImage {
                Image(uiImage: heroImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 230)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let plan {
                FloorPlanSketch(plan: plan)
                    .frame(height: 200)
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            Text(SummaryHero.title).monoText(26, weight: .bold, maxScale: 1).foregroundStyle(Theme.text)
            if let story { Text(story).sansText(15.5, maxScale: 1).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 10) {
                figure("Made", made, Theme.accentStrong)
                figure("Spent", spent, Theme.ochreInk)
                figure("Net", net, netTint)
            }
            if simulated {
                Text("Some figures are simulated (demo purchases and listings).").monoText(11.5, maxScale: 1).foregroundStyle(Theme.muted)
            }
        }
        .padding(24)
        .frame(width: 390)
        .background(Theme.bg)
    }

    private func figure(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).monoText(12, maxScale: 1).foregroundStyle(Theme.muted)
            Text(value).monoText(18, weight: .bold, maxScale: 1).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
