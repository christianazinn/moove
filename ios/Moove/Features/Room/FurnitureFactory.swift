import RealityKit
import UIKit
import MooveKit

/// Builds a simple procedural stand-in for a scanned object (bed, sofa, chair,
/// ...) from `FurnitureLayout` parts. The root's origin is the center of the
/// measured box and its axes are the box axes (x width, y height, z depth,
/// front = +Z); every part stays inside ±size/2. Returns nil for categories
/// with no layout, so the caller keeps the plain colored box.
///
/// No collision or input components: the caller keeps those on the object
/// entity and re-tints descendants for highlight/decision color.
@MainActor
enum FurnitureFactory {
    static func makeEntity(category: String, size: SIMD3<Float>, tint: UIColor) -> Entity? {
        guard let parts = FurnitureLayout.parts(category: category, size: size), !parts.isEmpty else { return nil }
        let root = Entity()
        for part in parts {
            let child = ModelEntity(mesh: mesh(part.shape, size: part.size), materials: [material(part.role, tint: tint)])
            child.position = part.center
            root.addChild(child)
        }
        return root
    }

    // MARK: Caches
    // Keyed by millimeter-quantized sizes and quantized tint. A room has a few
    // dozen objects with a handful of parts each, so these stay small; they are
    // cleared wholesale if they ever grow past `cacheLimit`.

    private struct MeshKey: Hashable { var kind: Int; var mm: SIMD3<Int32>; var radiusMM: Int32 }
    private struct MaterialKey: Hashable { var role: FurnitureLayout.Role; var rgba: SIMD4<UInt8> }

    private static let cacheLimit = 512
    private static var meshes: [MeshKey: MeshResource] = [:]
    private static var materials: [MaterialKey: PhysicallyBasedMaterial] = [:]

    private static func mesh(_ shape: FurnitureLayout.Shape, size: SIMD3<Float>) -> MeshResource {
        let size = pointwiseMax(size, SIMD3(repeating: 0.002))
        let mm = SIMD3<Int32>((size * 1000).rounded(.toNearestOrAwayFromZero))
        let key: MeshKey
        switch shape {
        case .box: key = MeshKey(kind: 0, mm: mm, radiusMM: 0)
        case .roundedBox(let r): key = MeshKey(kind: 1, mm: mm, radiusMM: Int32((r * 1000).rounded()))
        case .cylinder: key = MeshKey(kind: 2, mm: mm, radiusMM: 0)
        }
        if let cached = meshes[key] { return cached }
        let resource: MeshResource
        switch shape {
        case .box:
            resource = .generateBox(size: size)
        case .roundedBox(let r):
            resource = .generateBox(size: size, cornerRadius: max(0, min(r, size.min() / 2)))
        case .cylinder:
            if #available(iOS 18.0, *) {
                resource = .generateCylinder(height: size.y, radius: min(size.x, size.z) / 2)
            } else {
                // iOS 17 fallback: a box rounded to a pill in plan view.
                resource = .generateBox(size: size, cornerRadius: min(size.x, size.z) / 2 * 0.99)
            }
        }
        if meshes.count >= cacheLimit { meshes.removeAll() }
        meshes[key] = resource
        return resource
    }

    private static func material(_ role: FurnitureLayout.Role, tint: UIColor) -> PhysicallyBasedMaterial {
        let key = MaterialKey(role: role, rgba: tint.rgba8)
        if let cached = materials[key] { return cached }
        var m = PhysicallyBasedMaterial()
        let (color, roughness, metallic): (UIColor, Float, Float) = switch role {
        case .frame: (tint.darkened(0.2), 0.7, 0)
        case .cushion: (tint.lightened(0.35), 0.95, 0)
        case .top: (tint, 0.55, 0)
        case .leg: (RoomPalette.door, 0.6, 0)
        case .accent: (UIColor(red: 0.22, green: 0.23, blue: 0.25, alpha: 1), 0.35, 0.8)
        case .screen: (UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1), 0.15, 0)
        case .porcelain: (UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1), 0.3, 0)
        }
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: roughness)
        m.metallic = .init(floatLiteral: metallic)
        if materials.count >= cacheLimit { materials.removeAll() }
        materials[key] = m
        return m
    }
}

fileprivate extension UIColor {
    var rgba8: SIMD4<UInt8> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func q(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        return SIMD4(q(r), q(g), q(b), q(a))
    }

    /// Lower HSB brightness by `amount` (0...1, relative).
    func darkened(_ amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        guard getHue(&h, saturation: &s, brightness: &v, alpha: &a) else { return self }
        return UIColor(hue: h, saturation: s, brightness: v * (1 - amount), alpha: a)
    }

    /// Blend `amount` (0...1) of the way toward white.
    func lightened(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a)
    }
}
