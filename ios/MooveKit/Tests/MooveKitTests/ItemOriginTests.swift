import Testing
@testable import MooveKit

@Suite struct ItemOriginTests {
    func item(_ scanObjectId: String?, _ w: Double, _ h: Double, _ d: Double) -> Item {
        Item(id: 1, owner: "me", roomId: 1, scanObjectId: scanObjectId, name: "x", category: "other", widthM: w, heightM: h, depthM: d)
    }

    @Test func tellsScannedSweptAndPhotographedItemsApart() {
        #expect(item("59B5C0DE-0000-0000-0000-000000000000", 0.5, 0.9, 0.5).origin == .scan)
        #expect(item("demo-11", 0.7, 1.1, 0.7).origin == .scan)
        #expect(item("photo:42", 0.4, 1.0, 0.12).origin == .roomPhotos)
        #expect(item("7A1E0000-0000-0000-0000-000000000000", 0, 0, 0).origin == .photo)
        #expect(item(nil, 0, 0, 0).origin == .photo)
    }
}
