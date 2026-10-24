import Foundation

// OWNER: voxel-models agent. The detector's last categories that were still drawn as moving
// boxes (scan 9 follow-up): balls, helmets, rackets, weights, yoga mats, the ironing board and
// wind / brass instruments. Small props, front at +z, filling the scanned box.

private let brassC = 0xD1A54E
private let steel = 0xA9AEB2

extension Canvas {
    // MARK: ball

    /// A ball filling its box: a basketball (orange, black seams), a soccer ball (white with
    /// black patches), a tennis ball, a volleyball, or a plain rubber ball with a stripe.
    func ball(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let cx = D(X - 1) / 2, cy = D(Y - 1) / 2, cz = D(Z - 1) / 2
        let rx = D(X) / 2, ry = D(Y) / 2, rz = D(Z) / 2
        let basket = name.has("basketball"), soccer = name.has("soccer", "football") && !name.has("american"),
            tennis = name.has("tennis"), volley = name.has("volleyball", "beach ball")
        let base = colorFromName(name, basket ? 0xD9772E : soccer ? 0xF2F0EA : tennis ? 0xD4E04A : volley ? 0xF2EBD9
                                     : pick([0xC23B2E, 0x3F5A73, 0x8A6FA8, 0xC9A25A, 0x5B7896]))
        ellipsoid(cx, cy, cz, rx * 0.96, ry * 0.96, rz * 0.96) { x, y, z, _ in
            let dx = D(x) - cx, dy = D(y) - cy, dz = D(z) - cz
            if basket { return abs(dx) < 0.5 || abs(dy) < 0.5 ? 0x2B2A28 : base }
            if soccer { return hash3((x + 1) / 2, (y + 1) / 2, (z + 1) / 2, 17) < 0.28 ? 0x2B2A28 : base }
            if tennis { return abs(dx * dx - dz * dz) < 0.9 && abs(dy) < ry * 0.7 ? 0xF4F1EA : base }
            if volley { return dy > ry * 0.3 ? 0x2D6CC0 : dy < -ry * 0.3 ? 0xE0B13A : base }
            return abs(dy) < 0.6 ? 0xF4F1EA : base
        }
    }

    // MARK: helmet

    /// A helmet dome: a vented bike helmet with a short visor (default), or a full-face
    /// motorcycle / ski helmet with a dark visor across the front.
    func helmet(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let full = name.has("motorcycle", "motorbike", "full face", "full-face", "ski", "snowboard", "racing")
        let shell = colorFromName(name, pick([0xC23B2E, 0x2B2A28, 0xEBE6DC, 0x3F5A73, 0xC9A25A]))
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        let rx = D(X) / 2, rz = D(Z) / 2, ry = D(Y) - 0.5
        let cy = full ? D(Y) * 0.45 : 0.0
        let rY = full ? D(Y) * 0.55 : ry
        ellipsoid(cx, cy, cz, rx, rY, rz) { x, y, z, d in
            guard full || D(y) >= 0 else { return nil }
            if full && z >= Z - 2 && D(y) > D(Y) * 0.35 && D(y) < D(Y) * 0.7 && abs(D(x) - cx) < rx * 0.75 { return 0x1E2A33 }
            if !full && X >= 6 && D(y) > ry * 0.55 && x % 3 == 1 && abs(D(z) - cz) < rz * 0.7 && d < 0.9 { return 0x2B2A28 } // vents
            return y == 0 ? shade(shell, 0.7) : shell
        }
        if !full && Y >= 3 { box(rd(cx - rx * 0.5), max(1, Y / 3), Z - 1, rd(cx + rx * 0.5) + 1, max(1, Y / 3) + 1, Z, shade(shell, 0.8)) }
    }

    // MARK: racket

    /// A tennis / badminton racket: an oval head strung with a grid, a throat and a wrapped
    /// grip. Standing when it is taller than long, else lying flat.
    func racket(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let standing = Y >= max(X, Z)
        let alongX = X >= Z
        // across (a) and length (b) extents of the racket's plane, and the thin axis' middle
        let A = standing ? (alongX ? X : Z) : min(X, Z)
        let B = standing ? Y : max(X, Z)
        let mid = standing ? (alongX ? Z : X) / 2 : Y / 2
        let frame = colorFromName(name, pick([0x2B2A28, 0xC23B2E, 0x3F5A73, 0xEBE6DC]))
        let grip = 0x3A3835, strings = 0xF2EEE4
        func put2(_ a: Int, _ b: Int, _ c: Int, flat: Bool = false) {
            if standing {
                if alongX { set(a, b, mid, c, flat: flat) } else { set(mid, b, a, c, flat: flat) }
            } else {
                // lying: the length runs along the longer floor axis, head at the far end
                if alongX { set(b, mid, a, c, flat: flat) } else { set(a, mid, b, c, flat: flat) }
            }
        }
        let headLen = max(3, rd(D(B) * 0.58))
        let ca = D(A - 1) / 2, cb = D(B - 1) - D(headLen - 1) / 2
        let ra = D(A) / 2, rb = D(headLen) / 2
        for b in 0..<B {
            for a in 0..<A {
                let u = (D(a) - ca) / ra, v = (D(b) - cb) / rb
                let d = u * u + v * v
                if d <= 1 {
                    let edge = d > 0.62 || A < 4
                    if edge { put2(a, b, frame) } else if a % 2 == 0 || b % 2 == 0 { put2(a, b, strings, flat: true) }
                }
            }
        }
        // throat and handle
        let throat = B - headLen
        for b in 0..<max(0, throat) {
            let t = D(b) / D(max(1, throat))
            if t > 0.6 {
                let spread = (t - 0.6) / 0.4 * D(A) * 0.3
                put2(rd(ca - spread), b, frame); put2(rd(ca + spread), b, frame)
            } else {
                put2(rd(ca), b, t < 0.45 ? grip : frame)
                if A >= 6 && t < 0.45 { put2(rd(ca) + 1, b, grip) }
            }
        }
    }

    // MARK: weights

    /// A dumbbell (hex heads on a knurled steel handle) along its long side, a kettlebell (a
    /// cast-iron ball with a handle) when named, or a barbell with plates.
    func weights(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let iron = colorFromName(name, 0x2F2E2C)
        if name.has("kettlebell") {
            let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
            let bodyH = max(2, rd(D(Y) * 0.72))
            ellipsoid(cx, D(bodyH) / 2, cz, D(X) / 2, D(bodyH) / 2, D(Z) / 2) { _, y, _, _ in y == 0 ? shade(iron, 0.8) : iron }
            // handle: an arch over the top
            let hw = max(1, rd(D(X) * 0.3))
            box(rd(cx) - hw, Y - 1, rd(cz), rd(cx) + hw + 1, Y, rd(cz) + 1, iron)
            for x in [rd(cx) - hw, rd(cx) + hw] { box(x, bodyH - 1, rd(cz), x + 1, Y, rd(cz) + 1, iron) }
            return
        }
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let bar = name.has("barbell")
        let headL = bar ? max(1, L / 10) : max(1, rd(D(L) * 0.28))
        let cw = D(W - 1) / 2, cy = D(Y - 1) / 2
        let r = max(0.8, min(D(W), D(Y)) / 2)
        for u in 0..<L {
            let head = bar ? (u >= 1 && u < 1 + headL) || (u < L - 1 && u >= L - 1 - headL) : u < headL || u >= L - headL
            for y in 0..<Y {
                for w in 0..<W {
                    let dw = D(w) - cw, dy = D(y) - cy
                    if head {
                        // hexagonal head
                        if abs(dw) + abs(dy) * 0.5 <= r && abs(dy) <= r { put(a, u, y, w, (u == 0 || u == L - 1) ? 0x5A5E62 : iron) }
                    } else if abs(dw) < 0.6 && abs(dy) < 0.6 || (W <= 2 && abs(dy) < 0.6) {
                        put(a, u, y, w, u % 2 == 0 ? steel : shade(steel, 0.85))
                    }
                }
            }
        }
        if bar { for u in [0, L - 1] { put(a, u, rd(cy), rd(cw), steel) } }
    }

    // MARK: yoga mat

    /// A rolled yoga mat (a cylinder along its long side, the spiral showing at the ends, two
    /// straps), or a flat mat when the box is one layer thin.
    func yogaMat(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let mat = colorFromName(name, pick([0x8A6FA8, 0x4F8F8B, 0xD9A5A0, 0x3F5A73, 0x7A8C6E]))
        if Y <= 1 {
            box(0, 0, 0, X, 1, Z) { x, _, z in x == 0 || z == 0 || x == X - 1 || z == Z - 1 ? shade(mat, 0.85) : mat }
            return
        }
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let cw = D(W - 1) / 2, cy = D(Y - 1) / 2, r = max(0.8, min(D(W), D(Y)) / 2 - 0.1)
        let s0 = rd(D(L) * 0.25), s1 = L - 1 - rd(D(L) * 0.25)
        for u in 0..<L {
            for y in 0..<Y {
                for w in 0..<W {
                    let d = ((D(w) - cw) * (D(w) - cw) + (D(y) - cy) * (D(y) - cy)).squareRoot()
                    guard d <= r else { continue }
                    let end = u == 0 || u == L - 1
                    let c = end ? (Int(d.rounded()) % 2 == 0 ? shade(mat, 0.75) : mat) : (u == s0 || u == s1) ? 0x2B2A28 : mat
                    put(a, u, y, w, c)
                }
            }
        }
    }

    // MARK: ironing board

    /// An ironing board: a padded top with a tapered nose and an iron rest at the square end,
    /// on crossed steel legs. Stored folded (taller than it is long): the flat board standing
    /// on its square end with the legs folded against it.
    func ironingBoard(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let cover = colorFromName(name, pick([0x9FB8CC, 0xD9C7A4, 0xE7E2D8, 0xC9B7D6]))
        let dot = shade(cover, 0.82)
        if Y > max(X, Z) {
            // folded: a vertical board, nose up
            let alongX = X >= Z, A = alongX ? X : Z
            let mid = (alongX ? Z : X) / 2
            for y in 0..<Y {
                let t = D(y) / D(max(1, Y - 1))
                let half = t > 0.75 ? D(A) / 2 * (1 - (t - 0.75) / 0.25 * 0.7) : D(A) / 2
                for i in 0..<A where abs(D(i) - D(A - 1) / 2) <= half {
                    let c = (i + y) % 4 == 0 ? dot : cover
                    if alongX { set(i, y, mid, c) } else { set(mid, y, i, c) }
                }
            }
            let back = max(0, mid - 1)
            for y in 0..<max(1, Y - 3) where y % 3 != 2 {
                if alongX { set(1, y, back, steel); set(A - 2, y, back, steel) } else { set(back, y, 1, steel); set(back, y, A - 2, steel) }
            }
            return
        }
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let topY = Y - 1
        let cw = D(W - 1) / 2
        for u in 0..<L {
            let t = D(u) / D(max(1, L - 1))
            // the nose (high u) narrows to a rounded point
            let half = t > 0.62 ? D(W) / 2 * max(0.25, 1 - pow((t - 0.62) / 0.38, 1.6) * 0.8) : D(W) / 2
            for w in 0..<W where abs(D(w) - cw) <= half {
                put(a, u, topY, w, (u + w) % 3 == 0 ? dot : cover)
            }
        }
        // iron rest at the square end
        if L >= 10 { for w in [0, W - 1] { put(a, 0, topY - 1, w, steel) }; box(a, 0, topY - 1, 0, 2, topY, 1, steel); box(a, 0, topY - 1, W - 1, 2, topY, W, steel) }
        // crossed legs under the middle, feet across the board's width
        let l0 = D(L) * 0.18, l1 = D(L) * 0.68
        for w in [0, W - 1] {
            line(a, l0, 0, D(w), l1, D(topY - 1), D(w), steel)
            line(a, l1, 0, D(w), l0, D(topY - 1), D(w), steel)
        }
        for u in [rd(l0), rd(l1)] { box(a, u, 0, 0, u + 1, 1, W, 0x3A3835) }
    }

    // MARK: wind / brass instruments

    /// A saxophone standing up (a brass body, the U-bend at the bottom, the bell rising on the
    /// left, the neck and a black mouthpiece at the top, pearl keys), or a trumpet / trombone /
    /// flute lying along its long side.
    func horn(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let metal = colorFromName(name, name.has("silver", "flute") ? 0xC9CDD0 : name.has("clarinet", "oboe") ? 0x2B2A28 : brassC)
        let dark = shade(metal, 0.78)
        let sax = name.has("sax") || (!name.has("trumpet", "trombone", "cornet", "flute", "clarinet", "tuba", "horn", "flugelhorn")
                                      && Y >= max(X, Z))
        if sax {
            let cz = D(Z - 1) / 2
            let bodyX = D(X) - 1.5, bellX = 1.5
            let bend = 1
            // body: a tube widening downward from the neck to the bend
            for y in upTo(bend, Y - 2) {
                let t = D(y - bend) / D(max(1, Y - 3 - bend))
                cyl(bodyX - 0.5 * t, cz, max(0.7, 1.4 - 0.7 * t), y, y + 1) { _, yy, _, _ in yy % 3 == 0 ? dark : metal }
            }
            // U-bend and the bell rising on the left
            box(rd(bellX), 0, rd(cz) - 0, rd(bodyX) + 1, bend + 1, rd(cz) + 1, metal)
            let bellTop = max(3, rd(D(Y) * 0.45))
            for y in upTo(0, bellTop) {
                let t = D(y) / D(max(1, bellTop - 1))
                cyl(bellX - 0.5, cz, max(0.8, 0.9 + 1.2 * t * t), y, y + 1) { _, yy, _, _ in yy == bellTop - 1 ? dark : metal }
            }
            // neck bending to the mouthpiece at the top left
            line(bodyX - 0.5, D(Y - 2), cz, D(X) * 0.35, D(Y - 1), cz, metal)
            set(max(0, rd(D(X) * 0.3)), Y - 1, rd(cz), 0x1E1E1E)
            // pearl keys down the front
            for y in stride(from: bend + 2, to: Y - 3, by: 3) { set(rd(bodyX - 0.5), y, min(Z - 1, rd(cz) + 1), 0xF2EEE4, flat: true) }
            return
        }
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let cw = D(W - 1) / 2
        let straight = name.has("flute", "clarinet", "oboe", "piccolo")
        if straight {
            for u in 0..<L {
                let ww = rd(cw), y = max(0, Y / 2 - 1)
                put(a, u, y, ww, u % 4 == 0 ? dark : metal)
                if u % 3 == 1 && u > 1 && u < L - 2 { put(a, u, y + 1, ww, 0xC9CDD0) }
            }
            if name.has("clarinet", "oboe") { for w in upTo(max(0, rd(cw) - 1), min(W, rd(cw) + 2)) { put(a, L - 1, 0, w, metal) } }
            return
        }
        // trumpet: mouthpiece (u = 0), a lead pipe, a loop of tubing with three valves, the bell flaring at u = L - 1
        let bellLen = max(2, rd(D(L) * 0.32))
        let tubeY = max(1, rd(D(Y) * 0.35))
        for u in 0..<L {
            if u >= L - bellLen {
                let t = D(u - (L - bellLen)) / D(max(1, bellLen - 1))
                let r = max(0.6, (0.6 + t * t * (min(D(W), D(Y)) / 2 - 0.6)))
                for y in 0..<Y { for w in 0..<W {
                    let d = ((D(w) - cw) * (D(w) - cw) + (D(y) - D(tubeY)) * (D(y) - D(tubeY))).squareRoot()
                    if d <= r && (u < L - 1 || d > r - 1.2) { put(a, u, y, w, u == L - 1 ? dark : metal) }
                } }
            } else {
                put(a, u, tubeY, rd(cw), metal)
            }
        }
        // the loop beside the lead pipe and the valves rising above it
        let l0 = rd(D(L) * 0.25), l1 = max(l0 + 1, rd(D(L) * 0.6))
        let side = W >= 3 ? rd(cw) + 1 : rd(cw)
        box(a, l0, max(0, tubeY - 1), side, l1 + 1, max(1, tubeY), side + 1, metal)
        for u in [l0, l1] { put(a, u, tubeY, side, metal) }
        for k in 0..<3 {
            let u = l0 + 1 + k * max(1, (l1 - l0) / 4)
            for y in upTo(tubeY, Y) { put(a, u, y, rd(cw), y == Y - 1 ? 0xF2EEE4 : metal) }
        }
        put(a, 0, tubeY, rd(cw), dark)
    }
}
