import SwiftUI
import MooveKit

/// "Agents kept you safe" (#225, #229), on Sell & Buy > Agents between "Needs your OK" and
/// "Decided": the guardrails that fired (scams blocked, approvals asked, sentimental items left
/// alone, spend against the caps). Simulated money says so in the line and gets a tag.
/// It lived on the Summary tab until Summary was removed (decision 0129 addendum).
struct SafetyCard: View {
    @Environment(MooveStore.self) private var store

    var body: some View {
        let lines = SafetySummary(snapshot: store.snapshot).lines
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Agents kept you safe") {
                if lines.contains(where: \.simulated) { MonoTag(text: "Simulated", tone: Theme.ochreInk) }
            }
            if lines.isEmpty {
                Text(SafetySummary.emptyText).monoMeta().padding(.top, 16)
            } else {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: Self.icon(line.kind))
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Theme.accentStrong)
                            .frame(width: 18)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.text).monoText(13.5).fixedSize(horizontal: false, vertical: true)
                            if let detail = line.detail {
                                Text(detail).monoMeta().lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if line.simulated { MonoTag(text: "Sim", tone: Theme.ochreInk) }
                    }
                    .padding(.vertical, 12)
                    .frame(minHeight: 44)
                    .ruled()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(line.spoken)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agents.safety")
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
