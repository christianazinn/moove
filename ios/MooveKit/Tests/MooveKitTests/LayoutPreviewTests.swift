import Foundation
import Testing
@testable import MooveKit

/// Writes top-down SVGs of the designer layouts when `MOOVE_LAYOUT_SVG_DIR` is set
/// (for looking at them; nothing is checked beyond the SVG being well formed).
@Suite struct LayoutPreviewTests {
    static let cases: [(String, FloorPlan, [LayoutItem])] = [
        ("demo-house", DemoHouse.floorPlan, LayoutFixtures.demoFurniture),
        ("estimated-3b2b-scan9", LayoutFixtures.estimated3b2b, LayoutFixtures.scan9),
        ("estimated-3b2b-rescans", LayoutFixtures.estimated3b2b, LayoutFixtures.rescannedBedroom),
        ("demo-house-scan9", DemoHouse.floorPlan, LayoutFixtures.scan9),
        ("demo-house-furnished", DemoHouse.floorPlan, DesignLayoutTests.livingSet),
        ("estimated-3b2b-furnished", LayoutFixtures.estimated3b2b, DesignLayoutTests.livingSet),
    ]

    @Test func previews() throws {
        let dir = ProcessInfo.processInfo.environment["MOOVE_LAYOUT_SVG_DIR"]
        for (name, plan, items) in Self.cases {
            let placer = PropPlacer(plan: plan)
            for option in LayoutSolver(plan: plan).solveAll(items) {
                let placed = placer.place(option.placements, items: items)
                let title = "\(name) · \(option.name) · \(placed.count) placed, \(option.unplaced.count) not placed"
                let svg = LayoutPreview.svg(plan: plan, items: items, placements: placed, title: title)
                #expect(svg.hasPrefix("<svg") && svg.hasSuffix("</svg>\n"))
                if let dir {
                    let file = URL(fileURLWithPath: dir).appendingPathComponent("\(name)-\(option.style.rawValue).svg")
                    try svg.write(to: file, atomically: true, encoding: .utf8)
                }
            }
        }
    }
}
