import SwiftUI
import MooveKit

/// "Agents kept you safe" (#225, #229), on Sell & Buy > Agents between "Needs your OK" and
/// "Decided": the guardrails that fired (scams blocked, approvals asked, sentimental items left
/// alone, spend against the caps): its first three lines, one short clause each. Simulated money
/// gets the SIMULATED tag on the header.
/// It lived on the Summary tab until Summary was removed (decision 0129 addendum).
struct SafetyCard: View {
    @Environment(MooveStore.self) private var store

    /// At most three short lines (Lisa: less overstimulating): each line's first clause only
    /// ("1 scam deal blocked"); the rest stays in its VoiceOver label.
    static let maxLines = 3

    var body: some View {
        let lines = Array(SafetySummary(snapshot: store.snapshot).lines.prefix(Self.maxLines))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Agents kept you safe").listHeading().accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if lines.contains(where: \.simulated) { SimulatedBadge(spoken: "Includes simulated payments") }
            }
            .padding(.bottom, Theme.Space.s)
            if lines.isEmpty {
                Text("Nothing to guard yet").monoMeta().padding(.top, Theme.Space.s)
                    .accessibilityLabel(SafetySummary.emptyText)
            } else {
                ForEach(lines) { line in
                    HStack(spacing: 14) {
                        Image(systemName: Self.icon(line.kind))
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(Self.short(line.text)).monoText(13.5).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line.spoken)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents.safety")
    }

    /// "1 scam deal blocked · fraud score 0.85" -> "1 scam deal blocked".
    static func short(_ text: String) -> String {
        text.components(separatedBy: " · ").first ?? text
    }

    static func icon(_ kind: SafetySummary.LineKind) -> String {
        switch kind {
        case .fraud: "exclamationmark.shield"
        case .approvals: "hand.raised"
        case .sentimental: "heart"
        case .x402: "dollarsign.circle"
        case .roomX402: "person.2"
        case .card: "creditcard"
        case .ai: "gauge"
        }
    }
}

#Preview {
    ScrollView { SafetyCard().padding(.horizontal, Theme.gutter) }.environment(MooveStore.preview())
}
