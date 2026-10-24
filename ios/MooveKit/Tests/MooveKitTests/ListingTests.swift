import Foundation
import Testing
@testable import MooveKit

@Suite struct ListingTests {
    @Test func copyTextFormatsPrice() {
        let whole = Listing(id: 1, owner: "me", itemId: 1, title: "Desk", description: "Sturdy.", priceCents: 3_500)
        let cents = Listing(id: 2, owner: "me", itemId: 1, title: "Lamp", description: "Bright.", priceCents: 1_205)
        #expect(whole.copyText == "Desk\n$35\n\nSturdy.")
        #expect(cents.copyText == "Lamp\n$12.05\n\nBright.")
    }

    @Test func newestListingWinsForAnItem() {
        var s = SyncSnapshot(me: "me")
        s.listings = [
            Listing(id: 5, owner: "me", itemId: 1, title: "old", description: "", priceCents: 100, status: .rejected),
            Listing(id: 9, owner: "me", itemId: 1, title: "new", description: "", priceCents: 90),
        ]
        #expect(s.listing(for: 1)?.title == "new")
        #expect(s.listing(for: 2) == nil)
    }

    @Test func demoListingsAreSimulatedAndPointAtSellItems() {
        let s = DemoFixtures.inventory(owner: "me")
        #expect(!s.listings.isEmpty)
        for l in s.listings {
            #expect(l.simulated)
            #expect(s.items.first { $0.id == l.itemId }?.disposition == .sell)
        }
    }
}
