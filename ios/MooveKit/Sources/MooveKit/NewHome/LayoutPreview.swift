import Foundation

/// A top-down SVG of a floor plan and a layout: room outlines, doors, windows and each placed
/// piece as a labeled box with a tick on its front (+z). For checking layouts by eye (tests write
/// them when `MOOVE_LAYOUT_SVG_DIR` is set); not used by the app.
public enum LayoutPreview {
    public static func svg(plan: FloorPlan, items: [LayoutItem], placements: [Placement], title: String = "", pxPerM: Double = 60) -> String {
        let b = plan.bounds
        let pad = 0.6
        // Square, so Quick Look thumbnails don't crop it.
        let side = max(b.width, b.depth) + 2 * pad
        let w = side * pxPerM, h = side * pxPerM + 24
        // Plan y grows down the page, like the dollhouse seen from above with +z toward you.
        func X(_ x: Double) -> Double { (x - b.minX + pad) * pxPerM }
        func Y(_ y: Double) -> Double { (y - b.minY + pad) * pxPerM + 24 }
        func pt(_ p: PlanPoint) -> String { String(format: "%.1f,%.1f", X(p.x), Y(p.y)) }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        var out = String(format: "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%.0f\" height=\"%.0f\" viewBox=\"0 0 %.0f %.0f\">\n", w, h, w, h)
        out += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"
        out += "<text x=\"8\" y=\"17\" font-family=\"Helvetica\" font-size=\"14\" fill=\"#222\">\(esc(title))</text>\n"
        for r in plan.rooms {
            let fill = r.kind == .hallway ? "#eeeeee" : "#f7f3ea"
            out += "<polygon points=\"\(r.polygon.map(pt).joined(separator: " "))\" fill=\"\(fill)\" stroke=\"#333\" stroke-width=\"2\"/>\n"
            let c = r.centroid
            out += String(format: "<text x=\"%.1f\" y=\"%.1f\" font-family=\"Helvetica\" font-size=\"12\" fill=\"#aaa\" text-anchor=\"middle\">%@</text>\n",
                          X(c.x), Y(c.y), esc(r.name))
        }
        for d in plan.doors {
            out += "<line x1=\"\(String(format: "%.1f", X(d.from.x)))\" y1=\"\(String(format: "%.1f", Y(d.from.y)))\" x2=\"\(String(format: "%.1f", X(d.to.x)))\" y2=\"\(String(format: "%.1f", Y(d.to.y)))\" stroke=\"#f7f3ea\" stroke-width=\"5\"/>\n"
            out += "<line x1=\"\(String(format: "%.1f", X(d.from.x)))\" y1=\"\(String(format: "%.1f", Y(d.from.y)))\" x2=\"\(String(format: "%.1f", X(d.to.x)))\" y2=\"\(String(format: "%.1f", Y(d.to.y)))\" stroke=\"#d33\" stroke-width=\"2\" stroke-dasharray=\"4 3\"/>\n"
        }
        for wdw in plan.windows {
            out += "<line x1=\"\(String(format: "%.1f", X(wdw.from.x)))\" y1=\"\(String(format: "%.1f", Y(wdw.from.y)))\" x2=\"\(String(format: "%.1f", X(wdw.to.x)))\" y2=\"\(String(format: "%.1f", Y(wdw.to.y)))\" stroke=\"#39f\" stroke-width=\"5\"/>\n"
        }
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // Rugs first so pieces draw over them; then floor pieces; then props on top.
        let sorted = placements.sorted { a, b in
            func rank(_ p: Placement) -> Int {
                guard let i = byId[p.itemId] else { return 1 }
                if DesignRole.of(i) == .rug { return 0 }
                return p.onTopOf != nil || p.isWallMounted ? 2 : 1
            }
            return (rank(a), a.itemId) < (rank(b), b.itemId)
        }
        for p in sorted {
            guard let item = byId[p.itemId] else { continue }
            let r = OrientedRect(center: PlanPoint(p.x, p.y), halfWidth: item.widthM / 2, halfDepth: item.depthM / 2, rotationDeg: p.rotationDeg)
            let role = DesignRole.of(item)
            let color: String
            switch role {
            case .rug: color = "#e8d9c4"
            case .bed: color = "#9ec5e8"
            case .sofa, .armchair: color = "#b9e0a5"
            case .diningTable, .desk, .coffeeTable, .sideTable: color = "#f2c48d"
            case .diningChair, .deskChair: color = "#f6e08f"
            case .toilet, .sink, .bathtub: color = "#c9f0f0"
            default: color = "#d9d0e8"
            }
            let raised = p.onTopOf != nil || p.isWallMounted
            out += "<polygon points=\"\(r.corners.map(pt).joined(separator: " "))\" fill=\"\(color)\" fill-opacity=\"\(raised ? 0.85 : 0.9)\" stroke=\"\(raised ? "#c60" : "#555")\" stroke-width=\"\(raised ? 1.5 : 1)\"/>\n"
            let front = r.center + r.axes.z * r.halfDepth
            let tip = r.center + r.axes.z * (r.halfDepth + 0.12)
            out += "<line x1=\"\(String(format: "%.1f", X(front.x)))\" y1=\"\(String(format: "%.1f", Y(front.y)))\" x2=\"\(String(format: "%.1f", X(tip.x)))\" y2=\"\(String(format: "%.1f", Y(tip.y)))\" stroke=\"#c00\" stroke-width=\"2\"/>\n"
            let label = item.name.count > 16 ? String(item.name.prefix(15)) + "…" : item.name
            out += String(format: "<text x=\"%.1f\" y=\"%.1f\" font-family=\"Helvetica\" font-size=\"9\" fill=\"#111\" text-anchor=\"middle\">%@</text>\n",
                          X(r.center.x), Y(r.center.y) + 3, esc(label))
        }
        out += "</svg>\n"
        return out
    }
}
