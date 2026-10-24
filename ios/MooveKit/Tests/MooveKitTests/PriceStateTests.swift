import Testing
@testable import MooveKit

@Suite struct PriceStateTests {
    func item(photo: Bool = true, value: Int64? = nil, details: AgentStage? = nil, pricing: AgentStage? = nil) -> Item {
        Item(id: 1, owner: "me", roomId: 1, name: "Chair", category: "chair", widthM: 0.5, heightM: 1, depthM: 0.5,
             photoUrls: photo ? ["https://x/a.jpg"] : [], estValueCents: value, detailsStatus: details, pricingStatus: pricing)
    }

    @Test func pricedWinsOverEverything() {
        #expect(item(value: 4200, details: .pending, pricing: .failed).priceState == .priced(4200))
    }

    @Test func waitsForVisionOnlyWhenThereIsAPhoto() {
        #expect(item(details: .pending, pricing: .pending).priceState == .identifying)
        #expect(item(details: .running, pricing: .pending).priceState == .identifying)
        #expect(item(photo: false, details: .pending, pricing: .pending).priceState == .pricing)
        #expect(item(details: .done, pricing: .running).priceState == .pricing)
    }

    @Test func failedPricingSaysSo() {
        #expect(item(details: .done, pricing: .failed).priceState == .unpriced)
    }

    @Test func unknownStatusFallsBackToPricing() {
        #expect(item().priceState == .pricing)
    }
}
