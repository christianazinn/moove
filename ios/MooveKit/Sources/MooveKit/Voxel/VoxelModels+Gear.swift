import Foundation

// OWNER: voxel-models agent (#183). Everyday gear the scan's detector (#98) finds, in the house
// style (palette, jitter, front at +z): vacuums (upright / stick / canister / robot), computer
// monitors, scooters, bags (backpack, tote, duffel, golf, punching), fitness machines and boards.

/// Drawing along a piece's longest horizontal side: u runs along it (from -x, or from the back),
/// w across it, y up. Treadmills, rowers and lying boards use it so either footprint works.
struct AlongAxis {
    let alongX: Bool
    let L: Int, W: Int
    init(_ X: Int, _ Z: Int) {
        alongX = X >= Z
        L = alongX ? X : Z
        W = alongX ? Z : X
    }
}

extension Canvas {
    func put(_ a: AlongAxis, _ u: Int, _ y: Int, _ w: Int, _ c: Int, flat: Bool = false) {
        if a.alongX { set(u, y, w, c, flat: flat) } else { set(w, y, u, c, flat: flat) }
    }

    func box(_ a: AlongAxis, _ u0: Int, _ y0: Int, _ w0: Int, _ u1: Int, _ y1: Int, _ w1: Int, _ c: Int, flat: Bool = false) {
        if a.alongX { box(u0, y0, w0, u1, y1, w1, c, flat: flat) } else { box(w0, y0, u0, w1, y1, u1, c, flat: flat) }
    }

    func line(_ a: AlongAxis, _ u0: Double, _ y0: Double, _ w0: Double, _ u1: Double, _ y1: Double, _ w1: Double, _ c: Int) {
        if a.alongX { line(u0, y0, w0, u1, y1, w1, c) } else { line(w0, y0, u0, w1, y1, u1, c) }
    }

    /// A disc in the u-y plane (a flywheel, a wheel) at across-position w.
    func disc(_ a: AlongAxis, _ cu: Double, _ cy: Double, _ r: Double, _ w0: Int, _ w1: Int, _ c: (Double) -> Int?) {
        for y in thru(max(0, fl(cy - r)), min(ny - 1, ce(cy + r))) {
            for u in thru(max(0, fl(cu - r)), ce(cu + r)) {
                let d = ((D(u) - cu) * (D(u) - cu) + (D(y) - cy) * (D(y) - cy)).squareRoot()
                guard d <= r, let col = c(d) else { continue }
                for w in upTo(w0, w1) { put(a, u, y, w, col) }
            }
        }
    }

    // MARK: vacuum

    /// Robot vacuums: by name, or any vacuum at most 15 cm tall.
    static func isRobotVacuum(_ name: VName, _ Y: Int) -> Bool {
        name.has("robot", "roomba", "roborock", "robovac", "robo vac", "deebot", "braava") || Y <= 3
    }

    /// Upright vacuum (floor head in front, a column with a clear dust bin or a cloth bag, the
    /// handle up the middle, a hose down the side), a stick vacuum ("stick", "cordless", or a
    /// slim footprint), a canister / shop vac, or a robot disc.
    func vacuum(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if Self.isRobotVacuum(name, Y) { robotVacuum(X, Y, Z, name); return }
        if name.has("canister", "shop vac", "shop-vac", "shopvac", "wet dry", "wet/dry", "wet-dry", "henry", "cylinder vac") {
            canisterVacuum(X, Y, Z, name); return
        }
        let paints = [0x7A4FA0, 0xC9A23A, 0xC23B2E, 0x8F8D88, 0x3F5A73]
        let body = colorFromName(name, paints[Int(seed % UInt32(paints.count))])
        let plastic = 0x5A5E62, dark = P.charcoal
        let stick = name.has("stick", "cordless", "handheld", "dyson v") || (X <= 5 && Z <= 5 && !name.has("upright"))
        let mx = X / 2
        if stick {
            let hd = clamp(rd(D(Z) * 0.6), 2, Z), hh = Y >= 24 ? 2 : 1
            box(0, 0, Z - hd, X, hh, Z) { _, y, z in z == Z - 1 ? shade(dark, 1.2) : y == hh - 1 ? body : dark }
            set(mx, 0, Z - 1, 0x5FD07A, flat: true) // headlight
            let wandTop = rd(D(Y) * 0.62), zt = max(0, Z / 2 - 1)
            line(D(mx), D(hh), D(Z - hd / 2 - 1), D(mx), D(wandTop), D(zt), body)
            let binH = max(2, rd(D(Y) * 0.14))
            box(mx - 1, wandTop, zt, mx + 1, wandTop + binH, min(Z, zt + 2), flat: true) { x, y, _ in (x + y) % 3 == 0 ? 0x8F8D88 : 0x9FC1D6 }
            box(mx - 1, wandTop + binH, zt, mx + 1, min(Y - 2, wandTop + binH + 2), min(Z, zt + 2), plastic)
            line(D(mx), D(min(Y - 2, wandTop + binH + 2)), D(zt), D(mx), D(Y - 1), D(max(0, zt - 1)), dark) // handle
            return
        }
        // upright
        let hd = clamp(rd(D(Z) * 0.5), 2, Z), hh = clamp(rd(D(Y) * 0.09), 1, 3)
        box(0, 0, Z - hd, X, hh, Z) { x, y, z in
            if z == Z - 1 { return shade(dark, 1.15) }
            return y == hh - 1 && x > 0 && x < X - 1 ? body : dark
        }
        for x in [0, X - 1] { set(x, 0, Z - hd, P.black) } // rear wheels
        if rand() < 0.5 { set(mx, hh - 1, Z - 1, P.bulb, flat: true) }
        let bw = clamp(rd(D(X) * 0.6), 2, X), bx0 = (X - bw) / 2
        let cdp = clamp(rd(D(Z) * 0.45), 1, Z)
        let ch1 = max(hh + 3, rd(D(Y) * 0.68))
        let bagged = name.has("bag", "kirby", "hoover")
        let binTop = hh + 1 + max(1, rd(D(ch1 - hh) * 0.45))
        box(bx0, hh, 0, bx0 + bw, ch1, cdp) { x, y, z in
            if !bagged && z == cdp - 1 && y > hh && y < binTop && x > bx0 && x < bx0 + bw - 1 { return (x + y) % 3 == 0 ? 0x8F8D88 : 0x9FC1D6 }
            if z == 0 && (y == hh + 2 || y == ch1 - 2) { return dark } // cord hooks
            return y == ch1 - 1 ? shade(body, 1.08) : body
        }
        // handle with a loop grip
        let hz = cdp / 2
        box(mx, ch1, hz, mx + 1, Y - 1, hz + 1, plastic)
        box(mx - 1, Y - 1, hz, mx + 2, Y, hz + 1, dark)
        set(mx - 1, Y - 2, hz, dark); set(mx + 1, Y - 2, hz, dark)
        // hose down the side
        if bx0 >= 1 { box(bx0 - 1, hh, hz, bx0, ch1, hz + 1) { _, y, _ in y % 2 == 0 ? dark : plastic } }
    }

    func robotVacuum(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, seed % 2 == 0 ? 0x2B2A28 : 0xECE7DD)
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, R = D(min(X, Z)) / 2
        let hb = min(Y, 2)
        cyl(cx, cz, R, 0, hb) { x, y, z, d2 in
            if D(z) > cz && d2 > (R - 1) * (R - 1) { return shade(body, 0.8) } // bumper
            if y == hb - 1 && d2 > (R * 0.55) * (R * 0.55) && d2 < (R * 0.68) * (R * 0.68) { return shade(body, 0.9) }
            return body
        }
        set(rd(cx), hb - 1, rd(cz + R * 0.2), 0xC8CCD0, flat: true) // button
        if Y >= 3 { cyl(cx, cz - R * 0.35, max(0.8, R * 0.3), hb, hb + 1, 0x3A3835) } // lidar turret
    }

    func canisterVacuum(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, name.has("henry") ? 0xC23B2E : name.has("shop") ? 0xC9A23A : 0x3F5A73)
        let dark = P.charcoal
        let rc = max(1.5, min(D(X) * 0.3, D(Z) / 2))
        let ccx = rc - 0.5, ccz = D(Z - 1) / 2
        let ch = max(2, rd(D(Y) * 0.4))
        cyl(ccx, ccz, rc, 0, ch) { _, y, _, _ in y == 0 ? dark : y == ch - 1 ? 0x2B2A28 : body }
        if name.has("henry") && rd(ccz + rc) < Z { // the smiling face
            let fz = min(Z - 1, rd(ccz + rc - 0.5)), ey = rd(D(ch) * 0.65)
            set(rd(ccx) - 1, ey, fz, P.black); set(rd(ccx) + 1, ey, fz, P.black)
            set(rd(ccx), max(1, ey - 2), fz, P.black)
        }
        // hose arcing up to the wand, which leans down to a floor head at the front right
        let wx = D(X - 2), top = D(Y - 1)
        line(ccx + rc * 0.5, D(ch), ccz, wx - 1, top - 1, D(Z / 2), dark)
        line(wx, top, D(Z / 2), wx, 1, D(Z - 2), 0x9A9FA3)
        box(X - 4, 0, Z - 2, X, 1, Z, dark)
    }

    // MARK: monitor

    /// Computer monitor: a thin bezel and screen (off, a desktop with a window, or a code editor;
    /// the seed picks) on a neck and a flat foot. "curved"/"ultrawide" bends the ends forward,
    /// "dual" builds two panels on one wide foot, "imac"/"all-in-one" a silver chin and stand.
    func monitor(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, wall: Bool) {
        let dual = name.has("dual", "two monitors", "2 monitors") && X >= 10
        let aio = name.has("imac", "all-in-one", "all in one", "studio display", "pro display")
        let curved = name.has("curved", "ultrawide", "ultra-wide", "ultra wide")
        let bezel = colorFromName(name, aio ? 0xC8CBCF : 0x1C1C1E)
        let standC = aio ? 0xB9BCBF : shade(bezel, 1.15)
        let zp = Z >= 3 ? Z / 2 : Z - 1
        let py0 = wall ? 0 : clamp(rd(D(Y) * 0.2), 1, max(1, Y - 3))
        let content = Int(seed % 3)

        func screen(_ u: Int, _ v: Int, _ w: Int, _ h: Int) -> Int {
            switch content {
            case 1: // desktop: wallpaper, a window with a title bar, a dock
                if v == 0 { return 0x2A2D33 }
                let inWin = u >= w / 5 && u < w * 3 / 5 && v >= h * 2 / 5 && v < h * 4 / 5
                if inWin { return v == h * 4 / 5 - 1 ? 0xB9BCBF : 0xE8E6E1 }
                return mix(0x2F5D8A, 0x4A86B0, D(v) / D(max(1, h)))
            case 2: // code editor: colored lines on dark
                if v % 2 == 1 || u == 0 { return 0x1E2127 }
                let len = 2 + Int(hash3(v, 0, 1, seed) * D(max(1, w - 3)))
                let cols = [0xC678DD, 0x98C379, 0x61AFEF, 0xE5C07B]
                return u <= len ? cols[(v / 2) % cols.count] : 0x1E2127
            default:
                let d = D(u) - D(v) * 1.2
                return d > D(w) * 0.45 && d < D(w) * 0.6 ? 0x262C36 : P.screen
            }
        }
        func panel(_ x0: Int, _ x1: Int) {
            let w = x1 - x0, h = Y - py0
            let chin = aio ? max(1, rd(D(h) * 0.15)) : 0
            if zp > 0 { box(x0 + w / 4, py0 + 1, zp - 1, x1 - w / 4, Y - 1, zp, 0x26262A) } // back housing
            for x in upTo(x0, x1) {
                let bend = curved && zp + 1 < Z && (x - x0 < max(1, w / 6) || x1 - 1 - x < max(1, w / 6))
                let z = bend ? zp + 1 : zp
                for y in upTo(py0, Y) {
                    let isBezel = x == x0 || x == x1 - 1 || y == Y - 1 || y == py0 || y < py0 + chin
                    set(x, y, z, isBezel ? bezel : screen(x - x0 - 1, y - py0 - max(1, chin), w - 2, h - 2 - chin), flat: !isBezel)
                }
            }
            if aio { set((x0 + x1) / 2, py0 + chin / 2, zp, 0x6A6A70, flat: true) } // logo on the chin
        }
        if dual { panel(0, X / 2); panel(X / 2, X) } else { panel(0, X) }
        if wall {
            if zp > 0 { box(X / 2 - 1, Y / 2 - 1, 0, X / 2 + 1, Y / 2 + 1, zp, 0x2A2A2C) }
            return
        }
        // neck behind the panel(s), flat foot
        let fw = clamp(rd(D(X) * (dual ? 0.6 : 0.3)), 2, X), fx0 = (X - fw) / 2
        box(fx0, 0, 0, fx0 + fw, 1, max(1, min(Z, zp + 2)), standC)
        let nz = max(0, zp - 1), mx = X / 2
        let neckTop = py0 + max(1, rd(D(Y - py0) * 0.4))
        if aio {
            // one bent aluminium sheet: a wide blade leaning back from the foot to the panel
            for dx in -1...1 { line(D(mx + dx), 0, 0, D(mx + dx), D(neckTop), D(nz), standC) }
        } else {
            box(mx, 1, nz, mx + 1, neckTop, nz + 1, standC)
        }
    }

    // MARK: scooter

    /// Scooter seen side-on along x like the bike: small wheels, a low deck with grip tape, a
    /// rear fender brake, the stem up to a T-bar spanning z. "electric" gets bigger wheels, a
    /// thick battery deck, a headlight, a display and a kickstand; "kids" two front wheels.
    func scooter(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let electric = name.has("electric", "e-scooter", "escooter", "xiaomi", "segway", "ninebot", "moped", "vespa", "motor")
        let kids = !electric && name.has("kid", "child", "toddler", "mini", "three wheel", "3-wheel", "3 wheel", "maxi")
        let paints = kids ? [0xE07A9A, 0x4FB0C6, 0x8BC34A, 0xF2B33D] : electric ? [0x2B2A28, 0x5A5E62] : [0x9A9FA3, 0x3D6FA8, 0xC23B2E, 0x2B2A28]
        let frameC = colorFromName(name, paints[Int(seed % UInt32(paints.count))])
        let tire = 0x1E1E1F, hubC = electric ? 0x3A3D42 : kids ? 0xE4E1DA : 0xC8CCD0, grip = 0x232220
        let zc = Z / 2
        let R = clampD(D(Y) * (electric ? 0.12 : 0.085), 1.5, max(1.5, (D(X) - 1) / 4.5))
        let cy = R - 0.5, rx = R - 0.5, fx = D(X) - 0.5 - R

        func wheel(_ wcx: Double, _ z0: Int, _ z1: Int) {
            for y in thru(0, min(Y - 1, ce(cy + R))) {
                for x in thru(max(0, fl(wcx - R)), min(X - 1, ce(wcx + R))) {
                    let d = ((D(x) - wcx) * (D(x) - wcx) + (D(y) - cy) * (D(y) - cy)).squareRoot()
                    if d > R { continue }
                    for z in upTo(z0, z1) { set(x, y, z, d > R - 1 ? tire : hubC) }
                }
            }
        }
        let tw = electric && Z >= 10 ? 2 : 1
        wheel(rx, zc, min(Z, zc + tw))
        if kids && Z >= 5 {
            let s = max(1, Z / 4)
            wheel(fx, max(0, zc - s), max(0, zc - s) + 1)
            wheel(fx, min(Z - 1, zc + s), min(Z - 1, zc + s) + 1)
            box(rd(fx), rd(cy), max(0, zc - s), rd(fx) + 1, rd(cy) + 1, min(Z, zc + s + 1), frameC) // axle
        } else {
            wheel(fx, zc, min(Z, zc + tw))
        }

        // deck between the wheels, fender over the rear one
        let dt = electric ? 2 : 1
        let dy0 = max(1, rd(cy))
        let dwh = clamp(rd(D(Z) * 0.18), 0, 2)
        let dx0 = rd(rx + R * 0.6), dx1 = max(dx0 + 2, rd(fx - R))
        box(dx0, dy0, zc - dwh, dx1, dy0 + dt, zc + dwh + 1) { _, y, _ in
            if y == dy0 + dt - 1 { return grip }
            return electric ? 0x3A3D42 : frameC
        }
        let fenderY = min(Y - 1, rd(cy + R))
        box(max(0, rd(rx - R * 0.7)), fenderY, zc - min(dwh, 1), dx0 + 1, fenderY + 1, zc + min(dwh, 1) + 1, electric ? P.black : frameC)
        line(D(dx0), D(dy0), D(zc), D(dx0), D(fenderY), D(zc), electric ? P.black : frameC)

        // neck from the deck to the stem, stem from the front axle up to the bar
        let hx = rd(fx - 1.2)
        line(D(dx1), D(dy0), D(zc), fx - 0.3, cy + R + 0.5, D(zc), frameC)
        line(fx, cy, D(zc), D(hx), D(Y - 1), D(zc), frameC)
        let hwMax = max(0, min(zc, Z - 1 - zc))
        let hw = clamp(rd(D(Z) * 0.42), min(1, hwMax), min(hwMax, 8))
        for k in thru(-hw, hw) {
            let gripEnd = hw >= 2 && abs(k) >= hw - (hw >= 5 ? 1 : 0)
            set(hx, Y - 1, zc + k, gripEnd ? P.black : frameC)
        }
        if electric {
            set(hx, Y - 1, zc, 0x7FC4E8, flat: true) // display
            set(min(X - 1, hx + 1), rd(D(Y) * 0.7), zc, P.bulb, flat: true) // headlight
            let kx = (dx0 + dx1) / 2
            if zc - dwh - 1 >= 0 { line(D(kx), D(dy0), D(zc - dwh - 1), D(kx - 1), 0, D(zc - dwh - 1), P.black) } // kickstand
            set(dx0 + 1, dy0, min(Z - 1, zc + dwh + 1), 0x5FD07A, flat: true) // battery LED
        }
    }

    // MARK: bags

    /// Backpack (upright, rounded top, front pocket, straps on the back), tote / handbag (open top
    /// with two handles), briefcase / messenger (a flap and a clasp), duffel (the luggage builder's),
    /// golf bag (clubs sticking out) or punching bag. A bare "bag" is a duffel when it's long
    /// and low, else a backpack.
    func bag(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("golf") { golfBag(X, Y, Z, name); return }
        if name.has("punching", "heavy bag", "boxing bag", "kick bag", "boxing") { punchingBag(X, Y, Z, name); return }
        if name.has("duffel", "duffle", "holdall", "weekender", "gym bag", "sleeping bag", "sports bag", "travel bag", "kit bag") {
            duffel(X, Y, Z, name); return
        }
        if name.has("tote", "shopping bag", "handbag", "purse", "grocery", "messenger", "satchel", "briefcase", "laptop bag", "beach bag") {
            tote(X, Y, Z, name); return
        }
        if name.has("backpack", "rucksack", "knapsack", "school bag", "schoolbag", "book bag", "bookbag", "daypack") || X <= Y + Y / 5 {
            backpack(X, Y, Z, name)
        } else {
            duffel(X, Y, Z, name)
        }
    }

    func backpack(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let paints = [0x3F5A73, 0x2B2A28, 0xA8473D, 0x6C7B5E, 0xC9A25A, 0x7E95A8]
        let body = colorFromName(name, paints[Int(seed % UInt32(paints.count))])
        let trim = shade(body, 0.7), zipC = 0x1E1E1F
        let hh = Y >= 8 ? 1 : 0
        let H = Y - hh
        let pocketD = Z >= 4 ? 1 : 0
        let zb1 = Z - pocketD
        let cx = D(X - 1) / 2
        let r = max(1, min(D(X) / 2, D(H) * 0.3))
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0 && x < X && y >= 0 && y < H else { return false }
            let ty = (D(y) - (D(H) - 1 - r)) / r
            if ty <= 0 { return true }
            let tx = abs(D(x) - cx) / (D(X) / 2)
            return tx * tx + ty * ty <= 1.05
        }
        let xa = X / 4, xb = X - 1 - X / 4
        for y in upTo(0, H) {
            for x in upTo(0, X) where inside(x, y) {
                for z in upTo(0, zb1) {
                    var c = y == 0 ? shade(body, 0.8) : body
                    if z == 0 { c = (x == xa || x == xb) && y >= 1 && y < H - 1 ? trim : shade(body, 0.9) } // straps / back panel
                    if z == zb1 - 1 && y >= H / 2 && inside(x - 1, y) && inside(x + 1, y) && inside(x, y + 1)
                        && (!inside(x - 2, y) || !inside(x + 2, y) || !inside(x, y + 2)) { c = zipC }
                    set(x, y, z, c)
                }
            }
        }
        if pocketD > 0 && X >= 4 {
            let pt = max(2, rd(D(H) * 0.45))
            box(1, 1, Z - 1, X - 1, pt, Z) { _, y, _ in y == pt - 1 ? zipC : shade(body, 0.95) }
            set(X - 2, pt - 1, Z - 1, P.metal)
            if rand() < 0.5 { set(X / 2, pt - 2, Z - 1, [P.mustard, P.blush, P.sage, P.cream][Int(seed >> 4) % 4]) } // patch
        }
        if hh > 0 { box(X / 2 - 1, H, zb1 / 2, X / 2 + 2, H + 1, zb1 / 2 + 1, trim) } // top loop
    }

    func tote(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let leather = name.has("leather", "handbag", "purse", "briefcase", "satchel")
        let body = colorFromName(name, leather ? 0x8A5A3A : 0xE3D6BC)
        let strapC = leather ? shade(body, 0.7) : 0x2B2A28
        let flap = name.has("briefcase", "messenger", "satchel", "laptop bag")
        let handleH = clamp(rd(D(Y) * 0.3), 1, 6)
        let H = max(2, Y - handleH)
        for y in upTo(0, H) {
            let inset = rd((1 - D(y) / D(max(1, H - 1))) * D(X) * 0.08)
            box(inset, y, 0, X - inset, y + 1, Z) { x, _, z in
                if y == H - 1 && !flap && x > inset && x < X - inset - 1 && z > 0 && z < Z - 1 { return shade(body, 0.5) } // open top
                return y == 0 ? shade(body, 0.85) : body
            }
        }
        if flap {
            let fy = rd(D(H) * 0.45)
            box(0, fy, Z - 1, X, H, Z, shade(body, 0.92))
            set(X / 2, fy, Z - 1, P.brass)
            box(X / 2 - 1, H, Z / 2, X / 2 + 2, min(Y, H + 1), Z / 2 + 1, strapC)
            if H + 1 < Y { set(X / 2 - 1, H + 1, Z / 2, strapC); set(X / 2 + 1, H + 1, Z / 2, strapC) }
            return
        }
        // two handles arching over the top, on the front and back faces
        let ha = rd(D(X) * 0.3), hb = X - 1 - ha
        for z in Z > 1 ? [0, Z - 1] : [0] {
            for x in [ha, hb] { box(x, H, z, x + 1, Y - 1, z + 1, strapC) }
            box(ha, Y - 1, z, hb + 1, Y, z + 1, strapC)
        }
    }

    func golfBag(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let paints = [0x2B2A28, 0xECE7DD, 0x3F5A73, 0xA8473D]
        let body = colorFromName(name, paints[Int(seed % UInt32(paints.count))])
        let accent = shade(body, isDarkColor(body) ? 1.6 : 0.7)
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, R = max(1, D(min(X, Z)) / 2 - 0.2)
        let clubH = clamp(rd(D(Y) * 0.22), 2, 6)
        let bh = max(2, Y - clubH)
        cyl(cx, cz, R, 0, bh) { _, y, z, d2 in
            if y == 0 || y == bh - 1 { return shade(body, 0.7) }
            if D(z) > cz && d2 > (R - 1) * (R - 1) && y > bh / 5 && y < bh * 3 / 5 { return accent } // pocket
            return body
        }
        // clubs: shafts with head covers (woods) and bare heads (irons)
        let covers = [P.mustard, P.blush, P.navy, P.rust, P.sage]
        let n = 5
        for i in 0..<n {
            let a = D(i) / D(n) * 2 * Double.pi + rand() * 0.6
            let px = rd(cx + cos(a) * (R - 1) * 0.6), pz = rd(cz + sin(a) * (R - 1) * 0.6)
            let top = clamp(bh + 1 + fl(rand() * D(clubH - 1)), bh, Y - 1)
            box(px, bh, pz, px + 1, top, pz + 1, P.metal)
            set(px, top, pz, i < 3 ? covers[(i + Int(seed % 5)) % covers.count] : 0x5A5E62)
        }
    }

    func punchingBag(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, 0xA8473D)
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, R = D(min(X, Z)) / 2
        let baseH = clamp(rd(D(Y) * 0.15), 1, 4)
        cyl(cx, cz, R, 0, baseH, P.black)
        cyl(cx, cz, max(1, R * 0.62), baseH, Y) { _, y, _, _ in
            if y == Y - 1 { return P.black }
            return (y - baseH) % max(3, (Y - baseH) / 3) == 0 ? shade(body, 0.75) : body
        }
    }

    // MARK: fitness

    /// Treadmill (default), exercise bike ("bike", "spin", "peloton", "elliptical") or rowing
    /// machine ("rower", "rowing"), laid out along the footprint's long side.
    func fitness(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z)
        let frameC = colorFromName(name, name.has("water") ? P.oak : 0x3A3D42)
        let accents = [0xC23B2E, 0x2D6CC0, 0xE0782A]
        let accent = accents[Int(seed % UInt32(accents.count))]
        let L = a.L, W = a.W, wc = W / 2
        if name.has("rower", "rowing") {
            let railY = clamp(rd(D(Y) * 0.35), 1, Y - 3)
            let rr = clampD(D(min(Y, L)) * 0.3, 1.5, D(L) * 0.2)
            let fu = D(L) - 0.5 - rr
            box(a, 1, railY, wc, L - Int(rr), railY + 1, wc + 1, frameC) // rail
            box(a, 1, 0, 0, 2, 1, W, frameC); box(a, L - 2, 0, 0, L - 1, 1, W, frameC) // feet
            box(a, 1, 1, wc, 2, railY, wc + 1, frameC) // rear leg
            let water = name.has("water")
            disc(a, fu, rr + 0.5, rr, max(0, wc - 1), min(W, wc + 2)) { d in
                water ? (d > rr - 1 ? P.oak : 0x6FA8C8) : (d > rr - 1 ? accent : 0x2B2A28)
            }
            let seatU = rd(D(L) * 0.35)
            box(a, seatU - 1, railY + 1, max(0, wc - 1), seatU + 2, railY + 2, min(W, wc + 2), P.black)
            let footU = rd(fu - rr) - 2
            for w in [max(0, wc - 2), min(W - 1, wc + 2)] { box(a, footU, railY, w, footU + 1, railY + 3, w + 1, 0x2B2A28) }
            box(a, rd(fu - rr) - 1, rd(rr), max(0, wc - 2), rd(fu - rr), rd(rr) + 1, min(W, wc + 3), P.black) // handle
            line(a, fu, 2 * rr, D(wc), fu - 1, D(Y - 1), D(wc), frameC) // monitor arm
            put(a, rd(fu - 1), Y - 1, wc, 0x7FC4E8, flat: true)
            return
        }
        if name.has("bike", "cycle", "spin", "peloton", "elliptical", "cross trainer", "cross-trainer") {
            let elliptical = name.has("elliptical", "cross trainer", "cross-trainer")
            box(a, 1, 0, 0, 2, 1, W, frameC); box(a, L - 2, 0, 0, L - 1, 1, W, frameC)
            box(a, 1, 0, wc, L - 1, 1, wc + 1, frameC)
            let rf = clampD(D(Y) * 0.2, 1.5, D(L) * 0.25)
            let fu = D(L) - 1.5 - rf, fyc = rf + 1
            disc(a, fu, fyc, rf, wc, wc + 1) { d in d > rf - 1 ? (name.has("peloton") ? 0x2B2A28 : P.metal) : d < 0.8 ? accent : 0x3A3D42 }
            let barTop = D(Y - 2)
            line(a, D(L - 2), 1, D(wc), fu - rf * 0.5, barTop, D(wc), frameC)
            box(a, rd(fu - rf * 0.5), Y - 2, max(0, wc - W / 3), rd(fu - rf * 0.5) + 1, Y - 1, min(W, wc + W / 3 + 1), P.black)
            put(a, rd(fu - rf * 0.5), Y - 1, wc, 0x7FC4E8, flat: true)
            if elliptical {
                for w in [max(0, wc - 2), min(W - 1, wc + 2)] {
                    line(a, fu - rf, fyc, D(w), 2, 2, D(w), frameC)
                    line(a, fu - rf * 0.6, fyc, D(w), fu - rf * 0.9, barTop, D(w), P.charcoal)
                }
            } else {
                let su = D(L) * 0.3, seatY = D(rd(D(Y) * 0.62))
                line(a, D(L) * 0.35, 1, D(wc), su, seatY, D(wc), frameC)
                line(a, D(L) * 0.35, D(Y) * 0.3, D(wc), fu, fyc, D(wc), frameC)
                box(a, rd(su) - 1, rd(seatY), max(0, wc - 1), rd(su) + 2, rd(seatY) + 1, min(W, wc + 2), P.black)
                let bbU = rd(D(L) * 0.5), bbY = rd(D(Y) * 0.3)
                put(a, bbU, bbY, max(0, wc - 1), P.black); put(a, bbU, bbY, min(W - 1, wc + 1), P.black) // pedals
            }
            return
        }
        // treadmill: belt deck between rails, motor hood with an accent stripe, uprights, console
        let deckH = clamp(rd(D(Y) * 0.12), 1, 4)
        let hl = clamp(rd(D(L) * 0.15), 2, 6)
        box(a, 0, 0, 0, L - hl, deckH, W, frameC)
        box(a, 0, deckH - 1, 1, L - hl, deckH, max(1, W - 1), 0x1E1E1F)
        box(a, 0, 0, 0, 1, deckH, W, P.metal)
        box(a, L - hl, 0, 0, L, deckH + 1, W, frameC)
        box(a, L - hl, deckH, 0, L, deckH + 1, W, accent)
        let consoleY = Y - 2
        for w in [0, W - 1] {
            line(a, D(L - hl) + D(hl) / 2, D(deckH), D(w), D(L - hl - 1), D(consoleY), D(w), frameC)
            let railY = consoleY - max(1, rd(D(Y) * 0.15))
            box(a, max(0, L - hl - 2 - rd(D(L) * 0.2)), railY, w, L - hl - 1, railY + 1, w + 1, frameC)
        }
        box(a, max(0, L - hl - 3), consoleY - 1, 0, L - hl, Y, W, 0x2B2A28)
        box(a, max(0, L - hl - 3), consoleY, max(0, wc - 2), max(0, L - hl - 2), Y, min(W, wc + 2), 0x7FC4E8, flat: true)
    }

    // MARK: boards

    /// Skateboard (default: deck on trucks and wheels), surfboard (pointed nose, stringer, fin),
    /// snowboard (bindings) or skis (a pair). Standing upright when the item is taller than it is
    /// long (leaning on a wall), else lying along the footprint's long side.
    func board(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let surf = name.has("surf", "paddle", "bodyboard", "wakeboard", "skimboard")
        let snow = name.has("snowboard")
        let skis = !snow && !surf && name.word("ski", "skis")
        let skate = !surf && !snow && !skis
        let upright = Y > max(X, Z)
        let a = AlongAxis(X, Z)
        let L = upright ? Y : a.L, W = upright ? X : a.W
        let T = upright ? Z : Y
        // maps (u along, w across, layer t) to the grid
        func p(_ u: Int, _ w: Int, _ t: Int, _ c: Int) {
            if upright { set(w, u, t, c) } else if a.alongX { set(u, t, w, c) } else { set(w, t, u, c) }
        }
        let paints = [0x2D6CC0, 0xC23B2E, 0x1E9C8A, 0xE0782A, 0x7A3FB0, 0xF2B33D]
        let graphic = colorFromName(name, paints[Int(seed % UInt32(paints.count))])
        let raised = (skate || surf) && !upright && T >= 2 // deck sits on its wheels / fin
        let deckT = raised ? 1 : 0
        let extraLayer = raised ? 0 : min(T - 1, deckT + 1) // wheels, fin or bindings
        let half = D(W) / 2
        func halfWidth(_ t: Double) -> Double {
            if surf { return half * sin(Double.pi * (0.08 + 0.9 * t)).squareRoot() }
            let e = min(t, 1 - t)
            let end = e < 0.12 ? (1 - pow((0.12 - e) / 0.12, 2)).squareRoot() : 1
            return half * end * (snow ? 1 - 0.1 * sin(Double.pi * t) : 1)
        }
        if skis {
            let strips = W >= 3 ? [W / 2 - 1, W / 2 + 1] : [W / 2]
            for u in upTo(0, L) {
                for w in strips { p(u, w, deckT, u >= L - 2 ? shade(graphic, 0.8) : graphic) }
            }
            if extraLayer != deckT { for w in strips { p(L / 2, w, extraLayer, P.black); p(L / 2 - 1, w, extraLayer, P.black) } }
            return
        }
        let top = skate ? 0x232220 : surf ? 0xF2EFE6 : graphic
        for u in upTo(0, L) {
            let t = (D(u) + 0.5) / D(L)
            let hw = halfWidth(t)
            for w in upTo(0, W) where abs(D(w) + 0.5 - half) <= max(0.5, hw) {
                var c = top
                if surf && w == W / 2 { c = P.oak } // stringer
                if surf && abs(t - 0.62) < 0.03 { c = graphic } // stripe
                if !surf && !skate && abs(t - 0.5) < 0.12 { c = shade(graphic, 1.2) }
                p(u, w, deckT, c)
            }
        }
        guard extraLayer != deckT else { return }
        if skate {
            for t in [0.2, 0.8] {
                let u = rd(D(L) * t)
                for w in upTo(0, W) { p(u, w, extraLayer, w == 0 || w == W - 1 ? 0xE9DFCB : P.metal) }
            }
        } else if surf {
            p(max(0, rd(D(L) * 0.06)), W / 2, extraLayer, 0x2B2A28) // fin
        } else {
            for t in [0.35, 0.65] { p(rd(D(L) * t), W / 2, extraLayer, P.black) } // bindings
        }
    }
}
