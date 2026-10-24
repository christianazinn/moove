import Testing
@testable import MooveKit

/// Lisa's iPad scan 9 (Oct 24): "the toilet looks like a plant ... a random brown thing on the bed
/// that looks like a plant". Every object of that scan, at its scanned size, with the name the app
/// gives it (the category; vision may rename it later), and the model it should get.
struct Scan9VoxelTests {
    struct Object {
        var label: String
        var category: String
        /// meters
        var w: Double, d: Double, h: Double
        var want: VoxelModels.Kind
        var spec: VoxelItemSpec {
            VoxelItemSpec(category: category, name: category, widthM: w, depthM: d, heightM: h, id: "scan9-\(label)")
        }
    }

    static let objects: [Object] = [
        Object(label: "sink", category: "sink", w: 0.546, d: 0.437, h: 0.30, want: .sink),
        Object(label: "chair", category: "chair", w: 0.576, d: 0.617, h: 0.989, want: .chair),
        Object(label: "storage", category: "storage", w: 0.675, d: 0.587, h: 1.479, want: .bookshelf),
        Object(label: "bed", category: "bed", w: 1.552, d: 2.238, h: 0.618, want: .bed),
        Object(label: "bed tall", category: "bed", w: 1.062, d: 2.073, h: 1.495, want: .bed),
        Object(label: "table", category: "table", w: 1.017, d: 0.605, h: 0.831, want: .table),
        Object(label: "bathtub", category: "bathtub", w: 1.403, d: 0.773, h: 0.449, want: .bathtub),
        Object(label: "toilet", category: "toilet", w: 0.454, d: 0.707, h: 0.819, want: .toilet),
        Object(label: "shelf", category: "shelf", w: 0.452, d: 0.169, h: 0.239, want: .bookshelf),
        Object(label: "lamp", category: "lamp", w: 0.313, d: 0.25, h: 0.90, want: .lamp),
        Object(label: "heater", category: "heater", w: 0.303, d: 0.198, h: 0.640, want: .appliance),
        Object(label: "television", category: "television", w: 0.792, d: 0.343, h: 0.956, want: .tv),
        Object(label: "trash can", category: "trash can", w: 0.185, d: 0.146, h: 0.331, want: .trashCan),
        Object(label: "trash can 2", category: "trash can", w: 0.597, d: 0.107, h: 0.428, want: .trashCan),
        Object(label: "room divider", category: "room divider", w: 0.526, d: 0.495, h: 1.426, want: .screen),
        Object(label: "bag", category: "bag", w: 0.256, d: 0.161, h: 0.478, want: .bag),
        Object(label: "workbench", category: "workbench", w: 0.597, d: 0.222, h: 0.153, want: .softGoods),
        Object(label: "toy", category: "toy", w: 0.349, d: 0.274, h: 0.157, want: .toy),
        Object(label: "other", category: "other", w: 0.590, d: 0.517, h: 0.778, want: .unknown),
        Object(label: "humidifier", category: "humidifier", w: 0.603, d: 0.189, h: 0.520, want: .appliance),
    ]

    /// Kinds that had no model before scan 9 and the detector's leftover props, for the previews:
    /// (category, name, w, d, h).
    static let extraProps: [(String, String, Double, Double, Double)] = [
        ("toilet", "Toilet", 0.40, 0.70, 0.78), ("sink", "Bathroom vanity", 0.75, 0.50, 0.86),
        ("sink", "Pedestal sink", 0.55, 0.45, 0.85), ("bathtub", "Bathtub", 1.6, 0.75, 0.55),
        ("fireplace", "Fireplace", 1.3, 0.45, 1.1), ("stairs", "Stairs", 0.95, 2.4, 2.6),
        ("washerDryer", "Washer", 0.6, 0.62, 0.85), ("room divider", "Folding screen", 1.5, 0.3, 1.7),
        ("ball", "Basketball", 0.25, 0.25, 0.25), ("helmet", "Bike helmet", 0.22, 0.28, 0.18),
        ("racket", "Tennis racket", 0.28, 0.05, 0.68), ("weights", "Dumbbell", 0.35, 0.14, 0.14),
        ("weights", "Kettlebell", 0.2, 0.15, 0.25), ("yoga mat", "Yoga mat", 0.62, 0.14, 0.14),
        ("ironing board", "Ironing board", 1.3, 0.38, 0.9), ("saxophone", "Saxophone", 0.3, 0.18, 0.7),
        ("trumpet", "Trumpet", 0.5, 0.15, 0.18), ("decor", "Decor", 0.25, 0.25, 0.4),
        ("decor", "Vase", 0.2, 0.2, 0.35), ("toy", "Stuffed animal", 0.35, 0.3, 0.4),
        ("other", "Folded blanket", 0.5, 0.4, 0.12), ("other", "Other", 0.4, 0.3, 0.3),
        ("bed", "Metal bunk bed with ladder", 1.08, 2.06, 1.47), ("bed", "Loft bed with ladder", 1.0, 2.0, 1.8),
        ("table", "Lamp", 0.5, 0.5, 0.15),
    ]

    @Test func everyScan9ObjectGetsItsModel() {
        var bad: [String] = []
        for o in Self.objects {
            let k = VoxelModels.kind(o.spec)
            if k != o.want { bad.append("\(o.label): \(k), want \(o.want)") }
        }
        #expect(bad.isEmpty, "\(bad.joined(separator: "\n"))")
    }

    static let newKinds: [VoxelModels.Kind] = [.toilet, .sink, .bathtub, .fireplace, .stairs, .screen, .softGoods, .unknown,
                                                .ball, .helmet, .racket, .weights, .yogaMat, .ironingBoard, .horn]

    /// The new builders: their sample names route to them, they draw something (not a solid box),
    /// and stay under 4k triangles at the default size, the scan-9 sizes and the preview sizes.
    @Test func newKindsDrawCheaply() {
        for k in Self.newKinds {
            let (cat, name) = RenderBudgetTests.kindSamples[k]!
            let spec = VoxelItemSpec(category: cat, name: name, widthM: 0, depthM: 0, heightM: 0)
            #expect(VoxelModels.kind(spec) == k, "\(cat)/\(name)")
            let g = VoxelModels.build(spec)
            #expect(g.filledCount > 0 && g.filledCount < g.nx * g.ny * g.nz, "\(k) is a solid block")
            let t = VoxelMesher.mesh(g).triangleCount
            #expect(t < 4000, "\(k): \(t) triangles")
        }
        for o in Self.objects where Self.newKinds.contains(o.want) {
            let t = VoxelMesher.mesh(VoxelModels.build(o.spec)).triangleCount
            #expect(t < 4000, "\(o.label): \(t) triangles")
        }
        for (cat, name, w, d, h) in Self.extraProps {
            let spec = VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h)
            guard Self.newKinds.contains(VoxelModels.kind(spec)) else { continue }
            let t = VoxelMesher.mesh(VoxelModels.build(spec)).triangleCount
            #expect(t < 4000, "\(name): \(t) triangles")
        }
    }

    /// Lisa: "the toilet looks like a plant". Only plant names draw foliage-green tops: the
    /// generic decor / vase and table lamp defaults are neutral.
    @Test func defaultsDontLookLikePlants() {
        func greenish(_ c: VoxelColor) -> Bool {
            let r = Int((c >> 16) & 255), g = Int((c >> 8) & 255), b = Int(c & 255)
            return g > r + 8 && g > b + 8
        }
        for (cat, name) in [("decor", "decor"), ("decor", "vase"), ("lamp", "table lamp"), ("toy", "toy"), ("other", "other"), ("toilet", "toilet")] {
            for i in 0..<8 {
                let g = VoxelModels.build(VoxelItemSpec(category: cat, name: name, widthM: 0, depthM: 0, heightM: 0, id: "seed\(i)"))
                var green = 0
                for y in 0..<g.ny { for z in 0..<g.nz { for x in 0..<g.nx { if let c = g[x, y, z], greenish(c) { green += 1 } } } }
                #expect(green * 10 < g.filledCount, "\(cat)/\(name) seed \(i): \(green) of \(g.filledCount) voxels green")
            }
        }
    }

    // MARK: head noun and RoomPlan category (Lisa, Oct 24: a bunk bed drawn as a ladder)

    func kind(_ cat: String, _ name: String, _ w: Double = 0, _ d: Double = 0, _ h: Double = 0) -> VoxelModels.Kind {
        VoxelModels.kind(VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h))
    }

    @Test func bunkBedsWithLaddersAreBeds() {
        for name in ["Metal bunk bed with ladder", "Twin over full bunk bed with ladder", "Loft bed with ladder", "Wooden bunk bed, ladder"] {
            #expect(kind("bed", name, 1.08, 2.06, 1.47) == .bed, "\(name)")
            #expect(kind("bed", name) == .bed, "\(name), no size")
            #expect(kind("furniture", name, 1.08, 2.06, 1.47) == .bed, "\(name) as furniture")
            // still Rio's two-deck drawing
            let g = VoxelModels.build(VoxelItemSpec(category: "bed", name: name, widthM: 1.08, depthM: 2.06, heightM: 1.47))
            let mid = (0..<g.ny).filter { g[g.nx / 2, $0, g.nz / 2] != nil }
            #expect(mid.contains { $0 > g.ny / 2 } && mid.contains { $0 < g.ny / 3 }, "\(name): two decks")
        }
        // a loft bed in a short box is still drawn tall
        #expect(VoxelModels.build(VoxelItemSpec(category: "bed", name: "Loft bed", widthM: 1.0, depthM: 2.0, heightM: 0.5)).ny >= vox(1.4))
        // the head noun phrase
        #expect(VoxelModels.headPhrase("metal bunk bed with ladder") == "metal bunk bed")
        #expect(VoxelModels.headPhrase("wooden bunk bed, ladder") == "wooden bunk bed")
        #expect(VoxelModels.headPhrase("desk (with drawers)") == "desk")
        #expect(kind("furniture", "Desk with lamp") == .desk)
        #expect(kind("furniture", "Lamp with fabric shade") == .lamp)
        #expect(kind("furniture", "Thing with drawers", 0.8, 0.45, 0.9) == .dresser) // the head says nothing: the full name
    }

    /// RoomPlan categories at a typical size (w, d, h).
    static let roomPlanTypical: [(String, Double, Double, Double)] = [
        ("bed", 1.5, 2.0, 0.6), ("sofa", 2.0, 0.9, 0.85), ("table", 1.2, 0.8, 0.75), ("chair", 0.55, 0.55, 0.9),
        ("storage", 0.8, 0.45, 1.0), ("refrigerator", 0.75, 0.7, 1.75), ("stove", 0.76, 0.65, 0.92), ("oven", 0.6, 0.6, 0.9),
        ("dishwasher", 0.6, 0.6, 0.86), ("washerDryer", 0.6, 0.62, 0.85), ("television", 1.2, 0.1, 0.7), ("toilet", 0.4, 0.7, 0.78),
        ("sink", 0.6, 0.48, 0.85), ("bathtub", 1.6, 0.75, 0.55), ("fireplace", 1.3, 0.45, 1.1), ("stairs", 0.95, 2.4, 2.6),
    ]

    @Test func roomPlanCategoryKeepsItsKindWhateverTheTail() {
        var bad: [String] = []
        for (cat, w, d, h) in Self.roomPlanTypical {
            let own = kind(cat, cat, w, d, h)
            let family = VoxelModels.roomPlanFamilies[cat.lowercased()] ?? [own]
            #expect(family.contains(own), "\(cat): \(own)")
            for k in VoxelModels.Kind.allCases {
                let word = RenderBudgetTests.kindSamples[k]?.1 ?? k.rawValue
                for name in ["\(cat) with \(word)", "\(cat), \(word)"] {
                    let got = kind(cat, name, w, d, h)
                    if !family.contains(got) { bad.append("\(cat)/\(name): \(got)") }
                }
                // a name that is only another kind's word may not leave the family either
                let got = kind(cat, word, w, d, h)
                if !family.contains(got) { bad.append("\(cat)/\(word): \(got)") }
            }
        }
        #expect(bad.isEmpty, "\(bad.count) left their category's family:\n\(bad.joined(separator: "\n"))")
    }
}
