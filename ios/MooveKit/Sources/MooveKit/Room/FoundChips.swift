import Foundation

/// The live "Also found" chips during a scan. They show the detector's raw labels before the
/// crop classifier (after the scan) and vision (on the worker) have checked them, so kinds
/// the detector often invents are left out: on real iPad scans "vacuum" was mostly a mop,
/// broom, tripod, dolly or scooter, "bin" a cardboard box, "heater" a radiator, "room
/// divider" a shower curtain or door (#378, docs/object-recognition.md). The objects
/// themselves are still imported and rechecked; only the chip is hidden.
public enum FoundChips {
    public static let hiddenCategories: Set<String> = [
        "vacuum", "bin", "toy", "bean bag", "heater", "room divider", "workbench", "crib",
        "humidifier", "air purifier", "sewing machine", "water dispenser", "plant stand",
    ]

    /// Kinds to show, newest first, with how many of each.
    public static func counts(_ found: [String]) -> [(name: String, n: Int)] {
        var order: [String] = []
        var n: [String: Int] = [:]
        for f in found where !hiddenCategories.contains(f.lowercased()) {
            if n[f] == nil { order.append(f) }
            n[f, default: 0] += 1
        }
        return order.reversed().map { (name: $0, n: n[$0]!) }
    }
}
