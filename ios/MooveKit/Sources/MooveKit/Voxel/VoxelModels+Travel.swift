import Foundation

// OWNER: voxel-models agent. Moove pieces in the house style (palette, jitter, front at +z):
// bikes (side profile along x, centered in z) and luggage (hard-shell / soft-side uprights,
// lying duffels).

extension Canvas {
    // MARK: bike

    /// Bicycle seen side-on along x: two spoked wheels sized from the height, a diamond frame
    /// in the name's color (a saturated paint otherwise), seat post + saddle, stem + handlebar
    /// spanning z, chainring and chain on the +z (drive) side. Variants: kids / BMX (smaller
    /// wheels), e-bike (battery on the down tube, hub motor), cruiser (swept bars), road (drops).
    func bike(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let kids = name.has("kid", "child", "bmx", "balance bike")
        let electric = name.has("e-bike", "ebike", "electric")
        let cruiser = name.has("cruiser", "beach")
        let road = !cruiser && (name.word("road", "racing", "racer", "gravel") || name.has("drop bar"))
        let paints = [0xC23B2E, 0x2D6CC0, 0x1E9C8A, 0xE0782A, 0x7A3FB0]
        let frameC = colorFromName(name, paints[Int(seed % UInt32(paints.count))])
        let tire = 0x1E1E1F, rimC = P.metal, spokeC = 0xB9BCBF, black = P.black
        let chainC = 0x4A4845, ringC = 0x5A5E62

        let top = D(Y - 1)
        let zc = Z / 2
        let tw = Z >= 14 ? 2 : 1 // tire width in z
        let tz0 = zc - (tw - 1)
        let big = Y >= 30 // thicker tubes on large grids

        // wheel radius from the height, capped so both wheels fit along x with a gap
        var R = D(Y) * (kids ? 0.26 : 0.34)
        R = min(R, (D(X) - 1) / (kids ? 4.6 : 4.2))
        R = max(2.5, R)
        let cy = R - 0.5
        let rx = R - 0.5, fx = D(X) - 0.5 - R
        let wb = fx - rx

        func wheel(_ cx: Double, motor: Bool) {
            let spokes = R >= 5 ? 8 : 4
            for y in thru(max(0, fl(cy - R)), min(Y - 1, ce(cy + R))) {
                for x in thru(max(0, fl(cx - R)), min(X - 1, ce(cx + R))) {
                    let dx = D(x) - cx, dy = D(y) - cy
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d > R { continue }
                    var c: Int?
                    if d > R - 1.05 {
                        c = tire
                    } else if R >= 4 && d > R - 2 {
                        c = rimC
                    } else if d < (motor ? 1.6 : 0.75) {
                        c = motor ? P.charcoal : ringC
                    } else {
                        // distance from the nearest spoke ray
                        let a = atan2(dy, dx) * D(spokes) / (2 * Double.pi)
                        let off = abs(a - a.rounded()) * 2 * Double.pi / D(spokes) * d
                        if off < 0.45 { c = spokeC }
                    }
                    guard let c else { continue }
                    for z in upTo(tz0, tz0 + tw) { set(x, y, z, c) }
                    if c == P.charcoal || c == ringC { set(x, y, tz0 - 1, c); set(x, y, tz0 + tw, c) } // hub
                }
            }
        }
        wheel(rx, motor: electric)
        wheel(fx, motor: false)

        // frame points (x, y)
        let bb = (x: rx + wb * 0.45, y: max(1, cy - R * 0.1))
        let seatTop = (x: bb.x - wb * 0.12, y: min(top - 2, cy + R * 1.15))
        let headTop = (x: fx - wb * 0.22, y: min(top - 2, cy + R * 1.1))
        let headBot = (x: fx - wb * 0.15, y: min(headTop.y - 1, cy + R * 0.5))
        func tube(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ c: Int) {
            line(a.x, a.y, D(zc), b.x, b.y, D(zc), c)
            if big { line(a.x, a.y + 1, D(zc), b.x, b.y + 1, D(zc), c) }
        }
        let rearHub = (x: rx, y: cy), frontHub = (x: fx, y: cy)
        tube(seatTop, headTop, frameC) // top tube
        tube(bb, headBot, frameC) // down tube
        tube(bb, seatTop, frameC) // seat tube
        tube(bb, rearHub, shade(frameC, 0.9)) // chainstay
        tube(seatTop, rearHub, shade(frameC, 0.9)) // seat stay
        tube(headBot, headTop, shade(frameC, 1.08)) // head tube
        tube(headBot, frontHub, shade(frameC, 0.92)) // fork

        // seat post + saddle (kids sit relatively higher above their small wheels)
        let saddleY = min(Y - 2, rd(seatTop.y + max(1, R * (kids ? 0.9 : 0.6))))
        line(seatTop.x, seatTop.y, D(zc), seatTop.x - 0.3, D(saddleY - 1), D(zc), rimC)
        let sl = max(1, rd(R * 0.3)), sw = Z >= 8 ? 1 : 0, sx = rd(seatTop.x - 0.3)
        box(sx - sl, saddleY, zc - sw, sx + sl + 1, saddleY + 1, zc + sw + 1, black)

        // stem + handlebar spanning z
        let rise = cruiser ? max(2, rd(R * 0.5)) : max(1, rd(R * 0.3))
        let barY = min(Y - 1, rd(headTop.y) + rise + rd(R * 0.4))
        let hx = rd(headTop.x - (cruiser ? 0.6 : 0.3))
        line(headTop.x, headTop.y, D(zc), D(hx), D(barY), D(zc), rimC)
        let hwMax = max(0, min(zc, Z - 1 - zc))
        let hw = clamp(rd(D(Z) * 0.4), min(1, hwMax), min(hwMax, 8))
        let barC = road ? black : P.charcoal
        let sweep = max(2, rd(R * 0.5))
        for k in thru(-hw, hw) {
            let z = zc + k
            let t = hw == 0 ? 0 : D(abs(k)) / D(hw)
            let x = cruiser ? hx - rd(D(sweep) * t * t) : hx
            let grip = hw >= 2 && abs(k) >= hw - (hw >= 5 ? 1 : 0)
            set(x, barY, z, grip && !road ? black : barC)
            if cruiser && k != 0 && hw >= 2 { // keep the swept bar continuous
                let xp = hx - rd(D(sweep) * pow(D(abs(k) - 1) / D(hw), 2))
                for xi in thru(min(x, xp), max(x, xp)) { set(xi, barY, z, barC) }
            }
        }
        if road && hw >= 1 {
            // drops: forward, down, and back toward the rider at each end
            let drop = max(2, rd(R * 0.35))
            for z in [zc - hw, zc + hw] {
                set(hx + 1, barY, z, black)
                for y in thru(barY - drop + 1, barY) { set(hx + 1, y, z, black) }
                set(hx, barY - drop, z, black)
                set(hx + 1, barY + 1, z, P.charcoal) // brake hood
            }
        }

        // chainring, cranks, pedals and chain on the drive side (+z)
        let zr = min(Z - 1, zc + 1)
        let cr = max(1.2, R * 0.32)
        for y in thru(max(0, fl(bb.y - cr)), min(Y - 1, ce(bb.y + cr))) {
            for x in thru(max(0, fl(bb.x - cr)), min(X - 1, ce(bb.x + cr))) {
                let d = ((D(x) - bb.x) * (D(x) - bb.x) + (D(y) - bb.y) * (D(y) - bb.y)).squareRoot()
                if d <= cr && (d > cr - 1 || d < 0.6) { set(x, y, zr, ringC) }
            }
        }
        let crank = max(1.5, cr * 0.9)
        let p1 = (x: bb.x + crank * 0.6, y: max(0, bb.y - crank)), p2 = (x: bb.x - crank * 0.6, y: min(top, bb.y + crank))
        line(bb.x, bb.y, D(zr), p1.x, p1.y, D(zr), P.charcoal)
        line(bb.x, bb.y, D(zc - 1), p2.x, p2.y, D(zc - 1), P.charcoal)
        set(rd(p1.x), rd(p1.y), zr + 1, black) // pedals
        set(rd(p2.x), rd(p2.y), zc - 2, black)
        let cog = max(1, R * 0.15)
        line(bb.x, bb.y + cr, D(zr), rx, cy + cog, D(zr), chainC)
        line(bb.x, bb.y - cr, D(zr), rx, cy - cog, D(zr), chainC)
        set(rd(rx), rd(cy), zr, ringC) // rear cog

        if electric {
            // battery pack riding on top of the down tube, with a charge LED
            let dx = headBot.x - bb.x, dy = headBot.y - bb.y
            let len = max(1, (dx * dx + dy * dy).squareRoot())
            let nxv = -dy / len, nyv = dx / len
            let thick = max(1, rd(R * 0.22)), bw = Z >= 6 ? 1 : 0
            let steps = max(2, rd(len * 1.5))
            for i in 0...steps {
                let t = 0.22 + 0.55 * D(i) / D(steps)
                let px = bb.x + dx * t, py = bb.y + dy * t
                for o in 1...thick {
                    let bx = rd(px + nxv * D(o)), by = rd(py + nyv * D(o))
                    for z in thru(zc - bw, zc + bw) { set(bx, by, z, i == steps / 2 && o == thick ? 0x5FD07A : 0x2E3033) }
                }
            }
        }
    }

    // MARK: luggage

    /// Upright suitcase: hard shell with vertical ribs (dark gray / navy unless the name says a
    /// color) or soft-side fabric with a front pocket; corner wheels, a telescoping handle up the
    /// back, a carry handle on the +x side and a zipper seam around the middle in z.
    /// "duffel" builds a lying rounded bag instead.
    func suitcase(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("duffel", "duffle", "holdall", "weekender", "gym bag") { duffel(X, Y, Z, name); return }
        let soft = name.has("soft", "fabric", "nylon", "canvas", "polyester", "cloth")
        let defaults = soft ? [0x2B2A28, 0x3F5A73] : [0x3A3D42, 0x2C3E58]
        let body = colorFromName(name, defaults[Int(seed % 2)])
        let seamC = soft ? 0x1E1E1F : shade(body, 0.6)
        let wheelC = 0x1E1E1F, metalC = P.metal

        let handleH = clamp(rd(D(Y) * 0.14), 1, 6)
        let yb0 = 1, yb1 = max(yb0 + 2, Y - handleH) // body layers [yb0, yb1)
        let bx1 = max(2, X - 1) // body [0, bx1); the side handle sits at x = X - 1
        let zm = Z / 2
        let sp = bx1 >= 10 ? 3 : 2
        let lightC = shade(body, 1.14), darkC = shade(body, 0.86), topC = shade(body, 1.05), pipeC = shade(body, 0.78)
        let pocket = soft && Z >= 4 && bx1 >= 4
        let py1 = yb0 + max(2, rd(D(yb1 - yb0) * 0.62))
        box(0, yb0, 0, bx1, yb1, Z) { x, y, z in
            let rim = x == 0 || x == bx1 - 1 || y == yb0 || y == yb1 - 1
            if z == zm && rim { return seamC } // zipper / shell seam
            let face = z == 0 || z == Z - 1
            if soft {
                // the front pocket bulges out; the rest of the front sits one voxel back
                let inPocket = x >= 1 && x <= bx1 - 2 && y >= yb0 + 1 && y <= py1
                if pocket && z == Z - 1 && !inPocket { return -1 }
                if pocket && z == Z - 2 && !inPocket && (x == 0 || x == bx1 - 1 || y == yb1 - 1) { return pipeC }
                if face && (x == 0 || x == bx1 - 1 || y == yb1 - 1) { return pipeC }
                if pocket && z == Z - 1 && x >= 1 && x <= bx1 - 2 && y >= yb0 + 1 && y <= py1 {
                    return x == 1 || x == bx1 - 2 || y == yb0 + 1 || y == py1 ? seamC : shade(body, 0.95)
                }
            } else if face && !rim && y < yb1 - 2 && y > yb0 {
                let k = (x - 1) % sp
                if k == 0 { return lightC }
                if k == 1 && sp == 3 { return darkC }
            }
            return y == yb1 - 1 ? topC : body
        }
        // rounded top corners on larger cases
        if bx1 >= 6 && yb1 - yb0 >= 8 { for z in upTo(0, Z) { clear(0, yb1 - 1, z); clear(bx1 - 1, yb1 - 1, z) } }
        if soft && pocket { set(bx1 - 2, py1, Z - 1, metalC) } // pocket zipper pull
        set(bx1 - 1, rd(D(yb0 + yb1) * 0.6), zm, metalC) // main zipper pull

        // wheels: four spinners (hard) or two at the back plus feet (soft)
        let ws = X >= 10 && Z >= 6 ? 2 : 1
        for (cx, cz) in [(0, 0), (bx1 - ws, 0), (0, Z - ws), (bx1 - ws, Z - ws)] {
            let front = cz > 0
            box(cx, 0, cz, cx + ws, 1, cz + ws, soft && front ? 0x5A5E62 : wheelC)
        }

        // telescoping handle up the back: channels on the back face, posts and a grip on top
        let hz = Z >= 5 ? 1 : 0
        let xa = max(0, bx1 / 4), xb = max(xa + 1, bx1 - 1 - bx1 / 4)
        for x in [xa, xb] {
            for y in upTo(yb0 + 1, yb1 - 1) { set(x, y, 0, shade(body, 0.72)) }
            box(x, yb1 - 1, hz, x + 1, Y - 1, hz + 1, metalC)
        }
        box(xa, Y - 1, hz, xb + 1, Y, hz + 1, wheelC)
        // top carry handle in the middle
        if handleH >= 2 && Z >= 4 && bx1 >= 5 {
            let c = bx1 / 2
            box(c - 1, yb1, zm, c + 2, yb1 + 1, zm + 1, wheelC)
        }
        // side carry handle on +x, with a luggage tag on some
        let ym = (yb0 + yb1) / 2
        let hl = max(0, min(rd(D(Z) * 0.25), zm, Z - 1 - zm))
        box(X - 1, ym, zm - hl, X, ym + 1, zm + hl + 1, wheelC)
        if rand() < 0.5 && ym - 1 > yb0 {
            let tags = [P.mustard, P.rust, P.sage, P.blush]
            set(X - 1, ym - 1, zm, tags[min(tags.count - 1, fl(rand() * D(tags.count)))])
        }
    }

    /// Duffel bag lying along x: rounded-square cross-section with a flattened bottom, darker end
    /// panels, webbing bands carrying two handles that arch over the top, a zipper down the top.
    func duffel(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let defaults = [0x4E5B3A, 0x2C3E58]
        let body = colorFromName(name, defaults[Int(seed % 2)])
        let endC = shade(body, 0.8), bandC = shade(body, 0.6), strapC = 0x2B2A28
        let hh = clamp(rd(D(Y) * 0.18), 1, 5)
        let H = max(2, Y - hh)
        let zm = Z / 2
        let xa = clamp(rd(D(X) * 0.3), 1, max(1, X - 2)), xb = max(xa, X - 1 - xa)
        var colTop = Array(repeating: -1, count: Z)
        for y in upTo(0, H) {
            let ny0 = (D(y) + 0.5 - D(H) / 2) / (D(H) / 2)
            let ny = ny0 < 0 ? ny0 * 0.8 : ny0 // fuller, flatter bottom
            for z in upTo(0, Z) {
                let nz = (D(z) + 0.5 - D(Z) / 2) / (D(Z) / 2)
                let e = pow(abs(ny), 2.2) + pow(abs(nz), 2.2)
                for x in upTo(0, X) {
                    let end = x == 0 || x == X - 1
                    if e > (end ? 0.75 : 1) { continue }
                    if !end { colTop[z] = max(colTop[z], y) }
                    set(x, y, z, end ? endC : (x == xa || x == xb) ? bandC : y == 0 ? shade(body, 0.85) : body)
                }
            }
        }
        // zipper down the top
        if colTop[zm] >= 0 {
            for x in upTo(1, X - 1) where x != xa && x != xb { set(x, colTop[zm], zm, strapC) }
            set(min(X - 2, rd(D(X) * 0.7)), colTop[zm], zm, P.metal)
        }
        // handles arching over the top
        let s = max(0, min(rd(D(Z) * 0.2), zm, Z - 1 - zm))
        for x in [xa, xb] {
            for z in [zm - s, zm + s] where colTop[z] >= 0 {
                for y in upTo(colTop[z] + 1, Y - 1) { set(x, y, z, strapC) }
            }
            box(x, Y - 1, zm - s, x + 1, Y, zm + s + 1, strapC)
        }
    }
}
