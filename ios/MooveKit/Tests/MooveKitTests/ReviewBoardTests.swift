import Foundation
import Testing
@testable import MooveKit

@Suite struct ReviewBoardTests {
    let snapshot = DemoFixtures.inventory(owner: "me")
    var items: [Item] { snapshot.items }

    private func item(_ id: UInt64, value: Int64? = nil, _ d: Disposition = .undecided,
                      source: DispositionSource = .auto, sentimental: Bool = false) -> Item {
        Item(id: id, owner: "me", roomId: 1, name: "Item \(id)", category: "chair", widthM: 0.5, heightM: 1, depthM: 0.5,
             estValueCents: value, disposition: d, dispositionSource: source, maybeSentimental: sentimental)
    }

    // MARK: Deck

    @Test func demoDeckIsTheGuitar() {
        #expect(Review.deck(items).map(\.id) == [18])
    }

    @Test func deckPutsSentimentalFirstThenValue() {
        let deck = Review.deck([
            item(1, value: 5_000),
            item(2, value: 90_000),
            item(3, value: 1_000, sentimental: true),
            item(4, value: 20_000, .keep, sentimental: true), // auto-kept but sentimental: still the user's call
            item(5, value: 99_000, .sell),                     // decided by the agent: on the board
            item(6, value: nil),
        ])
        #expect(deck.map(\.id) == [4, 3, 2, 1, 6])
    }

    @Test func userDecisionLeavesTheDeckAndUndecidedComesBack() {
        var guitar = items.first { $0.id == 18 }!
        guitar.disposition = .keep
        guitar.dispositionSource = .user
        #expect(Review.deck([guitar]).isEmpty)
        // Undo sets it back to undecided (as the user): it's on the deck again.
        guitar.disposition = .undecided
        #expect(Review.deck([guitar]).map(\.id) == [18])
    }

    @Test func suggestionOnlyWhenTheAgentDecided() {
        #expect(Review.suggestion(item(1, .keep, sentimental: true)) == .keep)
        #expect(Review.suggestion(item(2)) == nil)
        #expect(Review.suggestion(item(3, .sell, source: .user)) == nil)
    }

    @Test func flipDeckIsTheWholeMoveNeedsYouFirst() {
        let all = [
            item(1, value: 5_000, .sell),
            item(2, value: 90_000, .keep),
            item(3, value: 1_000, sentimental: true),
            item(4, value: 20_000, .donate, source: .user),
            item(5),
        ]
        #expect(Review.flipDeck(all).map(\.id) == [3, 5, 2, 1])
        #expect(Review.flipDeck(all, includeYours: true).map(\.id) == [3, 5, 2, 1, 4])
    }

    @Test func demoFlipDeckStartsWithTheGuitar() {
        let deck = Review.flipDeck(items)
        #expect(deck.first?.id == 18)
        #expect(deck.count == items.count)
    }

    @Test func verdictLine() {
        // 0.5 × 1 × 0.5 m = 0.25 m³ × $60 = $15 to move.
        #expect(Review.verdict(item(1, value: 3_000, .sell)) == "Sell · worth $30, costs ~$15 to move")
        #expect(Review.verdict(item(2, .keep)) == "Keep")
        #expect(Review.verdict(item(3)) == nil)
        #expect(Review.verdict(item(4, value: 3_000, .sell, source: .user)) == nil)
    }

    // MARK: Piles

    @Test func pilesAreFourInOrderWithoutDeckItems() {
        let piles = Review.piles(items)
        #expect(piles.map(\.destination) == [.keep, .sell, .donate, .trash])
        #expect(piles.map(\.count) == [7, 4, 0, 0])
        #expect(!piles.flatMap(\.items).contains { $0.id == 18 })
        #expect(piles.map(\.count).reduce(0, +) + Review.deck(items).count == items.count)
    }

    @Test func pileTotals() {
        let piles = Review.piles(items)
        let sell = piles[1]
        #expect(sell.valueCents == Review.totals(items).expectedSaleCents)
        #expect(sell.items.first?.id == 11) // the Aeron, most valuable first
        #expect(sell.kg > 0)
        #expect(abs(piles[0].volumeM3 - Review.totals(items).volumeToMoveM3) < 1e-9)
        #expect(piles[2].valueCents == 0 && piles[2].kg == 0)
    }

    @Test func totalsIncludeDivertedKg() {
        let t = Review.totals(items)
        let expected = items.filter { $0.disposition == .sell || $0.disposition == .donate }.map(MoveSummary.estimatedKg).reduce(0, +)
        #expect(t.divertedKg == expected)
        #expect(t.divertedKg > 0)
    }

    // MARK: Keep by room

    @Test func keepByRoomWithoutLayoutIsOneGroup() {
        let keep = Review.piles(items)[0].items
        let groups = Review.keepByRoom(keep, layout: nil)
        #expect(groups.count == 1)
        #expect(groups[0].room == nil)
        #expect(groups[0].items == keep)
    }

    @Test func keepByRoomFollowsTheLayout() {
        let keep = [item(1, .keep), item(2, .keep), item(3, .keep)]
        let layout = Layout(id: 1, owner: "me", newHomeId: 9, name: "By function", placementsJson: Layout.encode([
            Placement(itemId: 2, room: "Office", x: 0, y: 0),
            Placement(itemId: 1, room: "Bedroom", x: 0, y: 0),
            Placement(itemId: 99, room: "Kitchen", x: 0, y: 0), // not kept: no empty group
        ]))
        let groups = Review.keepByRoom(keep, layout: layout)
        #expect(groups.map(\.room) == ["Office", "Bedroom", nil])
        #expect(groups.map { $0.items.map(\.id) } == [[2], [1], [3]])
    }

    @Test func savedLayoutIsTheNewestForMyNewHome() {
        var s = SyncSnapshot(me: "me")
        #expect(Review.savedLayout(in: s) == nil)
        s.newHomes = [NewHome(id: 9, owner: "me", name: "Demo house", source: .demo, floorPlanJson: "{}")]
        s.layouts = [
            Layout(id: 1, owner: "me", newHomeId: 9, name: "A", placementsJson: "[]", createdAt: Date(timeIntervalSince1970: 10)),
            Layout(id: 2, owner: "me", newHomeId: 9, name: "B", placementsJson: "[]", createdAt: Date(timeIntervalSince1970: 20)),
            Layout(id: 3, owner: "me", newHomeId: 8, name: "Other home", placementsJson: "[]", createdAt: Date(timeIntervalSince1970: 30)),
        ]
        #expect(Review.savedLayout(in: s)?.name == "B")
    }

    // MARK: Value range

    @Test func valueRangeFromComps() {
        let chair = items.first { $0.id == 11 }!
        #expect(Review.valueRange(chair, comps: snapshot.comps) == 38_000...45_000)
        #expect(Review.valueRange(items.first { $0.id == 18 }!, comps: snapshot.comps) == nil)
    }

    // MARK: Swipes

    @Test func swipeDirections() {
        #expect(ReviewSwipe.pointing(dx: 120, dy: 10) == .keep)
        #expect(ReviewSwipe.pointing(dx: -120, dy: 30) == .sell)
        #expect(ReviewSwipe.pointing(dx: 20, dy: -150) == nil) // vertical = scrolling, never donate
        #expect(ReviewSwipe.pointing(dx: -20, dy: 150) == nil) // never trash by swipe
        #expect(ReviewSwipe.pointing(dx: 0, dy: 0) == nil)
        #expect(ReviewSwipe.pointing(dx: 100, dy: 120) == .keep) // mostly sideways once vertical is discounted
    }

    @Test func swipeCommitsPastTheThresholdOrOnAFlick() {
        #expect(ReviewSwipe.commit(dx: 60, dy: 0, threshold: 110) == nil)
        #expect(ReviewSwipe.commit(dx: 115, dy: 0, threshold: 110) == .keep)
        // Vertical drags are scrolling: they never decide (Donate/Trash are buttons).
        #expect(ReviewSwipe.commit(dx: 0, dy: -110, threshold: 110) == nil)
        #expect(ReviewSwipe.commit(dx: 0, dy: -150, threshold: 110) == nil)
        #expect(ReviewSwipe.commit(dx: 5, dy: 160, threshold: 110) == nil)
        // A quick flick left: short drag, far predicted end.
        #expect(ReviewSwipe.commit(dx: -40, dy: 5, predictedDx: -400, predictedDy: 10, threshold: 110) == .sell)
        // A flick that reverses direction doesn't count.
        #expect(ReviewSwipe.commit(dx: 40, dy: 0, predictedDx: -400, predictedDy: 0, threshold: 110) == nil)
        #expect(ReviewSwipe.progress(dx: 55, dy: 0, threshold: 110) == 0.5)
        #expect(ReviewSwipe.progress(dx: 500, dy: 0, threshold: 110) == 1)
    }
}
