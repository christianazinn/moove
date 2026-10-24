import Foundation

/// One color per destination room, shared by everything that draws boxes: the Pack screen's box
/// cards and tape, the printed labels, and the 3D truck. Deterministic: the same room name always
/// gets the same color, on every launch and device.
///
/// Every color is light enough that near-black ink (#1E1B16) on it passes 4.5:1, so box numbers and
/// room names print and read on top of it.
public enum PackingPalette {
    /// Room colors, most distinct first: sage, mustard, sky, coral, lavender, teal, sand, rose.
    public static let roomColors: [VoxelColor] = [
        0x9CC08A, 0xE3B651, 0x8DB4DE, 0xE8957A, 0xBBA3DB, 0x7CC4B8, 0xC9B79A, 0xE59BB8,
    ]
    /// The open-first tote: bright orange, unlike any room.
    public static let openFirst: VoxelColor = 0xF2A65A
    /// The keep-with-you box: soft gold.
    public static let keepWithYou: VoxelColor = 0xF0D264
    /// Ink for text on any of these colors.
    public static let ink: VoxelColor = 0x1E1B16

    /// Common rooms get a fixed color (all bedrooms start from sky); "Bedroom 2" shifts one along,
    /// so two bedrooms never share a color. Anything else is hashed from its name.
    static let fixed: [(word: String, index: Int)] = [
        ("living", 0), ("kitchen", 1), ("bed", 2), ("dining", 3), ("office", 4), ("study", 4),
        ("bath", 5), ("garage", 6), ("hall", 6), ("entry", 6),
    ]

    /// The color for a destination room ("Bedroom 2", "Kitchen", "Open first", "Keep with you").
    public static func color(forRoom room: String) -> VoxelColor {
        let name = room.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name == "open first" { return openFirst }
        if name == "keep with you" { return keepWithYou }
        if name.isEmpty || name == "any room" || name == "other" { return roomColors[6] }
        let n = roomColors.count
        if let hit = fixed.first(where: { name.contains($0.word) }) {
            return roomColors[(hit.index + max(0, trailingNumber(name) - 1)) % n]
        }
        // Not `hashValue`: that changes between launches.
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 31 }
        return roomColors[abs(sum) % n]
    }

    /// "#9CC08A"
    public static func hex(_ color: VoxelColor) -> String {
        let s = String(color & 0xFFFFFF, radix: 16, uppercase: true)
        return "#" + String(repeating: "0", count: max(0, 6 - s.count)) + s
    }

    /// Red, green and blue in 0...1.
    public static func rgb(_ color: VoxelColor) -> (r: Double, g: Double, b: Double) {
        (Double((color >> 16) & 0xFF) / 255, Double((color >> 8) & 0xFF) / 255, Double(color & 0xFF) / 255)
    }

    /// "Bedroom 2" -> 2; no number -> 1.
    static func trailingNumber(_ name: String) -> Int {
        let digits = name.reversed().prefix { $0.isNumber }
        return Int(String(digits.reversed())) ?? 1
    }
}

extension MovingBox {
    /// This box's room color (`PackingPalette`).
    public var roomColor: VoxelColor { PackingPalette.color(forRoom: room) }
}
