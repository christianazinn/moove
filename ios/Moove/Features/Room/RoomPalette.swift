import SwiftUI
import UIKit
import MooveKit

/// Colors for the room views: soft "dollhouse" surfaces, plus a bright color
/// per object either by furniture category or by keep/sell/donate/trash.
enum RoomPalette {
    enum Mode: String, CaseIterable, Identifiable {
        case category, decision
        var id: String { rawValue }
        var label: String { self == .category ? "Furniture" : "Decision" }
    }

    static let floor = UIColor(red: 0.91, green: 0.84, blue: 0.74, alpha: 1)       // light oak
    static let floorEdge = UIColor(red: 0.74, green: 0.62, blue: 0.48, alpha: 1)
    static let wall = UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1)         // warm white
    static let wallTop = UIColor(red: 0.42, green: 0.44, blue: 0.5, alpha: 1)       // cut-line on wall tops
    static let door = UIColor(red: 0.69, green: 0.49, blue: 0.31, alpha: 1)         // walnut
    static let glass = UIColor(red: 0.55, green: 0.8, blue: 0.98, alpha: 0.45)

    static func category(_ category: String) -> UIColor {
        switch category.lowercased() {
        case "bed": hex(0x7C9EFF)
        case "sofa": hex(0xFF8FA3)
        case "chair": hex(0xFFB357)
        case "table": hex(0x4FC9A4)
        case "storage": hex(0xB388FF)
        case "lamp": hex(0xFFD84D)
        case "television": hex(0x5B6B8C)
        case "refrigerator", "stove", "oven", "dishwasher", "washerdryer", "appliance": hex(0x5CCBF2)
        case "sink", "toilet", "bathtub": hex(0x9FE3F5)
        case "fireplace": hex(0xE07A5F)
        case "stairs": hex(0xC9B79C)
        case "decor": hex(0xFF7EB6)
        default: hex(0xA0AEC0)
        }
    }

    /// The theme's disposition swatches (sage keep, ochre sell, slate donate, stone trash,
    /// clay undecided), fixed rather than adaptive so RealityKit materials and the black
    /// plan labels read the same in light and dark mode.
    static func decision(_ item: Item?) -> UIColor {
        guard let item else { return hex(0xC9BFAE) }
        switch item.disposition {
        case .keep: return hex(0x8B9A7B)
        case .sell: return hex(0xC9A35A)
        case .donate: return hex(0x93A3B1)
        case .trash: return hex(0xA39887)
        case .undecided: return hex(0xD27A5E)
        }
    }

    static func color(for object: RoomGeometry.Object, item: Item?, mode: Mode) -> UIColor {
        mode == .category ? category(object.category) : decision(item)
    }

    private static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
