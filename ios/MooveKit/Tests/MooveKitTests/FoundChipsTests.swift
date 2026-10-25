import Testing
@testable import MooveKit

struct FoundChipsTests {
    @Test func countsNewestFirstAndHidesUnreliableKinds() {
        let counts = FoundChips.counts(["bicycle", "vacuum", "plant", "bicycle", "bin", "Toy"])
        #expect(counts.map(\.name) == ["plant", "bicycle"])
        #expect(counts.first { $0.name == "bicycle" }?.n == 2)
    }

    @Test func onlyUnreliableKindsShowNothing() {
        #expect(FoundChips.counts(["vacuum", "heater"]).isEmpty)
    }

    @Test func hiddenKindsAreDetectorCategories() {
        let categories = Set(ObjectVocabulary.categories.values)
        #expect(FoundChips.hiddenCategories.isSubset(of: categories))
    }
}
