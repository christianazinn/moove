import SwiftUI
import MooveKit

/// "Get mover quotes" on the Pack screen's truck card. Owns its own sheet so PackView stays one line.
struct MoverQuotesButton: View {
    var estimate: TruckEstimate
    @State private var showing = false

    var body: some View {
        Button("Get mover quotes") { showing = true }
            .buttonStyle(.pill(.outline, compact: true))
            .accessibilityHint("Shows estimated prices for a truck rental, labor-only movers and full-service movers")
            .accessibilityIdentifier("pack.moverQuotes")
            .sheet(isPresented: $showing) {
                MoverQuotesView(request: MoverQuoteRequest(estimate: estimate))
                    .presentationDragIndicator(.visible)
            }
    }
}

/// Three mover options for the planned truck and crew: DIY truck rental, labor-only movers,
/// full-service movers. Asks the worker's movers agent (`POST /moves/quotes`); offline it works
/// out the same rate-table estimates on the phone. Everything is labeled an estimate.
struct MoverQuotesView: View {
    var request: MoverQuoteRequest
    var client = MoverQuotesClient()
    @State private var result: MoverQuotesResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(eyebrow: "Movers", title: "Mover quotes", lede: summary)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    if let result {
                        ForEach(result.quotes) { QuoteCard(quote: $0) }
                        footer(result)
                    } else {
                        ProgressView("Getting quotes…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .navigationTitle("Mover quotes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.monoText(14, weight: .bold, maxScale: 1.5)
                }
            }
            .mooveScreen()
            .task { if result == nil { result = await client.quotesOrOnDevice(request) } }
        }
    }

    private var summary: String {
        let truck = request.trucks > 1 ? "\(request.trucks) × \(request.truck.label)" : request.truck.label
        let h = request.hours.formatted(.number.precision(.fractionLength(0...1)))
        return "\(truck), \(request.crew) movers, about \(h) h."
    }

    private func footer(_ r: MoverQuotesResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(r.note)
                .sansText(15, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
            if r.onPhone {
                Text("Estimated on this phone. The movers agent couldn't be reached.")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
            } else if let steps = r.steps, !steps.isEmpty {
                Text("What the movers agent did").eyebrow().padding(.top, 6)
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    Text(step.message)
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Rates as of \(r.ratesAsOf).").monoMeta()
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuoteCard: View {
    var quote: MoverQuote

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(quote.provider)
                    .blockTitle()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                MonoTag(text: quote.tag, tone: quote.kind == .listedRate ? Theme.accentStrong : Theme.ochreInk)
            }
            Text("\(quote.lowCents.usd)–\(quote.highCents.usd)")
                .monoText(24, weight: .bold, maxScale: 1.6)
                .foregroundStyle(Theme.accentStrong)
                .accessibilityLabel("\(quote.tag), \(quote.lowCents.usd) to \(quote.highCents.usd)")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(quote.includes, id: \.self) { line in
                    Text("· \(line)").sansText(15).fixedSize(horizontal: false, vertical: true)
                }
            }
            if !quote.assumptions.isEmpty {
                Text(quote.assumptions.joined(separator: " · "))
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let s = quote.source.url, let url = URL(string: s) {
                Link(quote.kind == .listedRate ? "View the ad" : "Source: \(quote.source.name)", destination: url)
                    .monoText(13.5, weight: .bold)
                    .accessibilityHint("Opens in Safari")
            } else {
                Text("Source: \(quote.source.name)").monoMeta()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moverQuote.\(quote.id)")
    }
}
