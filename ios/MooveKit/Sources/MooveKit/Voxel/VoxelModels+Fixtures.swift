import Foundation

// OWNER: voxel-models agent. Lisa's scan 9 (Oct 24): "the toilet looks like a plant". RoomPlan's
// built-in fixtures (toilet, sink, bathtub, fireplace, stairs) had no model and were drawn by
// their box shape (a toilet as a dresser, a sink and a tub as moving boxes). Also here: the
// folding screen (a "room divider", once a bookshelf), soft goods (a pillow or a folded blanket:
// small flat things a furniture name can't be, like a 15 cm "workbench" on a bed) and the
// neutral unknown thing under a dust sheet (an unnamed "other", once a kraft moving box).
// Same conventions as the other builders: front at +z, filling the scanned box.

/// Porcelain white, a touch warm, and its shading.
private let porcelain = 0xF1F0EB
private let porcelainShadow = 0xD9D8D2
private let chrome = 0xB9BEC2
private let water = 0x9CC4DA

extension Canvas {
    // MARK: toilet

    /// Close-coupled toilet: a tank against the wall (z = 0) with a lid and a chrome flush
    /// lever, an oval bowl on a narrower pedestal toward the front, a seat ring (lid up against
    /// the tank) and water in the bowl.
    func toilet(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, porcelain)
        let seatC = name.has("wood seat", "wooden seat") ? P.oak : shade(body, 0.92)
        let low = shade(body, 0.86)
        let cx = D(X - 1) / 2
        let tankD = clamp(rd(D(Z) * 0.28), 2, max(2, Z / 2))
        let seatY = clamp(rd(D(Y) * 0.5), 3, max(3, Y - 3))
        let tank0 = max(1, seatY - 2)
        // bowl: an oval from just in front of the tank to the front edge
        let bz0 = D(tankD) - 1, bz1 = D(Z) - 0.5
        let bcz = (bz0 + bz1) / 2, brz = (bz1 - bz0) / 2, brx = D(X) / 2
        func inBowl(_ x: Int, _ z: Int, _ scale: Double) -> Bool {
            let dx = (D(x) - cx) / (brx * scale), dz = (D(z) - bcz) / (brz * scale)
            return dx * dx + dz * dz <= 1
        }
        for y in 0..<seatY {
            // pedestal narrow at the floor, flaring out to the bowl's rim
            let t = D(y) / D(max(1, seatY - 1))
            let s = t < 0.45 ? 0.62 + t * 0.3 : 0.76 + (t - 0.45) / 0.55 * 0.24
            for z in 0..<Z { for x in 0..<X where inBowl(x, z, s) { set(x, y, z, y == 0 ? low : body, flat: true) } }
        }
        // trapway back to the wall, under the tank
        box(rd(cx - D(X) * 0.22), 0, 0, rd(cx + D(X) * 0.22) + 1, tank0, tankD + 1, body, flat: true)
        // hollow bowl with water at the bottom
        for z in 0..<Z {
            for x in 0..<X where inBowl(x, z, 0.7) {
                for y in upTo(max(1, seatY - 3), seatY) { clear(x, y, z) }
                if inBowl(x, z, 0.56) { set(x, max(1, seatY - 3), z, water, flat: true) } else { set(x, max(1, seatY - 3), z, porcelainShadow, flat: true) }
            }
        }
        // seat ring on the rim
        for z in 0..<Z { for x in 0..<X where inBowl(x, z, 1.0) && !inBowl(x, z, 0.7) && D(z) > bz0 + 1 { set(x, seatY, z, seatC, flat: true) } }
        // tank: a block on the bowl's back, a lid slab on top, the flush lever on the front left
        box(0, tank0, 0, X, Y - 1, tankD, flat: true) { _, y, _ in y == tank0 ? low : body }
        box(0, Y - 1, 0, X, Y, tankD, shade(body, 1.03), flat: true)
        // seat lid raised against the tank front, the flush lever on the tank's front left corner
        if Y - 2 > seatY + 1 { box(1, seatY + 1, tankD, X - 1, min(Y - 2, seatY + 1 + rd(D(Y - seatY) * 0.7)), tankD + 1, seatC, flat: true) }
        set(0, Y - 3, tankD, chrome, flat: true)
    }

    // MARK: sink

    /// A low box (≤ 40 cm) is a basin on a counter: just the basin and its faucet. Taller: a
    /// pedestal sink ("pedestal", "wall-hung") or a vanity cabinet with a counter, an inset basin,
    /// two doors and a toe kick.
    func sink(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let basinC = colorFromName(name.removingWords("wood", "wooden", "oak", "walnut"), porcelain)
        let cx = D(X - 1) / 2
        let faucetH = clamp(rd(D(Y) * 0.22), 2, 4)
        if Y <= 8 {
            // countertop basin (the scan saw the bowl on a counter)
            let bh = max(2, Y - faucetH)
            basin(0, 0, 0, X, bh, Z, basinC, depth: max(1, bh - 1))
            faucet(rd(cx), bh, 0, top: Y - 1, reach: max(1, Z / 3))
            return
        }
        let pedestal = name.has("pedestal", "wall-hung", "wall hung", "wall mounted", "wall-mounted", "console sink")
        let counterTop = Y - faucetH // first layer above the counter
        if pedestal {
            let bh = clamp(rd(D(Y) * 0.22), 2, 5)
            basin(0, counterTop - bh, 0, X, counterTop, Z, basinC, depth: bh - 1)
            // column (or a chrome trap to the wall when wall-hung)
            if name.has("wall") {
                box(rd(cx), 1, 0, rd(cx) + 1, counterTop - bh, 2, chrome)
            } else {
                for y in upTo(0, counterTop - bh) {
                    let t = D(y) / D(max(1, counterTop - bh))
                    cyl(cx, D(Z) * 0.42, max(1, D(min(X, Z)) * (0.24 - 0.06 * t)), y, y + 1, y == 0 ? shade(basinC, 0.9) : basinC)
                }
            }
            faucet(rd(cx), counterTop, 0, top: Y - 1, reach: max(1, Z / 3))
            return
        }
        // vanity
        let cab = colorFromName(name, pick([P.white, P.oak, 0x5B6B78, 0xEBE6DC]))
        let counter = 0xE7E2D8
        let kick = 1
        box(0, 0, 0, X, counterTop - 1, Z - 1) { _, y, z in
            if y < kick && z >= Z - 2 { return -1 } // toe kick recess
            return cab
        }
        box(0, kick, Z - 1, X, counterTop - 1, Z) { x, y, _ in
            // two doors: frame lines at the edges and the middle seam
            if x == 0 || x == X - 1 || y == kick || y == counterTop - 2 || (X >= 8 && (x == X / 2 || x == (X - 1) / 2)) { return shade(cab, 0.88) }
            return cab
        }
        if X >= 8 {
            let ky = max(kick + 1, counterTop - 4)
            set(X / 2 - 2, ky, Z, P.brass); set(X / 2 + 1 + (X % 2), ky, Z, P.brass)
        }
        box(0, counterTop - 1, 0, X, counterTop, Z, counter)
        // the basin sunk into the counter
        let bx0 = max(1, rd(D(X) * 0.2)), bx1 = min(X - 1, X - rd(D(X) * 0.2))
        let bz0 = max(2, rd(D(Z) * 0.25)), bz1 = max(bz0 + 1, Z - 2)
        for z in upTo(bz0, bz1) {
            for x in upTo(bx0, bx1) {
                let corner = (x == bx0 || x == bx1 - 1) && (z == bz0 || z == bz1 - 1)
                if corner { continue }
                set(x, counterTop - 1, z, basinC == porcelain ? porcelainShadow : shade(basinC, 0.85))
                clear(x, counterTop - 1, z)
                set(x, counterTop - 2, z, shade(basinC, 0.9))
            }
        }
        set(rd(cx), counterTop - 2, (bz0 + bz1) / 2, P.charcoal, flat: true) // drain
        faucet(rd(cx), counterTop, max(0, bz0 - 2), top: Y - 1, reach: max(1, (bz1 - bz0) / 3))
    }

    /// A rounded-rectangle basin filling [x0, x1) × [y0, y1) × [z0, z1), hollowed `depth` layers from the top.
    func basin(_ x0: Int, _ y0: Int, _ z0: Int, _ x1: Int, _ y1: Int, _ z1: Int, _ c: Int, depth: Int) {
        let w = x1 - x0, d = z1 - z0
        guard w > 0, d > 0, y1 > y0 else { return }
        func inside(_ x: Int, _ z: Int, _ inset: Double) -> Bool {
            let u = abs(D(x - x0) - D(w - 1) / 2) / max(0.5, D(w) / 2 - inset)
            let v = abs(D(z - z0) - D(d - 1) / 2) / max(0.5, D(d) / 2 - inset)
            return pow(u, 3) + pow(v, 3) <= 1.05
        }
        for y in upTo(y0, y1) {
            for z in upTo(z0, z1) {
                for x in upTo(x0, x1) where inside(x, z, y == y0 ? 1 : 0) { set(x, y, z, y == y0 ? shade(c, 0.86) : c) }
            }
        }
        let hy0 = max(y0 + 1, y1 - depth)
        for y in upTo(hy0, y1) {
            for z in upTo(z0, z1) { for x in upTo(x0, x1) where inside(x, z, 1.2) { clear(x, y, z) } }
        }
        for z in upTo(z0, z1) { for x in upTo(x0, x1) where inside(x, z, 1.2) { set(x, hy0 - 1, z, shade(c, 0.88)) } }
        set((x0 + x1 - 1) / 2, hy0 - 1, (z0 + z1 - 1) / 2, P.charcoal, flat: true)
    }

    /// A chrome faucet: a column at (x, z) from `y` up to `top`, a spout reaching `reach` toward +z
    /// with its tip one layer down, and a handle on each side.
    func faucet(_ x: Int, _ y: Int, _ z: Int, top: Int, reach: Int) {
        guard top >= y else { return }
        box(x, y, z, x + 1, top + 1, z + 1, chrome, flat: true)
        box(x, top, z, x + 1, top + 1, z + 1 + reach, chrome, flat: true)
        if top - 1 >= y { set(x, top - 1, z + reach, chrome, flat: true) }
        set(x - 1, y, z, chrome, flat: true); set(x + 1, y, z, chrome, flat: true)
    }

    // MARK: bathtub

    /// Alcove bathtub along its long side: a white shell with a wide rim, an apron on the front,
    /// a rounded tub inside with some water in it, and a chrome spout and handles at the head
    /// end. "Clawfoot" / "freestanding": rounded ends standing on four brass feet.
    func bathtub(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let body = colorFromName(name, porcelain)
        let claw = name.has("clawfoot", "claw-foot", "claw foot", "freestanding", "free-standing", "roll top", "slipper")
        let rimTop = Y - 2 // one layer above it is left for the spout
        let rim = W >= 12 ? 2 : 1
        let foot = claw ? 1 : 0
        func outer(_ u: Int, _ w: Int) -> Bool {
            guard claw else { return true }
            let p = abs(D(u) - D(L - 1) / 2) / (D(L) / 2), q = abs(D(w) - D(W - 1) / 2) / (D(W) / 2)
            return pow(p, 4) + pow(q, 2.2) <= 1.08
        }
        func inner(_ u: Int, _ w: Int) -> Bool {
            let iu = D(L) / 2 - D(rim) - 0.4, iw = D(W) / 2 - D(rim) - 0.2
            let p = abs(D(u) - D(L - 1) / 2) / max(0.5, iu), q = abs(D(w) - D(W - 1) / 2) / max(0.5, iw)
            return pow(p, 4) + pow(q, 4) <= 1
        }
        let waterY = clamp(rd(D(rimTop) * 0.55), foot + 2, max(foot + 2, rimTop - 1))
        for u in 0..<L {
            for w in 0..<W where outer(u, w) {
                for y in upTo(foot, rimTop + 1) {
                    if inner(u, w) && y > foot + 1 {
                        if y < waterY { continue }
                        if y == waterY { put(a, u, y, w, water, flat: true); continue }
                        continue
                    }
                    let apron = w == W - 1 && y < rimTop
                    put(a, u, y, w, y == foot ? shade(body, 0.85) : y == rimTop ? shade(body, 1.02) : apron ? shade(body, 0.95) : body, flat: true)
                }
                if inner(u, w) { put(a, u, foot + 1, w, porcelainShadow, flat: true) }
            }
        }
        if claw {
            for (u, w) in [(2, 1), (L - 3, 1), (2, W - 2), (L - 3, W - 2)] { put(a, u, 0, w, P.brass) }
        }
        // spout and handles at the head end (u = 0), on the wall side of the rim
        let mw = W / 2
        put(a, 0, rimTop + 1, mw, chrome, flat: true)
        put(a, 1, rimTop + 1, mw, chrome, flat: true)
        if L > 8 { put(a, 2, rimTop + 1, mw, chrome, flat: true) }
        put(a, 0, rimTop + 1, max(0, mw - 2), chrome, flat: true)
        put(a, 0, rimTop + 1, min(W - 1, mw + 2), chrome, flat: true)
    }

    // MARK: fireplace

    /// Fireplace against the wall: a brick (or "stone", "white", "marble") surround, a wooden
    /// mantel shelf on top (a surface for props), a stone hearth slab in front, and a dark
    /// firebox with logs and a low flame.
    func fireplace(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let stone = name.has("stone", "rock", "fieldstone")
        let painted = name.has("white", "painted", "marble", "electric", "modern")
        let brick = colorFromName(name, painted ? 0xEDE8DF : stone ? 0xA8A29A : 0xA65A3F)
        let mortar = mix(brick, 0xE4DDD0, 0.55)
        let mantelC = name.has("white", "painted") ? 0xF4F1EA : P.walnut
        let hearth = 0x8F8D88
        let mantelY = Y - 1, bodyZ = max(2, Z - 1)
        let ox0 = rd(D(X) * 0.25), ox1 = X - rd(D(X) * 0.25)
        let oyTop = clamp(rd(D(Y) * 0.55), 3, max(3, mantelY - 2))
        box(0, 1, 0, X, mantelY, bodyZ) { x, y, z in
            if painted { return brick }
            // running bond bricks: a mortar line every third layer, joints staggered per course
            let course = y / 3
            if y % 3 == 0 { return mortar }
            let bx = (x + (course % 2 == 0 ? 0 : 2) + z) / 4
            if (x + (course % 2 == 0 ? 0 : 2) + z) % 4 == 0 { return mortar }
            return hash3(bx, course, 7, seed) < 0.3 ? shade(brick, 0.88) : brick
        }
        // mantel shelf (full depth) and the hearth slab in front
        box(0, mantelY, 0, X, Y, Z, mantelC)
        box(0, 0, 0, X, 1, Z, hearth)
        // firebox
        box(ox0, 1, 1, ox1, oyTop, bodyZ, 0x2B2A28, flat: true)
        box(ox0 - 1, oyTop, bodyZ - 1, ox1 + 1, oyTop + 1, bodyZ, painted ? shade(brick, 0.85) : 0x3A3835) // lintel
        let logY = 1, lz = max(1, bodyZ - 2)
        box(ox0 + 1, logY, lz, ox1 - 1, logY + 1, lz + 1, 0x6E4A33)
        if ox1 - ox0 >= 5 {
            box(ox0 + 2, logY + 1, lz, ox1 - 2, logY + 2, lz + 1, 0x8A5A3A)
            for x in upTo(ox0 + 2, ox1 - 2) where hash3(x, 2, 1, seed) < 0.75 { set(x, logY + 2, lz, x % 2 == 0 ? 0xF2A03C : 0xE0662A, flat: true) }
            for x in upTo(ox0 + 3, ox1 - 3) where x % 2 == 1 && oyTop > logY + 3 { set(x, logY + 3, lz - 1, 0xFFD78A, flat: true) }
        }
        surface(0, 0, X, Z, Y)
    }

    // MARK: stairs

    /// A straight flight climbing toward the back (z = 0 is the top step): white risers and
    /// stringers, oak treads with a darker nosing, and a banister on the right side where it fits
    /// under the scanned height.
    func stairs(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let treadC = colorFromName(name, P.oak), riserC = 0xF1EEE7, stringer = 0xE4E0D7
        let n = max(2, rd(D(Y) / 3.6))
        let rise = D(Y) / D(n), run = D(Z) / D(n)
        func top(_ z: Int) -> Int { // first empty layer above step at z
            let k = min(n - 1, fl(D(Z - 1 - z) / run))
            return min(Y, rd(D(k + 1) * rise))
        }
        for z in 0..<Z {
            let t = top(z)
            let front = z == Z - 1 || top(z + 1) < t
            box(0, 0, z, X, t, z + 1, flat: true) { x, y, _ in
                if y == t - 1 { return front ? shade(treadC, 0.82) : treadC }
                if x == 0 || x == X - 1 { return stringer }
                return riserC
            }
        }
        // banister: posts every other tread, a rail 0.9 m above the treads
        let railH = 17
        let bx = X - 1
        var lastRail: Int?
        for z in stride(from: Z - 1, through: 0, by: -1) {
            let r = top(z) + railH
            guard r < Y else { break }
            set(bx, r, z, P.walnut)
            if let lr = lastRail, lr < r - 1 { for y in upTo(lr + 1, r) { set(bx, y, z, P.walnut) } }
            lastRail = r
            let k = fl(D(Z - 1 - z) / run)
            let stepFront = z == Z - 1 || top(z + 1) < top(z)
            if stepFront && k % 2 == 0 { box(bx, top(z), z, bx + 1, r, z + 1, z == Z - 1 ? P.walnut : 0xF4F1EA) }
        }
    }

    // MARK: folding screen

    /// Folding screen / room divider: three or more framed panels standing in a zigzag across the
    /// footprint, wood frames around paper (shoji-style lattice) or fabric, on little feet.
    func foldingScreen(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let frame = colorFromName(name.removingWords("fabric", "paper", "canvas"), name.has("black") ? P.black : P.walnut)
        let fabric = name.has("fabric", "canvas", "linen") ? (secondary ?? P.linen) : 0xF2ECDF
        let shoji = !name.has("fabric", "canvas", "linen", "mirror")
        let panels = clamp(rd(D(L) / 9), 3, 6)
        // plan cells of each panel: a 4-connected line between alternating sides
        for i in 0..<panels {
            let u0 = D(i) * D(L - 1) / D(panels), u1 = D(i + 1) * D(L - 1) / D(panels)
            let w0 = i % 2 == 0 ? 0.0 : D(W - 1), w1 = i % 2 == 0 ? D(W - 1) : 0.0
            let steps = max(1, ce(max(abs(u1 - u0), abs(w1 - w0)) * 2))
            var cells: [(Int, Int)] = []
            var last: (Int, Int)?
            for s in 0...steps {
                let t = D(s) / D(steps)
                let c = (rd(u0 + (u1 - u0) * t), rd(w0 + (w1 - w0) * t))
                if let l = last, l != c {
                    if l.0 != c.0 && l.1 != c.1 { cells.append((c.0, l.1)) } // no diagonal gaps
                }
                if last.map({ $0 != c }) ?? true { cells.append(c) }
                last = c
            }
            let n = cells.count
            for (j, c) in cells.enumerated() {
                let edge = j == 0 || j == n - 1
                for y in upTo(1, Y) {
                    let rail = y == 1 || y == Y - 1 || y == Y - 2 && !shoji
                    let lattice = shoji && (y % 4 == 0 || (j % 3 == 0))
                    put(a, c.0, y, c.1, edge || rail ? frame : lattice ? shade(frame, 1.15) : fabric, flat: !(edge || rail))
                }
                if edge { put(a, c.0, 0, c.1, shade(frame, 0.8)) }
            }
        }
    }

    // MARK: soft goods

    /// Small flat soft things: a long, narrow box is a bed pillow; otherwise a folded blanket
    /// (stacked folds, a stripe band near one end) or a stack of towels.
    func softGoods(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let long = max(X, Z), short = max(1, min(X, Z))
        let blanketWords = name.has("blanket", "throw", "towel", "linen", "quilt", "comforter", "duvet", "bedding", "afghan")
        if VoxelModels.isPillow(name) || (!blanketWords && D(long) / D(short) >= 1.6) {
            pillow(X, Y, Z, name, fallback: 0xEEEAE2)
            return
        }
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let cloth = colorFromName(name, pick([P.oatmeal, 0x7E95A8, P.blush, 0xB9A58A, 0x9A8FA8]))
        let band = secondary ?? (cloth == P.oatmeal ? P.rust : P.cream)
        let towels = name.has("towel")
        let b0 = rd(D(L) * 0.14), b1 = b0 + max(1, rd(D(L) * 0.08))
        for y in 0..<Y {
            let layer = towels ? y / 2 : y
            let c = layer % 2 == 0 ? cloth : shade(cloth, 0.9)
            for u in 0..<L {
                for w in 0..<W {
                    // folded edges are rounded: the stack's long sides lose their corners on each fold
                    let side = w == 0 || w == W - 1
                    if side && (u == 0 || u == L - 1) { continue }
                    if y == Y - 1 && side && W >= 4 && (layer % 2 == 1 || u == 0 || u == L - 1) { continue }
                    let onBand = !towels && u >= b0 && u < b1
                    put(a, u, y, w, onBand ? (y % 2 == 0 ? band : shade(band, 0.92)) : c)
                }
            }
        }
    }

    // MARK: unknown

    /// An unnamed thing: a block under a pale dust sheet, rounded on top, the cloth hanging in
    /// folds down the sides and pooling at the floor. Deliberately neutral, so a scan's "other"
    /// doesn't read as a wrongly drawn piece.
    func drapedObject(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let cloth = colorFromName(name, 0xD8D3C9)
        let fold = shade(cloth, 0.86), lit = shade(cloth, 1.04)
        let hangTop = max(1, Y - 2)
        for z in 0..<Z {
            for x in 0..<X {
                let ex = min(x, X - 1 - x), ez = min(z, Z - 1 - z), e = min(ex, ez)
                let corner = ex == 0 && ez == 0
                // a few irregular folds stand out of the sheet's sides, each hanging from a seeded height
                let p = ex == 0 ? z + (x == 0 ? 0 : 101) : x + (z == 0 ? 211 : 307)
                let out = hash3(p, 5, 3, seed) < 0.3
                let foldTop = max(1, hangTop - 1 - Int(hash3(p, 6, 1, seed) * D(max(1, Y / 2))))
                for y in 0..<Y {
                    if corner && y >= 1 { continue } // rounded corners
                    if e == 0 {
                        // outer skin: the hem pools at the floor, a fold stands out here and there
                        if y == 0 { if out || hash3(p, 0, 2, seed) < 0.55 { set(x, y, z, fold) }; continue }
                        if out && y < foldTop { set(x, y, z, cloth) }
                        continue
                    }
                    if e == 1 && y == Y - 1 && X >= 5 && Z >= 5 { continue } // rounded top edge
                    let c = y == Y - 1 ? (hash3(x >> 1, 9, z >> 1, seed) < 0.18 ? fold : lit) : e == 1 ? fold : cloth
                    set(x, y, z, c)
                }
            }
        }
    }
}
