import SwiftUI
import MooveKit

/// Flat 2D drawing of a floor plan, scaled to fit. Plan y points down the
/// screen, matching the 3D view's default camera.
struct FloorPlanSketch: View {
    var plan: FloorPlan
    var showLabels = true

    var body: some View {
        Canvas { ctx, size in
            let b = plan.bounds
            guard b.width > 0, b.depth > 0 else { return }
            let inset: CGFloat = 6
            let scale = min((size.width - inset * 2) / b.width, (size.height - inset * 2) / b.depth)
            let ox = (size.width - b.width * scale) / 2, oy = (size.height - b.depth * scale) / 2
            func pt(_ p: PlanPoint) -> CGPoint { CGPoint(x: ox + (p.x - b.minX) * scale, y: oy + (p.y - b.minY) * scale) }

            for room in plan.rooms {
                var path = Path()
                path.addLines(room.polygon.map(pt))
                path.closeSubpath()
                ctx.fill(path, with: .color(Self.color(room.kind)))
            }
            for wall in plan.wallSegments() {
                var path = Path()
                path.move(to: pt(wall.from))
                path.addLine(to: pt(wall.to))
                ctx.stroke(path, with: .color(.primary.opacity(0.75)), lineWidth: 1.5)
            }
            for window in plan.windows {
                var path = Path()
                path.move(to: pt(window.from))
                path.addLine(to: pt(window.to))
                ctx.stroke(path, with: .color(.blue.opacity(0.6)), lineWidth: 3)
            }
            guard showLabels else { return }
            for room in plan.rooms where room.kind != .hallway && min(room.widthM, room.depthM) * scale > 40 {
                ctx.draw(Text(room.name).font(.caption2.weight(.medium)).foregroundStyle(.primary), at: pt(room.centroid))
            }
        }
        .accessibilityLabel("Floor plan with \(plan.rooms.count) rooms")
    }

    static func color(_ kind: RoomKind) -> Color {
        switch kind {
        case .bedroom: Color(red: 0.80, green: 0.86, blue: 0.97)
        case .living: Color(red: 0.96, green: 0.90, blue: 0.80)
        case .kitchen: Color(red: 0.84, green: 0.94, blue: 0.84)
        case .dining: Color(red: 0.97, green: 0.86, blue: 0.82)
        case .bathroom: Color(red: 0.80, green: 0.93, blue: 0.95)
        case .office: Color(red: 0.90, green: 0.86, blue: 0.96)
        case .hallway, .other: Color(white: 0.90)
        }
    }
}

#Preview {
    FloorPlanSketch(plan: DemoHouse.floorPlan).frame(height: 260).padding()
}
