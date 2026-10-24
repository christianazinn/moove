import Foundation
import Testing
@testable import MooveKit

/// `LayoutSolver.solve(_:style:around:)` (#184): photo-only items placed around a scan's furniture.
@Suite struct LayoutSolverAroundTests {
    /// An L-shaped bedroom (the notch is x > 2.5, y > 2.5) with a door on the bottom wall.
    let room = FloorPlanRoom(name: "Bedroom", polygon: [
        PlanPoint(0, 0), PlanPoint(5, 0), PlanPoint(5, 2.5), PlanPoint(2.5, 2.5), PlanPoint(2.5, 4.5), PlanPoint(0, 4.5),
    ])
    var plan: FloorPlan { FloorPlan(rooms: [room], doors: [WallOpening(from: PlanPoint(3.5, 0), to: PlanPoint(4.4, 0))]) }

    /// Scanned pieces: a bed against the left wall and a dresser turned 30°.
    let scannedItems = [
        LayoutItem(id: 1, name: "Bed", category: "bed", widthM: 1.5, depthM: 2.0, heightM: 0.6),
        LayoutItem(id: 2, name: "Dresser", category: "dresser", widthM: 1.0, depthM: 0.5, heightM: 0.9),
    ]
    let fixed = [
        Placement(itemId: 1, room: "Bedroom", x: 1.05, y: 3.4, rotationDeg: 90),
        Placement(itemId: 2, room: "Bedroom", x: 3.6, y: 1.6, rotationDeg: 30),
    ]
    /// Added by the photo sweep: no scanned position.
    let photoItems = [
        LayoutItem(id: 10, name: "Sofa", category: "sofa", widthM: 2.0, depthM: 0.9, heightM: 0.8),
        LayoutItem(id: 11, name: "Desk", category: "desk", widthM: 1.2, depthM: 0.6, heightM: 0.75),
        LayoutItem(id: 12, name: "Chair", category: "chair", widthM: 0.5, depthM: 0.5, heightM: 0.9),
        LayoutItem(id: 13, name: "Bookshelf", category: "bookshelf", widthM: 0.8, depthM: 0.3, heightM: 1.8),
    ]

    func rect(_ p: Placement, _ items: [LayoutItem]) -> OrientedRect {
        let item = items.first { $0.id == p.itemId }!
        return OrientedRect(center: PlanPoint(p.x, p.y), halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: p.rotationDeg)
    }

    var option: LayoutOption {
        LayoutSolver(plan: plan).solve(scannedItems + photoItems, style: .byFunction, around: fixed)
    }

    @Test func fixedPlacementsAreUnchanged() {
        let out = option.placements
        for p in fixed { #expect(out.filter { $0.itemId == p.itemId } == [p]) }
    }

    @Test func newItemsAvoidTheScannedFurniture() {
        let all = scannedItems + photoItems
        let new = option.placements.filter { p in !fixed.contains { $0.itemId == p.itemId } }
        #expect(Set(new.map(\.itemId)) == Set(photoItems.map(\.id)))
        for p in new {
            let r = rect(p, all)
            for f in fixed { #expect(!r.overlaps(rect(f, all)), "item \(p.itemId) overlaps scanned item \(f.itemId)") }
            for q in new where q.itemId > p.itemId { #expect(!r.overlaps(rect(q, all)), "\(p.itemId) overlaps \(q.itemId)") }
            for door in LayoutSolver(plan: plan).doorKeepOuts() { #expect(!r.overlaps(door), "item \(p.itemId) blocks the door") }
        }
    }

    @Test func newItemsStayInsideTheRoomPolygon() {
        let all = scannedItems + photoItems
        for p in option.placements where !fixed.contains(where: { $0.itemId == p.itemId }) {
            #expect(p.room == "Bedroom")
            #expect(LayoutSolver.inside(rect(p, all), room), "item \(p.itemId) pokes out of the room")
            // And clear of the notch, sampled.
            let r = rect(p, all)
            for u in stride(from: -1.0, through: 1.0, by: 0.25) {
                for v in stride(from: -1.0, through: 1.0, by: 0.25) {
                    let q = r.center + r.axes.x * (u * r.halfWidth * 0.999) + r.axes.z * (v * r.halfDepth * 0.999)
                    #expect(!(q.x > 2.5 + 1e-6 && q.y > 2.5 + 1e-6), "item \(p.itemId) covers the notch")
                }
            }
        }
    }

    @Test func itemsThatCantFitAreUnplaced() {
        let huge = LayoutItem(id: 20, name: "Sectional", category: "sofa", widthM: 4.8, depthM: 3.0, heightM: 0.8)
        let option = LayoutSolver(plan: plan).solve(scannedItems + photoItems + [huge], style: .byFunction, around: fixed)
        #expect(option.unplaced == [20])
        #expect(!option.placements.contains { $0.itemId == 20 })
    }

    @Test func roomFullOfScannedFurnitureLeavesTheRestUnplaced() {
        // One fixed slab covering the whole long arm: a sofa can't go anywhere.
        let slab = LayoutItem(id: 30, name: "Platform", category: "bed", widthM: 4.9, depthM: 2.4, heightM: 0.3)
        let tall = LayoutItem(id: 31, name: "Wardrobe", category: "storage", widthM: 2.4, depthM: 1.9, heightM: 2)
        let option = LayoutSolver(plan: plan).solve([slab, tall, photoItems[0]], style: .byFunction, around: [
            Placement(itemId: 30, room: "Bedroom", x: 2.5, y: 1.25),
            Placement(itemId: 31, room: "Bedroom", x: 1.25, y: 3.5),
        ])
        #expect(option.unplaced == [10])
    }

    @Test func sizesCanComeFromFixedItems() {
        let a = LayoutSolver(plan: plan).solve(photoItems, style: .byFunction, around: fixed, fixedItems: scannedItems)
        #expect(a == option)
    }

    @Test func noFixedPlacementsMatchesPlainSolve() {
        for style in LayoutSolver.Style.allCases {
            let solver = LayoutSolver(plan: DemoHouse.floorPlan)
            let items = DemoFixtures.inventory(owner: "me").items.map(LayoutItem.init)
            #expect(solver.solve(items, style: style, around: []) == solver.solve(items, style: style))
        }
    }

    @Test func wholeBoxMustBeInsideNotJustCorners() {
        // A diamond centered on the L's inner corner: every corner is in the room or on its edge,
        // but the box covers part of the notch.
        let diamond = OrientedRect(center: PlanPoint(2.5, 2.5), halfWidth: 0.5.squareRoot(), halfDepth: 0.5.squareRoot(), rotationDeg: 45)
        #expect(diamond.corners.allSatisfy { room.contains($0) || abs($0.x - 2.5) < 1e-6 || abs($0.y - 2.5) < 1e-6 })
        #expect(!LayoutSolver.inside(diamond, room))
        #expect(LayoutSolver.inside(OrientedRect(center: PlanPoint(1, 1), halfWidth: 0.5, halfDepth: 0.5, rotationDeg: 30), room))
    }
}
