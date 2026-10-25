import SwiftUI
import MooveKit

/// Items > Review. A strip with the kg kept out of landfill (`ReviewImpactBanner`), then flip cards for the whole move (`Review.flipDeck`): the items only you
/// can decide first (possibly sentimental or undecided; Moove never decides those), then every
/// item the agents sorted, with what Moove suggests, so you can confirm or change each. Swipe
/// right to keep, left to sell, up to donate, down to trash.
/// Below, "Where it goes": the Keep / Sell / Donate / Trash board. User decisions are never
/// overwritten by the agents.
struct ReviewView: View {
    @Environment(MooveStore.self) private var store
    /// This pass's cards, oldest first, with what each was before, for Undo and "4 of 12".
    @State private var history: [ReviewStep] = []
    /// Cards Undo put back, newest first: they go on top even once they count as yours.
    @State private var undone: [UInt64] = []
    /// After "Start over" the stack includes what you already decided.
    @State private var startedOver = false
    @State private var committed = 0

    var body: some View {
        let items = store.visibleItems
        let deck = cards(items)
        let piles = Review.piles(items)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    ReviewEmptyState().padding(.top, 28)
                } else {
                    // Kg kept out of landfill, live as you decide (moved here from the Summary tab).
                    ReviewImpactBanner(items: items)
                        .padding(.top, 4)
                    if !deck.isEmpty {
                        ReviewDeckView(cards: deck, comps: store.snapshot.comps, doneCount: history.count,
                                       canUndo: !history.isEmpty, onDecide: decide, onUndo: undo)
                            .padding(.top, 20)
                    } else {
                        ReviewAllDecided(totals: Review.totals(items), canUndo: !history.isEmpty,
                                         onUndo: undo, onStartOver: startOver)
                            .padding(.top, 20)
                    }
                    unnamed(items)
                    ListHeader(title: "Where it goes") {
                        if Review.deck(items).isEmpty {
                            Label("Nothing needs you", systemImage: "checkmark.circle")
                                .monoText(12.5)
                                .foregroundStyle(Theme.accentStrong)
                                .accessibilityIdentifier("review.caughtUp")
                        }
                    }
                    .padding(.top, Theme.Space.section)
                    .padding(.bottom, 16)
                    ReviewBoardView(
                        piles: piles,
                        onMove: move
                    )
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UInt64.self) { ItemDetailView(itemId: $0) }
        .navigationDestination(for: ReviewPileRoute.self) { ReviewPileScreen(destination: $0.destination) }
        .mooveScreen()
        .sensoryFeedback(.success, trigger: committed)
        .animation(.default, value: store.visibleItems)
        .onChange(of: store.visibleItems) { _, items in
            let ids = Set(items.map(\.id))
            history = history.filter { ids.contains($0.id) }
            undone = undone.filter { ids.contains($0) }
        }
    }

    /// Cards still to go: Undo's first, then the stack minus what this pass already did.
    private func cards(_ items: [Item]) -> [Item] {
        let done = Set(history.map(\.id))
        let back = undone.compactMap { id in items.first { $0.id == id } }
        let rest = Review.flipDeck(items, includeYours: startedOver)
            .filter { !done.contains($0.id) && !undone.contains($0.id) }
        return back.filter { !done.contains($0.id) } + rest
    }

    // MARK: Decisions

    /// Confirms or changes a card as your call (a confirmed suggestion becomes yours too).
    private func decide(_ item: Item, _ disposition: Disposition) {
        history.append(ReviewStep(id: item.id, before: item.disposition, chose: disposition))
        undone.removeAll { $0 == item.id }
        committed += 1
        guard item.disposition != disposition || item.dispositionSource != .user else { return }
        Task {
            if !(await store.setDisposition(disposition, for: item)) {
                history.removeAll { $0.id == item.id }
            }
        }
    }

    /// Puts the last card back on top, as it was (undecided stays undecided; an agent's call
    /// you changed goes back to that call, now as yours, since only the agents write "auto").
    private func undo() {
        guard let step = history.popLast(), let item = store.items.first(where: { $0.id == step.id }) else { return }
        undone.insert(step.id, at: 0)
        guard step.before != step.chose else { return }
        Task { await store.setDisposition(step.before, for: item) }
    }

    /// Flips through the whole move again, your own decisions included.
    private func startOver() {
        history = []
        undone = []
        startedOver = true
    }

    private func move(_ id: UInt64, _ disposition: Disposition) {
        guard let item = store.items.first(where: { $0.id == id }), item.disposition != disposition || item.dispositionSource != .user else { return }
        Task { await store.setDisposition(disposition, for: item) }
    }

    // MARK: Needs a name

    /// Items still called "Other" / "Unidentified item": tap one for Item detail, whose Fix it
    /// section renames it and picks what it is (which also fixes its 3D model).
    @ViewBuilder
    private func unnamed(_ items: [Item]) -> some View {
        let unnamed = ItemLabels.needingNames(items)
        if !unnamed.isEmpty {
            ListHeader(title: "Needs a name", count: "\(unnamed.count)")
                .padding(.top, Theme.Space.section)
                .accessibilityIdentifier("review.needsName")
            CollapsedList(data: unnamed, id: "review.unnamed") { item in
                NavigationLink(value: item.id) {
                    HStack(spacing: 12) {
                        ItemArt(item: item, size: 48)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                        Text(item.name.isEmpty ? "Unidentified item" : item.name.capitalizedFirst)
                            .monoText(14.5, weight: .bold).foregroundStyle(Theme.text).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "pencil")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 36, height: 44)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ruled()
                .accessibilityHint("\(ItemLabels.hint(for: item)). Opens it to rename it or pick what it is")
                .accessibilityIdentifier("review.unnamed.\(item.id)")
            }
        }
    }
}

/// One card done on this pass.
private struct ReviewStep {
    let id: UInt64
    let before: Disposition
    let chose: Disposition
}

private struct ReviewEmptyState: View {
    var body: some View {
        EmptyState(title: "Nothing to review", detail: "Scan a room first.")
    }
}

#Preview {
    NavigationStack { ReviewView() }.environment(MooveStore.preview())
}
