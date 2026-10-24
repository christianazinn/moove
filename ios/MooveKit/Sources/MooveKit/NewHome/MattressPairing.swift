import Foundation

/// A mattress that belongs on a bed frame going to the same home (a bought mattress for the
/// kept frame, or a kept one whose bed matches) isn't a second bed: the layout puts it on the
/// frame. It gets the bed's spot, room and rotation, `onTopOf` the bed, and is drawn as part
/// of the bed (the bed model already shows a mattress), so it never claims Bedroom 2.
public enum MattressPairing {
    /// Footprints this close (either way round) are the same bed size.
    static let tolerance = 0.15
    /// A piece named a frame (or "bed frame") takes a mattress up to this far off.
    static let frameTolerance = 0.25

    static func kind(_ item: LayoutItem) -> VoxelModels.Kind { VoxelModels.kind(VoxelItemSpec(item)) }

    public static func isMattress(_ item: LayoutItem) -> Bool { kind(item) == .mattress }

    /// A bed a mattress can go on: not a bunk (its own two decks), not a crib.
    static func isFrame(_ item: LayoutItem) -> Bool {
        guard kind(item) == .bed else { return false }
        let n = item.name.lowercased()
        return !n.contains("bunk") && item.heightM < 1.2
    }

    static func namedFrame(_ item: LayoutItem) -> Bool { item.name.lowercased().contains("frame") }

    /// How far apart two footprints are: the worse side's relative difference, best orientation.
    static func mismatch(_ a: LayoutItem, _ b: LayoutItem) -> Double {
        func rel(_ x: Double, _ y: Double) -> Double { abs(x - y) / max(x, y, 1e-6) }
        let straight = max(rel(a.widthM, b.widthM), rel(a.depthM, b.depthM))
        let turned = max(rel(a.widthM, b.depthM), rel(a.depthM, b.widthM))
        return min(straight, turned)
    }

    /// Mattress id -> the bed it goes on. Each bed takes one mattress; frames named as such
    /// first, then the closest size. Deterministic (ids break ties).
    public static func pairs(_ items: [LayoutItem]) -> [UInt64: UInt64] {
        let mattresses = items.filter(isMattress).sorted { $0.id < $1.id }
        guard !mattresses.isEmpty else { return [:] }
        var beds = items.filter(isFrame)
        var out: [UInt64: UInt64] = [:]
        for m in mattresses {
            let fits = beds.enumerated().compactMap { i, b -> (Int, Bool, Double, UInt64)? in
                let d = mismatch(m, b), frame = namedFrame(b)
                guard d <= (frame ? frameTolerance : tolerance) + 1e-9 else { return nil }
                return (i, frame, d, b.id)
            }
            guard let best = fits.min(by: { ($0.1 ? 0 : 1, $0.2, $0.3) < ($1.1 ? 0 : 1, $1.2, $1.3) }) else { continue }
            out[m.id] = beds[best.0].id
            beds.remove(at: best.0)
        }
        return out
    }

    /// The mattress's placement on its bed's: same spot, room and rotation, raised to sit on
    /// the frame (the bed's height when that is a frame or mattress-top height, minus the mattress).
    static func placement(_ mattress: LayoutItem, on bed: Placement, bedItem: LayoutItem) -> Placement {
        let top = min(bedItem.heightM, 0.7)
        let elevation = (max(0.05, top - mattress.heightM) * 1000).rounded() / 1000
        return Placement(itemId: mattress.id, room: bed.room, x: bed.x, y: bed.y, rotationDeg: bed.rotationDeg,
                         elevationM: elevation, onTopOf: bed.itemId)
    }

    /// Mattresses sitting on a bed in `placements`: the 3D views draw them as part of the bed.
    public static func drawnWithBed(_ placements: [Placement], items: [LayoutItem]) -> Set<UInt64> {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Set(placements.compactMap { p in
            guard let parent = p.onTopOf, let m = byId[p.itemId], isMattress(m),
                  let bed = byId[parent], isFrame(bed) else { return nil }
            return p.itemId
        })
    }
}

extension LayoutSolver {
    /// Solves with paired mattresses taken out, then puts each on its bed (or keeps it with its
    /// bed in storage / unplaced).
    func solvePairingMattresses(_ items: [LayoutItem], _ solve: ([LayoutItem]) -> LayoutOption) -> LayoutOption {
        let pairs = MattressPairing.pairs(items)
        guard !pairs.isEmpty else { return solve(items) }
        var option = solve(items.filter { pairs[$0.id] == nil })
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let bedSpots = Dictionary(option.placements.map { ($0.itemId, $0) }, uniquingKeysWith: { a, _ in a })
        for (mattressId, bedId) in pairs.sorted(by: { $0.key < $1.key }) {
            guard let mattress = byId[mattressId], let bedItem = byId[bedId] else { continue }
            if let bed = bedSpots[bedId] {
                option.placements.append(MattressPairing.placement(mattress, on: bed, bedItem: bedItem))
            } else {
                option.unplaced.append(mattressId)
                if option.stored.contains(bedId) { option.stored.append(mattressId) }
            }
        }
        return option
    }
}
