import Foundation
import Testing
@testable import MooveKit

@Suite struct ShoppingThumbnailsTests {
    private func route(_ spec: VoxelItemSpec) -> VoxelModels.Kind {
        VoxelModels.route(category: spec.category, name: VName(spec.name.lowercased()), attrs: Set(spec.attributes))
    }

    @Test func sizesComeFromTheNameThenCategory() {
        #expect(ShoppingThumbnails.size(name: "Desk chair", category: "furniture").category == "chair")
        #expect(ShoppingThumbnails.size(name: "Dining table", category: "").widthM == 1.5)
        #expect(ShoppingThumbnails.size(name: "Area rug", category: "decor").category == "rug")
        #expect(ShoppingThumbnails.size(name: "Mattress", category: "bed").category == "mattress")
        let fallback = ShoppingThumbnails.size(name: "Thing", category: "")
        #expect(fallback.category == "decor")
        #expect(fallback.widthM > 0 && fallback.depthM > 0 && fallback.heightM > 0)
    }

    @Test func everyDemoItemAndDealGetsARecognizableModel() {
        let s = DemoFixtures.demo(owner: "me")
        let expected: [String: VoxelModels.Kind] = [
            "Mattress": .mattress, "Sofa": .sofa, "Desk chair": .chair, "Dining table": .table, "Area rug": .rug,
        ]
        for item in s.myShoppingItems {
            let spec = ShoppingThumbnails.spec(for: item)
            #expect(route(spec) == expected[item.name], "\(item.name)")
            #expect(VoxelModels.build(spec).filledCount > 0)
            for deal in s.deals(for: item.id) {
                let dealSpec = ShoppingThumbnails.spec(for: deal, item: item)
                #expect(dealSpec.name == deal.title)
                #expect(dealSpec.widthM == spec.widthM)
                #expect(VoxelModels.build(dealSpec).filledCount > 0)
            }
        }
    }
}
