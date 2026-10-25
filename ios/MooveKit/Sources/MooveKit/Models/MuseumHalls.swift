import Foundation

/// Inventory's museum halls: items grouped by what they're for, not by room. An item's
/// hall comes from a few name words first (a nightstand sleeps, an office chair works),
/// then its voxel kind (`VoxelModels.kind`, the same routing as its 3D model).
public enum FunctionHall: String, CaseIterable, Sendable, Hashable, Identifiable {
    case sleep, sitAndLounge, workAndStudy, kitchenAndDining, media, storage, lightAndDecor, music
    case bathAndLaundry, getAroundAndPlay, everythingElse

    public var id: String { rawValue }

    /// Short name ("Sleep", "Sit & lounge").
    public var name: String {
        switch self {
        case .sleep: "Sleep"
        case .sitAndLounge: "Sit & lounge"
        case .workAndStudy: "Work & study"
        case .kitchenAndDining: "Kitchen & dining"
        case .media: "Media"
        case .storage: "Storage"
        case .lightAndDecor: "Light & decor"
        case .music: "Music"
        case .bathAndLaundry: "Bath & laundry"
        case .getAroundAndPlay: "Get around & play"
        case .everythingElse: "Everything else"
        }
    }

    /// The hall's sign: "The Sleep Hall"; the leftovers are the curiosities.
    public var title: String {
        switch self {
        case .everythingElse: "Cabinet of Curiosities"
        case .sitAndLounge: "The Sit & Lounge Hall"
        case .workAndStudy: "The Work & Study Hall"
        case .kitchenAndDining: "The Kitchen & Dining Hall"
        case .lightAndDecor: "The Light & Decor Hall"
        case .bathAndLaundry: "The Bath & Laundry Hall"
        case .getAroundAndPlay: "The Get Around & Play Hall"
        default: "The \(name) Hall"
        }
    }

    public static func of(_ item: Item) -> FunctionHall {
        of(name: item.name, category: item.category, attributes: item.attributes) { VoxelItemSpec(item) }
    }

    /// A shopping-list item's hall, so Shopping and Inventory share categories. It has no scan,
    /// so the shape fallback uses the typical size the Shopping thumbnails draw it at.
    public static func of(_ item: ShoppingItem) -> FunctionHall { of(name: item.name, category: item.category) }

    /// The hall for a thing known only by name and category (a shopping item or a deal).
    public static func of(name: String, category: String) -> FunctionHall {
        of(name: name, category: category, attributes: []) {
            let s = ShoppingThumbnails.size(name: name, category: category)
            return VoxelItemSpec(category: s.category, name: name, widthM: s.widthM, depthM: s.depthM, heightM: s.heightM)
        }
    }

    static func of(name: String, category: String, attributes: [String], spec: () -> VoxelItemSpec) -> FunctionHall {
        let text = " " + "\(name) \(category)".lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ") + " "
        func has(_ phrases: String...) -> Bool {
            phrases.contains { text.contains(" \($0) ") || text.contains(" \($0)s ") || text.contains(" \($0)es ") }
        }
        let attrs = Set(attributes.map { $0.lowercased() })

        // Seats and tables depend on what they're for.
        let isChair = has("chair", "stool") && !has("high chair", "wheelchair", "chair mat")
        if isChair || has("table") {
            if has("office", "desk", "gaming", "task", "swivel", "computer") || attrs.contains("chairtype.swivel")
                || attrs.contains("chairlegtype.star") { return .workAndStudy }
            if has("dining", "kitchen", "dinner", "breakfast", "bar stool", "counter stool") || attrs.contains("chairtype.dining") {
                return .kitchenAndDining
            }
            if has("coffee table", "side table", "end table", "bedside table", "nightstand", "armchair", "rocking chair",
                   "lounge", "accent", "recliner", "folding chair") {
                return has("bedside table") ? .sleep : .sitAndLounge
            }
            if has("table") && !isChair { return has("desk") ? .workAndStudy : .kitchenAndDining }
            if has("bean bag") { return .sitAndLounge }
        }

        // Words that say the job better than the shape does.
        if has("pet", "dog", "cat", "litter") { return .everythingElse }
        if has("bed", "mattress", "futon", "bunk", "nightstand", "night stand", "bedside", "pillow", "duvet", "comforter", "blanket", "bedding", "headboard", "crib", "bassinet") {
            return .sleep
        }
        if has("washer", "dryer", "washing machine", "ironing board", "hamper", "laundry", "towel", "shower", "toilet",
               "bathtub", "bath tub", "sink", "bath mat"), !has("hair dryer", "pressure washer", "dish washer", "dishwasher") {
            return .bathAndLaundry
        }
        if has("guitar", "amp", "amplifier", "piano", "drum", "violin", "ukulele", "cello", "saxophone", "trumpet", "keyboard stand", "synth", "synthesizer") {
            return .music
        }
        if has("monitor", "computer", "laptop", "printer", "mouse", "webcam", "desk lamp", "whiteboard", "office", "binder", "textbook") {
            return .workAndStudy
        }
        if has("keyboard") { return has("casio", "yamaha", "roland", "korg", "midi", "piano") ? .music : .workAndStudy }
        if has("tv", "television", "speaker", "soundbar", "game console", "playstation", "xbox", "nintendo", "projector",
               "turntable", "record player", "media console", "tv stand", "tv console", "receiver", "router", "camera", "tripod") {
            return .media
        }
        if has("fridge", "refrigerator", "freezer", "kettle", "toaster", "blender", "coffee maker", "coffee machine", "espresso",
               "microwave", "stove", "oven", "dishwasher", "dish washer", "pan", "pot", "dishes", "plate", "mug", "air fryer", "rice cooker") {
            return .kitchenAndDining
        }
        if has("bike", "bicycle", "scooter", "stroller", "skateboard", "surfboard", "ski", "snowboard", "helmet", "ball", "racket",
               "treadmill", "dumbbell", "weights", "yoga", "golf", "kayak", "toy", "lego", "board game", "puzzle", "motorcycle") {
            return .getAroundAndPlay
        }
        if has("lamp", "light", "plant", "vase", "clock", "mirror", "painting", "poster", "print", "art", "frame", "candle", "rug", "curtain") {
            return .lightAndDecor
        }
        if has("shelf", "shelves", "shelving", "bookcase", "bookshelf", "cabinet", "wardrobe", "closet", "drawer", "dresser", "chest", "bin", "crate") {
            return .storage
        }

        switch VoxelModels.kind(spec()) {
        case .bed, .mattress, .crib, .quiltRack: return .sleep
        case .sofa, .chair, .beanBag, .bench, .ottoman: return .sitAndLounge
        case .desk, .monitor, .books, .binder: return .workAndStudy
        case .table, .kitchenware, .appliance, .stove, .dishwasher, .microwave, .grill: return .kitchenAndDining
        case .tv, .electronics: return .media
        case .dresser, .bookshelf, .trunk, .basket, .rack, .box, .suitcase, .bag, .toolbox, .clothes: return .storage
        case .lamp, .art, .photos, .framedPhotos, .plant, .rug, .decor, .mirror, .clock: return .lightAndDecor
        case .guitar, .piano, .keyboard, .drums: return .music
        case .toilet, .sink, .bathtub: return .bathAndLaundry
        case .bike, .scooter, .fitness, .board, .motorcycle, .stroller, .wheelchair, .toy: return .getAroundAndPlay
        case .fan, .vacuum, .ladder, .lawnMower, .trashCan, .petCrate, .petBed, .catTree, .screen: return .everythingElse
        }
    }

    /// The halls that have items, biggest first (ties in `allCases` order, curiosities
    /// always last), each with its items most valuable first (then by name).
    public static func halls(_ items: [Item]) -> [(hall: FunctionHall, items: [Item])] {
        let grouped = Dictionary(grouping: items) { of($0) }
        return grouped
            .map { hall, items in
                (hall: hall, items: items.sorted { a, b in
                    let va = a.saleValueCents ?? -1, vb = b.saleValueCents ?? -1
                    if va != vb { return va > vb }
                    if a.name != b.name { return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending }
                    return a.id < b.id
                })
            }
            .sorted { a, b in
                if (a.hall == .everythingElse) != (b.hall == .everythingElse) { return b.hall == .everythingElse }
                if a.items.count != b.items.count { return a.items.count > b.items.count }
                return order(a.hall) < order(b.hall)
            }
    }

    private static func order(_ hall: FunctionHall) -> Int { allCases.firstIndex(of: hall) ?? 0 }

    /// "4 pieces · est. $640" under the hall's sign.
    public static func subtitle(_ items: [Item]) -> String {
        MuseumLabel.piecesLine(pieces: items.count, valueCents: items.compactMap(\.saleValueCents).reduce(0, +))
    }
}
