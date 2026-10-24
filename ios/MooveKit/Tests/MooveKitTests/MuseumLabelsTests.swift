import Foundation
import Testing
@testable import MooveKit

@Suite struct MuseumLabelsTests {
    private func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double) = (0.5, 0.5, 0.5),
                      material: String? = nil, brand: String? = nil, value: Int64? = nil, scanObjectId: String? = "uuid",
                      fragile: Bool = false, sentimental: Bool = false, attributes: [String] = []) -> Item {
        Item(id: id, owner: "me", roomId: 1, scanObjectId: scanObjectId, name: name, category: category,
             widthM: dims.0, heightM: dims.1, depthM: dims.2, material: material, brand: brand, estValueCents: value,
             fragile: fragile, maybeSentimental: sentimental, attributes: attributes)
    }

    private func item(_ name: String, _ category: String, _ dims: (Double, Double, Double) = (0.5, 0.5, 0.5),
                      material: String? = nil, brand: String? = nil, value: Int64? = nil, scanObjectId: String? = "uuid",
                      fragile: Bool = false, sentimental: Bool = false, attributes: [String] = []) -> Item {
        item(1, name, category, dims, material: material, brand: brand, value: value, scanObjectId: scanObjectId,
             fragile: fragile, sentimental: sentimental, attributes: attributes)
    }

    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let us = Locale(identifier: "en_US")

    // MARK: Halls

    @Test func demoBedroomSpreadsAcrossFunctionHalls() {
        let items = DemoFixtures.inventory(owner: "me").items
        let hall = Dictionary(uniqueKeysWithValues: items.map { ($0.name, FunctionHall.of($0)) })
        #expect(hall["Full size metal bed frame"] == .sleep)
        #expect(hall["Nightstand"] == .sleep)
        #expect(hall["Office chair"] == .workAndStudy)
        #expect(hall["Mesh office chair"] == .workAndStudy)
        #expect(hall["IKEA Micke desk"] == .workAndStudy)
        #expect(hall["Dell 27 inch monitor"] == .workAndStudy)
        #expect(hall["IKEA Kallax shelf"] == .storage)
        #expect(hall["Floor lamp"] == .lightAndDecor)
        #expect(hall["TCL 32 inch TV"] == .media)
        #expect(hall["Yamaha acoustic guitar"] == .music)
        #expect(hall["Bean bag"] == .sitAndLounge)
        #expect(hall["Mini fridge"] == .kitchenAndDining)
    }

    @Test func chairsGoWhereTheyAreUsed() {
        #expect(FunctionHall.of(item("Desk chair", "chair")) == .workAndStudy)
        #expect(FunctionHall.of(item("Chair", "chair", attributes: ["ChairType.swivel"])) == .workAndStudy)
        #expect(FunctionHall.of(item("Dining chair", "chair")) == .kitchenAndDining)
        #expect(FunctionHall.of(item("Chair", "chair", attributes: ["ChairType.dining"])) == .kitchenAndDining)
        #expect(FunctionHall.of(item("Armchair", "chair")) == .sitAndLounge)
        #expect(FunctionHall.of(item("Chair", "chair")) == .sitAndLounge)
        #expect(FunctionHall.of(item("Coffee table", "table", (1.0, 0.45, 0.6))) == .sitAndLounge)
        #expect(FunctionHall.of(item("Dining table", "table", (1.6, 0.75, 0.9))) == .kitchenAndDining)
    }

    @Test func wordsAndKindsPickTheRestOfTheHalls() {
        #expect(FunctionHall.of(item("Queen mattress", "bed", (1.5, 0.3, 2.0))) == .sleep)
        #expect(FunctionHall.of(item("Sofa", "sofa", (2.0, 0.85, 0.9))) == .sitAndLounge)
        #expect(FunctionHall.of(item("Sonos speaker", "electronics")) == .media)
        #expect(FunctionHall.of(item("Microwave", "microwave")) == .kitchenAndDining)
        #expect(FunctionHall.of(item("Washer", "washerDryer", (0.6, 0.85, 0.6))) == .bathAndLaundry)
        #expect(FunctionHall.of(item("Hair dryer", "electronics", (0.2, 0.25, 0.1))) != .bathAndLaundry)
        #expect(FunctionHall.of(item("Road bike", "bicycle", (1.7, 1.0, 0.5))) == .getAroundAndPlay)
        #expect(FunctionHall.of(item("Potted monstera", "plant")) == .lightAndDecor)
        #expect(FunctionHall.of(item("Dresser", "storage", (1.2, 0.8, 0.5))) == .storage)
        #expect(FunctionHall.of(item("Casio keyboard", "electronics", (1.0, 0.1, 0.3))) == .music)
        #expect(FunctionHall.of(item("Mechanical keyboard", "electronics", (0.45, 0.04, 0.15))) == .workAndStudy)
        #expect(FunctionHall.of(item("Dog bed", "other")) == .everythingElse)
        #expect(FunctionHall.of(item("Vacuum", "vacuum", (0.3, 1.1, 0.3))) == .everythingElse)
    }

    @Test func hallsAreBiggestFirstWithCuriositiesLast() {
        let items = [
            item(1, "Vacuum", "vacuum", (0.3, 1.1, 0.3)), item(2, "Fan", "fan"), item(3, "Step ladder", "ladder", (0.5, 1.5, 0.1)),
            item(4, "Bed", "bed", (1.4, 0.4, 2.0), value: 5_000), item(5, "Nightstand", "storage"),
            item(6, "Floor lamp", "lamp", (0.3, 1.7, 0.3), value: 2_000),
        ]
        let halls = FunctionHall.halls(items)
        #expect(halls.map(\.hall) == [.sleep, .lightAndDecor, .everythingElse])
        #expect(halls[0].items.map(\.id) == [4, 5], "priced first")
        #expect(FunctionHall.subtitle(halls[0].items) == "2 pieces · est. $50")
        #expect(FunctionHall.sleep.title == "The Sleep Hall")
        #expect(FunctionHall.everythingElse.title == "Cabinet of Curiosities")
    }

    // MARK: Placard lines

    @Test func catalogLineReadsLikeAMuseumLabel() {
        #expect(MuseumLabel.catalogLine(item("Bed", "bed", (1.4, 0.5, 1.95), material: "oak", brand: "IKEA")) == "Oak, IKEA · 140 × 195 cm")
        // Upright pieces show their face (W × H).
        #expect(MuseumLabel.catalogLine(item("TV", "television", (0.73, 0.48, 0.18))) == "Television · 73 × 48 cm")
        // Estimated sizes say so; unmeasured ones show none.
        #expect(MuseumLabel.catalogLine(item("Plant", "plant", (0.4, 0.9, 0.4), scanObjectId: "photo:3")) == "Plant · ≈40 × 90 cm")
        #expect(MuseumLabel.catalogLine(item("Road bike", "bicycle", (1.7, 1.0, 0.5), scanObjectId: nil)) == "Bicycle · ≈170 × 100 cm")
        #expect(MuseumLabel.catalogLine(item("Lamp", "lamp", (0, 0, 0), scanObjectId: nil)) == "Lamp")
        #expect(MuseumLabel.catalogLine(item("Washer", "washerDryer", (0, 0, 0))) == "Washer dryer")
    }

    @Test func acquiredLineIsHonestAboutDates() {
        let date = Date(timeIntervalSince1970: 1_792_800_000) // Oct 24, 2026 UTC
        #expect(MuseumLabel.acquiredLine(cataloguedAt: date, story: nil, now: date, calendar: utc, locale: us) == "Catalogued Oct 24, 2026")
        #expect(MuseumLabel.acquiredLine(cataloguedAt: date, story: "Grandma's, 1974", now: date, calendar: utc, locale: us)
                == "Acquired 1974 · catalogued Oct 24, 2026")
        #expect(MuseumLabel.storyYear("Grandma's, 1974", now: date, calendar: utc) == 1974)
        #expect(MuseumLabel.storyYear("Room 12345 on 2099", now: date, calendar: utc) == nil, "too long, and in the future")
        #expect(MuseumLabel.storyYear("Since 1850", now: date, calendar: utc) == nil)
        #expect(MuseumLabel.storyYear("From the 1990s flat", now: date, calendar: utc) == 1990)
    }

    @Test func autoStoryPicksTheMostTellingTruth() {
        #expect(MuseumLabel.autoStory(item("Guitar", "instrument", value: 10_900, sentimental: true))
                == "Possibly sentimental. Moove leaves this one to you.")
        var decided = item("Guitar", "instrument", value: 10_900, sentimental: true)
        decided.disposition = .keep
        decided.dispositionSource = .user
        #expect(MuseumLabel.autoStory(decided) == "Coming along: your call.")
        // ~$30 chair, 0.4 m³ → ~$24 to move: keep needs $30+, so selling wins.
        let chair = item("Mesh office chair", "chair", (0.64, 1.02, 0.62), value: 3_000)
        #expect(MuseumLabel.autoStory(chair) == "Worth ~$30, cheaper to sell than to move.")
        #expect(MuseumLabel.autoStory(chair, isTopPiece: true) == "Worth ~$30, the hall's most valuable piece.")
        #expect(MuseumLabel.autoStory(item("Mug", "kitchenware", (0.1, 0.1, 0.1), value: 500)) == "Worth ~$5, too little to list.")
        #expect(MuseumLabel.autoStory(item("Vase", "decor", (0.2, 0.3, 0.2), value: 6_000, fragile: true)) == "Fragile; handle with care.")
        #expect(MuseumLabel.autoStory(item("Plant", "plant", scanObjectId: "photo:3")) == "Spotted in the room photos; size estimated.")
        #expect(MuseumLabel.autoStory(item("Box", "box", scanObjectId: nil)) == "Added by hand.")
        #expect(MuseumLabel.autoStory(item("Toilet", "toilet")) == "Part of the building; it stays.")
        #expect(MuseumLabel.autoStory(item("Box", "box")) == "Measured by the LiDAR scan.")
    }

    @Test func smallHelpers() {
        #expect(MuseumLabel.piecesLine(pieces: 12, valueCents: 104_900) == "12 pieces · est. $1,049")
        #expect(MuseumLabel.piecesLine(pieces: 1, valueCents: 0) == "1 piece")
        #expect(MuseumLabel.fromRoom("Bedroom") == "from the Bedroom")
        #expect(MuseumLabel.fromRoom("My room") == "from My room")
        #expect(MuseumLabel.dollars(123_456_789) == "$1,234,568")
        #expect(MuseumLabel.topPiece([item(1, "a", "box", value: 100), item(2, "b", "box", value: 900), item(3, "c", "box")]) == 2)
        #expect(MuseumLabel.topPiece([item(1, "a", "box")]) == nil)
    }

    // MARK: Stories

    @Test func storiesRoundTripAndStayOneShortLine() {
        var json = ItemStories.setting("Grandma's, 1974", for: 18, in: "")
        json = ItemStories.setting("  first\ncamera  ", for: 7, in: json)
        #expect(ItemStories.decode(json) == [18: "Grandma's, 1974", 7: "first camera"])
        json = ItemStories.setting("   ", for: 18, in: json)
        #expect(ItemStories.decode(json) == [7: "first camera"])
        #expect(ItemStories.clean(String(repeating: "x", count: 100))?.count == ItemStories.maxLength)
        #expect(ItemStories.decode("not json").isEmpty)
        #expect(ItemStories.decode(#"{"abc":"x","5":""}"#).isEmpty)
    }
}
