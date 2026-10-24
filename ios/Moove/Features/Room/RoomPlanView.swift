import SwiftUI
import MooveKit

/// Top-down floor plan drawn from the same geometry: walls with door swings
/// and windows, furniture as colored footprints with labels, and a 1 m scale bar.
struct RoomPlanView: View {
    let geometry: RoomGeometry
    let items: [String: Item]
    let mode: RoomPalette.Mode
    let showLabels: Bool
    @Binding var selection: String?

    private let wallThickness: Float = 0.12

    var body: some View {
        GeometryReader { proxy in
            let map = PlanMapping(geometry: geometry, size: proxy.size)
            Canvas { context, _ in
                drawFloors(&context, map)
                drawObjects(&context, map)
                drawWalls(&context, map)
                drawScaleBar(&context, map, size: proxy.size)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                let p = map.world(location)
                let hit = geometry.objects.last { object in
                    contains(RoomGeometry.footprint(width: object.dimensions.x, depth: object.dimensions.z, object.transform), p)
                }
                selection = (hit?.id == selection) ? nil : hit?.id
            }
        }
    }

    // MARK: Layers

    private func drawFloors(_ context: inout GraphicsContext, _ map: PlanMapping) {
        for outline in geometry.floorOutlines {
            let path = map.path(outline)
            context.fill(path, with: .color(Color(RoomPalette.floor)))
            context.stroke(path, with: .color(Color(RoomPalette.floorEdge).opacity(0.5)), lineWidth: 1)
        }
    }

    private func drawObjects(_ context: inout GraphicsContext, _ map: PlanMapping) {
        // Highest tops last, so things sitting on others (photos on a nightstand) show.
        for object in geometry.objects.sorted(by: { $0.transform.position.y + $0.dimensions.y / 2 < $1.transform.position.y + $1.dimensions.y / 2 }) {
            let item = items[object.id]
            let selected = object.id == selection
            let color = Color(RoomPalette.color(for: object, item: item, mode: mode))
            let corners = RoomGeometry.footprint(width: object.dimensions.x, depth: object.dimensions.z, object.transform)
            let path = map.path(corners, cornerRadius: 4)
            context.fill(path, with: .color(color.opacity(0.9)))
            context.stroke(path, with: .color(selected ? .primary : .black.opacity(0.3)), lineWidth: selected ? 3 : 1.2)

            guard showLabels || selected else { continue }
            let center = map.point(SIMD2(object.transform.position.x, object.transform.position.z))
            var name = item?.name ?? object.category.capitalized
            if item?.maybeSentimental == true { name += " ♥" }
            let text = context.resolve(Text(name).font(.caption2.weight(.semibold)).foregroundStyle(.black.opacity(0.8)))
            let footprintWidth = CGFloat(max(object.dimensions.x, object.dimensions.z)) * map.scale
            if text.measure(in: CGSize(width: 400, height: 40)).width < footprintWidth + 24 || selected {
                context.draw(text, at: center)
            }
        }
    }

    private func drawWalls(_ context: inout GraphicsContext, _ map: PlanMapping) {
        let wallColor = Color(RoomPalette.wallTop)
        for wall in geometry.walls {
            let footprint = RoomGeometry.footprint(width: wall.dimensions.x, depth: wallThickness, wall.transform)
            context.fill(map.path(footprint), with: .color(wallColor))
            let center = geometry.bounds.map { ($0.min + $0.max) / 2 } ?? .zero
            let inward: Float = wall.transform.inverseApply(center).z < 0 ? -1 : 1
            for hole in geometry.holes(in: wall) {
                drawHole(&context, map, wall: wall, hole: hole, inward: inward)
            }
        }
    }

    private func drawHole(_ context: inout GraphicsContext, _ map: PlanMapping, wall: RoomGeometry.Surface, hole: WallHole, inward: Float) {
        let center = wall.transform.apply(SIMD3(hole.center.x, 0, 0))
        let gap = RoomGeometry.footprint(width: hole.size.x, depth: wallThickness + 0.02,
                                         .at(center, yaw: wall.transform.yaw))
        switch hole.kind {
        case .door, .opening:
            context.fill(map.path(gap), with: .color(Color(RoomPalette.floor)))
            guard hole.kind == .door else { return }
            // Leaf + quarter-circle swing from the hinge side.
            let hingeWorld = wall.transform.apply(SIMD3(hole.center.x - hole.size.x / 2, 0, 0))
            let tipClosed = wall.transform.apply(SIMD3(hole.center.x + hole.size.x / 2, 0, 0))
            let tipOpen = wall.transform.apply(SIMD3(hole.center.x - hole.size.x / 2, 0, inward * hole.size.x))
            let hinge = map.point(SIMD2(hingeWorld.x, hingeWorld.z))
            let a = map.point(SIMD2(tipClosed.x, tipClosed.z)), b = map.point(SIMD2(tipOpen.x, tipOpen.z))
            var swing = Path()
            swing.move(to: a)
            swing.addQuadCurve(to: b, control: CGPoint(x: a.x + b.x - hinge.x, y: a.y + b.y - hinge.y))
            context.stroke(swing, with: .color(Color(RoomPalette.door).opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            var leaf = Path()
            leaf.move(to: hinge)
            leaf.addLine(to: b)
            context.stroke(leaf, with: .color(Color(RoomPalette.door)), lineWidth: 3)
        case .window:
            context.fill(map.path(gap), with: .color(Color(RoomPalette.glass).opacity(1)))
            context.stroke(map.path(gap), with: .color(Color(RoomPalette.wallTop)), lineWidth: 1)
        case .wall:
            break
        }
    }

    private func drawScaleBar(_ context: inout GraphicsContext, _ map: PlanMapping, size: CGSize) {
        let length = map.scale  // 1 m
        let origin = CGPoint(x: 16, y: size.height - 18)
        var bar = Path()
        bar.move(to: origin)
        bar.addLine(to: CGPoint(x: origin.x + length, y: origin.y))
        bar.move(to: CGPoint(x: origin.x, y: origin.y - 4)); bar.addLine(to: CGPoint(x: origin.x, y: origin.y + 4))
        bar.move(to: CGPoint(x: origin.x + length, y: origin.y - 4)); bar.addLine(to: CGPoint(x: origin.x + length, y: origin.y + 4))
        context.stroke(bar, with: .color(.secondary), lineWidth: 1.5)
        context.draw(Text("1 m").font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: origin.x + length / 2, y: origin.y - 9))
    }

    private func contains(_ polygon: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}

/// World (x, z) meters ↔ view points, fitted with padding; +z points down the screen.
private struct PlanMapping {
    let scale: CGFloat
    let offset: CGPoint
    let minX: Float, minZ: Float

    init(geometry: RoomGeometry, size: CGSize) {
        let b = geometry.bounds ?? (SIMD3(-2, 0, -2), SIMD3(2, 0, 2))
        let w = CGFloat(max(b.max.x - b.min.x, 0.5)), d = CGFloat(max(b.max.z - b.min.z, 0.5))
        let pad: CGFloat = 28
        scale = min((size.width - pad * 2) / w, (size.height - pad * 2) / d)
        offset = CGPoint(x: (size.width - w * scale) / 2, y: (size.height - d * scale) / 2)
        minX = b.min.x
        minZ = b.min.z
    }

    func point(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: offset.x + CGFloat(p.x - minX) * scale, y: offset.y + CGFloat(p.y - minZ) * scale)
    }

    func world(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2(Float((p.x - offset.x) / scale) + minX, Float((p.y - offset.y) / scale) + minZ)
    }

    func path(_ polygon: [SIMD2<Float>], cornerRadius: CGFloat = 0) -> Path {
        let pts = polygon.map(point)
        guard cornerRadius > 0, pts.count == 4 else {
            var path = Path()
            path.addLines(pts)
            path.closeSubpath()
            return path
        }
        // Rounded rotated rectangle: build axis-aligned, then rotate into place.
        let center = CGPoint(x: pts.map(\.x).reduce(0, +) / 4, y: pts.map(\.y).reduce(0, +) / 4)
        let w = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y), h = hypot(pts[2].x - pts[1].x, pts[2].y - pts[1].y)
        let angle = atan2(pts[1].y - pts[0].y, pts[1].x - pts[0].x)
        let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let r = min(cornerRadius, min(w, h) / 3)
        return Path(roundedRect: rect, cornerRadius: r)
            .applying(CGAffineTransform(rotationAngle: angle))
            .applying(CGAffineTransform(translationX: center.x, y: center.y))
    }
}
