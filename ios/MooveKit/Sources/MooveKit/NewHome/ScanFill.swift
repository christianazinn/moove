import Foundation

/// Common-sense spots in a scanned room for items the scan didn't locate (the photo sweep's
/// finds, which have no RoomPlan object): an ottoman or stool tucks under a desk or table it fits
/// beneath, and a wall TV hangs over the TV stand, desk or dresser (`PropPlacer` hangs it on the
/// wall nearest the spot given here). Everything else is left to `LayoutSolver` / `PropPlacer`.
public enum ScanFill {
    /// Headroom an ottoman needs under a desk or table top.
    static let tuckClearanceM = 0.1

    /// Placements for the `unmatched` items that have an obvious spot next to the `placed`
    /// (scanned) pieces. `items` sizes both.
    public static func anchored(_ unmatched: [LayoutItem], around placed: [Placement], items: [LayoutItem], room: String) -> [Placement] {
        var sizes: [UInt64: LayoutItem] = [:]
        for item in items + unmatched where sizes[item.id] == nil { sizes[item.id] = item }
        let here = placed.filter { $0.room == room && $0.onTopOf == nil && $0.wallMounted != true }
        func hosts(_ roles: [DesignRole]) -> [(Placement, LayoutItem)] {
            roles.flatMap { r in here.compactMap { p in sizes[p.itemId].flatMap { DesignRole.of($0) == r ? (p, $0) : nil } } }
        }
        var out: [Placement] = []
        var taken = Set<UInt64>()
        for item in unmatched.sorted(by: { $0.id < $1.id }) {
            if tucks(item) {
                // Under the first desk or table it fits beneath, one per host.
                let host = hosts([.desk, .diningTable, .sideTable, .coffeeTable, .nightstand]).first { p, h in
                    !taken.contains(p.itemId) && h.heightM - item.heightM >= tuckClearanceM
                        && item.widthM <= h.widthM && item.depthM <= h.depthM
                }
                if let (p, _) = host {
                    taken.insert(p.itemId)
                    out.append(Placement(itemId: item.id, room: room, x: p.x, y: p.y, rotationDeg: p.rotationDeg))
                }
            } else if VoxelModels.kind(VoxelItemSpec(item)) == .tv, PropPlacer.role(of: VoxelItemSpec(item)) == .wall,
                      let (p, _) = hosts([.tvStand, .desk, .dresser]).first {
                // Over the piece a wall TV usually hangs above, not on whatever wall is nearest the middle.
                out.append(Placement(itemId: item.id, room: room, x: p.x, y: p.y, rotationDeg: p.rotationDeg))
            }
        }
        return out
    }

    /// An ottoman, footstool or stool low enough to slide under a desk.
    static func tucks(_ item: LayoutItem) -> Bool {
        let kind = VoxelModels.kind(VoxelItemSpec(item))
        let n = VName(item.name.lowercased())
        return kind == .ottoman || (kind == .chair && n.word("stool", "footstool") && item.heightM < 0.6)
    }
}
