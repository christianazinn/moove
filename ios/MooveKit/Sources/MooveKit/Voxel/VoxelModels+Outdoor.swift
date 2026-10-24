import Foundation

// OWNER: voxel-models agent. The scan detector's (#98, `ObjectVocabulary`) remaining wheeled and
// outdoor categories, which used to fall back to the kraft box: motorcycles, strollers,
// wheelchairs, grills and lawn mowers. Rolling things are laid out along the footprint's longest
// side (`AlongAxis`), like the treadmill and rower, so either footprint works.

extension Canvas {
    // MARK: motorcycle

    /// Motorcycle side-on: two wheels (cast, or spoked for "dirt"), an engine block with cooling
    /// fins, a tank and seat, fenders, a fork up to handlebars spanning the width, a headlight,
    /// a tail light and an exhaust down the side. "cruiser" / "harley" gets more chrome.
    func motorcycle(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let dirt = name.has("dirt", "motocross", "enduro", "pit bike", "mx ")
        let cruiser = !dirt && name.has("cruiser", "harley", "chopper", "touring", "bobber")
        let paint = colorFromName(name, dirt ? pick([0xE0A030, 0xC23B2E, 0x3D6FA8, 0x5FA052])
                                       : cruiser ? pick([0x2B2A28, 0x7A2E2A, 0x3F5A73]) : pick([0xC23B2E, 0x2B2A28, 0x3D6FA8, 0xEBE6DC, 0x5FA052]))
        let tire = 0x1E1E1F, chrome = 0xC8CCD0, engineC = cruiser ? chrome : 0x4A4D52, seatC = 0x232220
        let wc = W / 2
        let ww0 = W >= 8 ? wc - 1 : wc, ww1 = min(W, wc + 1)
        let R = clampD(D(Y) * (dirt ? 0.34 : 0.3), 2, max(2, D(L) / 4.6))
        let cy = R - 0.5, ru = R - 0.5, fu = D(L) - 0.5 - R
        for wu in [ru, fu] {
            disc(a, wu, cy, R, ww0, ww1) { d in
                if d > R - 1.3 { return tire }
                if d > R - 2.1 || d < 1 { return chrome }
                return dirt ? nil : 0x3A3D42
            }
        }
        // engine between the wheels
        let ew = W >= 5 ? max(1, W / 5) : 0
        let eu0 = rd(ru + R * 0.7), eu1 = max(eu0 + 2, rd(fu - R * 0.8))
        let ey0 = max(1, rd(cy - R * 0.2)), ey1 = max(ey0 + 2, rd(D(Y) * 0.5))
        box(a, eu0, ey0, wc - ew, eu1, ey1, wc + ew + 1, engineC)
        for y in stride(from: ey0 + 1, to: ey1, by: 2) { box(a, eu0, y, max(0, wc - ew - 1), eu1, y + 1, min(W, wc + ew + 2), shade(engineC, 1.2)) } // fins
        // tank and seat, then the fenders
        let tankTop = clamp(rd(D(Y) * 0.66), ey1 + 1, Y - 2)
        let tu0 = rd(D(L) * 0.45), tu1 = max(tu0 + 2, rd(fu - R * 0.45))
        let tw = min(wc, ew + 1)
        box(a, tu0, ey1, wc - tw, tu1, tankTop, min(W, wc + tw + 1), paint)
        box(a, tu0 + 1, tankTop - 1, wc, tu1 - 1, tankTop, wc + 1, shade(paint, 1.15)) // highlight
        let seatY = max(ey1, tankTop - 2)
        box(a, rd(ru - R * 0.2), seatY, wc - min(wc, ew), tu0, seatY + 1, min(W, wc + ew + 1), seatC)
        box(a, max(0, rd(ru - R * 0.75)), seatY - 1, wc, rd(ru + R * 0.3), seatY, wc + 1, paint) // tail
        put(a, max(0, rd(ru - R * 0.75)), seatY - 1, wc, 0xC23B2E, flat: true) // tail light
        line(a, ru, cy, D(wc), D(eu0), D(ey1), D(wc), engineC) // swing arm
        let fender = min(Y - 1, rd(cy + R) + (dirt ? 2 : 0))
        box(a, rd(fu - R * 0.7), fender, wc, rd(fu + R * 0.3), fender + 1, wc + 1, paint)
        // fork and handlebars across the whole width
        let hu = max(tu1, rd(fu - R * 0.35))
        line(a, fu, cy, D(wc), D(hu), D(Y - 2), D(wc), chrome)
        for w in 0..<W { put(a, hu, Y - 1, w, w == 0 || w == W - 1 ? P.black : 0x3A3D42) }
        put(a, min(L - 1, hu + 1), max(0, Y - 3), wc, P.bulb, flat: true) // headlight
        // exhaust down the side to the back
        let ex = min(W - 1, wc + ew + 1)
        line(a, D(eu0), D(ey0), D(ex), max(0, ru - R * 0.4), cy + 1, D(ex), chrome)
    }

    // MARK: stroller

    /// Stroller side-on: four wheels (a jogger: one in front), a seat or pram bassinet ("pram",
    /// "bassinet") in a fabric color, a canopy over the back half, a basket below, the frame up
    /// to a push bar at the back.
    func stroller(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let jogger = name.has("jog", "running", "three wheel", "3-wheel", "3 wheel", "bob ")
        let pram = name.has("pram", "bassinet", "carriage")
        let fabricC = colorFromName(name, pick([0x2B2A28, 0x3F5A73, 0x8F8D88, 0x6C7B5E, 0xD6C4A4]))
        let canopyC = secondary ?? shade(fabricC, 0.88)
        let frameC = name.has("silver", "chrome") ? P.metal : 0x34322F, tire = 0x1E1E1F
        let R = clampD(D(Y) * (jogger ? 0.15 : 0.09), 1.2, max(1.2, D(L) / 5))
        let cy = R - 0.5, ru = R - 0.5, fu = D(L) - 0.5 - R
        func wheel(_ u: Double, _ w: Int) { disc(a, u, cy, R, w, w + 1) { d in d > R - 1 ? tire : 0xC8CCD0 } }
        for w in Set([0, W - 1]) { wheel(ru, w); if !jogger { wheel(fu, w) } }
        if jogger { wheel(fu, W / 2) }
        box(a, rd(ru), rd(cy), 0, rd(ru) + 1, rd(cy) + 1, W, frameC) // rear axle
        // seat between the wheels, a canopy over its back
        let w0 = W > 3 ? 1 : 0, w1 = W > 3 ? W - 1 : W
        let s0 = rd(D(L) * 0.22), s1 = max(s0 + 2, rd(D(L) * 0.8))
        let sy0 = clamp(rd(D(Y) * 0.38), rd(cy) + 2, Y - 4), sy1 = clamp(rd(D(Y) * (pram ? 0.62 : 0.55)), sy0 + 1, Y - 2)
        box(a, s0, sy0, w0, s1, sy1, w1, fabricC)
        if !pram && s1 - s0 > 3 && w1 - w0 > 2 { box(a, s0 + 2, sy1 - 1, w0 + 1, s1 - 1, sy1, w1 - 1, shade(fabricC, 1.2)) } // seat liner
        let cu1 = s0 + max(2, (s1 - s0) * 3 / 5), canTop = max(sy1 + 1, rd(D(Y) * 0.88))
        for u in upTo(s0, cu1) {
            let t = D(u - s0) / D(max(1, cu1 - s0))
            let top = sy1 + rd(D(canTop - sy1) * max(0, 1 - t * t).squareRoot())
            box(a, u, max(sy1, top - 1), w0, u + 1, top, w1, canopyC)
            for w in Set([w0, w1 - 1]) { box(a, u, sy1, w, u + 1, top, w + 1, canopyC) }
        }
        if sy0 - rd(cy) >= 3 { box(a, s0 + 1, rd(cy) + 1, w0, s1 - 1, sy0 - 1, w1, 0x3A3835) } // basket
        // frame: back legs up to the push bar, front legs to the seat
        for w in Set([0, W - 1]) {
            line(a, ru, cy, D(w), 0.5, D(Y - 1), D(w), frameC)
            line(a, fu, cy, D(w), D(s1), D(sy0), D(w), frameC)
        }
        box(a, 0, Y - 1, 0, 2, Y, W, P.black) // push bar
    }

    // MARK: wheelchair

    /// Wheelchair facing +z: big push-rim wheels on both sides, casters and footrests in front,
    /// a sling seat and back, armrests, push handles at the back. "power" / "electric" adds a
    /// battery box and a joystick, with smaller drive wheels.
    func wheelchair(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let power = name.has("power", "electric", "motorized", "motorised")
        let frameC = colorFromName(name, pick([0x9A9FA3, 0x2B2A28, 0x3D6FA8, 0xA8473D])), seatC = 0x232220, tire = 0x1E1E1F
        let R = clampD(min(D(Y) * (power ? 0.22 : 0.34), D(Z) * 0.36), 2, max(2, D(Y) / 2))
        let wy = R - 0.5, wz = max(R - 0.5, D(Z) * 0.4)
        for x in Set([0, X - 1]) {
            for y in thru(0, min(Y - 1, ce(wy + R))) {
                for z in thru(max(0, fl(wz - R)), min(Z - 1, ce(wz + R))) {
                    let d = ((D(z) - wz) * (D(z) - wz) + (D(y) - wy) * (D(y) - wy)).squareRoot()
                    if d > R { continue }
                    if d > R - 1 { set(x, y, z, tire) }
                    else if d > R - 1.8 || d < 1 { set(x, y, z, 0xC8CCD0) }
                    else if abs(D(z) - wz) < 0.5 || abs(D(y) - wy) < 0.5 { set(x, y, z, P.metal) } // spokes
                }
            }
        }
        let xi0 = X >= 5 ? 1 : 0, xi1 = X >= 5 ? X - 1 : X
        let sy = clamp(rd(D(Y) * 0.5), 2, Y - 3)
        let zb = clamp(rd(wz - R * 0.7), 1, Z - 3), zf = max(zb + 2, rd(D(Z) * 0.8))
        box(xi0, sy, zb, xi1, sy + 1, zf, seatC) // seat
        box(xi0, sy + 1, zb, xi1, max(sy + 2, rd(D(Y) * 0.9)), zb + 1, seatC) // back
        for x in Set([xi0, xi1 - 1]) {
            box(x, sy + 1, zb - 1, x + 1, Y, zb, frameC) // back post
            line(D(x), D(Y - 1), D(zb - 1), D(x), D(Y - 1), 0, P.black) // push handle
            let ay = min(Y - 2, rd(D(Y) * 0.68))
            box(x, ay, zb, x + 1, ay + 1, rd(D(Z) * 0.68), frameC) // armrest
            line(D(x), D(sy), D(zf - 1), D(x), 1, D(Z - 2), frameC) // front frame to the footrest
            set(x, 0, Z - 2, tire) // caster
        }
        box(xi0 + (X >= 7 ? 1 : 0), 1, Z - 2, xi1 - (X >= 7 ? 1 : 0), 2, Z, P.black) // footrests
        if power {
            box(xi0 + 1, 1, zb, xi1 - 1, sy, zf - 1, 0x3A3835) // batteries
            set(xi1 - 1, min(Y - 1, rd(D(Y) * 0.68) + 1), rd(D(Z) * 0.66), 0x5FD07A, flat: true) // joystick
        }
    }

    // MARK: grill

    /// Gas grill (a cart with doors and casters, a firebox with knobs, a domed hood with a handle,
    /// side shelves on wide ones) or a kettle grill ("kettle", "charcoal", "weber", "kamado",
    /// "egg", or a small square footprint): a round bowl and lid on three legs, a top handle.
    func grill(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let kettle = name.has("kettle", "charcoal", "kamado", "egg", "hibachi") || (abs(X - Z) <= 2 && D(X) * voxelM < 0.8)
        if kettle { kettleGrill(X, Y, Z, name); return }
        let stainless = name.has("stainless", "steel", "silver")
        let body = colorFromName(name, stainless ? 0xB8BCBF : pick([0x2B2A28, 0x2B2A28, 0x7A2E2A, 0x3F5A73]))
        let lidC = stainless ? 0xC8CCD0 : body
        let shelfW = X >= 14 ? max(2, X / 6) : 0
        let c0 = shelfW, c1 = X - shelfW
        let cartTop = clamp(rd(D(Y) * 0.55), 2, Y - 4), boxTop = clamp(rd(D(Y) * 0.68), cartTop + 1, Y - 2)
        let mid = (c0 + c1) / 2
        box(c0, 1, 0, c1, cartTop, Z) { x, y, z in
            if z == Z - 1 {
                if x == mid { return shade(body, 0.6) } // door seam
                if (x == mid - 1 || x == mid + 1) && y == cartTop - 2 { return 0xC8CCD0 } // door pulls
            }
            return x == c0 || x == c1 - 1 ? shade(body, 0.9) : body
        }
        for x in Set([c0, c1 - 1]) { for z in Set([0, Z - 1]) { set(x, 0, z, P.black) } } // casters
        box(c0, cartTop, 0, c1, boxTop, Z) { x, y, z in
            z == Z - 1 && y == cartTop + (boxTop - cartTop) / 2 && (x - c0) % 2 == 1 && x < c1 - 1 ? P.black : shade(lidC, 0.82) // knobs
        }
        // the domed hood
        let hh = D(Y - boxTop), cz = D(Z - 1) / 2, rz = D(Z) / 2
        for y in upTo(boxTop, Y) {
            let dy = (D(y - boxTop) + 0.5) / hh
            for z in 0..<Z {
                let dz = (D(z) - cz) / rz
                guard dz * dz + dy * dy <= 1.05 else { continue }
                for x in upTo(c0, c1) { set(x, y, z, x == c0 || x == c1 - 1 ? shade(lidC, 0.88) : (dy > 0.75 ? shade(lidC, 1.12) : lidC)) }
            }
        }
        for x in upTo(c0 + 1, c1 - 1) { set(x, boxTop, Z - 1, 0xC8CCD0) } // hood handle
        if Y - boxTop >= 4 { set(mid, boxTop + (Y - boxTop) / 2, min(Z - 1, rd(cz + rz * 0.8)), P.brass, flat: true) } // thermometer
        if shelfW > 0 {
            box(0, boxTop - 1, 1, c0, boxTop, Z - 1, shade(body, 0.75))
            box(c1, boxTop - 1, 1, X, boxTop, Z - 1, shade(body, 0.75))
            cyl(D(c1) + D(shelfW - 1) / 2, cz, max(1, min(D(shelfW) / 2, rz * 0.6)), boxTop, boxTop + 1, 0x3A3835) // side burner
        }
    }

    func kettleGrill(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let egg = name.has("kamado", "egg")
        let body = colorFromName(name, egg ? 0x3E6B3A : pick([0x232220, 0x232220, 0xA8302A, 0x3F5A73]))
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, rx = D(X) / 2, rz = D(Z) / 2
        let cy = D(Y) * (egg ? 0.5 : 0.6)
        let ryLow = cy - D(Y) * (egg ? 0.12 : 0.3), ryHigh = D(Y - 2) - cy + 0.5
        ellipsoid(cx, cy, cz, rx, max(1, ryLow), rz) { _, y, _, _ in D(y) <= cy ? shade(body, 0.92) : nil } // bowl
        ellipsoid(cx, cy, cz, rx, max(1, ryHigh), rz) { _, y, _, d in D(y) > cy ? (d < 0.15 ? shade(body, 1.25) : body) : nil } // lid
        for x in 0..<X { for z in 0..<Z where footEllipse(x, z, X, Z) <= 1 && abs(D(x) - cx) < rx * 0.95 { set(x, rd(cy), z, footEllipse(x, z, X, Z) > 0.7 ? 0xC8CCD0 : body) } } // rim
        // legs from under the bowl out to the floor, wheels on two
        let by = max(1, cy - ryLow * 0.8)
        let feet: [(Double, Double)] = [(0, D(Z - 1)), (D(X - 1), D(Z - 1)), (cx, 0)]
        for (i, (fx, fz)) in feet.enumerated() {
            line(cx + (fx - cx) * 0.4, by, cz + (fz - cz) * 0.4, fx, 0, fz, 0xC8CCD0)
            if i < 2 && !egg { set(rd(fx), 0, rd(fz), P.black) }
        }
        if !egg && Y >= 10 { cyl(cx, cz, max(1, min(rx, rz) * 0.45), rd(D(Y) * 0.18), rd(D(Y) * 0.18) + 1, 0x9A9FA3) } // ash pan
        // top handle
        let hx0 = max(0, rd(cx) - 1), hx1 = min(X, rd(cx) + 2)
        box(hx0, Y - 1, rd(cz), hx1, Y, rd(cz) + 1, egg ? P.oak : P.black)
    }

    // MARK: lawn mower

    /// Push mower (a deck on four wheels, the engine with a pull cord, a grass bag and the
    /// handle back to a crossbar) or a riding mower ("riding", "tractor", "zero turn": hood,
    /// seat, steering wheel, a mowing deck between big rear and small front wheels).
    func lawnMower(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let a = AlongAxis(X, Z), L = a.L, W = a.W
        let riding = name.has("riding", "ride-on", "ride on", "tractor", "zero turn", "zero-turn")
        let paint = colorFromName(name, riding ? pick([0x3E7A3A, 0xE0A030, 0xC23B2E]) : pick([0xC23B2E, 0x3E7A3A, 0xE0A030, 0x2B2A28]))
        let tire = 0x1E1E1F, dark = 0x3A3835
        let wc = W / 2
        if riding {
            let Rr = clampD(D(Y) * 0.3, 1.5, D(L) / 4.5), Rf = max(1.2, Rr * 0.6)
            for w in Set([0, W - 1]) {
                disc(a, Rr - 0.5, Rr - 0.5, Rr, w, w + 1) { d in d > Rr - 1 ? tire : 0xE0C050 }
                disc(a, D(L) - 0.5 - Rf, Rf - 0.5, Rf, w, w + 1) { d in d > Rf - 1 ? tire : 0xE0C050 }
            }
            let w0 = W > 3 ? 1 : 0, w1 = W > 3 ? W - 1 : W
            box(a, rd(D(L) * 0.3), 1, 0, rd(D(L) * 0.7), 2, W, dark) // mowing deck
            let bodyY = clamp(rd(D(Y) * 0.5), 2, Y - 3)
            box(a, rd(Rr), rd(Rf), w0, L - 1, bodyY, w1, paint) // frame and hood
            box(a, rd(D(L) * 0.55), bodyY, w0 + 1, L - 1, bodyY + 1, w1 - 1, shade(paint, 1.12)) // hood top
            let su = rd(D(L) * 0.25)
            box(a, max(0, su - 1), bodyY, w0, su + 2, bodyY + 1, w1, P.black) // seat
            box(a, max(0, su - 1), bodyY, w0, su, min(Y - 1, bodyY + 3), w1, P.black) // seat back
            let colU = rd(D(L) * 0.52)
            line(a, D(colU + 2), D(bodyY), D(wc), D(colU), D(Y - 1), D(wc), dark)
            box(a, colU - 1, Y - 1, max(0, wc - 1), colU + 1, Y, min(W, wc + 2), P.black) // steering wheel
            return
        }
        let deckU0 = rd(D(L) * 0.42), deckH = clamp(rd(D(Y) * 0.22), 2, max(2, Y - 4))
        let R = max(1.2, min(D(deckH) * 0.75, D(L - deckU0) / 4))
        for w in Set([0, W - 1]) {
            for u in [D(deckU0) + R - 0.5, D(L) - 0.5 - R] { disc(a, u, R - 0.5, R, w, w + 1) { d in d > R - 1 ? tire : 0xC8CCD0 } }
        }
        let dw0 = W > 3 ? 1 : 0, dw1 = W > 3 ? W - 1 : W
        box(a, deckU0, 1, dw0, L, deckH, dw1, paint) // deck
        box(a, deckU0 + 1, deckH - 1, dw0 + 1, L - 1, deckH, dw1 - 1, shade(paint, 1.1))
        let e0 = deckU0 + (L - deckU0) / 4, e1 = max(e0 + 1, L - (L - deckU0) / 4)
        let eh = clamp(rd(D(Y) * 0.18), 1, max(1, Y - deckH - 2))
        box(a, e0, deckH, W / 4, e1, deckH + eh, max(W / 4 + 1, W - W / 4), dark) // engine
        put(a, (e0 + e1) / 2, deckH + eh, wc, P.black) // pull cord handle
        // grass bag behind the deck, between the handle bars
        let hw0 = W > 2 ? 1 : 0, hw1 = W > 2 ? W - 2 : W - 1
        if W >= 5 && deckU0 >= 3 { box(a, rd(D(deckU0) * 0.35), 1, 2, deckU0, min(Y - 3, deckH + rd(D(Y) * 0.15)), W - 2, 0x4A5A48) }
        for w in Set([hw0, hw1]) { line(a, D(deckU0), D(deckH), D(w), 0, D(Y - 1), D(w), P.black) }
        box(a, 0, Y - 1, hw0, 1, Y, hw1 + 1, P.black) // crossbar
    }
}
