import Foundation

// OWNER: voxel-models agent. The scan detector's (#98, `ObjectVocabulary`) remaining household
// categories, which used to fall back to the kraft box: trunks / toy chests, baskets / bins /
// hampers, trash cans, toolboxes, cribs, ladders, clocks, toys, coat / shoe / clothes racks, pet
// crates, pet beds and cat trees. House style: palette + jitter, front at +z, and every piece
// fills its scanned box (VoxelFootprintTests).

extension Canvas {
    /// One of `options`, picked by the seed (a per-item detail).
    func pick(_ options: [Int]) -> Int { options[Int(seed % UInt32(max(1, options.count)))] }

    /// Normalized squared distance of (x, z) from the footprint's center, on the ellipse that
    /// touches all four sides (<= 1 is inside).
    func footEllipse(_ x: Int, _ z: Int, _ X: Int, _ Z: Int) -> Double {
        let dx = (D(x) - D(X - 1) / 2) / (D(X) / 2), dz = (D(z) - D(Z - 1) / 2) / (D(Z) / 2)
        return dx * dx + dz * dz
    }

    // MARK: trunk

    /// Steamer trunk (straps, brass corners, a domed lid), wooden chest ("cedar", "hope chest",
    /// "wooden": plank lines and a latch) or a painted toy chest (a lid in an accent color, hand
    /// slots on the ends). Short feet at the corners.
    func trunk(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let toy = name.has("toy")
        let woodish = !toy && name.has("cedar", "hope chest", "blanket chest", "wood", "wooden", "treasure", "oak", "pine", "walnut")
        let steamer = !toy && !woodish
        let body = colorFromName(name, toy ? pick([0xEBE6DC, 0x7E95A8, 0xD9A5A0, 0x8B9A7B])
                                     : woodish ? pick([P.oak, P.walnut, 0x8A5A3A]) : pick([0x3F5A73, 0x2B2A28, 0x6E4A33, 0x5D6B47, 0xA8473D]))
        let lidC = toy ? accentPair(avoiding: body).0 : shade(body, 0.95)
        let trim = woodish ? shade(body, 0.72) : P.brass
        let strapC = 0x5A3A26
        let feet = Y >= 4 && !toy // a toy chest sits on a plinth
        let y0 = feet ? 1 : 0
        let seam = clamp(rd(D(Y) * 0.68), y0 + 1, Y - 2)
        let straps = X >= 8 ? [X / 4, X - 1 - X / 4] : []
        box(0, y0, 0, X, Y, Z) { x, y, z in
            let edgeX = x == 0 || x == X - 1, edgeZ = z == 0 || z == Z - 1
            if steamer && y == Y - 1 && edgeZ && Z >= 5 { return nil } // domed lid
            if y == seam { return shade(body, 0.62) } // lid seam
            if toy {
                if edgeX && y == seam - 2 && abs(z - Z / 2) <= max(0, Z / 6) { return nil } // hand slot
                return y > seam ? lidC : body
            }
            if edgeX && edgeZ && (y <= y0 + 1 || y >= Y - 2 || steamer) { return trim } // corner caps
            if steamer {
                if straps.contains(x) && (edgeZ || y == Y - 1 || (y == Y - 2 && edgeZ)) { return strapC }
                if (y == y0 || y == Y - 1) && (edgeX || edgeZ) { return shade(body, 0.75) }
                return y > seam ? lidC : body
            }
            return (y - y0) % 3 == 2 ? shade(body, 0.86) : (y > seam ? lidC : body) // planks
        }
        // latch, and a lid handle on toy chests
        set(X / 2, seam, Z - 1, toy ? shade(lidC, 0.7) : P.brass)
        if seam - 1 >= y0 { set(X / 2, seam - 1, Z - 1, toy ? body : P.brass) }
        if feet { for (x, z) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { set(x, 0, z, woodish || toy ? shade(body, 0.7) : P.black) } }
    }

    // MARK: baskets, bins, hampers

    /// Open woven basket (wicker over-under weave, handle slots), laundry basket with clothes
    /// inside, lidded hamper, plastic storage bin / tote (lid in an accent color) or fabric cube bin.
    func basket(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let hamper = name.word("hamper", "hampers")
        let laundry = hamper || name.has("laundry", "clothes")
        let fabric = name.has("fabric", "canvas", "felt", "cloth", "collapsible", "cube", "linen")
        let plastic = !fabric && (name.has("plastic", "tote", "sterilite", "rubbermaid", "container", "storage bin", "iris")
            || (name.word("bin", "bins") && !name.has("wicker", "woven", "rattan", "seagrass", "basket")))
        let lid = hamper || (plastic && !name.has("open"))
        let base = plastic ? colorFromName(name, pick([0xE4E1DA, 0x9AA3A8, 0x5A5E62]))
            : fabric ? colorFromName(name, pick([0x8F8D88, 0xD6C4A4, 0x5B7896, 0x2B2A28])) : colorFromName(name, 0xC9A875)
        let lidC = plastic ? (secondary ?? pick([0x3D6FA8, 0x3A3835, 0xC23B2E, 0x5FA052])) : shade(base, 0.9)
        let rounded = X >= 4 && Z >= 4
        let wallTop = lid ? Y - 1 : Y
        // flat colors (no per-voxel jitter) so the big walls stay a few quads each
        box(0, 0, 0, X, wallTop, Z, flat: true) { x, y, z in
            if rounded && (x == 0 || x == X - 1) && (z == 0 || z == Z - 1) { return nil }
            let wall = x == 0 || x == X - 1 || z == 0 || z == Z - 1
            if !wall && y > 0 { return lid ? shade(base, 0.5) : y < wallTop - 2 ? shade(base, 0.45) : nil } // the shadowed inside
            if plastic { return y == wallTop - 1 ? shade(base, 0.85) : y == 0 ? shade(base, 0.9) : base }
            if fabric { return y == wallTop - 1 ? shade(base, 0.78) : base }
            if y == wallTop - 1 { return shade(base, 0.8) } // rim
            return y % 2 == 0 ? base : shade(base, 0.84) // woven rows
        }
        // hand slots in the short ends, under the rim
        let hy = wallTop - 2
        if hy >= 1 && Z >= 4 && !plastic { for x in [0, X - 1] { for z in thru(Z / 2 - (Z >= 6 ? 1 : 0), Z / 2) { clear(x, hy, z) } } }
        if laundry && !lid && X >= 3 && Z >= 3 {
            // a heap of clothes inside
            let cloth = [P.cream, 0x5B7896, P.blush, P.sage, 0x3A3835, P.mustard]
            for z in upTo(1, Z - 1) {
                for x in upTo(1, X - 1) {
                    let h = max(1, wallTop - 1 - Int(hash3(x / 3, 0, z / 3, seed) * 2.5))
                    let c = cloth[Int(hash3(x / 3, 1, z / 3, seed) * D(cloth.count)) % cloth.count]
                    box(x, 1, z, x + 1, h, z + 1, c, flat: true)
                }
            }
        }
        if lid {
            box(0, Y - 1, 0, X, Y, Z) { x, _, z in rounded && (x == 0 || x == X - 1) && (z == 0 || z == Z - 1) ? nil : lidC }
            if X >= 5 { set(X / 2, Y - 1, Z / 2, shade(lidC, 0.7)) }
        }
    }

    // MARK: trash can

    /// Round step can (stainless by default, a lid and a pedal), open wastebasket ("wastebasket",
    /// "office", or small) or an outdoor wheelie bin ("wheelie", "outdoor", "garbage", or >= 90 cm
    /// tall): hinged lid, wheels at the back, a handle. "recycling" is blue.
    func trashCan(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let recycling = name.has("recycl")
        if name.has("wheelie", "outdoor", "curbside", "toter", "rollout", "roll-out", "garbage can", "garbage bin", "compost") || D(Y) * voxelM >= 0.9 {
            wheelieBin(X, Y, Z, name, recycling: recycling); return
        }
        let open = name.has("wastebasket", "waste basket", "wastepaper", "office", "paper bin") || Y <= 6
        let steel = !recycling && !name.has("plastic", "wicker")
        let body = colorFromName(name, recycling ? 0x3D6FA8 : steel ? 0xB8BCBF : 0x8F8D88)
        let lidH = open ? 0 : 1
        let m = D(min(X, Z)) / 2
        let inner = max(0, (m - 1.2) / m) * max(0, (m - 1.2) / m)
        for y in 0..<Y {
            for z in 0..<Z {
                for x in 0..<X {
                    let d = footEllipse(x, z, X, Z)
                    if d > 1 { continue }
                    if open && y > 0 && d < inner { continue }
                    var c = body
                    if y >= Y - lidH { c = d < 0.15 ? shade(body, 0.7) : shade(body, 0.88) }
                    else if y == Y - lidH - 1 && !open { c = shade(body, 0.68) } // lid seam
                    else if y == 0 { c = shade(body, 0.75) }
                    else if steel && abs(D(x) - D(X - 1) * 0.3) < 0.6 && D(z) > D(Z - 1) / 2 { c = shade(body, 1.12) } // shine
                    set(x, y, z, c)
                }
            }
        }
        if !open { set(X / 2, 0, Z - 1, P.black) } // pedal
    }

    func wheelieBin(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, recycling: Bool) {
        let body = colorFromName(name, recycling ? 0x3D6FA8 : pick([0x4E6B5C, 0x3A3835, 0x5A5E62]))
        let lidC = recycling ? 0xE0A030 : shade(body, 0.82)
        let inset = Y >= 12 && Z >= 6 ? 1 : 0
        box(0, 1, 0, X, Y - 1, Z) { x, y, z in
            // the body tapers toward the bottom front; grooves down the front
            if inset > 0 && y < Y / 3 && z == Z - 1 { return nil }
            if z == Z - 1 - (y < Y / 3 ? inset : 0) && x % 3 == 1 && y > 1 && y < Y - 3 { return shade(body, 0.8) }
            return y == Y - 2 ? shade(body, 0.9) : body
        }
        box(0, Y - 1, 0, X, Y, Z, lidC) // lid, overhanging
        set(X / 2, Y - 1, Z - 1, shade(lidC, 0.7)) // lid grip
        box(0, 0, 1, X, 1, Z - 1 - inset, shade(body, 0.7)) // base
        for x in [0, X - 1] { set(x, 0, 0, P.black); set(x, 1, 0, P.black) } // wheels at the back
        if X >= 5 { box(1, Y - 3, 0, X - 1, Y - 2, 1, shade(body, 0.6)) } // handle
    }

    // MARK: toolbox

    /// Carry toolbox (a lid seam, latches, a handle over the top) or a rolling tool chest
    /// ("tool chest", "cabinet", "rolling", or >= 55 cm tall): a stack of drawers with pull bars on casters.
    func toolbox(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let chest = name.has("tool chest", "tool cabinet", "rolling", "tool cart", "toolchest", "drawer") || D(Y) * voxelM >= 0.55
        let body = colorFromName(name, chest ? 0xB3261E : pick([0xB3261E, 0x2B2A28, 0x3D6FA8, 0xC9A23A, 0x5A5E62]))
        if chest {
            let casters = 1
            let k = max(2, (Y - casters) / 6)
            box(0, casters, 0, X, Y, Z) { x, y, z in
                if y == Y - 1 { return shade(body, 0.8) }
                if z == Z - 1 && x > 0 && x < X - 1 {
                    let r = (y - casters) % k
                    if r == 0 { return shade(body, 0.55) } // drawer seam
                    if r == k - 1 && x > 1 && x < X - 2 { return 0xC8CCD0 } // pull bar
                }
                return body
            }
            if casters > 0 { for (x, z) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { set(x, 0, z, P.black) } }
            return
        }
        let hh = Y >= 6 ? max(1, Y / 4) : 1
        let top = Y - hh
        box(0, 0, 0, X, top, Z) { _, y, _ in
            if y == top - 1 { return shade(body, 0.88) }
            if y == top - 2 && top >= 3 { return shade(body, 0.6) } // lid seam
            return y == 0 ? shade(body, 0.8) : body
        }
        let l0 = X / 4, l1 = X - 1 - X / 4
        if top >= 3 { for x in [l0, l1] { set(x, top - 2, Z - 1, 0xC8CCD0) } } // latches
        let hz = Z / 2
        for x in [l0, l1] { box(x, top, hz, x + 1, Y - 1, hz + 1, P.black) }
        box(l0, Y - 1, hz, l1 + 1, Y, hz + 1, P.black) // handle
    }

    // MARK: crib

    /// Slatted crib (corner posts, rails, a mattress with a sheet, end panels), mesh-sided
    /// playpen / pack 'n play, or a bassinet (an oval basket with a hood on legs).
    func crib(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("bassinet", "cradle", "moses") { bassinet(X, Y, Z, name); return }
        let playpen = name.has("playpen", "play pen", "pack n play", "pack 'n play", "pack and play", "pack-n-play", "play yard", "travel cot")
        let frame = colorFromName(name, playpen ? 0x5A5E62 : pick([0xEBE6DC, P.oak, 0x8F8D88, P.birch]))
        let base = clamp(rd(D(Y) * (playpen ? 0.12 : 0.32)), 1, max(1, Y - 4))
        // flat (unjittered) posts, rails and slats: thin repeated parts stay a few quads each
        for (x, z) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { box(x, 0, z, x + 1, Y, z + 1, frame, flat: true) }
        for y in [base, Y - 1] {
            box(0, y, 0, X, y + 1, 1, frame, flat: true); box(0, y, Z - 1, X, y + 1, Z, frame, flat: true)
            box(0, y, 0, 1, y + 1, Z, frame, flat: true); box(X - 1, y, 0, X, y + 1, Z, frame, flat: true)
        }
        let panel = !playpen && X >= 8 ? max(2, Y / 5) : 0
        box(0, base + 1, 0, X, Y - 1, Z, flat: true) { x, y, z in
            let fx = x == 0 || x == X - 1, fz = z == 0 || z == Z - 1
            if !(fx || fz) { return nil }
            if playpen { return 0xB8BDC1 } // mesh
            if fx && y >= Y - 1 - panel { return shade(frame, 0.94) } // end panels
            return (fz && x % 2 == 0) || (fx && z % 2 == 0) ? frame : nil // slats
        }
        // mattress with a sheet, a folded blanket and a small plush
        let (a, b) = accentPair(avoiding: 0xF4F1EA)
        let mt = min(Y - 2, base + 2)
        box(1, base, 1, X - 1, mt, Z - 1, flat: true) { _, y, z in y == mt - 1 ? ((z / 2) % 2 == 0 ? shade(a, 1.3) : 0xF4F1EA) : 0xE4E1DA }
        if X >= 8 && Z >= 6 && mt < Y - 1 {
            box(X - 1 - X / 3, mt, 1, X - 1, mt + 1, Z - 1, a)
            set(2, mt, 2, b); if mt + 1 < Y - 1 { set(2, mt + 1, 2, b) }
        }
    }

    func bassinet(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let shell = colorFromName(name, pick([0xEBE6DC, 0xC9A875, 0x8F8D88]))
        let legC = name.has("wood", "oak") ? P.oak : 0xC8CCD0
        let b0 = clamp(rd(D(Y) * 0.5), 1, Y - 3)
        let m = D(min(X, Z)) / 2, inner = max(0, (m - 1.2) / m) * max(0, (m - 1.2) / m)
        let hoodX = rd(D(X) * 0.35)
        for y in upTo(b0, Y) {
            for z in 0..<Z {
                for x in 0..<X {
                    let d = footEllipse(x, z, X, Z)
                    if d > 1 { continue }
                    let hood = x < hoodX && y > b0 + (Y - b0) / 2
                    if d < inner && y > b0 && !hood { if y < Y - 2 { set(x, y, z, 0xF4F1EA, flat: true) }; continue } // mattress
                    if hood && d < inner && y < Y - 1 { continue }
                    set(x, y, z, y == b0 ? 0xF4F1EA : hood ? shade(shell, 0.85) : shell, flat: true)
                }
            }
        }
        // crossed legs to the floor corners
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        for (x, z) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] {
            line(cx + (D(x) - cx) * 0.35, D(b0), cz + (D(z) - cz) * 0.35, D(x), 0, D(z), legC)
        }
    }

    // MARK: ladder

    /// A-frame step ladder (front legs with steps, back legs, spreader bars, a top cap) or, when
    /// thin (<= 15 cm deep), a straight / extension ladder. Aluminum by default, "wood" / "fiberglass".
    func ladder(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let wood = name.has("wood", "wooden", "oak", "pine", "library")
        let fiber = !wood && name.has("fiberglass", "fibreglass", "werner", "little giant")
        let rail = colorFromName(name, wood ? P.oak : fiber ? 0xE0A030 : P.metal)
        let stepC = wood ? shade(rail, 0.9) : fiber ? P.metal : shade(rail, 0.85)
        let capC = wood ? shade(rail, 0.78) : fiber ? P.black : 0xC9502E
        if Z <= 3 {
            for x in [0, X - 1] { box(x, 0, 0, x + 1, Y, Z) { _, y, _ in y == 0 ? P.black : rail } }
            for y in stride(from: 3, to: Y, by: 5) { box(1, y, Z / 2, X - 1, y + 1, Z / 2 + 1, stepC) }
            box(1, Y - 1, 0, X - 1, Y, Z, rail)
            return
        }
        let top = Y - 1, zt = D(Z - 1) / 2
        func zFront(_ y: Int) -> Double { D(Z - 1) + (zt + 1 - D(Z - 1)) * D(y) / D(max(1, top - 1)) }
        func zBack(_ y: Int) -> Double { (zt - 1) * D(y) / D(max(1, top - 1)) }
        for x in [0, X - 1] {
            for y in 0..<top {
                let zf = rd(zFront(y)), zb = rd(zBack(y))
                set(x, y, zf, y == 0 ? P.black : rail); if Z >= 8 { set(x, y, zf - 1, rail) }
                set(x, y, zb, y == 0 ? P.black : rail)
            }
            // spreader bar
            let ys = rd(D(Y) * 0.45)
            for z in thru(rd(zBack(ys)), rd(zFront(ys))) { set(x, ys, z, shade(P.metal, 0.75)) }
        }
        for y in stride(from: 4, to: top - 1, by: 5) {
            let zf = rd(zFront(y))
            box(1, y, zf - 1, X - 1, y + 1, zf + 1, stepC)
        }
        box(0, top, rd(zt) - 1, X, Y, rd(zt) + 2, capC) // top cap
    }

    // MARK: clock

    static func isStandingClock(_ n: VName, heightM: Double) -> Bool {
        n.has("grandfather", "grandmother", "longcase", "long case", "floor clock", "tall case", "standing clock") || heightM > 1.0
    }

    static func isTableClock(_ n: VName) -> Bool {
        n.has("alarm", "desk clock", "mantel", "mantle", "table clock", "bedside", "digital clock", "clock radio", "shelf clock")
    }

    /// Wall clock (a round face with a rim, hour marks and hands; hung like art), a grandfather
    /// clock (a tall case with a hood, a glass door and a pendulum) or a table clock ("alarm",
    /// "digital": a black box with glowing digits; "mantel": a wooden arch with a face).
    func clock(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if Self.isStandingClock(name, heightM: D(Y) * voxelM) && Z >= 2 && X >= 4 && Y >= 12 { grandfatherClock(X, Y, Z, name); return }
        if Self.isTableClock(name) && Z >= 2 {
            if name.has("alarm", "digital", "radio") { digitalClock(X, Y, Z, name) } else { mantelClock(X, Y, Z, name) }
            return
        }
        let frame = colorFromName(name, pick([P.black, P.oak, P.brass, 0xEBE6DC, P.walnut]))
        let face = frame == 0xEBE6DC ? 0xF8F5EE : 0xF4F1EA
        let cx = D(X - 1) / 2, cy = D(Y - 1) / 2, rx = D(X) / 2, ry = D(Y) / 2
        let rim = 1.0 - 1.6 / max(2, min(rx, ry))
        for y in 0..<Y {
            for x in 0..<X {
                let dx = (D(x) - cx) / rx, dy = (D(y) - cy) / ry
                let d = dx * dx + dy * dy
                if d > 1 { continue }
                for z in 0..<Z {
                    if z < Z - 1 { set(x, y, z, shade(frame, 0.85)) } else { set(x, y, z, d > rim * rim ? frame : face, flat: d <= rim * rim) }
                }
            }
        }
        clockHands(cx, cy, min(rx, ry) * rim, Z - 1)
    }

    /// Hour marks and two hands on the face centered at (cx, cy), radius r, in layer z.
    func clockHands(_ cx: Double, _ cy: Double, _ r: Double, _ z: Int) {
        let ink = 0x232220
        if r >= 3 {
            let n = r >= 6 ? 12 : 4
            for i in 0..<n {
                let a = D(i) / D(n) * 2 * Double.pi
                set(rd(cx + sin(a) * r * 0.82), rd(cy + cos(a) * r * 0.82), z, ink, flat: true)
            }
        }
        let hour = D(Int(seed % 12)) / 12 * 2 * Double.pi, minute = D(Int((seed >> 4) % 60)) / 60 * 2 * Double.pi
        line(cx, cy, D(z), cx + sin(hour) * r * 0.45, cy + cos(hour) * r * 0.45, D(z), ink, flat: true)
        line(cx, cy, D(z), cx + sin(minute) * r * 0.72, cy + cos(minute) * r * 0.72, D(z), ink, flat: true)
        set(rd(cx), rd(cy), z, 0xC23B2E, flat: true)
    }

    func grandfatherClock(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let woodC = colorFromName(name, pick([P.walnut, 0x8A5A3A, P.darkWood]))
        let plinth = max(2, rd(D(Y) * 0.12)), hood0 = rd(D(Y) * 0.72)
        let inset = X >= 7 ? 1 : 0
        wood(0, 0, 0, X, plinth, Z, woodC, .x)
        wood(inset, plinth, 0, X - inset, hood0, max(1, Z - inset), shade(woodC, 1.05), .y)
        wood(0, hood0, 0, X, Y - 1, Z, woodC, .x)
        box(0, Y - 1, 0, X, Y, Z) { x, _, _ in x == 0 || x == X - 1 ? nil : shade(woodC, 0.8) } // crown
        // glass door with a brass pendulum
        let dz = max(0, Z - inset - 1), dx0 = inset + 1, dx1 = X - inset - 1
        box(dx0, plinth + 1, dz, dx1, hood0 - 1, dz + 1, 0x2A3238, flat: true)
        let px = X / 2
        box(px, rd(D(hood0) * 0.55), dz, px + 1, hood0 - 1, dz + 1, P.brass, flat: true)
        box(max(dx0, px - 1), rd(D(hood0) * 0.5), dz, min(dx1, px + 2), rd(D(hood0) * 0.55), dz + 1, P.brass, flat: true)
        // face
        let fh = Y - 1 - hood0, cy = D(hood0) + D(fh - 1) / 2, cx = D(X - 1) / 2
        let r = max(1, min(D(X) / 2 - 1, D(fh) / 2 - 0.5))
        for y in upTo(hood0, Y - 1) {
            for x in 0..<X where (D(x) - cx) * (D(x) - cx) + (D(y) - cy) * (D(y) - cy) <= r * r { set(x, y, Z - 1, 0xF4F1EA, flat: true) }
        }
        clockHands(cx, cy, r, Z - 1)
    }

    func digitalClock(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, pick([0x2B2A28, 0xEBE6DC]))
        let digit = isDarkColor(body) ? 0xFF5A3C : 0x3FA8E0
        box(0, 0, 0, X, Y, Z) { x, y, z in
            if y == Y - 1 && (x == 0 || x == X - 1) && (z == 0 || z == Z - 1) { return nil }
            return y == 0 ? shade(body, 0.8) : body
        }
        // "12:00"-ish segments on the front
        if X >= 5 && Y >= 3 {
            box(1, 1, Z - 1, X - 1, Y - 1, Z, 0x111214, flat: true)
            for x in upTo(1, X - 1) where x % 2 == 1 || Y < 5 {
                for y in upTo(1, Y - 1) where hash3(x, y, 7, seed) < 0.6 { set(x, y, Z - 1, digit, flat: true) }
            }
        }
        if Y >= 4 && X >= 6 { set(X / 2, Y - 1, Z / 2, 0x8F8D88) } // snooze bar
    }

    func mantelClock(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let wood = colorFromName(name, pick([P.walnut, P.oak, 0x8A5A3A]))
        let cx = D(X - 1) / 2
        box(0, 0, 0, X, Y, Z) { x, y, _ in
            // an arched top: corners rounded off above 60%
            let t = D(y - rd(D(Y) * 0.6)) / max(1, D(Y) * 0.4)
            if t > 0 && abs(D(x) - cx) / (D(X) / 2) > (1 - t * t).squareRoot() + 0.15 { return nil }
            return y == 0 ? shade(wood, 0.75) : wood
        }
        let r = max(1, min(D(X) / 2 - 1, D(Y) * 0.32)), cy = D(Y) * 0.55
        for y in 0..<Y {
            for x in 0..<X where (D(x) - cx) * (D(x) - cx) + (D(y) - cy) * (D(y) - cy) <= r * r { set(x, y, Z - 1, 0xF4F1EA, flat: true) }
        }
        clockHands(cx, cy, r, Z - 1)
    }

    // MARK: toys

    /// Teddy bear / stuffed animal (default), dollhouse ("dollhouse", "play kitchen"), rocking
    /// horse, or a heap of building blocks ("toys", "lego", "blocks").
    func toy(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("dollhouse", "doll house", "play kitchen") { dollhouse(X, Y, Z, name); return }
        if name.has("rocking horse", "hobby horse") { rockingHorse(X, Y, Z, name); return }
        if name.has("lego", "blocks", "duplo") || (name.word("toys") && !name.has("stuffed", "plush", "teddy")) { toyBlocks(X, Y, Z, name); return }
        // a low box is a plush lying down (scan 9: a 16 cm tall "toy" on the bed)
        if D(Y) < D(max(X, Z)) * 0.7 { lyingPlush(X, Y, Z, name); return }
        teddy(X, Y, Z, name)
    }

    /// A plush lying on its belly along the footprint's long side: body, a round head with ears
    /// and a light muzzle at one end, stubby paws at the sides.
    func lyingPlush(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let fur = colorFromName(name, pick([0xC9A875, 0xEBE6DC, 0xD9A5A0, 0x8F8D88, 0xB98A5E]))
        let light = mix(fur, 0xF4EBDD, 0.55)
        let H = D(Y), cw = D(W - 1) / 2
        func blob(_ cu: Double, _ cy: Double, _ ru: Double, _ ry: Double, _ rw: Double, _ c: (Int, Int, Int, Double) -> Int?) {
            for y in thru(max(0, fl(cy - ry)), min(Y - 1, ce(cy + ry))) {
                for u in thru(max(0, fl(cu - ru)), min(L - 1, ce(cu + ru))) {
                    for w in thru(max(0, fl(cw - rw)), min(W - 1, ce(cw + rw))) {
                        let du = (D(u) - cu) / ru, dy = (D(y) - cy) / ry, dw = (D(w) - cw) / rw
                        let d = du * du + dy * dy + dw * dw
                        if d <= 1, let col = c(u, y, w, d) { put(a, u, y, w, col) }
                    }
                }
            }
        }
        // body over the back two thirds, head at the high-u end
        let bodyLen = D(L) * 0.68
        blob(bodyLen / 2, H * 0.36, bodyLen / 2, max(1, H * 0.36), D(W) * 0.36) { _, _, _, _ in fur }
        let headR = max(1.2, min(D(L) * 0.2, H * 0.48, D(W) * 0.42))
        let hu = D(L) - headR - 0.3, hy = min(H - 1 - headR * 0.4, headR)
        blob(hu, hy, headR, headR, headR) { _, _, _, _ in fur }
        // ears on top of the head, a muzzle and nose at the front, eyes
        for s in [-1.0, 1.0] {
            let ew = rd(cw + s * headR * 0.65)
            put(a, rd(hu - 0.3), min(Y - 1, rd(hy + headR * 0.95)), ew, light)
            put(a, rd(hu), min(Y - 1, rd(hy + headR * 0.95)), ew, fur)
            if headR >= 2 { put(a, min(L - 1, rd(hu + headR * 0.8)), rd(hy + headR * 0.3), rd(cw + s * headR * 0.45), P.black) }
        }
        put(a, L - 1, rd(hy - headR * 0.2), rd(cw), light)
        put(a, L - 1, rd(hy), rd(cw), P.black)
        // paws stretched out at the sides
        for s in [-1.0, 1.0] {
            for pu in [bodyLen * 0.2, bodyLen * 0.85] {
                let pw = s < 0 ? 0 : W - 1
                put(a, rd(pu), 0, pw, light); put(a, rd(pu) + 1, 0, pw, fur)
            }
        }
        put(a, 0, max(0, rd(H * 0.4)), rd(cw), light) // tail
    }

    func teddy(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let fur = colorFromName(name, pick([0x9C6B43, 0xC9A875, 0xEBE6DC, 0xD9A5A0, 0x8F8D88]))
        let light = mix(fur, 0xF4EBDD, 0.55)
        let cx = D(X - 1) / 2, H = D(Y), Zd = D(Z - 1)
        // sitting: body, legs stretched forward, arms out to the sides, head with ears on top
        let headR = max(1.2, min(D(X) * 0.3, H * 0.2, D(Z) * 0.42))
        let earR = max(0.8, headR * 0.38)
        let headY = H - 0.5 - earR * 0.9 - headR * 0.75
        ellipsoid(cx, H * 0.3, Zd * 0.42, D(X) * 0.3 + 0.3, H * 0.3 + 0.5, Zd * 0.42 + 0.5) { _, _, _, _ in fur }
        let legR = max(0.9, min(D(X) * 0.14, H * 0.13))
        for s in [-1.0, 1.0] {
            ellipsoid(cx + s * D(X) * 0.18, legR - 0.5, Zd - Zd * 0.22 + 0.5, legR + 0.2, legR, Zd * 0.22 + 0.5) { _, _, z, _ in D(z) > Zd - 0.6 ? light : fur }
            let armX = s < 0 ? D(X) * 0.14 - 0.5 : D(X - 1) - D(X) * 0.14 + 0.5
            ellipsoid(armX, H * 0.42, Zd * 0.55, D(X) * 0.14 + 0.5, max(0.8, H * 0.1), max(0.8, Zd * 0.18)) { _, _, _, _ in fur }
            ellipsoid(cx + s * headR * 0.72, H - 0.5 - earR, Zd * 0.45, earR, earR, max(0.6, earR * 0.6)) { _, _, _, d in d < 0.3 ? light : fur }
        }
        ellipsoid(cx, headY, Zd * 0.45, headR, headR * 0.9, headR) { _, _, _, _ in fur }
        let front = rd(Zd * 0.45 + headR) // face
        ellipsoid(cx, headY - headR * 0.25, Zd * 0.45 + headR * 0.75, max(0.7, headR * 0.4), max(0.6, headR * 0.3), max(0.6, headR * 0.35)) { _, _, _, _ in light }
        set(rd(cx), rd(headY - headR * 0.2), min(Z - 1, front), P.black) // nose
        for s in [-1.0, 1.0] { set(rd(cx + s * headR * 0.45), rd(headY + headR * 0.25), min(Z - 1, front - (headR > 2 ? 1 : 0)), P.black) }
        if X >= 7 { set(rd(cx), rd(headY - headR * 0.95), min(Z - 1, rd(Zd * 0.42 + Zd * 0.4)), secondary ?? 0xC23B2E) } // bow
    }

    func dollhouse(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let wall = colorFromName(name, pick([0xF4F1EA, 0xF3D9D2, 0xDDE8EE]))
        let roofC = pick([0xC0704A, 0x7E95A8, 0xD9A5A0, 0x5D6B47])
        let floorC = P.birch
        let roof0 = clamp(rd(D(Y) * 0.65), 2, Y - 2)
        let mid = max(1, roof0 / 2)
        // floors, back wall and side walls; open at the front
        for y in [0, mid] { box(0, y, 0, X, y + 1, Z, floorC, flat: true) }
        box(0, roof0 - 1, 0, X, roof0, Z, floorC, flat: true)
        box(0, 0, 0, X, roof0, 1, wall, flat: true)
        for x in [0, X - 1] {
            box(x, 0, 0, x + 1, roof0, Z, flat: true) { _, y, z in
                let win = y % max(2, mid) == max(1, mid / 2) && z == Z / 2 && Z >= 4
                return win ? 0x9FC1D6 : wall
            }
        }
        if X >= 8 { box(X / 2, 1, 0, X / 2 + 1, roof0 - 1, max(1, Z / 2), wall) } // inner wall
        // gable roof
        let rh = Y - roof0
        for y in upTo(roof0, Y) {
            let t = D(y - roof0 + 1) / D(max(1, rh))
            let inset = rd(t * (D(X) / 2 - 1))
            box(inset, y, 0, max(inset + 1, X - inset), y + 1, Z, flat: true) { x, _, _ in x <= inset || x >= X - inset - 1 || y == Y - 1 ? roofC : wall }
        }
        // tiny furniture
        let (a, b) = accentPair(avoiding: wall)
        if X >= 6 && Z >= 3 {
            box(1, 1, 1, 3, 2, 3, a); box(X - 3, mid + 1, 1, X - 1, mid + 2, 2, b)
        }
    }

    func rockingHorse(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let horse = colorFromName(name, pick([0xEBE6DC, P.oak, 0x8A5A3A]))
        let rockerC = name.has("white", "painted") ? 0xC23B2E : shade(horse, 0.8)
        let mane = horse == 0xEBE6DC ? 0x6E4A33 : 0x2B2A28
        let rh = max(1, rd(D(Y) * 0.1))
        for w in [0, W - 1] {
            for u in 0..<L {
                let t = (D(u) - D(L - 1) / 2) / (D(L) / 2)
                put(a, u, rd(t * t * D(rh)), w, rockerC)
            }
        }
        let wc = W / 2, w0 = max(0, wc - (W >= 6 ? 1 : 0)), w1 = min(W, wc + 1 + (W >= 6 ? 1 : 0))
        let by0 = max(rh + 2, rd(D(Y) * 0.42)), by1 = max(by0 + 1, rd(D(Y) * 0.6))
        let u0 = rd(D(L) * 0.2), u1 = max(u0 + 2, rd(D(L) * 0.75))
        box(a, u0, by0, w0, u1, by1, w1, horse) // body
        for u in [u0, u1 - 1] { for w in [0, W - 1] { line(a, D(u), D(by0), D(w0 == 0 ? w : (w == 0 ? w0 : w1 - 1)), D(u), 1, D(w), horse) } } // legs
        box(a, u0 + (u1 - u0) / 3, by1, w0, u0 + 2 * (u1 - u0) / 3, by1 + 1, w1, secondary ?? 0xA8473D) // saddle
        // neck and head at the front
        let hu = min(L - 1, u1 + max(1, (L - u1) / 2))
        line(a, D(u1 - 1), D(by1 - 1), D(wc), D(hu - 1), D(Y - 2), D(wc), horse)
        box(a, hu - 1, Y - 3, w0, L, Y - 1, w1, horse)
        box(a, max(u1 - 1, hu - 2), Y - 1, wc, hu, Y, wc + 1, mane) // mane / ears
        line(a, D(u1 - 1), D(by1), D(wc), D(hu - 2), D(Y - 1), D(wc), mane)
        put(a, L - 1, Y - 2, wc, P.black) // nose
        line(a, D(u0), D(by1 - 1), D(wc), 0, D(by0 - 1), D(wc), mane) // tail
    }

    func toyBlocks(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let colors = [colorFromName(name, 0xC23B2E), 0x3D6FA8, 0xF2B33D, 0x5FA052, 0xE07A9A, 0xF4F1EA]
        let cxs = (X - 1) / 2 / 2, czs = (Z - 1) / 2 / 2
        for cz in 0..<((Z + 1) / 2) {
            for cxi in 0..<((X + 1) / 2) {
                let peak = cxi == cxs && cz == czs
                let h = peak ? Y : max(1, Int(hash3(cxi, 0, cz, seed) * D(Y) * 0.6))
                for y in stride(from: 0, to: h, by: 2) {
                    let c = colors[Int(hash3(cxi, y, cz, seed ^ 0xABC) * D(colors.count)) % colors.count]
                    box(cxi * 2, y, cz * 2, cxi * 2 + 2, min(h, y + 2), cz * 2 + 2) { x, yy, z in
                        yy == min(h, y + 2) - 1 && (x + z) % 2 == 0 ? shade(c, 1.12) : c // studs
                    }
                }
            }
        }
    }

    // MARK: racks

    /// Coat rack / hall tree (a pole on spread feet, hooks fanning out at the top, a coat and a
    /// hat), shoe rack (slatted tiers with pairs of shoes) or clothes / garment rack (two uprights
    /// on caster feet, a top rail, garments hanging).
    func rack(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("shoe") { shoeRack(X, Y, Z, name); return }
        if name.has("clothes", "clothing", "garment", "rail", "rolling rack") { clothesRack(X, Y, Z, name); return }
        let wood = name.has("wood", "wooden", "oak", "bamboo", "walnut")
        let pole = colorFromName(name, wood ? P.oak : P.black)
        let px = (X - 1) / 2, pz = (Z - 1) / 2
        box(px, 0, pz, px + (X >= 10 ? 2 : 1), Y, pz + (Z >= 10 ? 2 : 1), pole)
        let pc = (D(px), D(pz))
        let corners = [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)]
        for (x, z) in corners {
            line(pc.0, 2, pc.1, D(x), 0, D(z), pole) // feet
            line(pc.0, D(Y - 4), pc.1, D(x), D(Y - 2), D(z), pole) // hooks
            set(x, Y - 1, z, pole)
        }
        // a coat on the back-left hook, a hat on top
        let (coat, hat) = accentPair(avoiding: pole)
        let cy0 = max(2, rd(D(Y) * 0.4))
        if X >= 5 && Z >= 4 { box(0, cy0, 1, 2, Y - 3, 3, coat); box(0, cy0, 1, 2, cy0 + 1, 3, shade(coat, 0.8)) }
        if Y >= 10 && X >= 4 { box(max(0, px - 1), Y - 2, max(0, pz - 1), px + 2, Y - 1, pz + 2, hat) }
    }

    func shoeRack(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let metal = name.has("metal", "steel", "wire", "black")
        let frame = colorFromName(name, metal ? P.black : pick([P.oak, P.birch, 0xEBE6DC, P.walnut]))
        let tiers = clamp(Y / 4, 2, 6)
        for x in [0, X - 1] {
            box(x, 0, 0, x + 1, Y, Z, flat: true) { _, _, z in metal && z != 0 && z != Z - 1 ? nil : frame }
        }
        let shoes = [0x2B2A28, 0xEBE6DC, 0x8A5A3A, 0x3F5A73, 0xA8473D, 0x8F8D88, 0xD9A5A0]
        for i in 0..<tiers {
            let y = i == tiers - 1 ? Y - 1 : rd(D(i) * D(Y - 1) / D(tiers - 1))
            box(1, y, 0, X - 1, y + 1, Z, flat: true) { _, _, z in metal || z % 2 == 0 ? shade(frame, 0.92) : nil } // slats
            // pairs of shoes on the tier below the top
            guard i < tiers - 1, y + 1 < Y - 1, Z >= 3 else { continue }
            let next = rd(D(i + 1) * D(Y - 1) / D(tiers - 1))
            let sh = min(2, max(1, next - y - 1))
            var x = 1
            var k = 0
            while x + 2 < X - 1 {
                let c = shoes[Int(hash3(i, k, 3, seed) * D(shoes.count)) % shoes.count]
                if hash3(i, k, 5, seed) < 0.8 {
                    for sx in [x, x + 1] { box(sx, y + 1, 1, sx + 1, y + 1 + sh, Z - 1, flat: true) { _, yy, z in yy == y + sh && z < Z / 2 ? nil : c } }
                }
                x += 3; k += 1
            }
        }
    }

    func clothesRack(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let frame = colorFromName(name, name.has("wood", "wooden", "bamboo") ? P.oak : pick([P.black, 0xC8CCD0, P.brass]))
        let zc = Z / 2
        for x in [0, X - 1] {
            box(x, 1, zc, x + 1, Y, zc + 1, frame) // upright
            box(x, 1, 0, x + 1, 2, Z, frame) // foot
            set(x, 0, 0, P.black); set(x, 0, Z - 1, P.black) // casters
        }
        box(0, Y - 1, zc, X, Y, zc + 1, frame) // top rail
        if Y >= 10 { box(1, 2, 0, X - 1, 3, Z) { _, _, z in z % 2 == 0 ? shade(frame, 0.85) : nil } } // bottom shelf
        let cloth = [P.cream, 0x5B7896, P.blush, P.sage, 0x3A3835, P.mustard, 0xA8473D, 0xEBE6DC]
        let gw = max(0, min(zc, Z - 1 - zc) - (Z >= 6 ? 1 : 0))
        var k = 0
        for x in stride(from: 2, to: X - 2, by: 2) {
            let c = cloth[Int(hash3(x, k, 1, seed) * D(cloth.count)) % cloth.count]
            let long = hash3(x, 9, k, seed) < 0.3
            let bottom = max(4, Y - 2 - rd(D(Y) * (long ? 0.6 : 0.38)))
            set(x, Y - 2, zc, 0xC8CCD0) // hanger hook
            box(x, bottom, zc - gw, x + 1, Y - 2, zc + gw + 1, flat: true) { _, y, z in
                y == Y - 3 && abs(z - zc) == gw && gw > 1 ? shade(c, 0.85) : c
            }
            k += 1
        }
    }

    // MARK: pets

    /// Wire dog crate (bars all round, a tray, a latched front door, a cushion inside) or a
    /// plastic travel kennel / carrier ("carrier", "plastic", "travel"): two-tone shell, a grated door.
    func petCrate(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("carrier", "plastic", "travel", "vari kennel", "petmate") { petCarrier(X, Y, Z, name); return }
        let wire = colorFromName(name, pick([0x2B2A28, 0x9A9FA3]))
        box(0, 0, 0, X, Y, Z, flat: true) { x, y, z in
            if y == 0 { return 0x5A5E62 } // tray
            let fx = x == 0 || x == X - 1, fz = z == 0 || z == Z - 1, top = y == Y - 1
            if !(fx || fz || top) { return nil }
            if (fx && fz) || (top && (fx || fz)) || (y == 1 && (fx || fz)) { return wire }
            if top { return x % 2 == 0 || z % 3 == 0 ? wire : nil }
            if fz { return x % 2 == 0 || y % 4 == 0 ? wire : nil }
            return z % 2 == 0 || y % 4 == 0 ? wire : nil
        }
        if X >= 5 { box(X - 2, Y / 2, Z - 1, X - 1, Y / 2 + 1, Z, 0xC8CCD0) } // latch
        if X >= 5 && Z >= 4 { box(1, 1, 1, X - 1, 2, Z - 1, accentPair(avoiding: wire).0) } // cushion
    }

    func petCarrier(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let lower = colorFromName(name, pick([0xD6C4A4, 0xEBE6DC, 0x8F8D88]))
        let upper = secondary ?? pick([0x8F8D88, 0x3F5A73, 0x5D6B47])
        let mid = max(1, Y / 2)
        let body = Y - 1
        box(0, 0, 0, X, body, Z, flat: true) { x, y, z in
            let fx = x == 0 || x == X - 1, fz = z == 0 || z == Z - 1
            if y == body - 1 && fx && fz { return nil } // rounded top edges
            if !(fx || fz || y == 0 || y == body - 1) { return nil }
            if z == Z - 1 && !fx && y > 0 && y < body - 1 { return x % 2 == 0 ? 0xC8CCD0 : nil } // grated door
            if fx && y == mid + 1 && z % 2 == 1 && z < Z - 1 { return 0x3A3835 } // vent slots
            return y == mid ? 0xC8CCD0 : y > mid ? upper : lower
        }
        let h0 = X / 3, h1 = max(h0 + 1, X - X / 3)
        box(h0, body, Z / 2, h1, Y, Z / 2 + 1, shade(upper, 0.7)) // handle
    }

    /// Round bolster bed (a raised rim with a dip at the front, a cushion inside) or a
    /// rectangular one ("orthopedic", "rectangular", "mat", "lounger": bolsters on three sides).
    func petBed(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let rim = colorFromName(name, pick([0x8F8D88, 0x7A5A40, 0xD6C4A4, 0x3F5A73, 0x5D6B47]))
        let fluffy = name.has("sherpa", "fluffy", "faux fur", "donut", "calming", "shag")
        let cushion = fluffy ? 0xEDE6D8 : (secondary ?? mix(rim, 0xF4EBDD, 0.45))
        let rect = name.has("orthopedic", "rectangle", "rectangular", "mat", "lounger", "crate pad")
        let ch = max(1, Y / 2)
        for z in 0..<Z {
            for x in 0..<X {
                var h: Int
                let onRim: Bool
                if rect {
                    onRim = x == 0 || x == X - 1 || z == 0
                    h = onRim ? Y : ch
                } else {
                    let d = footEllipse(x, z, X, Z)
                    if d > 1 { continue }
                    onRim = d > 0.5
                    h = onRim ? Y : ch
                    if onRim && D(z) > D(Z - 1) * 0.6 && abs(D(x) - D(X - 1) / 2) < D(X) * 0.2 { h = max(ch + 1, rd(D(Y) * 0.6)) } // entry dip
                }
                box(x, 0, z, x + 1, h, z + 1, flat: true) { _, y, _ in
                    if onRim { return y == h - 1 ? shade(rim, 1.08) : rim }
                    return y == h - 1 ? (fluffy && (x / 2 + z / 2) % 2 == 0 ? shade(cushion, 0.94) : cushion) : shade(rim, 0.9)
                }
            }
        }
    }

    /// Cat tree: a carpeted base, sisal posts, platforms alternating sides on the way up, a condo
    /// box with a round door, a perch with a lip on top and a dangling toy.
    func catTree(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let carpet = colorFromName(name, pick([0x8F8D88, 0xD6C4A4, 0x7A5A40, 0xEBE6DC, 0x3A3835]))
        let sisal = 0xC9B58A
        let baseH = Y >= 16 ? 2 : 1
        box(0, 0, 0, X, baseH, Z, flat: true) { _, y, _ in y == baseH - 1 ? carpet : shade(carpet, 0.85) }
        let pw = X >= 10 && Z >= 10 ? 2 : 1
        let pz = (Z - pw) / 2
        let lx = max(1, X / 4 - pw / 2), rx = min(X - 1 - pw, X - 1 - X / 4)
        let levels = clamp((Y - baseH) / 6, 2, 5)
        let perch = Y - 2
        func levelY(_ i: Int) -> Int { i == levels ? perch : baseH + rd(D(perch - baseH) * D(i) / D(levels)) }
        // posts: the left one carries the odd levels, the right one the even ones (and the perch)
        let topLeft = levels % 2 == 1 ? levels : levels - 1, topRight = levels % 2 == 0 ? levels : levels - 1
        box(lx, baseH, pz, lx + pw, levelY(topLeft), pz + pw, flat: true) { _, y, _ in y % 2 == 0 ? sisal : shade(sisal, 0.85) }
        box(rx, baseH, pz, rx + pw, levelY(topRight), pz + pw, flat: true) { _, y, _ in y % 2 == 0 ? sisal : shade(sisal, 0.85) }
        for i in 1...levels {
            let y = levelY(i)
            if i == levels {
                // perch with a raised lip
                box(0, y, 0, X, y + 1, Z, carpet, flat: true)
                box(0, y + 1, 0, X, Y, Z, flat: true) { x, _, z in x == 0 || x == X - 1 || z == 0 || z == Z - 1 ? shade(carpet, 1.06) : nil }
                continue
            }
            let left = i % 2 == 1
            let x0 = left ? 0 : X - max(3, rd(D(X) * 0.6)), x1 = left ? max(3, rd(D(X) * 0.6)) : X
            box(x0, y, 0, x1, y + 1, Z, carpet, flat: true)
            if i == 1 && Y - y > 3 { // a toy on a string under the first platform's edge
                let tx = left ? x0 : x1 - 1
                box(tx, max(baseH + 1, y - 3), Z - 1, tx + 1, y, Z, 0xEBE6DC)
                set(tx, max(baseH, y - 4), Z - 1, 0xC23B2E)
            }
        }
        // condo box on the base, under the second level's side
        let c0 = rx - 1, ch = levelY(min(2, levels)) - baseH - 1
        if ch >= 4 && X - c0 >= 4 && Z >= 4 && levels > 2 {
            let ccx = D(c0 + X - 1) / 2, ccy = D(baseH) + D(ch) / 2 - 0.5, r = max(1, min(D(X - c0) / 2 - 1.2, D(ch) / 2 - 1))
            box(c0, baseH, 0, X, baseH + ch, Z, flat: true) { x, y, z in
                let wall = x == c0 || x == X - 1 || z == 0 || z == Z - 1 || y == baseH + ch - 1
                if !wall { return nil }
                if z == Z - 1 && (D(x) - ccx) * (D(x) - ccx) + (D(y) - ccy) * (D(y) - ccy) <= r * r { return nil } // door
                return shade(carpet, 0.95)
            }
        }
    }
}
