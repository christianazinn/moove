import Testing
@testable import MooveKit

/// What the scan and the vision agent actually hand the renderer: RoomPlan's raw categories,
/// the vision agent's categories, and the broad ones older rows still carry ("furniture").
/// Anything recognizable must get its own model instead of falling back to a kraft box.
struct VoxelRoutingTests {
    func kind(_ cat: String, _ name: String, _ w: Double = 0, _ d: Double = 0, _ h: Double = 0) -> VoxelModels.Kind {
        VoxelModels.kind(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h))
    }

    @Test func roomPlanCategories() {
        // String(describing: CapturedRoom.Object.Category) as the scan writes it, with its default name
        #expect(kind("television", "Television") == .tv)
        #expect(kind("refrigerator", "Refrigerator") == .appliance)
        #expect(kind("washerDryer", "Washer/dryer") == .appliance)
        #expect(kind("stove", "Stove") == .stove)
        #expect(kind("oven", "Oven") == .stove)
        #expect(kind("dishwasher", "Dishwasher") == .dishwasher)
        #expect(kind("table", "Table") == .table)
        #expect(kind("storage", "Storage") == .bookshelf)
    }

    @Test func broadCategoryUsesTheName() {
        let cases: [(String, String, VoxelModels.Kind)] = [
            ("furniture", "Black standing desk", .desk),
            ("furniture", "White IKEA Malm desk with drawers", .desk),
            ("furniture", "Black mesh office desk chair", .chair),
            ("furniture", "Brass desk lamp", .lamp),
            ("furniture", "Tufted beige headboard bed", .bed),
            ("furniture", "Round walnut dining table", .table),
            ("furniture", "Walnut TV stand", .dresser),
            ("furniture", "Oak entryway bench", .bench),
            ("furniture", "Gray fabric ottoman", .ottoman),
            ("furniture", "Wooden bar stool", .chair),
            ("electronics", "Samsung 55 inch TV", .tv),
            ("appliance", "Stainless microwave", .microwave),
            ("appliance", "GE gas range", .stove),
            ("appliance", "Bosch dishwasher", .dishwasher),
            ("appliance", "Front-load washing machine", .appliance),
            ("other", "Blue road bike", .bike),
            ("other", "Black hard-shell suitcase", .suitcase),
            ("nightstand", "Two-drawer nightstand", .dresser),
        ]
        for (cat, name, want) in cases { #expect(kind(cat, name) == want, "\(cat)/\(name)") }
    }

    @Test func keywordTraps() {
        #expect(kind("decor", "Orange vase") != .stove) // "range" inside "orange"
        #expect(kind("kitchenware", "Le Creuset dutch oven") == .kitchenware)
        #expect(kind("electronics", "Hair dryer") == .electronics)
        #expect(kind("sofa", "Sofa bed") == .sofa)
        #expect(kind("furniture", "Bedside table") == .dresser)
    }

    @Test func unnamedBroadCategoryGuessesFromShape() {
        #expect(kind("furniture", "Furniture", 1.4, 0.6, 0.75) == .desk)
        #expect(kind("furniture", "Furniture", 1.6, 0.9, 0.75) == .table)
        #expect(kind("furniture", "Furniture", 0.8, 0.3, 1.8) == .bookshelf)
        #expect(kind("furniture", "Furniture", 1.5, 2.0, 0.5) == .bed)
        #expect(kind("other", "Thing", 0.4, 0.3, 0.3) == .box)
        #expect(kind("other", "Thing") == .box) // no size: box
    }

    @Test func newKindsBuild() {
        for k in [VoxelModels.Kind.stove, .dishwasher, .microwave, .bench, .ottoman, .bike, .suitcase] {
            let g = VoxelModels.build(VoxelItemSpec(category: k.rawValue, name: k.rawValue, widthM: 0, depthM: 0, heightM: 0))
            #expect(g.filledCount > 0, "\(k)")
        }
    }
}
