import SwiftUI
import MooveKit

/// Items > Review. On top, a deck of the items only you can decide (possibly sentimental or
/// undecided; Moove never decides those): swipe right to keep, left to sell (Donate and Trash are buttons,
/// so a vertical scroll never decides). Below, "Where it goes": the Keep / Sell / Donate / Trash board, where any
/// decision can be changed. User decisions are never overwritten by the agents.
struct ReviewView: View {
    @Environment(MooveStore.self) private var store
    /// Swiped cards waiting for the store to catch up, so the next card shows at once.
    @State private var pending: Set<UInt64> = []
    /// This visit's swipes, newest last, for Undo and "2 of 5".
    @State private var history: [UInt64] = []
    /// The board tile opened on iPhone.
    @State private var selected: Disposition?
    @State private var committed = 0

    var body: some View {
        let items = store.visibleItems
        let deck = Review.deck(items).filter { !pending.contains($0.id) }
        let piles = Review.piles(items.filter { !pending.contains($0.id) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    ReviewEmptyState().padding(.top, 28)
                } else {
                    if !deck.isEmpty {
                        ReviewDeckView(cards: deck, comps: store.snapshot.comps, decidedCount: history.count,
                                       canUndo: !history.isEmpty, onDecide: decide, onUndo: undo)
                            .padding(.top, 24)
                    } else if !history.isEmpty {
                        ReviewAllDecided(totals: Review.totals(items), canUndo: true, onUndo: undo)
                            .padding(.top, 24)
                    }
                    unnamed(items)
                    ListHeader(title: "Where it goes") {
                        if deck.isEmpty && history.isEmpty {
                            Label("Nothing needs you", systemImage: "checkmark.circle")
                                .monoText(12.5)
                                .foregroundStyle(Theme.accentStrong)
                                .accessibilityIdentifier("review.caughtUp")
                        }
                    }
                    .padding(.top, 36)
                    .padding(.bottom, 16)
                    ReviewBoardView(
                        piles: piles,
                        keepGroups: Review.keepByRoom(piles[0].items, layout: Review.savedLayout(in: store.snapshot)),
                        selected: $selected,
                        onMove: move
                    )
                    closeups(items)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 16)
            .padding(.bottom, 48)
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UInt64.self) { ItemDetailView(itemId: $0) }
        .mooveScreen()
        .sensoryFeedback(.success, trigger: committed)
        .animation(.default, value: store.visibleItems)
        .animation(.snappy, value: selected)
        .onChange(of: store.visibleItems) { _, items in
            // The store has the decision: stop hiding those cards (an undecided one comes back).
            let stillWaiting = Set(Review.deck(items).map(\.id))
            pending = pending.filter { stillWaiting.contains($0) }
            history = history.filter { id in items.contains { $0.id == id } }
        }
    }

    // MARK: Decisions

    private func decide(_ item: Item, _ disposition: Disposition) {
        pending.insert(item.id)
        history.append(item.id)
        committed += 1
        Task {
            if !(await store.setDisposition(disposition, for: item)) {
                pending.remove(item.id)
                history.removeAll { $0 == item.id }
            }
        }
    }

    /// Puts the last swiped card back on top of the deck (undecided, for you to decide again).
    private func undo() {
        guard let id = history.popLast(), let item = store.items.first(where: { $0.id == id }) else { return }
        pending.remove(id)
        Task { await store.setDisposition(.undecided, for: item) }
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
                .padding(.top, 40)
                .accessibilityIdentifier("review.needsName")
            ForEach(unnamed) { item in
                NavigationLink(value: item.id) {
                    HStack(spacing: 12) {
                        ItemArt(item: item, size: 48)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name.isEmpty ? "Unidentified item" : item.name.capitalizedFirst)
                                .monoText(14.5, weight: .bold).foregroundStyle(Theme.text).lineLimit(2)
                            Text(ItemLabels.hint(for: item)).monoText(12, maxScale: 1.8).foregroundStyle(Theme.muted).lineLimit(2)
                        }
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
                .accessibilityHint("Opens it to rename it or pick what it is")
                .accessibilityIdentifier("review.unnamed.\(item.id)")
            }
        }
    }

    // MARK: Close-ups (#276)

    @ViewBuilder
    private func closeups(_ items: [Item]) -> some View {
        let closeups = Review.wantingCloseups(items)
        if !closeups.isEmpty {
            ListHeader(title: "A photo would help", count: "\(closeups.count)")
                .padding(.top, 40)
            ForEach(closeups) { ReviewBoardRow(item: $0) }
        }
    }
}

private struct ReviewEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing to review").blockTitle()
            Text("Scan a room first.").monoMeta()
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { ReviewView() }.environment(MooveStore.preview())
}
