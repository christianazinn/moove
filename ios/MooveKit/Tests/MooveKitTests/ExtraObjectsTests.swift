import Foundation
import Testing
@testable import MooveKit

/// Points sampled on the surface of an upright box (what LiDAR sees), plus noise.
private func boxPoints(center: SIMD3<Float>, size: SIMD3<Float>, yaw: Float, count: Int = 800,
                       seed: UInt64 = 1, outliers: Int = 0) -> [SIMD3<Float>] {
    var rng = SplitMix(seed: seed)
    let t = RoomTransform.at(center, yaw: yaw)
    var pts: [SIMD3<Float>] = (0..<count).map { _ in
        // Random point on one of the four vertical faces or the top.
        let face = Int(rng.next() % 5)
        var p = SIMD3<Float>(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * size
        switch face {
        case 0: p.x = -size.x / 2
        case 1: p.x = size.x / 2
        case 2: p.z = -size.z / 2
        case 3: p.z = size.z / 2
        default: p.y = size.y / 2
        }
        return t.apply(p) + SIMD3(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * 0.01
    }
    for _ in 0..<outliers { pts.append(center + SIMD3(rng.unit() * 6 - 3, rng.unit() * 2, rng.unit() * 6 - 3)) }
    return pts
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() % 1_000_000) / 1_000_000 }
}

@Suite struct BoxFitTests {
    // A bike: 1.7 m long, 1.0 m tall, 0.6 m wide (handlebars), turned 30°, standing on the floor.
    let bike = (center: SIMD3<Float>(1.2, 0.5, -0.8), size: SIMD3<Float>(1.7, 1.0, 0.6), yaw: Float(30 * Double.pi / 180))

    @Test func recoversSizePositionAndYaw() throws {
        let fit = try #require(BoxFit.fit(boxPoints(center: bike.center, size: bike.size, yaw: bike.yaw), floorY: 0))
        #expect(abs(fit.size.x - 1.7) < 0.15)
        #expect(abs(fit.size.y - 1.0) < 0.1)
        #expect(abs(fit.size.z - 0.6) < 0.12)
        #expect(abs(fit.center.x - 1.2) < 0.08 && abs(fit.center.z + 0.8) < 0.08)
        #expect(abs(fit.center.y - 0.5) < 0.06)
        // Yaw is only defined mod 180° for a box.
        let dyaw = abs(remainder(fit.yaw - bike.yaw, .pi))
        #expect(dyaw < 0.1)
    }

    @Test func ignoresStrayDepthSamples() throws {
        let fit = try #require(BoxFit.fit(boxPoints(center: bike.center, size: bike.size, yaw: bike.yaw, outliers: 20), floorY: 0))
        #expect(abs(fit.size.x - 1.7) < 0.25)
    }

    @Test func extendsToTheFloorOnlyWhenClose() throws {
        // A plant whose LiDAR points start 10 cm up (pot rim occluded) still stands on the floor...
        var pts = boxPoints(center: SIMD3(0, 0.6, 0), size: SIMD3(0.4, 1.0, 0.4), yaw: 0)
        let low = try #require(BoxFit.fit(pts, floorY: 0))
        #expect(abs((low.center.y - low.size.y / 2)) < 0.02)
        // ...but a suitcase on top of a 0.9 m dresser does not.
        pts = boxPoints(center: SIMD3(0, 1.2, 0), size: SIMD3(0.5, 0.6, 0.3), yaw: 0)
        let high = try #require(BoxFit.fit(pts, floorY: 0))
        #expect(high.center.y - high.size.y / 2 > 0.8)
    }

    @Test func needsEnoughPoints() {
        #expect(BoxFit.fit([SIMD3(0, 0, 0), SIMD3(1, 1, 1)]) == nil)
    }
}

@Suite struct SightingMergerTests {
    @Test func mergesRepeatedSightingsAndDropsOneOffs() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...4 {
            merger.add(Sighting(label: "bicycle", confidence: 0.6 + Float(seed) * 0.05,
                                points: boxPoints(center: SIMD3(1, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0, count: 300, seed: UInt64(seed))))
        }
        // A one-off phantom across the room.
        merger.add(Sighting(label: "suitcase", confidence: 0.5, points: boxPoints(center: SIMD3(-2, 0.3, 2), size: SIMD3(0.5, 0.6, 0.3), yaw: 0, seed: 9)))
        let results = merger.results()
        #expect(results.count == 1)
        #expect(results.first?.label == "bicycle")
        #expect(results.first?.sightings == 4)
        #expect(abs((results.first?.bestConfidence ?? 0) - 0.8) < 1e-5)
    }

    @Test func keepsTwoBikesApart() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            merger.add(Sighting(label: "bicycle", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0, seed: UInt64(seed))))
            merger.add(Sighting(label: "bicycle", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.5, 2.5), size: SIMD3(1.7, 1, 0.6), yaw: 0, seed: UInt64(seed + 10))))
        }
        #expect(merger.results().count == 2)
    }

    @Test func dropsThingsRoomPlanAlreadyFound() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...3 {
            merger.add(Sighting(label: "bench", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.25, 0), size: SIMD3(1.2, 0.5, 0.4), yaw: 0, seed: UInt64(seed))))
        }
        let roomPlanTable = RoomGeometry.Object(id: "t", category: "table", dimensions: SIMD3(1.3, 0.75, 0.6), transform: .at(SIMD3(0, 0.375, 0)))
        #expect(merger.results(excluding: [roomPlanTable]).isEmpty)
        #expect(merger.results().count == 1)
    }

    @Test func capsPointsPerObject() {
        var merger = SightingMerger(floorY: 0)
        merger.maxPointsPerTrack = 500
        for seed in 1...5 {
            merger.add(Sighting(label: "bicycle", confidence: 0.7, points: boxPoints(center: SIMD3(0, 0.5, 0), size: SIMD3(1.7, 1, 0.6), yaw: 0, seed: UInt64(seed))))
        }
        #expect(merger.tracks.first!.points.count <= 500)
    }
}

/// Recall tuning (#82).
@Suite struct SightingMergerRecallTests {
    let scooter = (center: SIMD3<Float>(1, 0.575, 0), size: SIMD3<Float>(1.1, 1.15, 0.45))

    @Test func keepsABigObjectSeenOnceWithConfidence() {
        var merger = SightingMerger(floorY: 0)
        merger.add(Sighting(label: "scooter", confidence: 0.74, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0)))
        #expect(merger.results().map(\.label) == ["scooter"])
    }

    @Test func dropsSmallOrUnsureOneOffs() {
        var merger = SightingMerger(floorY: 0)
        // Big but unsure.
        merger.add(Sighting(label: "scooter", confidence: 0.45, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0)))
        // Sure but small (a 30 cm vase).
        merger.add(Sighting(label: "vase", confidence: 0.9, points: boxPoints(center: SIMD3(-2, 0.15, 1), size: SIMD3(0.2, 0.3, 0.2), yaw: 0, seed: 3)))
        #expect(merger.results().isEmpty)
    }

    @Test func oneObjectWithTwoLabelsGetsTheStrongerPlausibleOne() {
        // An e-scooter that also scores as a motorcycle in every frame (real: 0.88 vs 0.82).
        var merger = SightingMerger(floorY: 0)
        for seed in 1...3 {
            let pts = boxPoints(center: scooter.center, size: scooter.size, yaw: 0, count: 300, seed: UInt64(seed))
            merger.add(Sighting(label: "motorcycle", confidence: 0.88, points: pts))
            merger.add(Sighting(label: "scooter", confidence: 0.82, points: pts))
        }
        let out = merger.results()
        #expect(out.count == 1)
        // A 1.1 m "motorcycle" is implausible, so the scooter wins despite lower scores.
        #expect(out.first?.label == "scooter")
        #expect(out.first?.sightings == 6)
    }

    @Test func moreEvidenceWinsBetweenPlausibleLabels() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...4 {
            merger.add(Sighting(label: "bicycle", confidence: 0.6, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0, count: 300, seed: UInt64(seed))))
        }
        merger.add(Sighting(label: "scooter", confidence: 0.8, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0, count: 300, seed: 9)))
        #expect(merger.results().map(\.label) == ["bicycle"])
    }

    @Test func keepsThingsStandingOnRoomPlanFurniture() {
        // A monitor on a RoomPlan desk: on top of it, not inside it.
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            merger.add(Sighting(label: "monitor", confidence: 0.8, points: boxPoints(center: SIMD3(0, 1.0, 0), size: SIMD3(0.6, 0.45, 0.2), yaw: 0, seed: UInt64(seed))))
        }
        let desk = RoomGeometry.Object(id: "d", category: "table", dimensions: SIMD3(1.4, 0.75, 0.7), transform: .at(SIMD3(0, 0.375, 0)))
        #expect(merger.results(excluding: [desk]).map(\.label) == ["monitor"])
    }

    @Test func roomPlanCategoriesOnlyFillGaps() {
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            // A chair RoomPlan also found (boxes overlap partly)...
            merger.add(Sighting(label: "chair", confidence: 0.8, points: boxPoints(center: SIMD3(0.25, 0.45, 0), size: SIMD3(0.5, 0.9, 0.5), yaw: 0, seed: UInt64(seed))))
            // ...and one it missed.
            merger.add(Sighting(label: "chair", confidence: 0.8, points: boxPoints(center: SIMD3(3, 0.45, 2), size: SIMD3(0.5, 0.9, 0.5), yaw: 0, seed: UInt64(seed + 5))))
        }
        let roomPlanChair = RoomGeometry.Object(id: "c", category: "chair", dimensions: SIMD3(0.55, 0.9, 0.55), transform: .at(SIMD3(0, 0.45, 0)))
        let out = merger.results(excluding: [roomPlanChair])
        #expect(out.count == 1)
        #expect(abs((out.first?.box.center.x ?? 0) - 3) < 0.2)
    }

    @Test func dropsABunkLadderBetweenTheBunkAndAShelf() {
        // Rio's bunk room (Oct 24): the bunk's ladder sat 38% inside the bunk and 20% inside
        // the fridge shelf (the footprint rule from #272 catches it).
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            merger.add(Sighting(label: "ladder", confidence: 0.8, points: boxPoints(center: SIMD3(0, 0.475, 0), size: SIMD3(0.6, 0.95, 0.3), yaw: 0, seed: UInt64(seed))))
        }
        let bunk = RoomGeometry.Object(id: "b", category: "bed", dimensions: SIMD3(1.1, 1.47, 2.0), transform: .at(SIMD3(0.4, 0.735, 1.0)))
        let shelf = RoomGeometry.Object(id: "s", category: "storage", dimensions: SIMD3(0.7, 1.42, 1.9), transform: .at(SIMD3(-0.25, 0.71, -0.9)))
        #expect(merger.results().count == 1)
        #expect(merger.results(excluding: [bunk, shelf]).isEmpty)
    }

    @Test func dropsAFindSunkIntoAMattress() {
        // A "mirror" (really a dark wall panel) 0.28-1.23 m up, over a bed 0.57 m tall.
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            merger.add(Sighting(label: "mirror", confidence: 0.8, points: boxPoints(center: SIMD3(0, 0.755, 0.6), size: SIMD3(0.55, 0.95, 0.17), yaw: 0, seed: UInt64(seed))))
        }
        let bed = RoomGeometry.Object(id: "b", category: "bed", dimensions: SIMD3(1.56, 0.57, 2.08), transform: .at(SIMD3(0, 0.285, 0)))
        #expect(merger.results().count == 1)
        #expect(merger.results(excluding: [bed]).isEmpty)
    }

    @Test func dropsAShowerCurtainOverTheTub() {
        // Rio's bathroom (Oct 24): a "room divider" 0.53 × 0.50 × 1.43 m standing 5 cm above
        // the tub's rim, 78% over its footprint, was the shower curtain.
        var merger = SightingMerger(floorY: 0)
        for seed in 1...2 {
            merger.add(Sighting(label: "room divider", confidence: 0.8, points: boxPoints(center: SIMD3(0.2, 0.5 + 0.715, 0), size: SIMD3(0.53, 1.43, 0.5), yaw: 0, seed: UInt64(seed))))
            // a trash can on the floor beside the tub stays
            merger.add(Sighting(label: "trash can", confidence: 0.8, points: boxPoints(center: SIMD3(1.3, 0.17, 0), size: SIMD3(0.3, 0.34, 0.3), yaw: 0, seed: UInt64(seed + 4))))
        }
        let tub = RoomGeometry.Object(id: "t", category: "bathtub", dimensions: SIMD3(1.4, 0.45, 0.77), transform: .at(SIMD3(0, 0.225, 0)))
        #expect(Set(merger.results().map(\.label)) == ["room divider", "trash can"])
        #expect(merger.results(excluding: [tub]).map(\.label) == ["trash can"])
        // the same divider over a bed is just near it, not over a tub
        let bed = RoomGeometry.Object(id: "b", category: "bed", dimensions: SIMD3(1.4, 0.45, 0.77), transform: .at(SIMD3(0, 0.225, 0)))
        #expect(merger.results(excluding: [bed]).map(\.label).contains("room divider"))
    }

    @Test func trackIDsAreStable() {
        var merger = SightingMerger(floorY: 0)
        let a = merger.add(Sighting(label: "scooter", confidence: 0.7, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0)))
        let b = merger.add(Sighting(label: "guitar", confidence: 0.7, points: boxPoints(center: SIMD3(-2, 0.5, 0), size: SIMD3(0.4, 1.0, 0.12), yaw: 0, seed: 4)))
        let a2 = merger.add(Sighting(label: "scooter", confidence: 0.7, points: boxPoints(center: scooter.center, size: scooter.size, yaw: 0, seed: 7)))
        #expect(a == 0 && b == 1 && a2 == 0)
    }
}

/// Points on just one vertical face of a box (what LiDAR sees from one side), plus noise.
private func facePoints(center: SIMD3<Float>, size: SIMD3<Float>, face: SIMD3<Float>, count: Int = 300, seed: UInt64 = 1) -> [SIMD3<Float>] {
    var rng = SplitMix(seed: seed)
    return (0..<count).map { _ in
        var p = SIMD3<Float>(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * size
        if face.x != 0 { p.x = face.x * size.x / 2 }
        if face.z != 0 { p.z = face.z * size.z / 2 }
        return center + p + SIMD3(rng.unit() - 0.5, rng.unit() - 0.5, rng.unit() - 0.5) * 0.01
    }
}

/// A 4 m x 4 m room centered on the origin: walls at x = ±2 and z = ±2.
private let squareRoom: RoomGeometry = {
    func wall(_ id: String, _ p: SIMD3<Float>, yaw: Float) -> RoomGeometry.Surface {
        .init(id: id, kind: .wall, dimensions: SIMD3(4, 2.5, 0.1), transform: .at(p, yaw: yaw))
    }
    return RoomGeometry(walls: [
        wall("n", SIMD3(0, 1.25, -2), yaw: 0), wall("s", SIMD3(0, 1.25, 2), yaw: 0),
        wall("w", SIMD3(-2, 1.25, 0), yaw: .pi / 2), wall("e", SIMD3(2, 1.25, 0), yaw: .pi / 2),
    ])
}()

private func front(_ box: FittedBox) -> SIMD2<Float> { SIMD2(sin(box.yaw), cos(box.yaw)) }

/// #267: Lisa's iPad scan. Detector boxes sat toward the camera, faced either way,
/// doubled RoomPlan objects, and one glance was enough to add an object.
@Suite struct DetectorBoxTests {
    // MARK: 1. Center: padding grows away from the camera

    @Test func paddingKeepsTheSeenFaceInPlace() {
        // A 10 cm slab (the front LiDAR saw) at z = 0, camera 3 m in front (+z).
        let seen = FittedBox(center: SIMD3(0, 0.4, 0), size: SIMD3(1.2, 0.8, 0.1), yaw: 0)
        let padded = DetectorPlacement.padDepth(seen, to: 0.5, camera: SIMD3(0, 1.4, 3))
        #expect(abs(padded.size.z - 0.5) < 1e-5)
        #expect(abs(padded.center.z - -0.2) < 1e-4)  // front face stays at z = +0.05
        #expect(abs((padded.center.z + padded.size.z / 2) - 0.05) < 1e-4)
        // Seen from behind (camera at -z), it grows the other way. Same with yaw 180°.
        #expect(abs(DetectorPlacement.padDepth(seen, to: 0.5, camera: SIMD3(0, 1.4, -3)).center.z - 0.2) < 1e-4)
        var turned = seen
        turned.yaw = .pi
        #expect(abs(DetectorPlacement.padDepth(turned, to: 0.5, camera: SIMD3(0, 1.4, 3)).center.z - -0.2) < 1e-4)
    }

    @Test func paddingIsEvenWithoutAUsefulCamera() {
        let seen = FittedBox(center: SIMD3(0, 0.4, 0), size: SIMD3(1.2, 0.8, 0.1), yaw: 0)
        #expect(DetectorPlacement.padDepth(seen, to: 0.5, camera: nil).center == seen.center)
        // Seen side-on (camera along the width axis): its depth faces weren't the near side.
        #expect(DetectorPlacement.padDepth(seen, to: 0.5, camera: SIMD3(3, 1.4, 0)).center == seen.center)
        // Already deep enough: untouched.
        #expect(DetectorPlacement.padDepth(seen, to: 0.05, camera: SIMD3(0, 1.4, 3)) == seen)
    }

    @Test func mergerKnowsWhereTheCameraWas() {
        var merger = SightingMerger(floorY: 0)
        let pts = facePoints(center: SIMD3(0, 0.5, 0), size: SIMD3(1.7, 1, 0.6), face: SIMD3(0, 0, 1))
        merger.add(Sighting(label: "bicycle", confidence: 0.8, points: pts, camera: SIMD3(-1, 1.4, 3), time: 0))
        merger.add(Sighting(label: "bicycle", confidence: 0.8, points: pts, camera: SIMD3(1, 1.4, 3), time: 1))
        let t = merger.tracks[0]
        #expect(t.camera.map { abs($0.x) < 1e-5 && abs($0.z - 3) < 1e-5 } == true)
    }

    // MARK: 2. Fit from all sightings

    @Test func boxCombinesSightingsFromDifferentSides() throws {
        // A 1.7 x 1.0 x 0.6 bike seen from the front, then from its right end.
        let center = SIMD3<Float>(1, 0.5, 0), size = SIMD3<Float>(1.7, 1, 0.6)
        var merger = SightingMerger(floorY: 0)
        merger.add(Sighting(label: "bicycle", confidence: 0.8, points: facePoints(center: center, size: size, face: SIMD3(0, 0, 1)),
                            camera: SIMD3(1, 1.4, 3), time: 0))
        let firstDepth = try #require(merger.tracks.first).box.size.z
        merger.add(Sighting(label: "bicycle", confidence: 0.8, points: facePoints(center: center, size: size, face: SIMD3(1, 0, 0), seed: 2),
                            camera: SIMD3(4, 1.4, 0), time: 2))
        let box = try #require(merger.results().first).box
        #expect(merger.tracks.count == 1)
        #expect(firstDepth < 0.1)  // one side alone is a slab
        // Both views land in one track (their near faces are 0.9 m apart, which used to
        // start a second bike) and the box is refitted from all their points. Two bare
        // faces make an L, which the min-area fit tilts a little; more views tighten it.
        #expect(abs(box.size.x - 1.7) < 0.15 && box.size.z > 0.4)
        #expect(abs(box.center.x - 1) < 0.2 && abs(box.center.z) < 0.25)
    }

    // MARK: 3. Facing

    @Test func backGoesToTheWallItStandsAgainst() {
        // A sofa-ish box 10 cm off the north wall (z = -2), fitted facing the wall.
        let box = FittedBox(center: SIMD3(0.3, 0.4, -1.5), size: SIMD3(2, 0.8, 0.8), yaw: .pi)
        let faced = DetectorPlacement.faced(box, in: squareRoom, camera: nil)
        #expect(front(faced).y > 0.99)  // front toward +z, into the room
        #expect(faced.center == box.center && faced.size == box.size)
        // Against the east wall (x = 2) with its width along it: front toward -x.
        let east = FittedBox(center: SIMD3(1.65, 0.4, 0.5), size: SIMD3(1.2, 0.8, 0.5), yaw: -.pi / 2)
        #expect(front(DetectorPlacement.faced(east, in: squareRoom, camera: nil)).x < -0.99)
    }

    @Test func freeStandingPiecesFaceTheRoomCenter() {
        // An ottoman 1 m from the south wall, fitted facing the wall: turn to the center.
        let box = FittedBox(center: SIMD3(0, 0.2, 1.0), size: SIMD3(0.6, 0.4, 0.5), yaw: 0)
        #expect(front(DetectorPlacement.faced(box, in: squareRoom, camera: nil)).y < -0.99)
        // A wall end-on to the box (its side, not its back) doesn't count as "against".
        let side = FittedBox(center: SIMD3(1.5, 0.4, 1.0), size: SIMD3(0.8, 0.8, 0.5), yaw: .pi / 2)
        let f = front(DetectorPlacement.faced(side, in: squareRoom, camera: nil))
        #expect(f.x < -0.99)  // toward the center (-x), not decided by the south wall
    }

    @Test func withoutWallsItFacesTheCamera() {
        let box = FittedBox(center: SIMD3(0, 0.4, 0), size: SIMD3(1, 0.8, 0.5), yaw: 0)
        #expect(front(DetectorPlacement.faced(box, in: RoomGeometry(), camera: SIMD3(0, 1.4, -2))).y < -0.99)
        #expect(DetectorPlacement.faced(box, in: RoomGeometry(), camera: nil) == box)
    }

    @Test func placePadsThenFaces() {
        // A bench's front slab (12 cm) seen from the room, 25 cm off the north wall.
        let o = RoomGeometry.Object(id: "b", category: "bench", dimensions: SIMD3(1.2, 0.45, 0.12),
                                    transform: .at(SIMD3(0, 0.225, -1.7), yaw: .pi))
        let placed = DetectorPlacement.place(o, in: squareRoom, camera: SIMD3(0, 1.4, 1))
        #expect(abs(placed.dimensions.z - 0.35) < 1e-5)
        #expect(abs(placed.transform.position.z - -1.815) < 1e-3)  // grew toward the wall
        #expect(abs(placed.transform.yaw) < 1e-3)  // front (+z) into the room
    }

    // MARK: 4. RoomPlan duplicates

    @Test func partialFootprintOverlapIsADuplicate() {
        // RoomPlan saw the ottoman as a 0.6 m storage box; the detector box is off by 0.35 m
        // (about 40% footprint overlap; the old >50%-inside rule kept it).
        let roomPlanBox = RoomGeometry.Object(id: "s", category: "storage", dimensions: SIMD3(0.6, 0.45, 0.6), transform: .at(SIMD3(0, 0.225, 0)))
        func run(offset: Float) -> Int {
            var merger = SightingMerger(floorY: 0)
            for seed in 1...2 {
                merger.add(Sighting(label: "ottoman", confidence: 0.8,
                                    points: boxPoints(center: SIMD3(offset, 0.225, 0), size: SIMD3(0.6, 0.45, 0.6), yaw: 0, seed: UInt64(seed))))
            }
            return merger.results(excluding: [roomPlanBox]).count
        }
        #expect(run(offset: 0.35) == 0)
        #expect(run(offset: 0.52) == 1)  // ~13% overlap: a separate piece beside it
    }

    @Test func footprintOverlapIsExactForRotatedBoxes() {
        let a = FittedBox(center: SIMD3(0, 0.5, 0), size: SIMD3(1, 1, 1), yaw: 0)
        let b = FittedBox(center: SIMD3(0.5, 0.5, 0), size: SIMD3(1, 1, 1), yaw: 0)
        #expect(abs(SightingMerger.footprintOverlap(a, b) - 0.5) < 1e-4)
        let diamond = FittedBox(center: SIMD3(0, 0.5, 0), size: SIMD3(1, 1, 1), yaw: .pi / 4)
        // A unit square and the same square turned 45°: overlap = 2(√2 - 1) ≈ 0.828.
        #expect(abs(SightingMerger.footprintOverlap(a, diamond) - 0.8284) < 1e-3)
        let far = FittedBox(center: SIMD3(3, 0.5, 0), size: SIMD3(1, 1, 1), yaw: 0.3)
        #expect(SightingMerger.footprintOverlap(a, far) == 0)
    }

    // MARK: 5. False positives

    let ottoman = (center: SIMD3<Float>(0, 0.225, 0), size: SIMD3<Float>(0.7, 0.45, 0.6))

    @Test func oneGlanceNeedsHighConfidence() {
        var merger = SightingMerger(floorY: 0)
        merger.add(Sighting(label: "ottoman", confidence: 0.8, points: boxPoints(center: ottoman.center, size: ottoman.size, yaw: 0)))
        #expect(merger.results().isEmpty)  // 0.7 used to be enough
        merger = SightingMerger(floorY: 0)
        merger.add(Sighting(label: "ottoman", confidence: 0.9, points: boxPoints(center: ottoman.center, size: ottoman.size, yaw: 0)))
        #expect(merger.results().count == 1)
    }

    @Test func sightingsFromTheSameViewCountOnce() {
        func run(_ second: (time: Double, camera: SIMD3<Float>)) -> SightingMerger.Track? {
            var merger = SightingMerger(floorY: 0)
            merger.add(Sighting(label: "ottoman", confidence: 0.8, points: boxPoints(center: ottoman.center, size: ottoman.size, yaw: 0, seed: 1),
                                camera: SIMD3(0, 1.4, 2), time: 10))
            merger.add(Sighting(label: "ottoman", confidence: 0.8, points: boxPoints(center: ottoman.center, size: ottoman.size, yaw: 0, seed: 2),
                                camera: second.camera, time: second.time))
            return merger.results().first
        }
        // Same frame, same place (two boxes on one object): one view, not confirmed.
        #expect(run((10.1, SIMD3(0.05, 1.4, 2))) == nil)
        // 0.4 s later: a second look.
        #expect(run((10.4, SIMD3(0.05, 1.4, 2)))?.views == 2)
        // Same instant but from 30° around: also a second look.
        #expect(run((10.0, SIMD3(2 * sin(Float.pi / 6), 1.4, 2 * cos(Float.pi / 6))))?.views == 2)
    }
}
