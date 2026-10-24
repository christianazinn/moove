import RealityKit
import UIKit
import MooveKit

/// The kept items as boxes in the new home, plus the fly-in: items start piled
/// beside the house (the "old room"), lift, arc over the walls and settle into
/// their layout spots, staggered. Switching layouts glides them to new spots.
@MainActor
final class FurnitureLayer {
    let root = Entity()
    private var entities: [UInt64: ModelEntity] = [:]
    private var items: [UInt64: LayoutItem] = [:]
    private var flight: Task<Void, Never>?

    /// Shows `placements`, flying in from the old-room pile if `flyIn`, otherwise gliding from where items are.
    func show(_ placements: [Placement], items list: [LayoutItem], plan: FloorPlan, flyIn: Bool) {
        flight?.cancel()
        items = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let placed = placements.filter { items[$0.itemId] != nil }
        let wanted = Set(placed.map(\.itemId))
        for (id, e) in entities where !wanted.contains(id) {
            e.removeFromParent()
            entities[id] = nil
        }
        var newcomers = Set<UInt64>()
        for p in placed where entities[p.itemId] == nil {
            let e = Self.entity(for: items[p.itemId]!)
            entities[p.itemId] = e
            root.addChild(e)
            newcomers.insert(p.itemId)
        }

        if flyIn {
            let pile = Self.pile(placed.compactMap { items[$0.itemId] }, beside: plan.bounds)
            for p in placed { if let t = pile[p.itemId] { entities[p.itemId]?.transform = t } }
            // Biggest pieces first, like real movers.
            let order = placed.sorted { area($0) > area($1) }
            flight = Task { [weak self] in
                for (i, p) in order.enumerated() {
                    if i > 0 { try? await Task.sleep(for: .milliseconds(110)) }
                    guard let self, !Task.isCancelled, let e = self.entities[p.itemId] else { return }
                    self.launch(e, to: self.transform(for: p))
                }
            }
        } else {
            for p in placed {
                guard let e = entities[p.itemId] else { continue }
                let target = transform(for: p)
                if newcomers.contains(p.itemId) {
                    e.transform = target
                } else {
                    _ = e.move(to: target, relativeTo: root, duration: 0.7, timingFunction: .easeInOut)
                }
            }
        }
    }

    private func area(_ p: Placement) -> Double {
        items[p.itemId].map { $0.widthM * $0.depthM } ?? 0
    }

    private func transform(for p: Placement) -> Transform {
        let h = Float(items[p.itemId]?.heightM ?? 0.5)
        return Transform(
            scale: .one,
            rotation: simd_quatf(angle: Float(p.rotationDeg * .pi / 180), axis: [0, 1, 0]),
            translation: [Float(p.x), h / 2, Float(p.y)]
        )
    }

    /// Up to an apex above the midpoint, then down onto the spot: a two-segment arc.
    private func launch(_ e: ModelEntity, to target: Transform) {
        let start = e.transform
        let distance = simd_distance(start.translation, target.translation)
        var apex = target
        apex.translation = (start.translation + target.translation) / 2
        apex.translation.y = max(start.translation.y, target.translation.y) + 1.6 + distance * 0.12
        apex.rotation = simd_slerp(start.rotation, target.rotation, 0.5)
        let up = 0.5 + Double(distance) * 0.02, down = 0.45 + Double(distance) * 0.015
        _ = e.move(to: apex, relativeTo: root, duration: up, timingFunction: .easeOut)
        Task { [weak e] in
            try? await Task.sleep(for: .seconds(up))
            guard let e, !Task.isCancelled else { return }
            _ = e.move(to: target, relativeTo: e.parent, duration: down, timingFunction: .easeIn)
        }
    }

    // MARK: Look

    /// Items laid out in rows to the left of the house: where the fly-in starts.
    private static func pile(_ items: [LayoutItem], beside b: PlanBounds) -> [UInt64: Transform] {
        var out: [UInt64: Transform] = [:]
        let columns = 3
        var x = 0.0, z = 0.0, rowDepth = 0.0, col = 0
        let originX = b.minX - 6.0, originZ = b.center.y - 3
        for item in items.sorted(by: { $0.id < $1.id }) {
            if col == columns { col = 0; x = 0; z += rowDepth + 0.3; rowDepth = 0 }
            out[item.id] = Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: [Float(originX + x + item.widthM / 2), Float(item.heightM / 2), Float(originZ + z + item.depthM / 2)])
            x += item.widthM + 0.3
            rowDepth = max(rowDepth, item.depthM)
            col += 1
        }
        return out
    }

    private static func entity(for item: LayoutItem) -> ModelEntity {
        let w = Float(item.widthM), h = Float(item.heightM), d = Float(item.depthM)
        let corner = min(0.04, min(w, h, d) / 4)
        let color = Self.color(item.category)
        let body = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d, cornerRadius: corner), materials: [Self.material(color)])
        // A darker strip on the front face shows which way the piece faces.
        let front = ModelEntity(mesh: .generateBox(width: w * 0.6, height: min(0.06, h * 0.3), depth: 0.01),
                                materials: [Self.material(color.withAlphaComponent(1).darker())])
        front.position = [0, h / 2 - min(0.06, h * 0.3), d / 2 + 0.006]
        body.addChild(front)
        body.name = item.name
        return body
    }

    private static func material(_ color: UIColor) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: 0.6)
        m.metallic = .init(floatLiteral: 0)
        return m
    }

    /// Muted, warm palette matching the app theme: sage, slate, wood, ochre, terracotta.
    static func color(_ category: String) -> UIColor {
        switch category.lowercased() {
        case "bed": Theme.uiColor(0x7B8B99)
        case "sofa", "couch": Theme.uiColor(0x8B9A7B)
        case "table", "desk": Theme.uiColor(0xA88B66)
        case "chair": Theme.uiColor(0x6E7E5F)
        case "storage", "dresser", "nightstand", "bookshelf": Theme.uiColor(0xB9A07A)
        case "lamp": Theme.uiColor(0xB48A3E)
        case "appliance": Theme.uiColor(0x8F8577)
        case "decor", "plant": Theme.uiColor(0xB0563D)
        default: Theme.uiColor(0x9C9383)
        }
    }
}

private extension UIColor {
    func darker() -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.6, green: g * 0.6, blue: b * 0.6, alpha: a)
    }
}
