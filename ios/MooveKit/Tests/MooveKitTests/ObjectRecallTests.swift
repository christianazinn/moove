import Foundation
import Testing
@testable import MooveKit

@Suite struct ObjectVocabularyTests {
    /// The labels baked into MooveObjects-yoloe11l-v1 (models-v1 release), in model order.
    static let modelLabels = [
        "kids scooter", "folding e-scooter", "kick scooter", "electric scooter", "bicycle", "motorcycle", "skateboard", "surfboard", "skis", "snowboard", "golf bag", "tennis racket", "treadmill", "exercise bike", "rowing machine", "weight bench", "dumbbell", "kettlebell", "yoga mat", "punching bag", "stroller", "wheelchair", "helmet", "basketball", "soccer ball", "guitar", "electric guitar", "ukulele", "piano", "electronic keyboard", "drum kit", "violin", "cello", "guitar amplifier", "saxophone", "trumpet", "computer monitor", "desktop computer", "laptop", "printer", "speaker", "game console", "projector", "record player", "television", "microwave", "coffee machine", "toaster", "blender", "vacuum cleaner", "upright vacuum cleaner", "cordless stick vacuum", "robot vacuum", "air purifier", "electric fan", "space heater", "humidifier", "portable air conditioner", "sewing machine", "ironing board", "mini fridge", "refrigerator", "washing machine", "water dispenser", "floor lamp", "table lamp", "desk lamp", "office chair", "chair", "armchair", "stool", "ottoman", "bean bag", "sofa", "bed", "mattress", "crib", "high chair", "bench", "desk", "table", "nightstand", "dresser", "wardrobe", "bookshelf", "cabinet", "tv stand", "filing cabinet", "shoe rack", "coat rack", "clothes rack", "shelf", "folding table", "rolling cart", "ladder", "room divider", "trunk", "mirror", "rug", "painting", "framed picture", "poster", "wall clock", "vase", "potted plant", "plant stand", "sculpture", "globe", "stuffed animal", "dollhouse", "rocking horse", "christmas tree", "cardboard box", "storage bin", "suitcase", "backpack", "duffel bag", "laundry basket", "basket", "trash can", "toolbox", "lawn mower", "grill", "workbench", "pet crate", "cat tree", "dog bed",
    ]

    @Test func everyModelLabelHasACategory() {
        #expect(Self.modelLabels.count == 127)
        for label in Self.modelLabels { #expect(ObjectVocabulary.category(for: label) != nil, "\(label)") }
        #expect(Set(ObjectVocabulary.categories.keys) == Set(Self.modelLabels))
    }

    @Test func scootersAndBikesStaySeparate() {
        for label in ["kids scooter", "folding e-scooter", "kick scooter", "electric scooter"] {
            #expect(ObjectVocabulary.category(for: label) == "scooter")
        }
        #expect(ObjectVocabulary.category(for: "bicycle") == "bicycle")
        #expect(ObjectVocabulary.category(for: "motorcycle") == "motorcycle")
    }

    @Test func ignoresPaddingAndUnknownLabels() {
        #expect(ObjectVocabulary.category(for: "127") == nil)
        #expect(ObjectVocabulary.category(for: "person") == nil)
    }

    @Test func roomPlanCategoriesUseRoomPlanNames() {
        #expect(ObjectVocabulary.category(for: "washing machine") == "washerDryer")
        #expect(ObjectVocabulary.isRoomPlanCategory("washerDryer"))
        #expect(ObjectVocabulary.isRoomPlanCategory("chair"))
        #expect(!ObjectVocabulary.isRoomPlanCategory("scooter"))
    }

    @Test func bigThingsHaveALowerBarThanMisfiringOnes() {
        #expect(ObjectVocabulary.minimumConfidence(for: "scooter") < ObjectVocabulary.defaultMinimumConfidence)
        #expect(ObjectVocabulary.minimumConfidence(for: "lamp") > ObjectVocabulary.defaultMinimumConfidence)
        #expect(ObjectVocabulary.minimumConfidence(for: "guitar") <= ObjectVocabulary.defaultMinimumConfidence)
    }

    @Test func aShortMotorcycleIsImplausible() {
        #expect(ObjectVocabulary.plausibility(of: "motorcycle", size: SIMD3(1.1, 1.1, 0.5)) < 0.5)
        #expect(ObjectVocabulary.plausibility(of: "motorcycle", size: SIMD3(2.0, 1.1, 0.7)) == 1)
        #expect(ObjectVocabulary.plausibility(of: "scooter", size: SIMD3(1.1, 1.1, 0.5)) == 1)
    }
}

@Suite struct DetectionFilterTests {
    let box = NormRect(x: 0.2, y: 0.1, width: 0.5, height: 0.7)

    @Test func oneDetectionPerCategoryPerObject() {
        // Real output for scooter_razor2.jpg: two scooter prompts on one box.
        let out = DetectionFilter.filter([
            ("folding e-scooter", 0.71, box),
            ("kick scooter", 0.33, NormRect(x: 0.21, y: 0.1, width: 0.5, height: 0.7)),
        ])
        #expect(out.count == 1)
        #expect(out.first?.category == "scooter")
        #expect(out.first?.label == "folding e-scooter")
    }

    @Test func keepsDifferentCategoriesOnTheSameBoxForTheMergerToResolve() {
        // Real output for scooter_e3.jpg: motorcycle 0.88 and folding e-scooter 0.82 on one box.
        let out = DetectionFilter.filter([("motorcycle", 0.88, box), ("folding e-scooter", 0.82, box)])
        #expect(Set(out.map(\.category)) == ["motorcycle", "scooter"])
    }

    @Test func appliesPerCategoryThresholdsAndDropsUnknowns() {
        let out = DetectionFilter.filter([
            ("desk lamp", 0.45, box),       // lamps need 0.5
            ("treadmill", 0.28, NormRect(x: 0, y: 0, width: 0.2, height: 0.2)),  // big gear: 0.25
            ("131", 0.9, box),              // padding slot
        ])
        #expect(out.map(\.category) == ["treadmill"])
    }

    @Test func keepsTwoBikesSideBySide() {
        let out = DetectionFilter.filter([
            ("bicycle", 0.8, NormRect(x: 0.0, y: 0.2, width: 0.3, height: 0.5)),
            ("bicycle", 0.7, NormRect(x: 0.5, y: 0.2, width: 0.3, height: 0.5)),
        ])
        #expect(out.count == 2)
    }
}

@Suite struct AutoPhotoTests {
    /// A portrait phone at `position` looking along world -z (turned `yaw` about +Y),
    /// with the iPhone's 1920×1440 sensor. The sensor is landscape, so for a portrait
    /// phone ARKit's camera +x points down in the world and +y points right.
    func pose(at position: SIMD3<Float> = .zero, yaw: Float = 0) -> CameraPose {
        let c = cos(yaw), s = sin(yaw)
        return CameraPose(columns: [SIMD4(0, -1, 0, 0), SIMD4(c, 0, -s, 0), SIMD4(s, 0, c, 0), SIMD4(position.x, position.y, position.z, 1)],
                          fx: 1500, fy: 1500, cx: 960, cy: 720, imageWidth: 1920, imageHeight: 1440)
    }

    @Test func projectionMatchesTheDetectorsUnprojection() throws {
        let p = pose(at: SIMD3(0.3, 1.4, 0.5), yaw: 0.4)
        // The detector unprojects sensor pixel (u, v) at depth d as below; projecting back must land on it.
        let u: Float = 1300, v: Float = 400, d: Float = 2.2
        let cam = SIMD3((u - p.cx) / p.fx * d, -(v - p.cy) / p.fy * d, -d)
        let world = p.position + SIMD3(p.columns[0].x, p.columns[0].y, p.columns[0].z) * cam.x
            + SIMD3(p.columns[1].x, p.columns[1].y, p.columns[1].z) * cam.y + SIMD3(p.columns[2].x, p.columns[2].y, p.columns[2].z) * cam.z
        let (pt, depth) = try #require(p.project(world))
        #expect(abs(depth - d) < 1e-4)
        let sensor = CameraPose.sensor(upright: pt)
        #expect(abs(sensor.x - u / 1920) < 1e-4 && abs(sensor.y - v / 1440) < 1e-4)
    }

    @Test func uprightIsTheSensorImageTurnedClockwise() {
        // Sensor top-left corner ends up at the upright image's top-right.
        #expect(CameraPose.upright(sensor: SIMD2(0, 0)) == SIMD2(1, 0))
        // ...and its bottom-left at the upright top-left.
        #expect(CameraPose.upright(sensor: SIMD2(0, 1)) == SIMD2(0, 0))
        #expect(CameraPose.sensor(upright: CameraPose.upright(sensor: SIMD2(0.3, 0.8))) == SIMD2(0.3, 0.8))
    }

    @Test func worldUpIsUpAndRightIsRightInTheUprightPhoto() throws {
        let p = pose(at: SIMD3(0, 1.2, 0))
        let above = try #require(p.project(SIMD3(0, 2.0, -2))).point
        let right = try #require(p.project(SIMD3(0.8, 1.2, -2))).point
        let ahead = try #require(p.project(SIMD3(0, 1.2, -2))).point
        #expect(abs(ahead.x - 0.5) < 1e-4 && abs(ahead.y - 0.5) < 1e-4)
        #expect(above.y < 0.4 && abs(above.x - 0.5) < 1e-4)
        #expect(right.x > 0.6 && abs(right.y - 0.5) < 1e-4)
    }

    @Test func pointsBehindTheCameraDontProject() {
        #expect(pose().project(SIMD3(0, 0, 1)) == nil)
        #expect(pose().project(SIMD3(0, 0, -1)) != nil)
    }

    let scooter = (size: SIMD3<Float>(1.1, 1.15, 0.45), transform: RoomTransform.at(SIMD3(0, 0.575, -2.5)))

    @Test func picksTheWellFramedSharpView() throws {
        let frames = [
            Keyframe(id: 0, pose: pose(at: SIMD3(0, 1.2, 0)), sharpness: 100, depth: nil),           // whole scooter, centered
            Keyframe(id: 1, pose: pose(at: SIMD3(1.3, 1.2, 0)), sharpness: 100, depth: nil),         // scooter cut off at the edge
            Keyframe(id: 2, pose: pose(at: SIMD3(0, 1.2, -0.3)), sharpness: 15, depth: nil),        // closer but blurred
            Keyframe(id: 3, pose: pose(at: SIMD3(0, 1.2, -6), yaw: 0), sharpness: 100, depth: nil),  // facing away
        ]
        let best = try #require(CropPicker.best(size: scooter.size, transform: scooter.transform, in: frames))
        #expect(best.keyframeID == 0)
        #expect(best.visible > 0.99)
    }

    @Test func rejectsViewsWhereSomethingIsInFront() throws {
        let p = pose(at: SIMD3(0, 1.2, 0))
        // LiDAR sees something 1 m away (the scooter is ~2.3 m away) across the whole view.
        let blocked = DepthGrid(width: 16, height: 12, values: Array(repeating: 1.0, count: 192))
        let clear = DepthGrid(width: 16, height: 12, values: Array(repeating: 2.3, count: 192))
        let a = try #require(CropPicker.candidate(size: scooter.size, transform: scooter.transform, in: Keyframe(id: 0, pose: p, sharpness: 1, depth: blocked)))
        let b = try #require(CropPicker.candidate(size: scooter.size, transform: scooter.transform, in: Keyframe(id: 1, pose: p, sharpness: 1, depth: clear)))
        #expect(a.occluded > 0.9)
        #expect(b.occluded == 0)
        #expect(CropPicker.score(a, typicalSharpness: 1) == 0)
        #expect(CropPicker.score(b, typicalSharpness: 1) > 0)
    }

    @Test func noPhotoWhenNothingShowsTheObject() {
        let frames = [Keyframe(id: 0, pose: pose(at: SIMD3(0, 1.2, -6)), sharpness: 1, depth: nil)]
        #expect(CropPicker.best(size: scooter.size, transform: scooter.transform, in: frames) == nil)
    }

    @Test func cropKeepsContextAndStaysInTheImage() {
        let c = CropCandidate(keyframeID: 0, rect: NormRect(x: 0.9, y: 0.4, width: 0.1, height: 0.05), visible: 1, occluded: 0, distance: 2, sharpness: 1)
        let r = CropPicker.cropRect(c)
        #expect(r.width >= 0.2 && r.height >= 0.2)
        #expect(r.maxX <= 1 && r.x >= 0 && r.maxY <= 1)
        #expect(abs(r.intersection(c.rect).area - c.rect.area) < 1e-6)
    }

    @Test func sharpnessDropsWithBlur() {
        let w = 32, h = 32
        let edges = (0..<(w * h)).map { i in UInt8(((i % w) / 4 + (i / w) / 4) % 2 == 0 ? 0 : 255) }
        // A 3-tap horizontal box blur of the same checkerboard.
        let blurred = (0..<(w * h)).map { i -> UInt8 in
            let x = i % w, y = i / w
            let xs = [max(x - 1, 0), x, min(x + 1, w - 1)]
            return UInt8(xs.map { Int(edges[y * w + $0]) }.reduce(0, +) / 3)
        }
        #expect(Sharpness.score(luma: edges, width: w, height: h) > Sharpness.score(luma: blurred, width: w, height: h) * 1.5)
        #expect(Sharpness.score(luma: Array(repeating: 128, count: w * h), width: w, height: h) == 0)
    }

    @Test func keyframeGateWantsNewViewsAndNoBlur() {
        var gate = KeyframeGate()
        let kept = [
            gate.offer(pose(), time: 0),
            gate.offer(pose(at: SIMD3(0.05, 0, 0)), time: 0.5),            // barely moved
            gate.offer(pose(at: SIMD3(0.4, 0, 0)), time: 1.0),             // walked 40 cm
            gate.offer(pose(at: SIMD3(0.4, 0, 0), yaw: 1.2), time: 1.3),   // whipping round at ~230°/s
            gate.offer(pose(at: SIMD3(0.4, 0, 0), yaw: 1.3), time: 2.3),   // settled on a new view
        ]
        #expect(kept == [true, false, true, false, true])
        #expect(gate.kept.count == 3)
    }
}
