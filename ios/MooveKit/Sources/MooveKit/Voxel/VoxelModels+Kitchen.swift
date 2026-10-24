import Foundation

// OWNER: voxel-models agent. Moove pieces in the house style (palette, jitter, front at +z):
// ranges / wall ovens, dishwashers and microwaves. Finish comes from the name (stainless,
// white, black, or any keyword color); everything scales from the kind's minDims up.

extension Canvas {
    // MARK: shared bits

    /// Appliance finish: black / black stainless reads dark, "stainless" reads brushed steel,
    /// else the name's color word, else `fallback`.
    func applianceFinish(_ name: VName, _ fallback: Int) -> Int {
        if name.primary != nil { return colorFromName(name, fallback) }
        if name.word("black") { return 0x2B2A28 }
        if name.has("stainless") { return P.metal }
        return colorFromName(name, fallback)
    }

    func isDarkColor(_ c: Int) -> Bool { (((c >> 16) & 255) + ((c >> 8) & 255) + (c & 255)) < 300 }

    // MARK: stove

    /// Freestanding range: cabinet body, oven door with a dark glass window and a horizontal
    /// handle, a storage drawer below, a backguard with knobs, and a cooktop with four burners
    /// (cast-iron grates for gas, dark glass with ring elements otherwise). Wall ovens (or an
    /// "oven" without "range") get a control strip and a door filling the front instead.
    func stove(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let wallOven = name.has("wall oven", "built-in oven", "built in oven")
            || (name.word("oven") && !name.has("range", "stove", "cooktop", "cook top"))
        if wallOven { self.wallOven(X, Y, Z, name); return }

        let body = applianceFinish(name, P.white)
        let dark = isDarkColor(body)
        let seam = shade(body, 0.7)
        let handleC = dark ? P.metal : 0xB9BCBF
        let knobC = dark ? 0xB9BCBF : P.charcoal
        let zf = max(1, Z - 2) // front face; the handle sits one voxel proud of it
        let bg = max(1, rd(D(Y) * 0.1)) // backguard height above the cooktop
        let yTop = max(3, Y - 1 - bg) // cooktop layer
        let bgD = max(1, Z / 7) // backguard depth

        // cabinet
        let topC = shade(body, 0.96), backC = shade(body, 0.85), sideC = shade(body, 0.94)
        box(0, 0, 0, X, yTop + 1, zf + 1) { x, y, z in
            if z == 0 { return backC }
            if y == 0 { return z == zf ? 0x3A3835 : shade(body, 0.8) } // toe kick
            if y == yTop { return topC }
            if (x == 0 || x == X - 1) && z < zf { return sideC }
            return body
        }
        // dark feet tucked under the corners
        for (fx, fz) in [(0, 0), (X - 1, 0), (0, zf), (X - 1, zf)] { set(fx, 0, fz, P.black) }

        // front: drawer at the bottom, oven door above, seams between them
        let dTop = 1 + max(1, rd(D(Y) * 0.15)) // first door row
        let doorTop = yTop // door rows [dTop, doorTop)
        box(0, 1, zf, X, yTop, zf + 1) { x, y, _ in
            x == 0 || x == X - 1 || y == dTop ? seam : nil // side edges + the drawer / door gap
        }
        // window: dark glass with an inner frame and a diagonal sheen
        let wy0 = dTop + 2, wy1 = max(wy0 + 1, doorTop - 2)
        let wx0 = max(1, rd(D(X) * 0.18)), wx1 = min(X - 1, X - wx0)
        let frameC = dark ? 0x1B1C1E : 0x3A3D42
        box(wx0 - 1, wy0 - 1, zf, wx1 + 1, min(wy1 + 1, doorTop - 1), zf + 1) { x, y, _ in
            if x == wx0 - 1 || x == wx1 || y == wy0 - 1 || y == wy1 { return frameC }
            return nil
        }
        box(wx0, wy0, zf, wx1, wy1, zf + 1, flat: true) { x, y, _ in
            (x - wx0 + (y - wy0)) % 6 == 2 ? 0x3A4250 : 0x1D2026
        }
        // oven light glimpsed through the glass on bigger ovens
        if wx1 - wx0 >= 6 && wy1 - wy0 >= 3 { set((wx0 + wx1) / 2, wy1 - 1, zf, 0x5A4A30, flat: true) }
        // horizontal door handle near the top of the door, standing off the face
        let hy = doorTop - 1
        box(1, hy, zf + 1, X - 1, hy + 1, zf + 2) { x, _, _ in x == 1 || x == X - 2 ? shade(handleC, 0.85) : handleC }
        // drawer pull
        let dy = max(1, (dTop - 1) / 2 + (dTop > 3 ? 1 : 0))
        if dTop - 1 >= 1 { box(X / 2 - max(1, X / 6), dy, zf + 1, X / 2 + max(1, X / 6), dy + 1, zf + 2, handleC) }

        // backguard with knobs and a clock display on its front face
        box(0, yTop + 1, 0, X, Y, bgD) { _, y, z in z == 0 ? backC : y == Y - 1 ? topC : body }
        let ky = yTop + 1 + (Y - 1 - (yTop + 1)) / 2
        let mid = X / 2
        set(mid, ky, bgD - 1, 0x7FC4E8, flat: true)
        if X >= 10 { set(mid - 1, ky, bgD - 1, 0x7FC4E8, flat: true) }
        for x in stride(from: 1, to: X - 1, by: 2) where abs(x - mid) > 1 {
            if worn(x, ky, bgD, 0.3) { continue }
            set(x, ky, bgD, knobC)
        }

        // cooktop: four burners in the zone in front of the backguard
        let gas = name.has("gas", "propane")
        let zx0 = 1, zx1 = X - 1, zz0 = bgD, zz1 = zf + 1
        let zw = D(zx1 - zx0), zd = D(zz1 - zz0)
        let r = max(1, min(zw / 4, zd / 4) - 0.25)
        let centers: [(Double, Double)] = [0.27, 0.73].flatMap { fx in
            [0.3, 0.72].map { fz in (D(zx0) + zw * fx - 0.5, D(zz0) + zd * fz - 0.5) }
        }
        if gas {
            // steel deck, a burner cap per burner, and continuous cast-iron grates one layer up
            let deck = dark ? 0x3A3835 : shade(body, 0.93)
            box(zx0, yTop, zz0, zx1, yTop + 1, zz1, deck)
            let grate = 0x2B2A28, cap = 0x1A1A1A
            box(zx0, yTop + 1, zz0, zx1, yTop + 2, zz1) { x, _, z in
                let edge = x == zx0 || x == zx1 - 1 || z == zz0 || z == zz1 - 1
                let midX = x == (zx0 + zx1) / 2, midZ = z == (zz0 + zz1) / 2
                return edge || midX || midZ ? grate : nil
            }
            for (cx, cz) in centers {
                set(rd(cx), yTop + 1, rd(cz), cap)
                // grate fingers reaching toward each burner
                set(rd(cx), yTop + 1, rd(cz - r), grate)
                set(rd(cx), yTop + 1, rd(cz + r), grate)
                set(rd(cx - r), yTop + 1, rd(cz), grate)
                set(rd(cx + r), yTop + 1, rd(cz), grate)
                set(rd(cx), yTop, rd(cz), 0x4A4845) // burner bowl
            }
        } else {
            // smooth dark glass top with ring elements and a thin frame
            let glassTop = 0x15181D, ring = 0x5A3E38, ringHi = 0x6B4B44
            box(zx0, yTop, zz0, zx1, yTop + 1, zz1, flat: true) { x, _, z in
                for (i, (cx, cz)) in centers.enumerated() {
                    let rr = i % 2 == 0 ? r : max(1, r * 0.8)
                    let d = ((D(x) - cx) * (D(x) - cx) + (D(z) - cz) * (D(z) - cz)).squareRoot()
                    if d <= rr && d > rr - 1 { return (x + z) % 3 == 0 ? ringHi : ring }
                    if d < 0.5 && rr >= 2 { return ring }
                }
                return glassTop
            }
        }
    }

    /// Wall oven: a slab with a control strip on top and a door with a big window filling the front.
    func wallOven(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = applianceFinish(name, P.metal)
        let dark = isDarkColor(body)
        let seam = shade(body, 0.7)
        let handleC = dark ? P.metal : 0xB9BCBF
        let zf = max(1, Z - 2)
        box(0, 0, 0, X, Y, zf + 1) { _, y, z in z == 0 ? shade(body, 0.85) : y == Y - 1 ? shade(body, 0.96) : body }
        let strip = max(1, rd(D(Y) * 0.14))
        let sy0 = Y - 1 - strip
        // control strip: dark glass band with a display and touch keys
        box(1, sy0, zf, X - 1, Y - 1, zf + 1, flat: true) { _, _, _ in 0x23252A }
        set(X / 2, sy0 + strip / 2, zf, 0x7FC4E8, flat: true)
        for x in stride(from: 2, to: X - 2, by: 2) where abs(x - X / 2) > 1 { set(x, sy0 + strip / 2, zf, 0x8F949A, flat: true) }
        // door outline and window
        box(0, 0, zf, X, sy0, zf + 1) { x, y, _ in y == 0 || x == 0 || x == X - 1 || y == sy0 - 1 ? seam : nil }
        let wx0 = max(2, rd(D(X) * 0.16)), wx1 = max(wx0 + 1, X - wx0)
        let wy0 = 2, wy1 = max(wy0 + 1, sy0 - 3)
        box(wx0 - 1, wy0 - 1, zf, wx1 + 1, wy1 + 1, zf + 1) { x, y, _ in
            x == wx0 - 1 || x == wx1 || y == wy0 - 1 || y == wy1 ? (dark ? 0x1B1C1E : 0x3A3D42) : nil
        }
        box(wx0, wy0, zf, wx1, wy1, zf + 1, flat: true) { x, y, _ in (x - wx0 + (y - wy0)) % 6 == 2 ? 0x3A4250 : 0x1D2026 }
        // handle across the top of the door
        box(1, sy0 - 2, zf + 1, X - 1, sy0 - 1, zf + 2, handleC)
    }

    // MARK: dishwasher

    /// Dishwasher: front panel with a control strip on top and a bar handle, recessed toe kick,
    /// brushed stainless by default (white / black / any color word from the name).
    func dishwasher(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = applianceFinish(name, P.metal)
        let dark = isDarkColor(body)
        let steel = body == P.metal
        let seam = shade(body, 0.72)
        let handleC = dark ? P.metal : steel ? 0xC4C8CC : 0xB9BCBF
        let zf = max(1, Z - 2)
        let tk = max(1, rd(D(Y) * 0.08)) // toe kick height
        let strip = max(1, rd(D(Y) * 0.1)) // control strip height
        let sy0 = Y - strip // strip rows [sy0, Y)
        let backC = shade(body, 0.85), sideC = shade(body, 0.94), topC = shade(body, 0.96)

        // tub / cabinet sitting on a recessed toe kick
        box(0, tk, 0, X, Y, zf + 1) { x, y, z in
            if z == 0 { return backC }
            if y == Y - 1 && z < zf { return topC }
            if (x == 0 || x == X - 1) && z < zf { return sideC }
            return body
        }
        box(1, 0, 1, X - 1, tk, max(2, zf - 1), 0x2B2A28)
        // leveling feet at the front corners
        set(1, 0, zf - 1, P.black); set(X - 2, 0, zf - 1, P.black)

        // door face: brushed vertical grain on steel, outline seams
        let brushA = shade(body, 1.02), brushB = shade(body, 0.97)
        box(0, tk, zf, X, sy0, zf + 1) { x, y, _ in
            if x == 0 || x == X - 1 || y == tk { return seam }
            if steel { return x % 2 == 0 ? brushA : brushB }
            return body
        }
        // control strip: slightly darker band with buttons and a status light
        let stripC = dark ? 0x1F1F1F : steel ? shade(body, 0.82) : shade(body, 0.92)
        box(0, sy0, zf, X, Y, zf + 1) { x, y, _ in y == sy0 && strip > 1 ? seam : stripC }
        let by = sy0 + (Y - 1 - sy0 + (strip > 1 ? 1 : 0)) / 2
        let btn = dark ? 0x8F949A : P.charcoal
        for x in stride(from: X - 2, to: X / 2, by: -2) { set(x, by, zf, btn) }
        set(2, by, zf, 0x7FD39A, flat: true) // status LED
        // bar handle just under the strip, on standoffs
        let hy = max(tk + 1, sy0 - 2)
        let hx0 = max(1, X / 6), hx1 = min(X - 1, X - X / 6)
        box(hx0, hy, zf + 1, hx1, hy + 1, zf + 2, handleC)
        // brand badge low on the door
        set(X / 2, tk + 2, zf, dark ? 0xB0B4B8 : 0x6F6D68, flat: true)
    }

    // MARK: microwave

    /// Countertop microwave: door with a dark window on the left ~2/3 inside a darker frame,
    /// keypad column with a display on the right, small feet. Over-the-range models hang on the
    /// wall: no feet, a vent strip across the top and a handle along the door.
    func microwave(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let otr = name.has("over the range", "over-the-range", "over range") || name.word("otr")
        let body = applianceFinish(name, otr ? P.metal : 0x3A3835)
        let dark = isDarkColor(body)
        let zf = otr ? max(1, Z - 2) : Z - 1
        let yb = otr ? 0 : 1 // feet layer under countertop models
        let backC = shade(body, 0.85), topC = shade(body, 1.04)

        box(0, yb, 0, X, Y, zf + 1) { _, y, z in
            if z == 0 { return backC }
            if y == Y - 1 { return topC }
            return body
        }
        if !otr { for (fx, fz) in [(0, 0), (X - 1, 0), (0, zf), (X - 1, zf)] { set(fx, 0, fz, P.black) } }

        // door: darker frame around the window
        let vent = otr && Y - yb >= 5 ? 1 : 0 // OTR vent strip across the top
        let dy0 = yb, dy1 = Y - vent // door rows [dy0, dy1)
        let wx1 = clamp(rd(D(X) * 0.66), 3, X - 2) // door columns [0, wx1)
        let frameC = dark ? 0x1B1C1E : shade(body, 0.6)
        box(0, dy0, zf, wx1, dy1, zf + 1) { x, y, _ in
            x == 0 || x == wx1 - 1 || y == dy0 || y == dy1 - 1 ? frameC : nil
        }
        box(1, dy0 + 1, zf, wx1 - 1, dy1 - 1, zf + 1, flat: true) { x, y, _ in
            if (x + y) % 5 == 0 { return 0x3A4250 } // sheen
            return (x + y) % 2 == 0 ? 0x23272E : 0x1F2329 // perforated screen
        }
        // keypad column: panel, display, buttons
        let panelC = dark ? 0x2A2A2C : shade(body, 0.9)
        box(wx1, dy0, zf, X, dy1, zf + 1) { x, y, _ in
            x == wx1 ? shade(panelC, 0.8) : panelC
        }
        let px0 = wx1 + 1 < X ? wx1 + 1 : wx1
        box(px0, dy1 - 2, zf, X - (X - px0 >= 3 ? 1 : 0), dy1 - 1, zf + 1, flat: true) { _, _, _ in 0x7FC4E8 }
        let keyC = dark ? 0xC8CCD0 : 0x6F6D68
        for y in stride(from: dy1 - 4, to: dy0, by: -2) {
            for x in stride(from: px0, to: X, by: 2) { set(x, y, zf, keyC) }
        }
        // door release button at the bottom of the keypad
        if dy1 - dy0 >= 4 { box(px0, dy0 + 1, zf, X - (X - px0 >= 3 ? 1 : 0), dy0 + 2, zf + 1, dark ? 0x8F949A : 0x4A4845) }

        if otr {
            // vent slots across the top, handle along the door's opening edge
            if vent > 0 { box(0, Y - 1, zf, X, Y, zf + 1) { x, _, _ in x % 2 == 0 ? 0x3A3835 : shade(body, 0.9) } }
            box(1, dy1 - 2, zf + 1, wx1 - 1, dy1 - 1, zf + 2, dark ? P.metal : 0xB9BCBF)
        }
        // side vent slots (countertop models)
        if !otr && Z >= 6 {
            for z in stride(from: 2, to: zf - 1, by: 2) { set(X - 1, Y - 2, z, shade(body, 0.7)) }
        }
    }
}
