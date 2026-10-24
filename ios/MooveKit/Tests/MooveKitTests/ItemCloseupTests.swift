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

    @Test func reviewListsMostValuableFirst() {
        var a = item("Monitor", category: "electronics", value: 12_000); a.id = 1
        var b = item("Laptop", category: "electronics", value: 65_000); b.id = 2
        var c = item("Chair", category: "chair", value: 2_000); c.id = 3
        #expect(Review.wantingCloseups([a, b, c]).map(\.id) == [2, 1])
    }
}
