import Testing
@testable import MooveKit

@Suite struct ReviewTests {
    let items = DemoFixtures.inventory(owner: "me").items

    @Test func needsYouComesFirstWithSentimentalOnTop() {
        let sections = Review.sections(items)
        #expect(sections.first?.section == .needsYou)
        let needs = sections[0].items
        #expect(needs.allSatisfy { $0.maybeSentimental })
        #expect(needs.count == 1) // the guitar, as on the seeded Bedroom
    }

    @Test func sentimentalItemMovesOutOfNeedsYouOnceUserDecides() {
        var guitar = items.first { $0.id == 18 }!
        guitar.disposition = .keep
        guitar.dispositionSource = .user
        #expect(ReviewSection.of(guitar) == .keep)
    }

    @Test func undecidedNonSentimentalNeedsYou() {
        let item = Item(id: 1, owner: "me", roomId: 1, name: "Box", category: "storage", widthM: 1, heightM: 1, depthM: 1)
        #expect(ReviewSection.of(item) == .needsYou)
    }

    @Test func everyItemLandsInExactlyOneSection() {
        let total = Review.sections(items).map(\.items.count).reduce(0, +)
        #expect(total == items.count)
    }

    @Test func totalsMatchFixture() {
        let t = Review.totals(items)
        // Sell: the mesh chair (the sort agent's one sell). Keep: the other 7 seeded items.
        #expect(t.expectedSaleCents == 3_000)
        #expect(t.itemsToMove == 7)
        #expect(t.needsYou == 1)
        #expect(t.divertedFromLandfill == 1)
    }
}
