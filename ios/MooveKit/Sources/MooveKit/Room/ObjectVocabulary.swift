import Foundation

/// What the scan's object detector (#82) can see, and how its labels become Moove
/// categories. The detector is YOLOE-11L with these text prompts baked in (see
/// ios/scripts/fetch-models.sh); several prompts can share a category, e.g. four kinds
/// of scooter. People, pets, food, body parts and small things are deliberately absent.
public enum ObjectVocabulary {
    /// Model label (text prompt) → Moove category. RoomPlan's own categories use its
    /// names (`chair`, `storage`, `washerDryer`...) so duplicates can be matched up.
    public static let categories: [String: String] = [
        // Rides & sports
        "kids scooter": "scooter", "folding e-scooter": "scooter", "kick scooter": "scooter", "electric scooter": "scooter",
        "bicycle": "bicycle", "motorcycle": "motorcycle", "skateboard": "skateboard", "surfboard": "surfboard",
        "skis": "skis", "snowboard": "snowboard", "golf bag": "golf clubs", "tennis racket": "racket",
        "treadmill": "treadmill", "exercise bike": "exercise bike", "rowing machine": "rowing machine",
        "weight bench": "weight bench", "dumbbell": "weights", "kettlebell": "weights", "yoga mat": "yoga mat",
        "punching bag": "punching bag", "stroller": "stroller", "wheelchair": "wheelchair", "helmet": "helmet",
        "basketball": "ball", "soccer ball": "ball",
        // Instruments
        "guitar": "guitar", "electric guitar": "guitar", "ukulele": "guitar", "piano": "piano",
        "electronic keyboard": "keyboard instrument", "drum kit": "drums", "violin": "violin", "cello": "cello",
        "guitar amplifier": "amplifier", "saxophone": "saxophone", "trumpet": "trumpet",
        // Electronics
        "computer monitor": "monitor", "desktop computer": "computer", "laptop": "laptop", "printer": "printer",
        "speaker": "speaker", "game console": "game console", "projector": "projector", "record player": "turntable",
        "television": "television",
        // Appliances
        "microwave": "microwave", "coffee machine": "coffee machine", "toaster": "toaster", "blender": "blender",
        "vacuum cleaner": "vacuum", "upright vacuum cleaner": "vacuum", "cordless stick vacuum": "vacuum",
        "robot vacuum": "vacuum", "air purifier": "air purifier", "electric fan": "fan", "space heater": "heater",
        "humidifier": "humidifier", "portable air conditioner": "air conditioner", "sewing machine": "sewing machine",
        "ironing board": "ironing board", "mini fridge": "refrigerator", "refrigerator": "refrigerator",
        "washing machine": "washerDryer", "water dispenser": "water dispenser",
        // Furniture
        "floor lamp": "lamp", "table lamp": "lamp", "desk lamp": "lamp", "office chair": "chair", "chair": "chair",
        "armchair": "chair", "high chair": "chair", "stool": "stool", "ottoman": "ottoman", "bean bag": "bean bag",
        "sofa": "sofa", "bed": "bed", "mattress": "mattress", "crib": "crib", "bench": "bench",
        "desk": "table", "table": "table", "folding table": "table", "nightstand": "storage", "dresser": "storage",
        "wardrobe": "storage", "bookshelf": "storage", "cabinet": "storage", "tv stand": "storage",
        "filing cabinet": "storage", "shoe rack": "shoe rack", "coat rack": "coat rack", "clothes rack": "clothes rack",
        "shelf": "shelf", "rolling cart": "cart", "ladder": "ladder", "room divider": "room divider", "trunk": "trunk",
        // Decor
        "mirror": "mirror", "rug": "rug", "painting": "art", "framed picture": "art", "poster": "art",
        "wall clock": "clock", "vase": "vase", "potted plant": "plant", "plant stand": "plant stand",
        "sculpture": "decor", "globe": "decor", "christmas tree": "decor",
        "stuffed animal": "toy", "dollhouse": "toy", "rocking horse": "toy",
        // Boxes & bags
        "cardboard box": "box", "storage bin": "bin", "suitcase": "suitcase", "backpack": "backpack",
        "duffel bag": "bag", "laundry basket": "basket", "basket": "basket", "trash can": "trash can",
        // Tools & outdoor
        "toolbox": "toolbox", "lawn mower": "lawn mower", "grill": "grill", "workbench": "workbench",
        "pet crate": "pet crate", "cat tree": "cat tree", "dog bed": "pet bed",
    ]

    /// Moove category for a model label, or nil for labels Moove ignores (including
    /// the model's unused padding slots, labeled "127"..."159").
    public static func category(for label: String) -> String? { categories[label] }

    /// Categories RoomPlan also finds. Detections of these only count where RoomPlan
    /// has nothing nearby (it found 0 objects in one real room), see `SightingMerger`.
    public static let roomPlanCategories: Set<String> = [
        "bed", "sofa", "chair", "table", "storage", "refrigerator", "stove", "oven", "dishwasher",
        "washerdryer", "sink", "toilet", "bathtub", "fireplace", "television", "stairs",
    ]

    public static func isRoomPlanCategory(_ category: String) -> Bool { roomPlanCategories.contains(category.lowercased()) }

    /// Default minimum score (the model's real per-class score, not Vision's rescaled one).
    public static let defaultMinimumConfidence: Float = 0.4

    /// Per-category minimum scores. Big things worth finding get a lower bar; categories
    /// that misfire on photos (a scooter's T-bar reads as a desk lamp, a deck as a bench,
    /// any rectangle as a picture or speaker) need a higher one.
    public static let minimumConfidence: [String: Float] = [
        "scooter": 0.3, "bicycle": 0.35, "motorcycle": 0.45, "treadmill": 0.25, "exercise bike": 0.3,
        "rowing machine": 0.3, "piano": 0.35, "guitar": 0.35, "drums": 0.35, "vacuum": 0.3, "stroller": 0.35,
        "lamp": 0.5, "bench": 0.5, "art": 0.5, "speaker": 0.5, "shelf": 0.5, "storage": 0.5, "rug": 0.5,
        "blender": 0.55, "toaster": 0.55, "helmet": 0.5, "ball": 0.5, "basket": 0.5, "trash can": 0.5,
        "decor": 0.5, "toy": 0.5, "table": 0.5, "chair": 0.5, "bed": 0.5, "sofa": 0.5,
    ]

    public static func minimumConfidence(for category: String) -> Float {
        minimumConfidence[category] ?? defaultMinimumConfidence
    }

    /// LiDAR mostly sees the near side, so thin objects come out too shallow from
    /// one angle; these minimum depths (m) keep their footprints realistic.
    public static let minimumDepth: [String: Float] = [
        "scooter": 0.4, "bicycle": 0.45, "motorcycle": 0.7, "bench": 0.35, "suitcase": 0.2, "plant": 0.25,
        "microwave": 0.3, "laptop": 0.2, "skateboard": 0.2, "surfboard": 0.08, "skis": 0.08, "snowboard": 0.08,
        "treadmill": 0.6, "exercise bike": 0.5, "rowing machine": 0.5, "piano": 0.5, "guitar": 0.1,
        "drums": 0.6, "monitor": 0.15, "television": 0.1, "mirror": 0.04, "art": 0.03, "vacuum": 0.25,
        "stroller": 0.5, "box": 0.2, "lamp": 0.25, "fan": 0.25,
    ]

    /// How believable a measured size is for a category (1 = fine, lower = unlikely).
    /// Breaks ties when one object gets two labels, e.g. an e-scooter that also scores
    /// as a motorcycle: anything under 1.4 m long isn't a motorcycle.
    public static func plausibility(of category: String, size: SIMD3<Float>) -> Float {
        let length = max(size.x, size.z)
        switch category {
        case "motorcycle": return length < 1.4 ? 0.3 : 1
        case "lamp": return length > 0.8 ? 0.4 : 1  // lamps are tall and thin; long footprints are something else
        default: return 1
        }
    }
}

/// A rectangle in normalized image coordinates (0...1), top-left origin.
public struct NormRect: Equatable, Sendable {
    public var x, y, width, height: Float
    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Float { x + width }
    public var maxY: Float { y + height }
    public var area: Float { max(width, 0) * max(height, 0) }
    public var center: SIMD2<Float> { SIMD2(x + width / 2, y + height / 2) }

    public func intersection(_ o: NormRect) -> NormRect {
        let x0 = max(x, o.x), y0 = max(y, o.y), x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        return NormRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
    }

    public func iou(_ o: NormRect) -> Float {
        let i = intersection(o).area
        let u = area + o.area - i
        return u > 0 ? i / u : 0
    }

    /// Clamped to the unit square.
    public var clipped: NormRect { intersection(NormRect(x: 0, y: 0, width: 1, height: 1)) }
}

/// One detector box in one frame, already mapped to a Moove category.
public struct FrameDetection: Equatable, Sendable {
    public var label: String
    public var category: String
    public var confidence: Float
    public var box: NormRect

    public init(label: String, category: String, confidence: Float, box: NormRect) {
        self.label = label
        self.category = category
        self.confidence = confidence
        self.box = box
    }
}

public enum DetectionFilter {
    /// Raw detector output (label, real score, box) → the detections worth measuring:
    /// known categories above their threshold, one per object per category (the model
    /// often fires several prompts of one category, e.g. "kick scooter" and "electric
    /// scooter", on the same box, which would otherwise count as two sightings).
    public static func filter(_ raw: [(label: String, confidence: Float, box: NormRect)], sameObjectIoU: Float = 0.5) -> [FrameDetection] {
        let candidates = raw.compactMap { r -> FrameDetection? in
            guard let category = ObjectVocabulary.category(for: r.label),
                  r.confidence >= ObjectVocabulary.minimumConfidence(for: category) else { return nil }
            return FrameDetection(label: r.label, category: category, confidence: r.confidence, box: r.box)
        }.sorted { $0.confidence > $1.confidence }
        var kept: [FrameDetection] = []
        for d in candidates where !kept.contains(where: { $0.category == d.category && $0.box.iou(d.box) > sameObjectIoU }) {
            kept.append(d)
        }
        return kept
    }
}
