import Foundation

/// What a piece does in a room, for the designer layout ([decision 0300](../../../../../docs/decisions/0300-new-home-layout-design.md)).
/// From the voxel kind (`VoxelModels.kind`: fix-it kind, RoomPlan attributes, name words, size),
/// `PropPlacer.role` (small things and wall pieces), and a few name words. Bathroom fixtures are
/// matched on their category/name words ("toilet", "sink", "bathtub"), so they work before the
/// voxel models have kinds for them.
public enum DesignRole: String, Sendable, Hashable, CaseIterable {
    case bed, nightstand, dresser, wardrobe
    case sofa, armchair, coffeeTable, sideTable, tvStand, tv, rug, floorLamp
    case diningTable, diningChair, desk, deskChair, bookshelf
    case kitchen, toilet, sink, bathtub
    case plant, tableLamp, prop, wall, other

    public static func of(_ item: LayoutItem) -> DesignRole { of(VoxelItemSpec(item)) }

    static func of(_ spec: VoxelItemSpec) -> DesignRole {
        let cat = VoxelModels.trimmed(spec.category.lowercased())
        let n = VName(spec.name.lowercased())
        if cat == "toilet" || n.word("toilet", "wc") { return .toilet }
        if ["bathtub", "bath", "tub", "shower"].contains(cat) || n.has("bathtub", "bath tub") || n.word("tub", "shower") { return .bathtub }
        if cat == "sink" || n.has("vanity", "washbasin", "wash basin") || n.word("sink") {
            return n.has("kitchen") ? .kitchen : .sink
        }
        let mount = PropPlacer.role(of: spec)
        let kind = VoxelModels.kind(spec)
        if mount == .wall { return .wall }
        if mount == .prop { return kind == .lamp ? .tableLamp : .prop }
        let w = spec.widthM.isFinite ? spec.widthM : 0, h = spec.heightM.isFinite ? spec.heightM : 0
        // RoomPlan's plain "storage" box is any cabinet: tell them apart by shape.
        if ["storage", "cabinet"].contains(cat), kind == .bookshelf || kind == .dresser,
           !n.has("shelf", "bookcase", "book case", "kallax", "tv", "media", "wardrobe", "armoire") {
            if w > 0 && w <= 0.65 && h > 0 && h <= 0.8 { return .nightstand }
            if h > 0 && h < 1.25 { return .dresser }
            return spec.depthM > 0.45 ? .wardrobe : .bookshelf
        }
        switch kind {
        case .bed, .mattress: return .bed
        case .sofa:
            if n.has("armchair", "arm chair", "accent chair", "recliner", "club chair", "lounge chair") { return .armchair }
            return w > 0 && w < 1.2 ? .armchair : .sofa
        case .beanBag: return .armchair
        case .chair:
            if n.has("office", "desk chair", "task chair", "gaming", "swivel", "computer chair") { return .deskChair }
            if n.has("armchair", "arm chair", "accent", "lounge", "rocking", "recliner") { return .armchair }
            return .diningChair
        case .table:
            if n.has("coffee", "cocktail") { return .coffeeTable }
            if n.has("side table", "end table", "accent table") { return .sideTable }
            if n.has("nightstand", "night stand", "bedside") { return .nightstand }
            if n.has("desk") { return .desk }
            if h > 0 && h < 0.55 { return .coffeeTable }
            return .diningTable
        case .desk: return .desk
        case .dresser:
            if n.has("tv stand", "television stand", "media console", "tv console", "entertainment center", "media cabinet", "tv unit") { return .tvStand }
            if n.has("wardrobe", "armoire", "closet") { return .wardrobe }
            if n.has("nightstand", "night stand", "bedside") || (w > 0 && w <= 0.65 && h > 0 && h <= 0.8) { return .nightstand }
            return h >= 1.5 ? .wardrobe : .dresser
        case .bookshelf: return .bookshelf
        case .tv: return .tv
        case .rug: return .rug
        case .lamp: return .floorLamp
        case .appliance, .stove, .dishwasher, .microwave, .kitchenware: return .kitchen
        case .plant: return .plant
        default: return .other
        }
    }

    /// Two beds this narrow (or a bunk) can share a kids' room.
    static let twinWidthM = 1.15

    /// Bathroom fixtures.
    var isBath: Bool { self == .toilet || self == .sink || self == .bathtub }
}
