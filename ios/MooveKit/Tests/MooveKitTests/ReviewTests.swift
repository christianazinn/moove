import Testing
@testable import MooveKit

@Suite struct ReviewTests {
    let items = DemoFixtures.inventory(owner: "me").items

    @Test func needsYouComesFirstWithSentimentalOnTop() {
        let sections = Review.sections(items)
        #expect(sections.first?.section == .needsYou)
        let needs = sections[0].items
        #expect(needs.allSatisfy { $0.maybeSentimental })
        #expect(needs.count == 2)
    }

    @Test func sentimentalItemMovesOutOfNeedsYouOnceUserDecides() {
        var quilt = items.first { $0.id == 18 }!
        quilt.disposition = .keep
        quilt.dispositionSource = .user
        #expect(ReviewSection.of(quilt) == .keep)
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
        #expect(t.expectedSaleCents == 42_000 + 4_000 + 2_000 + 7_500)
        #expect(t.itemsToMove == 3)
        #expect(t.needsYou == 2)
        #expect(t.divertedFromLandfill == 6)
    }
}
