import Testing
@testable import MooveKit

@Suite struct PriceStateTests {
    func item(photo: Bool = true, value: Int64? = nil, details: AgentStage? = nil, pricing: AgentStage? = nil, name: String = "Chair") -> Item {
        Item(id: 1, owner: "me", roomId: 1, name: name, category: name.lowercased(), widthM: 0.5, heightM: 1, depthM: 0.5,
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

    /// A raw RoomPlan "storage" box whose photo never uploaded: nothing can name or price it.
    @Test func aGenericItemWithNoPhotoNeedsAPhoto() {
        #expect(item(photo: false, details: .pending, pricing: .pending, name: "storage").priceState == .needsPhoto)
        #expect(item(photo: false, details: .pending, pricing: .failed, name: "other").priceState == .needsPhoto)
        #expect(item(photo: true, details: .pending, pricing: .pending, name: "storage").priceState == .identifying)
        #expect(item(photo: false, value: 3000, name: "storage").priceState == .priced(3000))
    }

    @Test func unknownStatusFallsBackToPricing() {
        #expect(item().priceState == .pricing)
    }
}
