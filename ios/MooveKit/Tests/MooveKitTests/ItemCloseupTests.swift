import Testing
@testable import MooveKit

@Suite struct ItemCloseupTests {
    func item(_ name: String, category: String, value: Int64? = nil, brand: String? = nil,
              confidence: IdentifyConfidence? = .medium, hint: String? = "model sticker on the bottom",
              status: AgentStage? = .done) -> Item {
        Item(id: 1, owner: "me", roomId: 1, name: name, category: category, widthM: 0.3, heightM: 0.02, depthM: 0.2,
             brand: brand, estValueCents: value, detailsStatus: status, identifyConfidence: confidence, closeupHint: hint)
    }

    @Test func asksForTheCloseupOnAnUnsureLaptop() {
        let laptop = item("Apple MacBook Pro", category: "electronics", value: 65_000, brand: "Apple")
        #expect(laptop.closeupRequest == "Moove isn't sure which model this is. A photo of the model sticker on the bottom would pin down its price.")
    }

    @Test func noAskWhenSureOrNoHintOrStillIdentifying() {
        #expect(item("MacBook", category: "electronics", confidence: .high).closeupRequest == nil)
        #expect(item("MacBook", category: "electronics", hint: "").closeupRequest == nil)
        #expect(item("MacBook", category: "electronics", hint: nil).closeupRequest == nil)
        #expect(item("MacBook", category: "electronics", confidence: nil).closeupRequest == nil)
        #expect(item("MacBook", category: "electronics", status: .running).closeupRequest == nil)
    }

    @Test func cheapGenericThingsDontAsk() {
        #expect(item("Black mesh office chair", category: "chair", value: 4_000).closeupRequest == nil)
        // unpriced and generic: nothing suggests the model matters
        #expect(item("Floor lamp", category: "lamp").closeupRequest == nil)
    }

    @Test func valuableOrBrandedThingsAsk() {
        #expect(item("Office chair", category: "chair", value: 30_000).closeupRequest != nil)
        #expect(item("Office chair", category: "chair", brand: "Herman Miller").closeupRequest != nil)
        #expect(item("Monitor", category: "electronics", value: 5_000).closeupRequest != nil)
    }

    @Test func tidiesTheHint() {
        #expect(item("TV", category: "tv", hint: "  The label on the back. ").closeupPhoto == "label on the back")
        #expect(item("TV", category: "tv", hint: "a model sticker").closeupPhoto == "model sticker")
    }
}

/// Rio's hotel rooms (Oct 24): fixtures were priced and counted in sales, and some estimates
/// came from a single listing.
@Suite struct PriceTrustTests {
    func item(_ name: String, _ category: String, value: Int64? = 4_800, disposition: Disposition = .sell) -> Item {
        Item(id: 1, owner: "me", roomId: 1, name: name, category: category, widthM: 0.5, heightM: 0.8, depthM: 0.7,
             estValueCents: value, disposition: disposition, pricingStatus: .done)
    }

    @Test func fixturesStayWithTheBuilding() {
        for (n, c) in [("white two-piece elongated toilet", "appliance"), ("white alcove bathtub with apron front", "appliance"),
                       ("gray cast iron column radiator", "other"), ("sink", "sink"), ("Bath tub", "other")] {
            let it = item(n, c)
            #expect(it.isBuiltInFixture, "\(n)")
            #expect(it.priceState == .builtIn)
            #expect(it.saleValueCents == nil)
        }
        for (n, c) in [("shower caddy", "decor"), ("toilet paper", "decor"), ("oil radiator heater", "appliance"), ("office chair", "chair")] {
            #expect(!item(n, c).isBuiltInFixture, "\(n)")
        }
    }

    @Test func salesTotalsSkipFixtures() {
        let items = [item("white two-piece elongated toilet", "appliance", value: 4_800), item("office chair", "chair", value: 3_000)]
        #expect(Review.totals(items).expectedSaleCents == 3_000)
    }

    @Test func oneOrTwoListingsIsRough() {
        #expect(Item.isRoughEstimate(compCount: 1))
        #expect(Item.isRoughEstimate(compCount: 2))
        #expect(!Item.isRoughEstimate(compCount: 3))
        #expect(!Item.isRoughEstimate(compCount: 0), "no recorded listings (seeded / demo) isn't flagged")
        var s = SyncSnapshot()
        s.comps = [Comp(id: 1, itemId: 9, source: "fb", title: "a", priceCents: 1, url: ""), Comp(id: 2, itemId: 9, source: "fb", title: "b", priceCents: 1, url: "")]
        #expect(s.compCounts[9] == 2)
    }
}
