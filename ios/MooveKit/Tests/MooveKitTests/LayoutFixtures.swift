import Foundation
@testable import MooveKit

/// Inventories for the designer-layout tests and previews.
enum LayoutFixtures {
    /// What New Home lays out in the offline demo: the demo's kept items plus the bought mattress.
    static var demoFurniture: [LayoutItem] {
        let demo = DemoFixtures.demo(owner: "demo")
        return demo.items.filter { $0.disposition == .keep }.map(LayoutItem.init) + demo.boughtLayoutItems
    }

    /// A 3 bed / 2 bath listing with no floor plan (the imported homes' rooms).
    static var estimated3b2b: FloorPlan { EstimatedFloorPlan.build(beds: 3, baths: 2, sqft: nil) }

    /// Kept items like the iPad's scan 9 (the bunk room) plus a bathroom scan: RoomPlan names and sizes.
    static let scan9: [LayoutItem] = [
        LayoutItem(id: 901, name: "Bed", category: "bed", widthM: 1.56, depthM: 2.08, heightM: 0.57),
        LayoutItem(id: 902, name: "Bunk bed", category: "bed", widthM: 1.08, depthM: 2.06, heightM: 1.47),
        LayoutItem(id: 903, name: "Table", category: "table", widthM: 1.2, depthM: 0.8, heightM: 0.75),
        LayoutItem(id: 904, name: "Chair", category: "chair", widthM: 0.5, depthM: 0.52, heightM: 0.85),
        LayoutItem(id: 905, name: "Chair", category: "chair", widthM: 0.5, depthM: 0.52, heightM: 0.85),
        LayoutItem(id: 906, name: "Storage", category: "storage", widthM: 1.0, depthM: 0.5, heightM: 0.9),
        LayoutItem(id: 907, name: "Storage", category: "storage", widthM: 0.45, depthM: 0.4, heightM: 0.55),
        LayoutItem(id: 908, name: "Lamp", category: "lamp", widthM: 0.3, depthM: 0.3, heightM: 0.45),
        LayoutItem(id: 909, name: "Television", category: "television", widthM: 1.1, depthM: 0.25, heightM: 0.7),
        LayoutItem(id: 910, name: "Toilet", category: "toilet", widthM: 0.4, depthM: 0.7, heightM: 0.75),
        LayoutItem(id: 911, name: "Sink", category: "sink", widthM: 0.6, depthM: 0.5, heightM: 0.85),
        LayoutItem(id: 912, name: "Bathtub", category: "bathtub", widthM: 0.75, depthM: 1.6, heightM: 0.55),
        LayoutItem(id: 913, name: "Sofa", category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.85),
    ]

    /// Lisa's case: the same bedroom scanned three times, every scan's kept items sent to New Home.
    static var rescannedBedroom: [LayoutItem] {
        (0..<3).flatMap { scan -> [LayoutItem] in
            let base = UInt64(700 + scan * 10)
            return [
                LayoutItem(id: base + 1, name: "Bed", category: "bed", widthM: 1.56 + Double(scan) * 0.02, depthM: 2.08, heightM: 0.57),
                LayoutItem(id: base + 2, name: "Storage", category: "storage", widthM: 0.45, depthM: 0.4, heightM: 0.55),
                LayoutItem(id: base + 3, name: "Lamp", category: "lamp", widthM: 0.3, depthM: 0.3, heightM: 0.45),
                LayoutItem(id: base + 4, name: "Chair", category: "chair", widthM: 0.5, depthM: 0.52, heightM: 0.85),
            ]
        }
    }
}
