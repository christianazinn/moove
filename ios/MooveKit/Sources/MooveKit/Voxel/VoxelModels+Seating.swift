import Foundation

// OWNER: voxel-models agent. Moove pieces in the house style (palette, jitter, front at +z):
// benches and ottomans.
//
// bench: a plank bench by default (oak, plank seams along x, four legs or two slab ends);
// "storage" (a box base with drawer or cubby fronts and a seat cushion), "shoe" / "entryway"
// (a seat over a lower shelf, a couple of shoes on it), "picnic" (A-frame legs, slatted planks),
// "garden" / "park" (slats on cast-iron ends, a slatted back when tall enough), "metal" (a solid
// metal seat on U-frame legs), "upholstered" / "tufted" / "bed bench" / fabric color words
// (a padded top with tufting dots on wood or metal legs).
// ottoman: an upholstered block with piping, on short legs or a plinth; "tufted" adds buttons,
// "round" / "drum" is round in plan, "storage" adds a lid seam, "leather" a glossier palette.
// Both register their seat top as a surface() so props can sit on them.

extension Canvas {
    func bench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let storage = name.has("storage", "cubby", "cubbies", "drawer", "trunk", "toy box", "blanket chest", "lift-top", "lift top")
        let shoe = name.has("shoe", "entryway", "entry way", "mudroom", "hallway", "hall bench", "boot")
        let picnic = name.has("picnic")
        let outdoor = picnic || name.has("garden", "park", "outdoor", "patio", "porch", "yard")
        let padded = name.has("upholster", "tufted", "padded", "bed bench", "end of bed", "velvet", "linen", "boucle", "bouclé",
                              "fabric", "cushioned", "leather", "faux")
        let metal = name.has("metal", "steel", "iron", "aluminum", "aluminium", "wrought")
        // a fabric color in the name itself (not the material) reads as an upholstered bench
        let fabricColor = name.parts.first?.word("grey", "gray", "navy", "blue", "green", "sage", "pink", "blush", "rose", "beige",
                                                 "cream", "ivory", "red", "burgundy", "mustard", "yellow", "teal", "purple") ?? false
        if storage { storageBench(X, Y, Z, name) }
        else if shoe { shoeBench(X, Y, Z, name) }
        else if outdoor { outdoorBench(X, Y, Z, name, picnic: picnic) }
        else if padded { upholsteredBench(X, Y, Z, name) }
        else if metal { metalBench(X, Y, Z, name) }
        else if fabricColor { upholsteredBench(X, Y, Z, name) }
        else { plankBench(X, Y, Z, name) }
    }

    /// Wood seat along x with plank seams on top; the seam rows are evenly spaced in z.
    private func plankSeat(_ X: Int, _ y0: Int, _ y1: Int, _ Z: Int, _ w: Int) {
        wood(0, y0, 0, X, y1, Z, w, .x)
        let planks = clamp(rd(D(Z) * voxelM / 0.11), 1, max(1, Z / 2))
        let seam = shade(w, 0.78)
        for k in upTo(1, planks) {
            let z = rd(D(Z * k) / D(planks))
            box(0, y1 - 1, z, X, y1, z + 1, seam)
        }
    }

    private func plankBench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let w = colorFromName(name, P.oak)
        let t = Y >= 9 ? 2 : 1
        let sy = Y - t
        plankSeat(X, sy, Y, Z, w)
        surface(0, 0, X, Z, Y)
        let legC = shade(w, 0.88)
        if name.has("slab", "waterfall", "live edge", "live-edge", "modern", "minimal") {
            // two solid slab ends with a notch underneath
            let th = X >= 20 ? 2 : 1
            wood(0, 0, 0, th, sy, Z, legC, .y)
            wood(X - th, 0, 0, X, sy, Z, legC, .y)
            if sy >= 4 && Z >= 6 { box(0, 0, 2, th, 1, Z - 2, -1); box(X - th, 0, 2, X, 1, Z - 2, -1) }
            return
        }
        let lw = X >= 24 && Z >= 8 ? 2 : 1
        let ix = X >= 12 ? 1 : 0, iz = Z >= 6 ? 1 : 0
        var xs = [ix, X - ix - lw]
        if X >= 40 { xs.append(X / 2 - lw / 2) }
        let zs = [iz, Z - iz - lw]
        for lx in xs { for lz in zs { wood(lx, 0, lz, lx + lw, sy, lz + lw, legC, .y) } }
        let rail = shade(w, 0.82)
        if sy >= 4 {
            // aprons under the seat, front and back
            wood(ix + lw, sy - 1, iz, X - ix - lw, sy, iz + 1, rail, .x)
            wood(ix + lw, sy - 1, Z - iz - 1, X - ix - lw, sy, Z - iz, rail, .x)
        }
        if sy >= 5 && Z - 2 * iz - 2 * lw > 0 {
            // low stretchers: one across each leg pair, one long one down the middle
            let fy = max(1, rd(D(sy) * 0.25))
            for lx in xs { wood(lx, fy, iz + lw, lx + lw, fy + 1, Z - iz - lw, rail, .z) }
            wood(ix + lw, fy, Z / 2, X - ix - lw, fy + 1, Z / 2 + 1, rail, .x)
        }
    }

    private func storageBench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, P.white)
        let knob = body == P.white || body == 0xEBE6DC ? P.brass : P.charcoal
        let cushion = secondary ?? (name.has("leather") ? 0x8A5A3A : accentPair(avoiding: body).0)
        let cushH = Y >= 8 ? 2 : 1
        let top = Y - cushH // first cushion layer
        let kick = top >= 5 ? 1 : 0
        let back = max(1, Z - 1) // the case stops one voxel short so knobs stand proud
        if kick > 0 { box(1, 0, 1, X - 1, 1, back - 1, shade(body, 0.62)) }
        wood(0, kick, 0, X, top - 1, back, shade(body, 0.96), .x)
        wood(0, top - 1, 0, X, top, Z, body, .x) // top board with an overhang
        let zf = max(0, Z - 2)
        let y0 = kick, y1 = top - 1
        if y1 - y0 >= 2 {
            let cubby = name.has("cubby", "cubbies", "basket", "bins", "open")
            let lid = !cubby && name.has("lift", "lid", "trunk", "chest", "hinged")
            if lid {
                // one big lift-top front: a seam under the top board and a center pull
                box(0, y0, zf, X, y1, zf + 1) { x, y, _ in x == 0 || x == X - 1 || y == y1 - 1 ? shade(body, 0.74) : body }
                set(X / 2, y1 - 2, zf + 1, knob)
            } else {
                let n = clamp(rd(D(X) * voxelM / 0.38), 1, max(1, X / 3))
                let weave = [P.kraft, 0xC9A875, shade(P.kraft, 0.85)]
                for k in 0..<n {
                    let x0 = rd(D(X * k) / D(n)), x1 = rd(D(X * (k + 1)) / D(n))
                    if cubby && x1 - x0 >= 3 && Z >= 4 {
                        // an open cubby framed by the case; some hold a woven basket (seeded detail)
                        box(x0 + 1, y0 + 1, 1, x1 - 1, y1, back, -1)
                        let hb = max(1, (y1 - y0 - 1) * 2 / 3)
                        if rand() < 0.65 && y1 - y0 - 1 >= 2 && x1 - x0 >= 4 {
                            let wc = weave[Int(rand() * 3) % 3]
                            box(x0 + 1, y0 + 1, 1, x1 - 1, y0 + 1 + hb, back) { x, y, _ in (x + y) % 2 == 0 ? wc : shade(wc, 0.86) }
                        }
                    } else {
                        drawerFront(x0, x1, y0, y1, zf, body, knob, x1 - x0 >= 12)
                    }
                }
            }
        }
        // seat cushion: piped edge, rounded corners, optional buttons
        let pipe = shade(cushion, 0.86)
        box(0, top, 0, X, Y, Z) { x, y, z in
            let ex = x == 0 || x == X - 1, ez = z == 0 || z == Z - 1
            if y == Y - 1 && ex && ez { return nil }
            if y == Y - 1 && (ex || ez) { return pipe }
            return cushion
        }
        if name.has("tufted", "button") { tufts(1, Z - 1, 1, X - 1, Y - 1, shade(cushion, 0.7), deep: false) }
        surface(0, 0, X, Z, Y)
    }

    private func shoeBench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let w = colorFromName(name, P.oak)
        let t = Y >= 9 ? 2 : 1
        let sy = Y - t
        plankSeat(X, sy, Y, Z, w)
        surface(0, 0, X, Z, Y)
        let side = X >= 20 ? 2 : 1
        wood(0, 0, 0, side, sy, Z, shade(w, 0.9), .y)
        wood(X - side, 0, 0, X, sy, Z, shade(w, 0.9), .y)
        guard sy >= 3 else { return }
        let shelfY = sy >= 6 ? 1 : 0
        let shelfC = shade(w, 0.94)
        wood(side, shelfY, 0, X - side, shelfY + 1, Z, shelfC, .x)
        var gapTop = sy
        if sy >= 12 {
            // a second shelf halfway up
            let midY = shelfY + (sy - shelfY) / 2
            wood(side, midY, 0, X - side, midY + 1, Z, shelfC, .x)
            gapTop = midY
        }
        if sy - shelfY >= 3 { box(side, sy - 1, 0, X - side, sy, 1, shade(w, 0.82)) } // back rail
        // a couple of pairs of shoes on the bottom shelf (seeded colors and gaps)
        let free = gapTop - (shelfY + 1)
        let inner = X - 2 * side
        guard free >= 1, inner >= 4, Z >= 4 else { return }
        let shoeColors = [P.charcoal, P.white, P.rust, P.navy, 0x7A5A40, P.sage]
        let L = clamp(vox(0.27), 2, Z - 1)
        let pairs = clamp(inner / 5, 1, 4)
        let sole = shelfY + 1
        for k in 0..<pairs where k < 2 || rand() < 0.5 {
            let c = shoeColors[Int(rand() * D(shoeColors.count)) % shoeColors.count]
            let px = side + 1 + rd(D(inner - 3) * D(k) / D(max(1, pairs - 1)) * (pairs > 1 ? 1 : 0))
            for sx in [px, px + 2] where sx < X - side {
                box(sx, sole, Z - L, sx + 1, sole + 1, Z, shade(c, 0.6)) // sole
                if free >= 2 { box(sx, sole + 1, Z - L, sx + 1, sole + 2, Z - L / 2, c) } // heel / upper
            }
        }
    }

    private func metalBench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        // a solid metal seat on inverted-U tube legs with a foot rail
        let c = colorFromName(name, P.charcoal)
        let frame = shade(c, 0.8)
        let sy = Y - 1
        box(0, sy, 0, X, Y, Z) { x, _, z in x == 0 || x == X - 1 || z == 0 || z == Z - 1 ? shade(c, 0.9) : c }
        surface(0, 0, X, Z, Y)
        let ix = X >= 12 ? 1 : 0
        var xs = [ix, X - 1 - ix]
        if X >= 40 { xs.append(X / 2) }
        for lx in xs {
            box(lx, 0, 0, lx + 1, sy, 1, frame)
            box(lx, 0, Z - 1, lx + 1, sy, Z, frame)
            box(lx, sy - 1, 1, lx + 1, sy, Z - 1, frame) // top of the U under the seat
            box(lx, 0, 1, lx + 1, 1, Z - 1, frame) // foot rail
        }
    }

    private func outdoorBench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, picnic: Bool) {
        let iron = name.removingWords("metal", "iron", "steel", "black", "wrought", "cast", "aluminum", "aluminium")
        let slatC = colorFromName(iron, picnic ? P.oak : 0x9C6B45)
        let frameC = picnic ? shade(slatC, 0.88) : name.word("green") ? 0x3E5A44 : name.word("white") ? P.white : 0x2B2A28
        let hasBack = !picnic && Y >= 14 && Z >= 6
        let seatY = hasBack ? clamp(vox(0.45) - 1, 2, Y - 5) : Y - 1
        let z0 = hasBack ? 1 : 0
        // slats along x with gaps (picnic planks are wider)
        let period = picnic ? 4 : 3
        for z in upTo(z0, Z) where (z - z0) % period != period - 1 || z == Z - 1 {
            wood(0, seatY, z, X, seatY + 1, z + 1, slatC, .x)
        }
        surface(0, z0, X, Z, seatY + 1)
        guard seatY >= 1 else { return }
        let thick = X >= 24 ? 2 : 1
        if picnic {
            // A-frame legs at each end, a cleat under the seat, a long brace
            let zc = D(Z - 1) / 2
            for ex in [1, X - 1 - thick] {
                for dx in 0..<thick {
                    line(D(ex + dx), 0, 0, D(ex + dx), D(seatY - 1), zc, frameC)
                    line(D(ex + dx), 0, D(Z - 1), D(ex + dx), D(seatY - 1), zc, frameC)
                    box(ex + dx, seatY - 1, 0, ex + dx + 1, seatY, Z, shade(frameC, 0.92))
                }
            }
            if seatY >= 4 { wood(1, rd(D(seatY) * 0.4), Z / 2, X - 1, rd(D(seatY) * 0.4) + 1, Z / 2 + 1, shade(frameC, 0.95), .x) }
            return
        }
        // cast-iron ends: front and back legs, a seat rail, curled feet
        var ends = [0, X - thick]
        if X >= 36 { ends.append(X / 2) }
        let backTop = hasBack ? Y : seatY
        for ex in ends {
            box(ex, 0, 0, ex + thick, backTop, 1, frameC) // back leg (rises into the back post)
            box(ex, 0, Z - 1, ex + thick, seatY, Z, frameC) // front leg
            box(ex, seatY - 1, 0, ex + thick, seatY, Z, frameC) // seat rail
            if seatY >= 4 && Z >= 6 { set(ex, 1, 1, frameC); set(ex, 1, Z - 2, frameC); if thick > 1 { set(ex + 1, 1, 1, frameC); set(ex + 1, 1, Z - 2, frameC) } }
            if hasBack {
                // armrest from the back post to a front post
                let armY = min(Y - 2, seatY + max(2, (Y - seatY) / 3))
                box(ex, armY, 0, ex + thick, armY + 1, Z, frameC)
                box(ex, seatY, Z - 1, ex + thick, armY, Z, frameC)
            }
        }
        if hasBack {
            // horizontal back slats at z = 0 between the end posts, a top rail
            for y in stride(from: seatY + 2, to: Y - 1, by: 2) { wood(thick, y, 0, X - thick, y + 1, 1, slatC, .x) }
            wood(thick, Y - 1, 0, X - thick, Y, 1, shade(slatC, 1.04), .x)
        }
    }

    private func upholsteredBench(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let metalLegs = name.has("metal", "brass", "gold", "steel", "iron", "chrome", "hairpin")
        let fab = colorFromName(name.removingWords("oak", "walnut", "pine", "wood", "wooden", "metal", "steel", "brass", "gold", "iron", "chrome"), P.linen)
        let legC = metalLegs ? (name.word("brass", "gold") ? P.brass : 0x2B2A28) : P.walnut
        let legH = clamp(rd(D(Y) * 0.4), 1, Y - 2)
        let frameH = Y >= 8 ? 1 : 0
        let padY0 = legH + frameH
        let ix = X >= 14 ? 1 : 0, iz = Z >= 8 ? 1 : 0
        var xs = [ix, X - 1 - ix]
        if X >= 36 { xs.append(X / 2) }
        for lx in xs {
            for lz in [iz, Z - 1 - iz] {
                if metalLegs { box(lx, 0, lz, lx + 1, legH, lz + 1, legC) } else { wood(lx, 0, lz, lx + 1, legH, lz + 1, legC, .y) }
            }
        }
        if frameH > 0 {
            if metalLegs { box(0, legH, 0, X, legH + 1, Z, shade(legC, 0.9)) } else { wood(0, legH, 0, X, legH + 1, Z, shade(legC, 0.95), .x) }
        }
        let pipe = shade(fab, 0.88), welt = shade(fab, 0.8)
        box(0, padY0, 0, X, Y, Z) { x, y, z in
            let ex = x == 0 || x == X - 1, ez = z == 0 || z == Z - 1
            if y == Y - 1 && ex && ez { return nil } // soft rounded corners
            if y == Y - 1 && (ex || ez) { return pipe }
            if y == padY0 && (ex || ez) && Y - padY0 >= 3 { return welt }
            return fab
        }
        // tufting: flat buttons on any padded bench, sunk in on a "tufted" one
        tufts(1, Z - 1, 1, X - 1, Y - 1, shade(fab, 0.68), deep: name.has("tufted", "chesterfield") && Y - padY0 >= 2)
        surface(0, 0, X, Z, Y)
    }

    /// Button dots on the top layer `y` over [x0, x1) × [z0, z1), rows 3 apart with alternate
    /// rows offset (a diamond pattern). `deep` sinks each button one layer into the padding.
    private func tufts(_ z0: Int, _ z1: Int, _ x0: Int, _ x1: Int, _ y: Int, _ c: Int, deep: Bool, inside: (Int, Int) -> Bool = { _, _ in true }) {
        for z in upTo(z0, z1) where (z - z0) % 3 == 1 {
            let row = (z - z0) / 3
            for x in upTo(x0, x1) where (x - x0 + (row % 2 == 1 ? 2 : 0)) % 3 == 1 && inside(x, z) {
                if deep { clear(x, y, z); set(x, y - 1, z, c) } else { set(x, y, z, c) }
            }
        }
    }

    func ottoman(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let leather = name.has("leather", "vinyl", "faux leather", "pleather")
        let round = name.has("round", "drum", "circular", "cylinder", "cylindrical")
        let storage = name.has("storage", "lift", "lid", "trunk", "chest")
        let tufted = name.has("tufted", "button", "chesterfield", "diamond")
        let fab = colorFromName(name, leather ? 0x8A5A3A : P.oatmeal)
        // leather: deeper seams and a glossier top
        let hi = shade(fab, leather ? 1.12 : 1.04)
        let pipe = shade(fab, leather ? 0.66 : 0.8)
        let base = shade(fab, 0.55)

        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, ex = D(X) / 2, ez = D(Z) / 2
        let inRound = { (x: Int, z: Int, shrink: Double) -> Bool in
            let dx = (D(x) - cx) / max(0.5, ex - shrink), dz = (D(z) - cz) / max(0.5, ez - shrink)
            return dx * dx + dz * dz <= 1
        }
        let inside = { (x: Int, z: Int) -> Bool in
            round ? inRound(x, z, 0) : (x >= 0 && z >= 0 && x < X && z < Z)
        }
        let edge = { (x: Int, z: Int) -> Bool in
            inside(x, z) && (!inside(x - 1, z) || !inside(x + 1, z) || !inside(x, z - 1) || !inside(x, z + 1))
        }

        // legs on a square ottoman, a recessed plinth on round / storage / skirted ones
        let plinth = round || storage || name.has("plinth", "skirt", "skirted", "base")
        let legH = plinth ? 1 : clamp(rd(D(Y) * 0.15), 1, 3)
        if plinth {
            box(0, 0, 0, X, 1, Z) { x, _, z in
                if round { return inRound(x, z, 1) ? base : nil }
                return x >= 1 && z >= 1 && x < X - 1 && z < Z - 1 ? base : nil
            }
        } else {
            let legC = name.word("brass", "gold") ? P.brass : name.has("metal", "black legs", "chrome") ? 0x2B2A28 : P.walnut
            for (lx, lz) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { box(lx, 0, lz, lx + 1, legH, lz + 1, legC) }
        }

        let y0 = legH
        let lidY = storage ? clamp(Y - 3, y0 + 1, Y - 2) : -1
        box(0, y0, 0, X, Y, Z) { x, y, z in
            guard inside(x, z) else { return nil }
            let e = edge(x, z)
            if y == Y - 1 {
                // soft rounded corners on the square block
                if !round && (x == 0 || x == X - 1) && (z == 0 || z == Z - 1) { return nil }
                return e ? shade(hi, 0.95) : hi
            }
            guard e else { return fab }
            if y == Y - 2 { return pipe } // top piping
            if y == lidY { return shade(fab, 0.55) } // lid seam
            if y == y0 && Y - y0 >= 5 { return pipe } // bottom welt
            // a vertical seam down the middle of the front / back on square ones
            if !round && (z == 0 || z == Z - 1) && x == X / 2 && X >= 10 { return shade(fab, 0.85) }
            return fab
        }
        if storage && !round { set(X / 2, max(y0, lidY - 1), Z - 1, pipe) } // lid pull under the seam
        if tufted {
            tufts(1, Z - 1, 1, X - 1, Y - 1, shade(fab, leather ? 0.55 : 0.68), deep: Y - y0 >= 3) { x, z in inside(x, z) && !edge(x, z) }
        }

        if round {
            // the square inscribed in the ellipse
            let sx = max(0, fl(ex * 0.7)), sz = max(0, fl(ez * 0.7))
            surface(rd(cx) - sx + (X % 2 == 0 ? 1 : 0), rd(cz) - sz + (Z % 2 == 0 ? 1 : 0), rd(cx) + sx, rd(cz) + sz, Y)
        } else {
            surface(0, 0, X, Z, Y)
        }
    }
}
