import SwiftUI
import MooveKit

// Shared by the four commerce screens (Spending, Listings, Shopping, Approvals). It lives in the
// commerce lane's Spending folder rather than Moove/Shared so other lanes' files stay untouched.

/// The body of a commerce screen with no rows: connecting, can't reach the backend, or truly empty
/// (with a next step). Each screen passes its own empty-state words.
struct CommercePlaceholder<Action: View>: View {
    let state: CommerceScreenState
    let emptyTitle: String
    let emptyDetail: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.muted)
                    Text(state.title ?? "Connecting…").blockTitle()
                }
                Text("Waiting for the first rows from the backend.").monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
            case .offline(let why):
                Label {
                    Text(state.title ?? "Offline").blockTitle()
                } icon: {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(Theme.danger)
                }
                Text(why).monoMeta().fixedSize(horizontal: false, vertical: true)
                Text(CommerceScreenState.offlineNextStep)
                    .sansText(14).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            case .empty, .content:
                Text(emptyTitle).blockTitle()
                Text(emptyDetail).monoMeta().fixedSize(horizontal: false, vertical: true)
                action.padding(.top, 10)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .contain)
    }
}

extension CommercePlaceholder where Action == EmptyView {
    init(state: CommerceScreenState, emptyTitle: String, emptyDetail: String) {
        self.init(state: state, emptyTitle: emptyTitle, emptyDetail: emptyDetail) { EmptyView() }
    }
}

/// CLAUDE.md hard rule (Coinbase track): anything simulated says so, in the same filled ochre
/// pill everywhere (payments, listings, Visa checkouts), so it can't be mistaken for an outlined tag.
/// Contrast: page color on ochre ink is about 4.9:1 in light mode and 7.7:1 in dark mode.
struct SimulatedBadge: View {
    /// What VoiceOver says, e.g. "Simulated payment, no money moved".
    var spoken = "Simulated, not real"

    var body: some View {
        Text("SIMULATED")
            .monoText(10.5, weight: .bold, maxScale: 1.6)
            .tracking(0.5)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.bg)
            .background(Theme.ochreInk, in: .capsule)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }
}

/// An approval nobody answered in time (#186): an outlined muted pill, so it reads as a status and
/// can't be mistaken for the filled SIMULATED pill. Contrast: muted ink on the page color is about
/// 5.5:1 in light mode and 6.7:1 in dark mode.
struct ExpiredBadge: View {
    var body: some View {
        Label {
            Text("EXPIRED").monoText(10.5, weight: .bold, maxScale: 1.6).tracking(0.5)
        } icon: {
            Image(systemName: "clock.badge.xmark").font(.system(size: 10, weight: .semibold))
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Theme.muted)
        .overlay(Capsule().strokeBorder(Theme.muted, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Expired, no answer in \(ApprovalExpiry.hours) hours")
    }
}

/// A failure or refusal explained in words: danger-tinted, with an icon, never truncated.
struct CommerceProblem: View {
    let text: String
    var systemImage = "exclamationmark.triangle"
    var tint: Color = Theme.danger

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 12)).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .monoText(12.5)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// An HStack that becomes a VStack at accessibility text sizes, so amounts never get squeezed
/// into "$4…" next to badges and timestamps.
struct AdaptiveLine<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing / 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: spacing))
        layout { content }
    }
}

/// Headline figures between rules, split by hairlines. At accessibility text sizes they stack, so
/// labels like "Simulated" don't break mid-word and amounts don't truncate in a third of the width.
struct StatStrip: View {
    struct Figure {
        var label: String
        var value: String
        var tint: Color = Theme.text
        var spoken: String
    }

    let figures: [Figure]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(figures.indices, id: \.self) { i in
                        figure(i).padding(.vertical, 14)
                        if i < figures.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(figures.indices, id: \.self) { i in
                        figure(i)
                            .padding(.vertical, 18)
                            .padding(.leading, i == 0 ? 0 : 14)
                            .padding(.trailing, i == figures.count - 1 ? 0 : 14)
                        if i < figures.count - 1 { Rectangle().fill(Theme.line).frame(width: 1) }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ruled(.top)
        .ruled()
    }

    private func figure(_ i: Int) -> some View {
        let f = figures[i]
        return StatFigure(label: f.label, value: f.value, tint: f.tint).accessibilityLabel(f.spoken)
    }
}

extension View {
    /// A money figure: one line, wins space over its neighbors, shrinks a little before it truncates.
    func amountText() -> some View {
        lineLimit(1).minimumScaleFactor(0.75).layoutPriority(2)
    }
}

extension MooveStore {
    /// What a commerce screen shows when it has no rows of its own.
    func commerceState(hasRows: Bool) -> CommerceScreenState {
        CommerceScreenState(status: status, hasRows: hasRows)
    }
}
