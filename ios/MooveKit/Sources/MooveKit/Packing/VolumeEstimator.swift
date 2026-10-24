import Foundation

/// Truck size, crew and a mover cost range from what's moving.
///
/// - Load: loose furniture volume × 1.15 plus box volume × 1.05 (packing slack).
///   The keep-with-you box and sentimental pieces that ride in the car don't count.
/// - Truck: the smallest one the load fills to 85% or less; past a 26 ft truck,
///   as many 26 ft trucks as it takes.
/// - Crew: 2 movers, 3 over 20 m³. Hours: 1.5 + 0.35 per m³, rounded up to the half hour.
/// - Cost: hours × movers × $45-$65 an hour, plus $40-$120 per truck.
public enum VolumeEstimator {
    public static let maxFill = 0.85

    /// - Parameters:
    ///   - items: the inventory (filtered like `PackingPlanner.plan`: kept items
    ///     plus undecided sentimental ones). Boxed items are counted via `boxes`.
    ///   - boxes: the plan's boxes.
    public static func estimate(items: [Item], boxes: [MovingBox]) -> TruckEstimate {
        let furniture = PackingPlanner.movingItems(items)
            .filter { PackingPlanner.handling(of: $0, room: "").onTruckLoose }
            .reduce(0) { $0 + $1.volumeM3 }
        let boxed = boxes.filter { !$0.keepWithYou }.reduce(0) { $0 + $1.size.volumeM3 }
        let load = furniture * 1.15 + boxed * 1.05
        guard load > 0 else { return .zero }

        let truck: TruckSize
        let trucks: Int
        if let fit = TruckSize.allCases.first(where: { load <= $0.capacityM3 * maxFill }) {
            truck = fit
            trucks = 1
        } else {
            truck = .ft26
            trucks = Int((load / (TruckSize.ft26.capacityM3 * maxFill)).rounded(.up))
        }
        let movers = load > 20 ? 3 : 2
        let hours = ((1.5 + load * 0.35) * 2).rounded(.up) / 2
        let crewHours = hours * Double(movers)
        let low = Int64((crewHours * 4_500).rounded()) + Int64(trucks) * 4_000
        let high = Int64((crewHours * 6_500).rounded()) + Int64(trucks) * 12_000
        return TruckEstimate(loadM3: (load * 100).rounded() / 100, truck: truck, trucks: trucks, moverHours: hours,
                             movers: movers, costLowCents: low, costHighCents: high)
    }
}
