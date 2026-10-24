import Foundation

/// Procedural low-poly furniture for a RoomPlan object box: a handful of boxes,
/// rounded boxes and cylinders per category, sized to fill the box. The app's
/// RealityKit `FurnitureFactory` turns the parts into meshes and materials.
///
/// Box-local space: origin at the box center, x width, y height (up), z depth.
/// The front of the furniture faces +Z (RoomPlan's object front); backs
/// (sofa/chair backs, bed headboard, toilet tank) sit at -Z.
public enum FurnitureLayout {
    public enum Shape: Equatable, Sendable {
        case box
        /// Radius in meters, already clamped <= min(size) / 2.
        case roundedBox(cornerRadius: Float)
        /// Axis +Y; diameter = size.x (size.x == size.z), height = size.y.
        case cylinder
    }

    public enum Role: String, Sendable, CaseIterable {
        /// Main body/structure (tint darkened).
        case frame
        /// Soft parts: mattress, seat/back cushions, pillows (tint lightened).
        case cushion
        /// Tabletops, counters, worktops (tint).
        case top
        /// Legs, feet (neutral wood).
        case leg
        /// Handles, knobs, trim, drawer lines (neutral dark metal).
        case accent
        /// TV screen, oven window, appliance glass (near-black glossy).
        case screen
        /// Toilet/sink/bathtub basins (white).
        case porcelain
    }

    public struct Part: Equatable, Sendable {
        public var shape: Shape
        /// Box-local, origin = box CENTER, x width, y height, z depth.
        public var center: SIMD3<Float>
        public var size: SIMD3<Float>
        public var role: Role

        public init(shape: Shape, center: SIMD3<Float>, size: SIMD3<Float>, role: Role) {
            self.shape = shape
            self.center = center
            self.size = size
            self.role = role
        }
    }

    /// nil for unknown categories (caller falls back to the colored box).
    public static func parts(category: String, size: SIMD3<Float>) -> [Part]? {
        guard [size.x, size.y, size.z].allSatisfy({ $0.isFinite && $0 > 0.02 }) else { return nil }
        let b = Builder(size: size)
        let parts: [Part]
        switch category.lowercased() {
        case "bed": parts = b.bed()
        case "sofa": parts = b.sofa()
        case "chair": parts = b.chair()
        case "table": parts = b.table()
        case "storage": parts = b.storage()
        case "television": parts = b.television()
        case "refrigerator": parts = b.refrigerator()
        case "stove": parts = b.stove(burners: true)
        case "oven": parts = b.stove(burners: false)
        case "dishwasher": parts = b.dishwasher()
        case "washerdryer": parts = b.washerDryer()
        case "toilet": parts = b.toilet()
        case "bathtub": parts = b.bathtub()
        case "sink": parts = b.sink()
        case "fireplace": parts = b.fireplace()
        case "stairs": parts = b.stairs()
        default: return nil
        }
        return parts.compactMap(b.contained)
    }

    /// Number of stair steps for a stairs box of height `height`.
    static func stepCount(height: Float) -> Int { min(max(Int((height / 0.18).rounded()), 2), 16) }

    /// Number of sofa seat cushions for a sofa's inner (between-arms) width.
    static func seatCount(innerWidth: Float) -> Int { innerWidth < 0.9 ? 1 : innerWidth < 1.6 ? 2 : 3 }
}

private func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(max(v, lo), hi) }

/// Builds parts in box-local coordinates from min/max corners. `x0`/`x1` etc. are
/// absolute box-local positions; `y(f)` is a height `f` meters above the bottom.
private struct Builder {
    typealias Part = FurnitureLayout.Part
    typealias Role = FurnitureLayout.Role
    let w: Float, h: Float, d: Float
    init(size: SIMD3<Float>) { (w, h, d) = (size.x, size.y, size.z) }

    var left: Float { -w / 2 }
    var right: Float { w / 2 }
    var back: Float { -d / 2 }
    var front: Float { d / 2 }
    var bottom: Float { -h / 2 }
    var top: Float { h / 2 }
    var foot: Float { min(w, d) }
    /// Leg thickness: 3-7 cm, never more than a fifth of the footprint.
    var legT: Float { min(clamp(foot * 0.06, 0.03, 0.07), foot / 5) }
    /// Front panel / door thickness.
    var skin: Float { min(clamp(d * 0.04, 0.01, 0.025), d / 8) }
    func y(_ f: Float) -> Float { bottom + f }

    func box(_ role: Role, _ lo: SIMD3<Float>, _ hi: SIMD3<Float>, radius: Float = 0) -> Part {
        let size = hi - lo
        let shape: FurnitureLayout.Shape = radius > 0 ? .roundedBox(cornerRadius: min(radius, size.min() / 2)) : .box
        return Part(shape: shape, center: (lo + hi) / 2, size: size, role: role)
    }

    func cylinder(_ role: Role, x: Float, z: Float, diameter: Float, y0: Float, y1: Float) -> Part {
        Part(shape: .cylinder, center: SIMD3(x, (y0 + y1) / 2, z), size: SIMD3(diameter, y1 - y0, diameter), role: role)
    }

    /// Four legs at the corners of the footprint `x0...x1`, `z0...z1`.
    func legs(x0: Float, x1: Float, z0: Float, z1: Float, y0: Float, y1: Float, t: Float, role: Role = .leg) -> [Part] {
        [(x0, z0), (x1 - t, z0), (x0, z1 - t), (x1 - t, z1 - t)].map { box(role, SIMD3($0.0, y0, $0.1), SIMD3($0.0 + t, y1, $0.1 + t)) }
    }

    /// Clamps a part into the box (safety net for tiny boxes) and drops empty ones.
    func contained(_ p: Part) -> Part? {
        let half = SIMD3(w, h, d) / 2
        var lo = pointwiseMax(p.center - p.size / 2, -half), hi = pointwiseMin(p.center + p.size / 2, half)
        if p.shape == .cylinder {
            let dia = min(hi.x - lo.x, hi.z - lo.z), cx = (lo.x + hi.x) / 2, cz = (lo.z + hi.z) / 2
            lo.x = cx - dia / 2; hi.x = cx + dia / 2; lo.z = cz - dia / 2; hi.z = cz + dia / 2
        }
        let size = hi - lo
        guard size.min() > 1e-4 else { return nil }
        var shape = p.shape
        if case .roundedBox(let r) = shape { shape = .roundedBox(cornerRadius: min(r, size.min() / 2)) }
        return Part(shape: shape, center: (lo + hi) / 2, size: size, role: p.role)
    }

    // MARK: - Categories

    func bed() -> [Part] {
        let legH = clamp(h * 0.1, 0.01, 0.1), baseTop = y(clamp(h * 0.3, legH + 0.01, 0.35)), mattTop = y(clamp(h * 0.55, h * 0.35, 0.6))
        let hbD = clamp(d * 0.06, 0.01, 0.08), z0 = back + hbD
        var parts = [
            box(.frame, SIMD3(left, y(legH), z0), SIMD3(right, baseTop, front)),
            box(.cushion, SIMD3(left + w * 0.02, baseTop, z0), SIMD3(right - w * 0.02, mattTop, front - d * 0.02), radius: 0.04),
            box(.frame, SIMD3(left, bottom, back), SIMD3(right, top, z0), radius: 0.02),
        ]
        let pillowH = min(0.12, (top - mattTop) * 0.8, h * 0.12), pillowD = min(0.4, d * 0.18)
        let n = w >= 0.9 ? 2 : 1, gap = w * 0.06, pw = (w - gap * Float(n + 1)) / Float(n)
        for i in 0..<n {
            let x0 = left + gap + Float(i) * (pw + gap)
            parts.append(box(.cushion, SIMD3(x0, mattTop, z0 + d * 0.03), SIMD3(x0 + pw, mattTop + pillowH, z0 + d * 0.03 + pillowD), radius: 0.04))
        }
        return parts + legs(x0: left + legT, x1: right - legT, z0: z0 + legT, z1: front - legT, y0: bottom, y1: y(legH), t: legT)
    }

    func sofa() -> [Part] {
        let legH = clamp(h * 0.1, 0.01, 0.08), baseTop = y(clamp(h * 0.3, legH + 0.02, 0.3)), seatTop = baseTop + clamp(h * 0.15, 0.02, 0.15)
        let armW = min(clamp(w * 0.1, 0.06, 0.2), w * 0.15), armTop = y(clamp(h * 0.65, h * 0.4, 0.65))
        let backFrameD = min(clamp(d * 0.12, 0.04, 0.15), d * 0.2), backCushD = min(clamp(d * 0.15, 0.05, 0.2), d * 0.2)
        let x0 = left + armW, x1 = right - armW, seatZ = back + backFrameD + backCushD
        var parts = [
            box(.frame, SIMD3(x0, y(legH), back), SIMD3(x1, baseTop, front)),
            box(.frame, SIMD3(left, y(legH), back), SIMD3(x0, armTop, front), radius: 0.03),
            box(.frame, SIMD3(x1, y(legH), back), SIMD3(right, armTop, front), radius: 0.03),
            box(.frame, SIMD3(x0, baseTop, back), SIMD3(x1, top, back + backFrameD)),
        ]
        let n = FurnitureLayout.seatCount(innerWidth: x1 - x0), sw = (x1 - x0) / Float(n)
        for i in 0..<n {
            let a = x0 + Float(i) * sw, c = a + sw
            parts.append(box(.cushion, SIMD3(a, baseTop, seatZ), SIMD3(c, seatTop, front), radius: 0.04))
            parts.append(box(.cushion, SIMD3(a, seatTop, back + backFrameD), SIMD3(c, top - h * 0.05, seatZ), radius: 0.04))
        }
        return parts + legs(x0: left, x1: right, z0: back, z1: front, y0: bottom, y1: y(legH), t: legT)
    }

    func chair() -> [Part] {
        let seatTop = y(clamp(h * 0.5, 0.02, 0.5)), seatT = clamp(h * 0.06, 0.01, 0.06), backT = min(clamp(d * 0.08, 0.02, 0.06), d / 5)
        return [
            box(.cushion, SIMD3(left, seatTop - seatT, back), SIMD3(right, seatTop, front), radius: 0.02),
            box(.frame, SIMD3(left, seatTop, back), SIMD3(right, top, back + backT), radius: 0.02),
        ] + legs(x0: left, x1: right, z0: back, z1: front, y0: bottom, y1: seatTop - seatT, t: legT)
    }

    func table() -> [Part] {
        let topT = clamp(h * 0.05, 0.01, 0.05), inset = min(0.04, foot * 0.05)
        return [box(.top, SIMD3(left, top - topT, back), SIMD3(right, top, front), radius: 0.01)]
            + legs(x0: left + inset, x1: right - inset, z0: back + inset, z1: front - inset, y0: bottom, y1: top - topT, t: legT)
    }

    func storage() -> [Part] {
        let s = skin, kick = min(0.06, h * 0.08), n = min(max(Int((h / 0.4).rounded()), 2), 4)
        let gap = min(0.01, h * 0.02), rowH = (h - kick - gap * Float(n + 1)) / Float(n)
        let handleW = min(0.12, w * 0.25), handleH = min(0.02, rowH * 0.3)
        var parts = [box(.frame, SIMD3(left, bottom, back), SIMD3(right, top, front - 2 * s))]
        for i in 0..<n {
            let y0 = y(kick + gap + Float(i) * (rowH + gap)), ym = y0 + rowH / 2
            parts.append(box(.top, SIMD3(left + gap, y0, front - 2 * s), SIMD3(right - gap, y0 + rowH, front - s)))
            parts.append(box(.accent, SIMD3(-handleW / 2, ym - handleH / 2, front - s), SIMD3(handleW / 2, ym + handleH / 2, front)))
        }
        return parts
    }

    func television() -> [Part] {
        let bezel = min(0.02, w * 0.03, h * 0.05)
        guard d > max(0.12, h * 0.2) else {  // wall-mounted panel
            let s = min(0.01, d / 3)
            return [
                box(.frame, SIMD3(left, bottom, back), SIMD3(right, top, front - s), radius: 0.005),
                box(.screen, SIMD3(left + bezel, bottom + bezel, front - s), SIMD3(right - bezel, top - bezel, front)),
            ]
        }
        let panelD = min(clamp(d * 0.3, 0.03, 0.08), d), plateH = min(0.02, h * 0.03), panelBottom = y(h * 0.15)
        let neckW = min(0.1, w * 0.15), neckD = min(0.04, d * 0.3), s = min(0.01, panelD / 3), pz0 = -panelD / 2, pz1 = panelD / 2
        return [
            box(.frame, SIMD3(left, panelBottom, pz0), SIMD3(right, top, pz1 - s), radius: 0.005),
            box(.screen, SIMD3(left + bezel, panelBottom + bezel, pz1 - s), SIMD3(right - bezel, top - bezel, pz1)),
            box(.accent, SIMD3(-neckW / 2, y(plateH), -neckD / 2), SIMD3(neckW / 2, panelBottom, neckD / 2)),
            box(.accent, SIMD3(-w * 0.3, bottom, back + d * 0.1), SIMD3(w * 0.3, y(plateH), front - d * 0.1), radius: 0.005),
        ]
    }

    func refrigerator() -> [Part] {
        let s = skin, split = y(h > 1.2 ? h * 0.65 : h * 0.5), lineH = min(0.01, h * 0.02)
        let hx = right - min(0.06, w * 0.12), hw = min(0.025, w * 0.05)
        return [
            box(.frame, SIMD3(left, bottom, back), SIMD3(right, top, front - s), radius: 0.02),
            box(.accent, SIMD3(left, split - lineH / 2, front - s), SIMD3(right, split + lineH / 2, front)),
            box(.accent, SIMD3(hx - hw, split + (top - split) * 0.15, front - s), SIMD3(hx, split + (top - split) * 0.55, front)),
            box(.accent, SIMD3(hx - hw, split - (split - bottom) * 0.45, front - s), SIMD3(hx, split - (split - bottom) * 0.1, front)),
        ]
    }

    func stove(burners: Bool) -> [Part] {
        let s = skin, burnerH = burners ? min(0.015, h * 0.03) : 0, topT = min(0.03, h * 0.06)
        let topY = top - burnerH, bodyTop = topY - topT, knobS = min(0.03, w * 0.08, h * 0.06)
        var parts = [
            box(.frame, SIMD3(left, bottom, back), SIMD3(right, bodyTop, front - s)),
            box(.top, SIMD3(left, bodyTop, back), SIMD3(right, topY, front)),
            box(.screen, SIMD3(left + w * 0.15, y(h * 0.15), front - s), SIMD3(right - w * 0.15, y(h * 0.6), front), radius: 0.01),
            box(.accent, SIMD3(left + w * 0.15, y(h * 0.65), front - s), SIMD3(right - w * 0.15, y(h * 0.65) + min(0.02, h * 0.03), front)),
        ]
        let knobY = (y(h * 0.68) + bodyTop) / 2, knobs = burners ? 4 : 2
        for i in 0..<knobs {
            let x = left + w * (Float(i) + 1) / Float(knobs + 1)
            parts.append(box(.accent, SIMD3(x - knobS / 2, knobY - knobS / 2, front - s), SIMD3(x + knobS / 2, knobY + knobS / 2, front)))
        }
        if burners {
            let dia = foot * 0.24
            for (x, z) in [(-w / 4, -d / 4), (w / 4, -d / 4), (-w / 4, d / 4), (w / 4, d / 4)] {
                parts.append(cylinder(.accent, x: x, z: z, diameter: dia, y0: topY, y1: top))
            }
        }
        return parts
    }

    func dishwasher() -> [Part] {
        let s = skin, strip = min(0.08, h * 0.1), hw = min(0.3, w * 0.5), hh = min(0.02, h * 0.03)
        let hy = top - strip - hh * 2
        return [
            box(.frame, SIMD3(left, bottom, back), SIMD3(right, top, front - 2 * s)),
            box(.top, SIMD3(left, y(min(0.06, h * 0.08)), front - 2 * s), SIMD3(right, top - strip, front - s)),
            box(.accent, SIMD3(left, top - strip, front - 2 * s), SIMD3(right, top, front - s)),
            box(.accent, SIMD3(-hw / 2, hy - hh, front - s), SIMD3(hw / 2, hy, front)),
        ]
    }

    func washerDryer() -> [Part] {
        let s = skin, strip = min(0.1, h * 0.15), ring = min(w * 0.7, (h - strip) * 0.8), win = ring * 0.8
        let cy = (bottom + top - strip) / 2, knobS = min(0.05, strip * 0.6, w * 0.1)
        return [
            box(.frame, SIMD3(left, bottom, back), SIMD3(right, top, front - 2 * s), radius: 0.02),
            box(.accent, SIMD3(left, top - strip, front - 2 * s), SIMD3(right, top, front - s)),
            box(.accent, SIMD3(-ring / 2, cy - ring / 2, front - 2 * s), SIMD3(ring / 2, cy + ring / 2, front - s), radius: ring / 2),
            box(.screen, SIMD3(-win / 2, cy - win / 2, front - s), SIMD3(win / 2, cy + win / 2, front), radius: win / 2),
            box(.top, SIMD3(right - w * 0.1 - knobS, top - strip / 2 - knobS / 2, front - s), SIMD3(right - w * 0.1, top - strip / 2 + knobS / 2, front)),
        ]
    }

    func toilet() -> [Part] {
        let tankD = min(clamp(d * 0.3, 0.05, 0.25), d * 0.4), z0 = back + tankD
        let dia = min(w, front - z0) * 0.95, cz = (z0 + front) / 2, seatTop = y(h * 0.55), seatT = min(0.03, h * 0.05)
        return [
            box(.porcelain, SIMD3(left + w * 0.05, y(h * 0.45), back), SIMD3(right - w * 0.05, top, z0), radius: 0.02),
            cylinder(.porcelain, x: 0, z: cz, diameter: dia * 0.55, y0: bottom, y1: y(h * 0.2)),
            cylinder(.porcelain, x: 0, z: cz, diameter: dia, y0: y(h * 0.2), y1: seatTop - seatT),
            box(.cushion, SIMD3(-dia / 2, seatTop - seatT, cz - dia / 2), SIMD3(dia / 2, seatTop, cz + dia / 2), radius: dia / 2),
        ]
    }

    func bathtub() -> [Part] {
        let t = min(clamp(foot * 0.08, 0.03, 0.08), foot / 4), bt = min(t, h / 4)
        return [
            box(.porcelain, SIMD3(left, bottom, back), SIMD3(right, y(bt), front)),
            box(.porcelain, SIMD3(left, y(bt), back), SIMD3(left + t, top, front), radius: 0.01),
            box(.porcelain, SIMD3(right - t, y(bt), back), SIMD3(right, top, front), radius: 0.01),
            box(.porcelain, SIMD3(left + t, y(bt), back), SIMD3(right - t, top, back + t), radius: 0.01),
            box(.porcelain, SIMD3(left + t, y(bt), front - t), SIMD3(right - t, top, front), radius: 0.01),
        ]
    }

    func sink() -> [Part] {
        let s = skin, faucetH = min(0.2, h * 0.15), counterTop = top - faucetH, counterT = min(0.04, h * 0.06)
        let cabTop = counterTop - counterT, stem = min(0.03, foot * 0.08), spout = min(0.15, d * 0.3)
        let fz = back + d * 0.1, basin = min(w * 0.6, d * 0.6)
        return [
            box(.frame, SIMD3(left, bottom, back), SIMD3(right, cabTop, front - s)),
            box(.top, SIMD3(left + w * 0.04, y(min(0.05, h * 0.06)), front - s), SIMD3(-w * 0.01, cabTop - min(0.03, h * 0.04), front)),
            box(.top, SIMD3(w * 0.01, y(min(0.05, h * 0.06)), front - s), SIMD3(right - w * 0.04, cabTop - min(0.03, h * 0.04), front)),
            box(.porcelain, SIMD3(left, cabTop, back), SIMD3(right, counterTop, front), radius: 0.01),
            cylinder(.porcelain, x: 0, z: (fz + front) / 2 + stem, diameter: basin, y0: counterTop, y1: counterTop + min(0.02, faucetH * 0.2)),
            box(.accent, SIMD3(-stem / 2, counterTop, fz), SIMD3(stem / 2, top, fz + stem)),
            box(.accent, SIMD3(-stem / 2, top - stem, fz + stem), SIMD3(stem / 2, top, fz + stem + spout)),
        ]
    }

    func fireplace() -> [Part] {
        let s = skin, mantelT = min(0.06, h * 0.08), hearthH = min(0.05, h * 0.06)
        return [
            box(.frame, SIMD3(left, y(hearthH), back), SIMD3(right, top - mantelT, front - s - d * 0.1)),
            box(.screen, SIMD3(left + w * 0.25, y(hearthH), front - s - d * 0.1), SIMD3(right - w * 0.25, y(h * 0.55), front - d * 0.1)),
            box(.top, SIMD3(left, top - mantelT, back), SIMD3(right, top, front)),
            box(.top, SIMD3(left + w * 0.1, bottom, back), SIMD3(right - w * 0.1, y(hearthH), front)),
        ]
    }

    func stairs() -> [Part] {
        let n = FurnitureLayout.stepCount(height: h), rise = h / Float(n), run = d / Float(n)
        return (0..<n).map { i in
            box(.frame, SIMD3(left, bottom, front - Float(i + 1) * run), SIMD3(right, y(Float(i + 1) * rise), front - Float(i) * run))
        }
    }
}
