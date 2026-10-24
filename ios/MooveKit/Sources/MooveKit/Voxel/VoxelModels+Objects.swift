import Foundation

// OWNER: voxel-models agent. Small objects, ported from models.js (buildBooks, buildArt,
// buildPhotos, buildBinder, buildKitchenware, buildPlant, buildRug, buildClothes,
// buildElectronics, buildDecor, buildBox).

/// Painted landscape for art canvases. u: 0..1 left to right, v: 0..1 bottom to top.
func landscape(_ u: Double, _ v: Double) -> Int {
    let sun = (u - 0.72) * (u - 0.72) + ((v - 0.78) * 1.2) * ((v - 0.78) * 1.2) < 0.012
    let far = 0.52 + 0.11 * sin(u * 6.5 + 1.2) + 0.05 * sin(u * 15)
    let near = 0.36 + 0.06 * sin(u * 9 + 3)
    let lake = v < 0.2 && v > 0.1 && u > 0.25 && u < 0.85
    if v > far {
        if sun { return 0xF2C46D }
        return mix(0xEFDCBC, 0x9FBFD6, clampD((v - far) / (1 - far) * 1.3, 0, 1))
    }
    if v > near { return v > far - 0.05 ? 0xB4C0C8 : 0x8FA3B0 }
    if lake { return 0x8FB3C9 }
    if v > near - 0.05 { return 0x9AAB83 }
    return v < 0.08 ? 0x5F7457 : 0x7D9468
}

extension Canvas {
    func books(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.word("box", "crate", "carton") {
            let kraft = P.kraft
            let H = max(2, Y - 1)
            let rim = shade(kraft, 1.05)
            box(0, 0, 0, X, H, Z) { x, y, z in
                let wall = x == 0 || x == X - 1 || z == 0 || z == Z - 1 || y == 0
                if !wall { return -1 }
                if (z == Z - 1 || z == 0) && x == X / 2 && y > H - 3 { return 0xD9C7A4 } // tape
                return y == H - 1 ? rim : kraft
            }
            // open flaps standing up on the long sides
            box(0, H, 0, X, Y, 1, shade(kraft, 0.92))
            box(0, H, Z - 1, X, Y, Z, shade(kraft, 0.92))
            // books standing inside, tops visible
            for z in upTo(1, Z - 1) {
                for x in upTo(1, X - 1) {
                    let col = bookColors[((x / 2) * 7 + z * 3 + Int(seed & 7)) % bookColors.count]
                    let top = H - 1 - (hash3(x >> 1, 0, z, seed) < 0.3 ? 1 : 0)
                    box(x, 1, z, x + 1, max(2, top + (x % 3 == 0 ? 1 : 0)), z + 1, z % 3 == 0 ? 0xF1EBDD : col)
                }
            }
            return
        }
        // stack of books
        var y = 0
        while y < Y {
            let th = rand() < 0.3 ? 2 : 1
            let bw = clamp(rd(D(X) * (0.7 + rand() * 0.3)), 1, X)
            let bd = clamp(rd(D(Z) * (0.7 + rand() * 0.3)), 1, Z)
            let ox = fl(rand() * D(X - bw + 1)), oz = fl(rand() * D(Z - bd + 1))
            let c = bookColors[min(bookColors.count - 1, fl(rand() * D(bookColors.count)))]
            box(ox, y, oz, ox + bw, y + th, oz + bd) { x, _, z in
                x == ox + bw - 1 || z == oz + bd - 1 || x == ox || z == oz ? c : 0xF1EBDD
            }
            box(ox, y, oz, ox + 1, y + th, oz + bd, c)
            y += th
        }
    }

    func art(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, wall: Bool) {
        let frameC = name.word("black") ? P.black : name.word("white") ? P.white : name.has("gold", "gilt") ? P.brass : P.walnut
        let t = min(Z, 2)
        let zf = t - 1 // front layer
        let mat = X >= 10 && Y >= 10 ? 1 : 0
        let frameDark = shade(frameC, 0.9)
        let iw = D(X - 2 - 2 * mat), ih = D(Y - 2 - 2 * mat)
        box(0, 0, 0, X, Y, t) { x, y, z in
            let frame = x == 0 || x == X - 1 || y == 0 || y == Y - 1
            if frame { return (x + y) % 3 == 0 ? frameDark : frameC }
            if z != zf { return P.kraft }
            if mat == 1 && (x == 1 || x == X - 2 || y == 1 || y == Y - 2) { return 0xF4EFE4 }
            return landscape((D(x - 1 - mat) + 0.5) / iw, (D(y - 1 - mat) + 0.5) / ih)
        }
        // if there's depth to spare, add a small easel-ish leg so it stands
        if Z >= 4 && !wall {
            box(X / 2, 0, t, X / 2 + 1, 1, Z, P.walnut)
            line(X / 2, rd(D(Y) * 0.6), t - 1, X / 2, 0, Z - 1, P.walnut)
        }
    }

    func photos(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let bodyC = 0xC96F4E // terracotta shoebox
        let lidC = 0xEFE7D6
        let H = max(1, Y - 1)
        let rim = shade(bodyC, 1.1)
        // open box body (hollow)
        box(0, 0, 0, X, H, Z) { x, y, z in
            let wall = x == 0 || x == X - 1 || z == 0 || z == Z - 1 || y == 0
            if !wall { return -1 }
            return z == Z - 1 && y == H - 1 && x > 0 && x < X - 1 ? rim : bodyC
        }
        // photos standing inside, with white borders, poking above the rim
        let pc = [0x8FB3C9, 0xD9A5A0, 0x9AAB83, 0xC9A25A, 0x7E95A8]
        for x in upTo(1, X - 1) {
            for z in upTo(1, Z - 1) {
                let top = H + (hash3(x, 1, z, seed) < 0.5 ? 1 : 0)
                box(x, 1, z, x + 1, min(Y, top), z + 1, (z + x) % 2 == 1 ? 0xF4F1EA : pc[(x * 3 + z) % pc.count])
            }
        }
        // lid ajar: shifted back and to the right, covering the back part
        let lz1 = max(1, ce(D(Z) * 0.55))
        let seam = shade(bodyC, 0.95)
        box(min(1, X - 1), Y - 1, 0, X, Y, lz1) { x, _, _ in x == X / 2 ? seam : lidC }
        if Y >= 2 { box(X - 1, Y - 2, 0, X, Y - 1, lz1, lidC) }
        // a loose photo on the side
        if X >= 6 && Z >= 3 {
            set(1, Y - 1, Z - 1, 0xF4F1EA)
            set(2, Y - 1, Z - 1, 0x8FB3C9)
        }
    }

    func binder(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let red = name.word("red")
        let cover = red ? 0xB8382D : 0x2F5D9A
        let spine = red ? 0x2F5D9A : 0xB8382D
        let ring = 0xC8CCD0
        // Poke Ball emblem (5x5 pixel art scaled into a square on the front cover, +z)
        let ball: [[UInt8]] = [".RRR.", "RRRRR", "KKWKK", "WWWWW", ".WWW."].map { Array($0.utf8) }
        let side = max(3, min(X - 1, Y))
        let bx0 = 1 + fdiv(X - 1 - side, 2), by0 = fdiv(Y - side, 2)
        func ballAt(_ x: Int, _ y: Int) -> Int? {
            let u = fl(D(x - bx0) / D(side) * 5), v = 4 - fl(D(y - by0) / D(side) * 5)
            if u < 0 || u > 4 || v < 0 || v > 4 { return nil }
            switch ball[v][u] {
            case UInt8(ascii: "R"): return 0xE8463A
            case UInt8(ascii: "W"): return 0xF4F1EA
            case UInt8(ascii: "K"): return 0x1C1C1E
            default: return nil
            }
        }
        let rings = [rd(D(Y) * 0.25), rd(D(Y) * 0.5), rd(D(Y) * 0.75)]
        box(0, 0, 0, X, Y, Z) { x, y, z in
            if x == 0 { return rings.contains(y) ? ring : spine }
            if z > 0 && z < Z - 1 && (x == X - 1 || y == 0 || y == Y - 1) { return 0xF4F1EA } // pages
            if z == Z - 1 || Z == 1, let b = ballAt(x, y) { return b }
            return cover
        }
    }

    func kitchenware(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let w = P.birch
        let cw = X >= 8 ? X - 2 : X // crate width (leave room for a handle)
        let H = max(2, Y - 2)
        let bottom = shade(w, 0.85), cornerC = shade(w, 0.8), slatDark = shade(w, 0.92)
        // slatted crate
        box(0, 0, 0, cw, H, Z) { x, y, z in
            let corner = (x == 0 || x == cw - 1) && (z == 0 || z == Z - 1)
            let wall = x == 0 || x == cw - 1 || z == 0 || z == Z - 1
            if y == 0 { return bottom }
            if corner { return cornerC }
            if !wall { return -1 }
            if y % 3 == 2 && y != H - 1 { return -1 } // slat gaps
            return (x + z) % 5 == 0 ? slatDark : w
        }
        // plates stacked on the left
        let pr = max(1, min(D(cw - 2) * 0.22, D(Z - 2) / 2))
        let pcx = 1 + pr - 0.5, pcz = D(Z - 1) / 2
        for y in upTo(1, min(H + 1, Y)) { cyl(pcx, pcz, pr, y, y + 1, y % 2 == 1 ? 0xF1ECE2 : 0xD8D2C6) }
        // pot on the right, rim above the crate, handle sticking out past the crate wall
        let potC = name.has("copper") ? 0xB87333 : 0x5A5E62
        let rr = max(1, min(D(cw - 2) * 0.28, D(Z - 2) / 2))
        let qx = D(cw - 1) - rr - 0.2
        let potTop = min(Y - 1, H + 1)
        cyl(qx, pcz, rr, 1, potTop, potC, hollow: true)
        cyl(qx, pcz, rr, potTop - 1, potTop, shade(potC, 1.2), hollow: true)
        let hy = potTop - 1, hz = rd(pcz)
        box(rd(qx + rr), hy, hz, X, hy + 1, hz + 1, 0x1F1F1F)
        // pan handle angling up at the back + wooden spoon
        line(rd(pcx) + 1, H, 1, rd(pcx) + 2, Y - 1, 0, 0x2A2A2A)
        box(rd(D(cw) / 2), 2, rd(D(Z) / 2), rd(D(cw) / 2) + 1, Y, rd(D(Z) / 2) + 1, P.oak)
    }

    func plant(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let potC = colorFromName(name, P.terracotta)
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        let R = D(min(X, Z)) / 2
        let ph = clamp(rd(D(Y) * 0.3), 2, 10)
        let pr = max(1, R * 0.62)
        for y in upTo(0, ph) {
            let r = pr * (0.82 + 0.18 * (D(y) / D(max(1, ph - 1))))
            cyl(cx, cz, r, y, y + 1, y == 0 ? shade(potC, 0.8) : y % 3 == 1 ? shade(potC, 0.95) : potC)
        }
        cyl(cx, cz, pr + 0.7, ph - 1, ph, shade(potC, 1.08), hollow: true) // rim
        cyl(cx, cz, pr - 0.3, ph - 1, ph, 0x4A3628) // soil
        let top = Y - 1
        // species from the name; monstera (models.js) otherwise
        if name.has("snake", "sansevieria", "zz plant", "aloe") { snakePlant(X, Y, Z, ph, cx, cz, R); return }
        if name.has("cactus", "succulent") { cactus(X, Y, Z, ph, cx, cz, R); return }
        if name.has("fiddle", "ficus", "tree", "olive", "palm", "lemon", "rubber") { pottedTree(X, Y, Z, ph, cx, cz, R, name); return }
        if name.has("pothos", "ivy", "trailing", "hanging", "philodendron", "spider") { trailingPlant(X, Y, Z, ph, cx, cz, R); return }
        let leafs = clamp(rd(D(Y - ph) / 1.8), 4, 13)
        let greens = [0x3E6B3A, 0x4F7F42, 0x5F8F4A, 0x467A3C]
        for i in 0..<leafs {
            let a = D(i) * 2.399 + rand() * 0.5 // golden-angle spread
            let t = (D(i) + 0.5) / D(leafs)
            // lower leaves spread wide, upper leaves stay nearer the center
            let ly = D(ph + 1) + D(top - ph - 2) * (0.15 + 0.85 * t)
            let dist = R * (0.75 - 0.4 * t) * (0.85 + 0.3 * rand())
            let lr = clampD(R * (0.62 - 0.2 * t), 1.6, 5.5)
            let lx = clampD(cx + cos(a) * dist, lr * 0.6, D(X - 1) - lr * 0.6)
            let lz = clampD(cz + sin(a) * dist, lr * 0.6, D(Z - 1) - lr * 0.6)
            let sx = rd(cx) + (i % 2), sz = rd(cz) + ((i >> 1) % 2)
            line(sx, ph - 1, sz, rd(lx), rd(ly), rd(lz), 0x5C7A3E)
            let base = greens[i % greens.count]
            let veinC = shade(base, 1.3), edgeC = shade(base, 1.12)
            // flat, heart-shaped leaf tilted outward (outer edge droops one voxel)
            let ux = cos(a), uz = sin(a)
            for z in thru(fl(lz - lr), ce(lz + lr)) {
                for x in thru(fl(lx - lr), ce(lx + lr)) {
                    let dx = D(x) - lx, dz = D(z) - lz
                    let along = dx * ux + dz * uz, across = -dx * uz + dz * ux
                    let e = (along / lr) * (along / lr) + (across / (lr * 0.8)) * (across / (lr * 0.8))
                    if e > 1 { continue }
                    if along < -lr * 0.55 && abs(across) < lr * 0.25 { continue } // notch at the stem
                    let ang = atan2(across, along)
                    if e > 0.35 && abs(sin(ang * 3.5 + D(i))) < 0.18 { continue } // monstera slits
                    let y = rd(ly - (along > lr * 0.45 ? 1 : 0))
                    let vein = abs(across) < 0.5
                    set(x, y, z, vein ? veinC : e > 0.6 ? edgeC : base)
                }
            }
        }
        // unfurling new leaf at the crown
        box(rd(cx), top - 2, rd(cz), rd(cx) + 1, top + 1, rd(cz) + 1, 0x86AD5E)
    }

    /// Upright sword leaves in two greens with yellow edges.
    func snakePlant(_ X: Int, _ Y: Int, _ Z: Int, _ ph: Int, _ cx: Double, _ cz: Double, _ R: Double) {
        let n = clamp(rd(R * 2.2), 4, 12)
        for i in 0..<n {
            let a = D(i) * 2.399 + rand() * 0.6
            let d = R * 0.35 * rand()
            let lx = rd(cx + cos(a) * d), lz = rd(cz + sin(a) * d)
            let h = ph + rd(D(Y - ph) * (0.55 + 0.45 * rand()))
            for y in upTo(ph, min(Y, h)) {
                let band = (y + i) % 4 == 0
                set(lx, y, lz, band ? 0x8FB26A : (i % 2 == 0 ? 0x3E6B3A : 0x4F7F42))
                if y < h - 2 { set(lx + (i % 2 == 0 ? 1 : 0), y, lz + (i % 2 == 0 ? 0 : 1), 0xC9C46A) }
            }
        }
    }

    /// Columnar cactus with arms (or a cluster of succulent rosettes when short).
    func cactus(_ X: Int, _ Y: Int, _ Z: Int, _ ph: Int, _ cx: Double, _ cz: Double, _ R: Double) {
        let green = 0x5F8F4A, spine = 0xE9E3C8
        if Y - ph < 5 {
            for i in 0..<4 {
                let a = D(i) * Double.pi / 2 + rand()
                ellipsoid(cx + cos(a) * R * 0.3, D(ph) + 0.5, cz + sin(a) * R * 0.3, max(1, R * 0.35), 1.2, max(1, R * 0.35)) { x, y, z, _ in (x + z + y) % 3 == 0 ? 0x86AD5E : 0x6E9A57 }
            }
            return
        }
        let r = max(1, R * 0.35)
        cyl(cx, cz, r, ph, Y - 1) { x, y, z, _ in (x + y + z) % 5 == 0 ? spine : green }
        cyl(cx, cz, max(0.8, r - 0.6), Y - 1, Y, green)
        // arms
        let ay = ph + rd(D(Y - ph) * 0.4)
        for (dx, h) in [(-1.0, 0.75), (1.0, 0.6)] {
            let ax = cx + dx * (r + 1.2)
            box(rd(cx + dx * r), ay, rd(cz), rd(ax) + (dx > 0 ? 1 : 0), ay + 1, rd(cz) + 1, green)
            box(rd(ax), ay, rd(cz), rd(ax) + 1, ay + rd(D(Y - ay) * h), rd(cz) + 1, green)
        }
    }

    /// Indoor tree: a trunk with a few leafy canopy clusters.
    func pottedTree(_ X: Int, _ Y: Int, _ Z: Int, _ ph: Int, _ cx: Double, _ cz: Double, _ R: Double, _ name: VName) {
        let trunk = 0x6E4A33
        let fiddle = name.has("fiddle", "rubber")
        let leaf = name.has("olive") ? 0x8B9A7B : 0x4F7F42
        let trunkTop = ph + rd(D(Y - ph) * 0.45)
        box(rd(cx), ph - 1, rd(cz), rd(cx) + 1, trunkTop + 1, rd(cz) + 1, trunk)
        let clusters = clamp(rd(D(Y - ph) / 5), 3, 7)
        for i in 0..<clusters {
            let a = D(i) * 2.399 + rand() * 0.4
            let t = D(i) / D(max(1, clusters - 1))
            let ccy = D(trunkTop) + D(Y - 1 - trunkTop) * t * 0.85
            let d = R * 0.45 * (1 - t * 0.5)
            let ccx = clampD(cx + cos(a) * d, 1, D(X - 2)), ccz = clampD(cz + sin(a) * d, 1, D(Z - 2))
            line(cx, D(trunkTop), cz, ccx, ccy, ccz, trunk)
            let rr = fiddle ? max(1.2, R * 0.38) : max(1.2, R * 0.45)
            let hi = shade(leaf, 1.15)
            ellipsoid(ccx, ccy, ccz, rr, max(1, rr * 0.7), rr) { x, y, z, d in
                if hash3(x, y, z, self.seed) < (fiddle ? 0.1 : 0.25) { return nil } // airy foliage
                return d > 0.6 || y > rd(ccy) ? hi : leaf
            }
        }
    }

    /// A bushy mound with vines trailing over the pot rim.
    func trailingPlant(_ X: Int, _ Y: Int, _ Z: Int, _ ph: Int, _ cx: Double, _ cz: Double, _ R: Double) {
        let leaf = 0x5F8F4A, light = 0x86AD5E
        ellipsoid(cx, D(ph), cz, max(1, R * 0.75), max(1, D(min(Y - ph, 4))), max(1, R * 0.75)) { x, y, z, _ in
            hash3(x, y, z, self.seed) < 0.2 ? nil : ((x + y * 2 + z) % 4 == 0 ? light : leaf)
        }
        let vines = clamp(rd(R * 1.5), 3, 8)
        for i in 0..<vines {
            let a = D(i) * 2 * Double.pi / D(vines) + rand() * 0.4
            let vx = rd(cx + cos(a) * (R - 0.4)), vz = rd(cz + sin(a) * (R - 0.4))
            let len = 2 + fl(rand() * D(max(1, ph)))
            for k in 0..<len { set(vx, ph - k, vz, k % 2 == 0 ? leaf : light) }
        }
    }

    func rug(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("round", "circle", "circular") { roundRug(X, Z, name); return }
        if name.has("stripe", "striped", "runner", "dhurrie") || name.has("shag", "solid", "plain", "jute", "sisal")
            || name.has("geometric", "moroccan", "diamond", "trellis", "kilim", "berber") {
            patternRug(X, Z, name)
            return
        }
        let field = colorFromName(name, 0xD8C7A8)
        let border = name.word("blue", "navy") ? 0x2F4A63 : 0x9C5236
        let accent = 0x3F5A73
        let longX = X >= Z
        let fr = X > 8 && Z > 8 ? 1 : 0 // fringe rows on the short ends
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        let motif = shade(field, 0.85)
        box(0, 0, 0, X, 1, Z) { x, _, z in
            let along = longX ? x : z, L = longX ? X : Z
            if fr == 1 && (along == 0 || along == L - 1) { return (longX ? z : x) % 2 == 0 ? 0xEFE7D6 : nil }
            let ex = min(x - (longX ? fr : 0), X - 1 - x - (longX ? fr : 0))
            let ez = min(z - (longX ? 0 : fr), Z - 1 - z - (longX ? 0 : fr))
            let e = min(ex, ez)
            if e < 1 { return border }
            if e == 1 { return 0xEFE7D6 }
            if e == 2 { return (x + z) % 4 < 2 ? accent : border } // patterned band
            if e == 3 { return 0xEFE7D6 }
            // center medallion (diamond)
            let dd = abs(D(x) - cx) / (D(X) * 0.22) + abs(D(z) - cz) / (D(Z) * 0.22)
            if dd < 0.35 { return border }
            if dd < 0.55 { return accent }
            if dd < 0.62 { return 0xEFE7D6 }
            // scattered motifs
            if (x * 7 + z * 13) % 23 == 0 { return motif }
            return field
        }
    }

    /// Striped / solid (shag, jute) / lattice rugs, chosen by the name.
    func patternRug(_ X: Int, _ Z: Int, _ name: VName) {
        let jute = name.has("jute", "sisal", "seagrass")
        let field = colorFromName(name, jute ? 0xC9A875 : 0xD8C7A8)
        let accent = name.word("blue", "navy") ? 0x2F4A63 : field == 0xD8C7A8 ? 0x9C5236 : shade(field, 0.7)
        let cream = 0xEFE7D6
        let longX = X >= Z
        let stripes = name.has("stripe", "striped", "runner", "dhurrie")
        let solid = name.has("shag", "solid", "plain", "jute", "sisal")
        let lo = shade(field, 0.9), hi = shade(field, 1.06)
        box(0, 0, 0, X, 1, Z) { x, _, z in
            let along = longX ? x : z, across = longX ? z : x
            let L = longX ? X : Z
            if (along == 0 || along == L - 1) && L > 8 { return across % 2 == 0 ? cream : nil } // fringe
            if solid {
                if jute { return (x + z) % 3 == 0 ? lo : (x * 3 + z) % 7 == 0 ? hi : field } // weave
                return hash3(x, 0, z, self.seed) < 0.3 ? hi : hash3(x, 1, z, self.seed) < 0.2 ? lo : field // shag pile
            }
            if stripes {
                let k = (along / 3) % 4
                return k == 0 ? accent : k == 2 ? cream : field
            }
            // lattice (moroccan trellis / diamonds)
            let u = (x + z) % 6, v = (x - z + 600) % 6
            return u == 0 || v == 0 ? accent : field
        }
    }

    func roundRug(_ X: Int, _ Z: Int, _ name: VName) {
        let field = colorFromName(name, 0xD8C7A8)
        let accent = name.word("blue", "navy") ? 0x2F4A63 : 0x9C5236
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, r = D(min(X, Z)) / 2
        cyl(cx, cz, r, 0, 1) { _, _, _, d2 in
            let d = d2.squareRoot()
            if d > r - 1 { return accent }
            if Int(d) % 4 == 2 { return 0xEFE7D6 }
            return Int(d) % 8 < 4 ? field : shade(field, 0.9)
        }
    }

    func clothes(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let cols = [0x5B7896, 0xE9DFCB, 0x8B9A7B, 0x34322F, 0xD9A5A0, 0xB9764F, 0x9A9690]
        if name.has("basket", "hamper") {
            let H = max(2, Y - 1)
            box(0, 0, 0, X, H, Z) { x, y, z in
                let wall = x == 0 || x == X - 1 || z == 0 || z == Z - 1 || y == 0
                if !wall { return -1 }
                return (x + y + z) % 2 == 1 ? 0xC9A875 : 0xA88552 // woven
            }
            for z in upTo(1, Z - 1) {
                for x in upTo(1, X - 1) {
                    box(x, 1, z, x + 1, H + (hash3(x, 0, z, seed) < 0.4 ? 1 : 0), z + 1, cols[((x >> 1) + (z >> 1) * 3) % cols.count])
                }
            }
            return
        }
        var y = 0
        var k = fl(rand() * D(cols.count))
        while y < Y {
            let th = Y - y >= 2 && rand() < 0.5 ? 2 : 1
            let bw = clamp(rd(D(X) * (0.8 + rand() * 0.2)), 1, X)
            let bd = clamp(rd(D(Z) * (0.8 + rand() * 0.2)), 1, Z)
            let ox = fl(rand() * D(X - bw + 1)), oz = fl(rand() * D(Z - bd + 1))
            let c = cols[k % cols.count]
            k += 1
            let fold = shade(c, 0.85), y0 = y
            box(ox, y, oz, ox + bw, y + th, oz + bd) { _, yy, z in z == oz + bd / 2 && yy == y0 + th - 1 ? fold : c }
            y += th
        }
    }

    func electronics(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let dark = 0x2A2A2C
        if name.has("laptop", "notebook", "macbook") {
            box(0, 0, 0, X, 1, Z, 0xB8BCC0)
            box(1, 0, 1, X - 1, 1, Z - 2) { x, _, z in (x + z) % 2 == 1 ? 0x3A3A3C : 0x4A4A4C }
            box(0, 1, 0, X, Y, 1, flat: true) { x, y, _ in x == 0 || x == X - 1 || y == Y - 1 ? 0xB8BCC0 : P.screen }
            return
        }
        if name.has("monitor", "screen", "display") {
            tv(X, Y, Z, name, wall: attr(VoxelModels.wallMountAttribute.lowercased()))
            return
        }
        if name.has("speaker", "subwoofer") {
            box(0, 0, 0, X, Y, Z, dark)
            let cx = D(X - 1) / 2
            for (cy, rr) in [(D(Y) * 0.3, D(min(X, Y)) * 0.3), (D(Y) * 0.75, D(min(X, Y)) * 0.15)] {
                for y in upTo(0, Y) {
                    for x in upTo(0, X) {
                        let d = ((D(x) - cx) * (D(x) - cx) + (D(y) - cy) * (D(y) - cy)).squareRoot()
                        if d < rr { set(x, y, Z - 1, d < rr * 0.4 ? 0x555558 : 0x161618) }
                    }
                }
            }
            return
        }
        // generic device / console: dark box with vents, light strip and LED
        box(0, 0, 0, X, Y, Z) { x, y, z in
            if y == Y - 1 && x % 2 == 0 && z > 0 && z < Z - 1 { return 0x1C1C1E }
            if z == Z - 1 && y == Y / 2 && x > 0 && x < X - 1 { return 0x45454A }
            return dark
        }
        set(X - 2, Y / 2, Z - 1, 0x7FC4E8, flat: true)
        if name.has("console", "playstation", "xbox", "switch", "game") && X >= 6 { box(1, 0, Z - 1, 3, 1, Z, 0xE8E6E1) }
    }

    func decor(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, R = D(min(X, Z)) / 2
        if name.has("candle") {
            cyl(cx, cz, max(1, R * 0.7), 0, max(1, Y - 1), P.cream)
            set(rd(cx), Y - 1, rd(cz), P.bulb, flat: true)
            return
        }
        // vase with dried stems
        let vh = max(2, rd(D(Y) * 0.5))
        let vc = colorFromName(name, P.sage)
        for y in upTo(0, vh) {
            let t = D(y) / D(max(1, vh - 1))
            cyl(cx, cz, max(1, R * (0.55 + 0.25 * sin(t * Double.pi)) - (t > 0.8 ? 0.4 : 0)), y, y + 1, vc)
        }
        for _ in 0..<5 {
            let ex = clampD(cx + (rand() - 0.5) * D(X) * 0.8, 0, D(X - 1))
            let ez = clampD(cz + (rand() - 0.5) * D(Z) * 0.8, 0, D(Z - 1))
            line(D(rd(cx)), D(vh), D(rd(cz)), ex, D(Y - 2), ez, 0x9A8A62)
            ellipsoid(ex, D(Y) - 1.5, ez, 1, 1, 1, 0xE3D3B0)
        }
    }

    /// Fallback: a taped kraft moving box with a shipping label on the front.
    func kraftBox(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let kraft = P.kraft
        let tape = 0xD9C7A4
        let tx0 = X / 2 - (X >= 8 ? 1 : 0), tx1 = X / 2 + 1
        let top = shade(kraft, 1.05), flapSeam = shade(kraft, 0.82), edge = shade(kraft, 0.85), sideC = shade(kraft, 0.95)
        let tapeDown = Y - max(2, rd(D(Y) * 0.3))
        box(0, 0, 0, X, Y, Z) { x, y, z in
            let onTape = x >= tx0 && x < tx1
            if y == Y - 1 {
                if onTape { return tape }
                if z == Z / 2 && Z >= 4 { return flapSeam } // flap seam
                return top
            }
            if onTape && (z == 0 || z == Z - 1) && y >= tapeDown { return tape }
            if x == 0 || x == X - 1 { return z == 0 || z == Z - 1 ? edge : sideC }
            return kraft
        }
        // shipping label on the front
        if X >= 6 && Y >= 5 {
            let lx = rd(D(X) * 0.65), ly = rd(D(Y) * 0.45)
            box(lx, ly, Z - 1, min(X - 1, lx + 3), ly + 2, Z) { x, y, _ in y == ly + 1 && x == lx ? 0x3A3835 : 0xF4F1EA }
        }
    }
}
