import Testing
@testable import MooveKit

@Suite struct FurnitureLayoutTests {
    static let categories = ["bed", "sofa", "chair", "table", "storage", "television", "refrigerator", "stove", "oven",
                             "dishwasher", "washerDryer", "toilet", "bathtub", "sink", "fireplace", "stairs"]
    static let typical: [String: SIMD3<Float>] = [
        "bed": SIMD3(1.6, 1.0, 2.1), "sofa": SIMD3(2.1, 0.85, 0.9), "chair": SIMD3(0.5, 0.9, 0.55), "table": SIMD3(1.4, 0.75, 0.8),
        "storage": SIMD3(0.9, 1.2, 0.45), "television": SIMD3(1.2, 0.7, 0.06), "refrigerator": SIMD3(0.7, 1.8, 0.7),
        "stove": SIMD3(0.76, 0.9, 0.65), "oven": SIMD3(0.6, 0.6, 0.55), "dishwasher": SIMD3(0.6, 0.85, 0.6),
        "washerDryer": SIMD3(0.6, 0.85, 0.6), "toilet": SIMD3(0.4, 0.75, 0.7), "bathtub": SIMD3(1.7, 0.55, 0.75),
        "sink": SIMD3(0.8, 0.9, 0.5), "fireplace": SIMD3(1.5, 1.2, 0.4), "stairs": SIMD3(1.0, 2.6, 3.0),
    ]

    @Test(arguments: categories)
    func partsFitInsideTheBox(category: String) throws {
        for size in [SIMD3<Float>(0.4, 0.4, 0.4), Self.typical[category]!, SIMD3(3, 2.5, 3)] {
            let parts = try #require(FurnitureLayout.parts(category: category, size: size), "\(category) \(size)")
            #expect((2...16).contains(parts.count), "\(category) \(size): \(parts.count) parts")
            for p in parts {
                let lo = p.center - p.size / 2, hi = p.center + p.size / 2
                let half: SIMD3<Float> = size / 2 + 1e-4
                let ok = all(lo .>= -half) && all(hi .<= half)
                #expect(ok, "\(category) \(size): \(p) outside box")
                #expect(p.size.min() > 0, "\(category) \(size): empty part \(p)")
                switch p.shape {
                case .cylinder: #expect(abs(p.size.x - p.size.z) < 1e-5)
                case .roundedBox(let r): #expect(r > 0 && r <= p.size.min() / 2 + 1e-6)
                case .box: break
                }
            }
        }
    }

    @Test func typicalPartCounts() {
        func count(_ c: String) -> Int { FurnitureLayout.parts(category: c, size: Self.typical[c]!)?.count ?? 0 }
        #expect(count("bed") == 9)  // base, mattress, headboard, 2 pillows, 4 legs
        #expect(count("sofa") == 14)  // base, 2 arms, back, 3 seats + 3 backs, 4 legs
        #expect(count("chair") == 6)
        #expect(count("table") == 5)
        #expect(count("television") == 2)  // wall-mounted: bezel + screen
        #expect(FurnitureLayout.parts(category: "television", size: SIMD3(1.2, 0.8, 0.3))?.count == 4)  // on a stand
        #expect(count("stairs") == 14)
    }

    @Test func categoryIsCaseInsensitive() {
        let size = SIMD3<Float>(0.6, 0.85, 0.6)
        let a = FurnitureLayout.parts(category: "washerDryer", size: size)
        #expect(a != nil)
        #expect(FurnitureLayout.parts(category: "WasherDryer", size: size) == a)
        #expect(FurnitureLayout.parts(category: "washerdryer", size: size) == a)
        #expect(FurnitureLayout.parts(category: "SOFA", size: size) != nil)
    }

    @Test func unknownAndDegenerateGiveNil() {
        #expect(FurnitureLayout.parts(category: "lamp", size: SIMD3(0.3, 1.5, 0.3)) == nil)
        #expect(FurnitureLayout.parts(category: "decor", size: SIMD3(0.3, 0.3, 0.3)) == nil)
        #expect(FurnitureLayout.parts(category: "bed", size: SIMD3(1.6, 0, 2)) == nil)
        #expect(FurnitureLayout.parts(category: "bed", size: SIMD3(1.6, 0.01, 2)) == nil)
        #expect(FurnitureLayout.parts(category: "bed", size: SIMD3(.nan, 1, 2)) == nil)
        #expect(FurnitureLayout.parts(category: "bed", size: SIMD3(.infinity, 1, 2)) == nil)
        #expect(FurnitureLayout.parts(category: "chair", size: SIMD3(-0.5, 0.9, 0.5)) == nil)
    }

    @Test func sofaSeatsGrowWithWidth() {
        func seats(_ w: Float) -> Int {
            FurnitureLayout.parts(category: "sofa", size: SIMD3(w, 0.85, 0.9))!.filter { $0.role == .cushion }.count / 2
        }
        #expect(seats(0.8) == 1)
        #expect(seats(1.5) == 2)
        #expect(seats(2.4) == 3)
    }

    @Test func stairsStepsGrowWithHeightAndRiseTowardTheBack() {
        func steps(_ h: Float) -> [FurnitureLayout.Part] { FurnitureLayout.parts(category: "stairs", size: SIMD3(1, h, 3))! }
        #expect(steps(0.2).count == 2)
        #expect(steps(1.0).count == 6)
        #expect(steps(2.7).count == 15)
        #expect(steps(10).count == 16)
        let s = steps(1.8)
        for (a, b) in zip(s, s.dropFirst()) {
            #expect(b.size.y > a.size.y && b.center.z < a.center.z)
        }
    }

    @Test func backsSitAtNegativeZ() {
        let sofa = FurnitureLayout.parts(category: "sofa", size: SIMD3(2, 0.85, 0.9))!
        let back = sofa.filter { $0.role == .frame }.max { $0.center.y < $1.center.y }!  // tallest frame part is the back
        #expect(back.center.z < 0)
        let bed = FurnitureLayout.parts(category: "bed", size: SIMD3(1.6, 1, 2.1))!
        #expect(bed[2].center.z < -0.9 && bed[2].size.y == 1)  // headboard
    }
}
