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
                ctx.stroke(path, with: .color(Theme.planWall), lineWidth: 1.5)
            }
            for window in plan.windows {
                var path = Path()
                path.move(to: pt(window.from))
                path.addLine(to: pt(window.to))
                ctx.stroke(path, with: .color(Theme.slate), lineWidth: 3)
            }
            guard showLabels else { return }
            for room in plan.rooms where room.kind != .hallway && min(room.widthM, room.depthM) * scale > 40 {
                ctx.draw(Text(room.name).font(.mono(10, weight: .bold)).foregroundStyle(Theme.text), at: pt(room.centroid))
            }
        }
        .accessibilityLabel("Floor plan with \(plan.rooms.count) rooms")
    }

    /// Muted, warm floor tints per room type; same family as the 3D view.
    static func color(_ kind: RoomKind) -> Color {
        switch kind {
        case .bedroom: Theme.accentSoft
        case .living: Theme.planFloor
        case .kitchen: Theme.surface
        case .dining: Theme.dangerSoft
        case .bathroom: Theme.surface2
        case .office: Theme.accentSoft
        case .hallway, .other: Theme.surface
        }
    }
}

#Preview {
    FloorPlanSketch(plan: DemoHouse.floorPlan).frame(height: 260).padding()
}
