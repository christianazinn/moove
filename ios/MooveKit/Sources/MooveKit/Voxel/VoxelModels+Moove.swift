import Foundation

// OWNER: voxel-models agent. Pieces Moove's inventory has that MoveWise didn't model,
// written in the same style (palette, jitter, front at +z): fridges and other appliances,
// box and pedestal fans, bean bags, mirrors (optionally cracked), quilt racks and framed photos.

extension Canvas {
    // MARK: appliances

    func appliance(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("washer", "dryer", "washing machine", "laundry") { washer(X, Y, Z, name); return }
        if name.has("fridge", "refrigerator", "freezer") || D(Y) * voxelM >= 0.6 { fridge(X, Y, Z, name); return }
        countertopAppliance(X, Y, Z, name)
    }

    /// Fridge: white (or named color / stainless) cabinet, door on +z with a vertical handle,
    /// a freezer door on tall ones, condenser coils on the back, dark feet.
    func fridge(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = name.has("stainless") ? P.metal : colorFromName(name, P.white)
        let isDark = (((body >> 16) & 255) + ((body >> 8) & 255) + (body & 255)) < 300
        let seam = shade(body, 0.7)
        let handleC = isDark ? P.metal : 0xB9BCBF
        let zf = max(0, Z - 2) // door face (the handle sits one voxel proud of it)
        // feet
        for (fx, fz) in [(1, 1), (X - 2, 1), (1, zf - 1), (X - 2, zf - 1)] { set(fx, 0, fz, P.black) }
        let topC = shade(body, 0.96), backC = shade(body, 0.85), sideC = shade(body, 0.95)
        box(0, 1, 0, X, Y, zf + 1) { x, y, z in
            if y == Y - 1 { return topC }
            if z == 0 { return backC }
            if (x == 0 || x == X - 1) && z < zf { return sideC }
            return body
        }
        // condenser coils on the back
        for y in stride(from: 3, to: Y - 2, by: 2) { box(1, y, 0, X - 1, y + 1, 1, 0x3A3835) }
        let tall = Y >= 24
        // french doors on wide (>= 0.8 m) full-size fridges, from the scan
        let french = tall && (X >= 16 || name.has("french door", "side by side", "side-by-side"))
        let split = french ? rd(D(Y) * 0.3) : tall ? rd(D(Y) * 0.66) : Y - 1 - max(2, rd(D(Y) * 0.22))
        // door outline (gasket gap) and kick plate on the front face
        box(0, 1, zf, X, Y, zf + 1) { x, y, _ in
            if y == 1 { return x % 2 == 0 ? 0x3A3835 : 0x4A4845 } // kick plate vent
            if y == 2 || x == 0 || y == Y - 1 { return seam }
            if tall && y == split { return seam } // freezer / fridge doors
            if french && y > split && x == X / 2 { return seam } // french doors meet in the middle
            return nil
        }
        // handles on the opening side (+x), protruding toward +z
        let hx = X - 2
        if french {
            for fx in [X / 2 - 1, X / 2 + 1] { box(fx, split + 2, zf + 1, fx + 1, min(Y - 2, split + 2 + max(3, rd(D(Y) * 0.4))), zf + 2, handleC) }
            box(2, split - 2, zf + 1, X - 2, split - 1, zf + 2, handleC) // freezer drawer bar
        } else if tall {
            box(hx, split - max(2, rd(D(Y) * 0.25)), zf + 1, hx + 1, split - 1, zf + 2, handleC)
            box(hx, split + 2, zf + 1, hx + 1, min(Y - 2, split + 2 + max(2, rd(D(Y) * 0.12))), zf + 2, handleC)
        } else {
            box(hx, max(3, rd(D(Y) * 0.45)), zf + 1, hx + 1, min(Y - 2, rd(D(Y) * 0.8)), zf + 2, handleC)
            // mini fridges: a small freezer flap line inside the top of the door
            box(1, split, zf, X - 2, split + 1, zf + 1, shade(body, 0.85))
        }
        // brand badge
        set(X / 2, Y - 3, zf, isDark ? 0xB0B4B8 : 0x8F8D88, flat: true)
    }

    /// Washer / dryer: white cube, porthole door and control strip on the front.
    func washer(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, P.white)
        let zf = Z - 1
        box(0, 0, 0, X, Y, Z) { _, y, _ in y == 0 ? shade(body, 0.8) : y == Y - 1 ? shade(body, 0.96) : body }
        // control panel strip with a dial and a display
        let panel = max(1, rd(D(Y) * 0.15))
        box(0, Y - 1 - panel, zf, X, Y - 1, Z, shade(body, 0.9))
        set(X - 3, Y - 1 - (panel + 1) / 2, zf, P.charcoal)
        set(2, Y - 1 - (panel + 1) / 2, zf, 0x7FC4E8, flat: true)
        // porthole
        let cx = D(X - 1) / 2, cy = D(Y - 1 - panel) / 2
        let r = max(1.5, min(D(X) * 0.36, cy - 0.5))
        for y in upTo(1, Y - 1 - panel) {
            for x in upTo(1, X - 1) {
                let d = ((D(x) - cx) * (D(x) - cx) + (D(y) - cy) * (D(y) - cy)).squareRoot()
                if d > r { continue }
                if d > r - 1 { set(x, y, zf, 0xB9BCBF) } else { set(x, y, zf, d < r * 0.5 && x < rd(cx) ? 0x7E95A8 : 0x4A5A68, flat: true) }
            }
        }
    }

    /// Microwave / toaster / kettle-sized box: glass door window on the left, controls on the right.
    func countertopAppliance(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, name.has("stainless") ? P.metal : 0x3A3835)
        let zf = Z - 1
        box(0, 0, 0, X, Y, Z) { _, y, z in y == Y - 1 ? shade(body, 1.05) : z == 0 ? shade(body, 0.85) : body }
        let wx1 = max(2, rd(D(X) * 0.68))
        box(1, 1, zf, wx1, Y - 1, Z, flat: true) { x, y, _ in
            if x == 1 || x == wx1 - 1 || y == 1 || y == Y - 2 { return 0x5A5E62 }
            return (x - y) % 5 == 0 ? 0x3A4250 : 0x23272E
        }
        // display + buttons
        if X - wx1 >= 2 {
            set(wx1 + 1, Y - 2, zf, 0x7FC4E8, flat: true)
            for y in stride(from: Y - 4, to: 0, by: -2) { set(wx1 + 1, y, zf, 0xC8CCD0) }
        }
        // feet
        for fx in [0, X - 1] { set(fx, 0, 0, P.black); set(fx, 0, zf, P.black) }
    }

    // MARK: fans

    func fan(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("pedestal", "standing", "stand fan", "oscillating", "tower") || D(Y) > D(X) * 1.6 { pedestalFan(X, Y, Z, name); return }
        // box fan: square plastic frame, front and back grilles, five blades in the middle, a knob
        let frameC = colorFromName(name, 0xE4E1DA)
        let grille = shade(frameC, 0.72)
        let blade = 0x8FA3B0, hub = P.charcoal
        let cx = D(X - 1) / 2, cy = D(Y - 1) / 2
        let R = D(min(X, Y)) / 2 - 1
        let zm = Z / 2
        let frameHi = shade(frameC, 1.03)
        box(0, 0, 0, X, Y, Z) { x, y, z in
            if x == 0 || x == X - 1 || y == 0 || y == Y - 1 { return z == Z - 1 ? frameHi : frameC }
            if z == 0 || z == Z - 1 { return x % 2 == 0 || y % 3 == 0 ? grille : -1 }
            if Z >= 3 && z == zm {
                let dx = D(x) - cx, dy = D(y) - cy
                let r = (dx * dx + dy * dy).squareRoot()
                if r < 1.2 { return hub }
                if r < R && sin(5 * atan2(dy, dx) + r * 0.35) > 0.25 { return blade }
            }
            return -1
        }
        if Z <= 2 {
            // too thin for a blade layer: show the hub on the grille
            set(rd(cx), rd(cy), Z - 1, hub)
        }
        // speed knob on the top front corner
        set(X - 2, Y - 1, Z - 1, P.charcoal)
    }

    func pedestalFan(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, 0xE4E1DA)
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        let headR = max(2, min(D(X) / 2 - 0.5, D(Y) * 0.25))
        let hy = D(Y) - 1 - headR
        let zc = rd(cz) + (Z >= 4 ? 1 : 0) // cage plane, a little forward
        // weighted base + pole
        cyl(cx, cz, max(1, D(min(X, Z)) * 0.4), 0, 1, shade(body, 0.85))
        box(rd(cx), 1, rd(cz), rd(cx) + 1, rd(hy), rd(cz) + 1, shade(body, 0.92))
        // motor housing behind the cage
        box(rd(cx) - 1, rd(hy) - 1, max(0, zc - 2), rd(cx) + 1, rd(hy) + 1, zc, body)
        // cage ring, spokes and blades in the plane z = zc
        for y in upTo(0, Y) {
            for x in upTo(0, X) {
                let dx = D(x) - cx, dy = D(y) - hy
                let r = (dx * dx + dy * dy).squareRoot()
                if r > headR { continue }
                let a = atan2(dy, dx)
                if r > headR - 1 { set(x, y, zc, body) } else if r < 1 { set(x, y, zc, P.charcoal) } else if sin(4 * a + r * 0.4) > 0.3 {
                    set(x, y, zc, 0x9FC1D6)
                } else if sin(8 * a) > 0.92 && zc + 1 < Z {
                    set(x, y, zc + 1, shade(body, 0.8)) // front grille spokes
                }
            }
        }
    }

    // MARK: soft seating

    /// Bean bag: a slumped pear-shaped blob, taller at the back (low z), a seat hollow toward +z,
    /// and soft panel seams.
    func beanBag(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let fab = colorFromName(name, P.mustard)
        let seamC = shade(fab, 0.84), lowC = shade(fab, 0.8), hiC = shade(fab, 1.05)
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        let rx = D(X) / 2, rz = D(Z) / 2
        // seat hollow: an ellipsoid pressed into the front-top
        let sy = D(Y) * 1.05, sz = cz + D(Z) * 0.2
        let srx = D(X) * 0.36, sry = D(Y) * 0.5, srz = D(Z) * 0.42
        for y in upTo(0, Y) {
            let t = (D(y) + 0.5) / D(Y)
            // radius profile: rounded foot, full belly, tapering to a soft top
            let foot = t < 0.15 ? 0.84 + t : 1.0
            let taper = 1.0 - pow(max(0, t - 0.3) / 0.75, 2)
            let allowed = min(foot, taper)
            if allowed <= 0 { continue }
            for z in upTo(0, Z) {
                for x in upTo(0, X) {
                    let nx = (D(x) - cx) / rx, nz = (D(z) - cz) / rz
                    // the back (low z) stands taller than the front
                    let lean = 1.0 - max(0, nz) * 0.35 * t
                    let rr = (nx * nx + nz * nz).squareRoot()
                    if rr > allowed * lean { continue }
                    let ex = (D(x) - cx) / srx, ey = (D(y) - sy) / sry, ez = (D(z) - sz) / srz
                    if ex * ex + ey * ey + ez * ez < 1 { continue }
                    let ang = atan2(nz, nx)
                    var c = fab
                    if y == 0 { c = lowC } else if abs(sin(ang * 3)) < 0.1 && rr > 0.25 { c = seamC } else if t > 0.7 { c = hiC }
                    set(x, y, z, c)
                }
            }
        }
    }

    // MARK: wall pieces

    /// Mirror: framed glass facing +z with a diagonal glint; "broken"/"cracked" adds an impact
    /// point with radiating cracks.
    func mirror(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let frameC = name.word("black") ? P.black : name.word("white") ? P.white
            : name.has("oak", "wood", "pine", "walnut", "birch") ? colorFromName(name, P.oak) : P.brass
        let t = min(Z, 2)
        let zf = t - 1
        let frameDark = shade(frameC, 0.9)
        box(0, 0, 0, X, Y, t) { x, y, z in
            if x == 0 || x == X - 1 || y == 0 || y == Y - 1 { return (x + y) % 3 == 0 ? frameDark : frameC }
            return z == zf ? nil : P.kraft
        }
        // glass (flat: no jitter), lighter toward the top, with diagonal glints
        let topY = D(Y) * 0.7
        box(1, 1, zf, X - 1, Y - 1, zf + 1, flat: true) { x, y, _ in
            if (x - y) % 7 == 0 || (X >= 10 && (x - y) % 7 == 1) { return 0xC9DCE8 }
            return D(y) > topY ? 0xB4CCDB : 0xA9C4D6
        }
        if name.has("round", "circle", "circular", "oval") {
            // round / oval: clear everything outside the ellipse, frame ring on its edge
            let cx = D(X - 1) / 2, cy = D(Y - 1) / 2, rx = D(X) / 2, ry = D(Y) / 2
            for y in upTo(0, Y) {
                for x in upTo(0, X) {
                    let e = ((D(x) - cx) / rx) * ((D(x) - cx) / rx) + ((D(y) - cy) / ry) * ((D(y) - cy) / ry)
                    if e > 1 { for z in upTo(0, t) { clear(x, y, z) } } else if e > 0.72 { for z in upTo(0, t) { set(x, y, z, frameC) } }
                }
            }
        }
        // cracked when the name says so or the condition is very poor
        guard name.has("broken", "crack", "shatter", "smash") || wear >= 2.5 else { return }
        // cracks radiating from an impact point
        let ix = rd(D(X) * 0.62), iy = rd(D(Y) * 0.58)
        let crack = 0x5A6B77, hole = 0x2B3238
        let rays = 6
        for k in 0..<rays {
            let a = D(k) * 2 * Double.pi / D(rays) + rand() * 0.8
            let len = D(max(X, Y)) * (0.3 + 0.45 * rand())
            var x = D(ix), y = D(iy)
            let steps = max(1, rd(len))
            var dirA = a
            for s in 0..<steps {
                x += cos(dirA); y += sin(dirA)
                let px = rd(x), py = rd(y)
                guard px >= 1, px < X - 1, py >= 1, py < Y - 1 else { break }
                set(px, py, zf, crack, flat: true)
                if s % 3 == 2 { dirA += (rand() - 0.5) * 0.7 } // jagged
            }
        }
        // shattered center
        set(ix, iy, zf, hole, flat: true)
        if X >= 8 && Y >= 8 { set(ix + 1, iy, zf, hole, flat: true); set(ix, iy - 1, zf, hole, flat: true) }
    }

    /// Framed photo(s): wood frame, cream mat, one or two little snapshots of people on a sunny day.
    func framedPhotos(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let frameC = name.word("black") ? P.black : name.word("white") ? P.white : name.has("gold", "gilt") ? P.brass : P.walnut
        let t = min(Z, 2)
        let zf = t - 1
        let mat = X >= 8 && Y >= 8 ? 1 : 0
        let ix0 = 1 + mat, iy0 = 1 + mat
        let iw = X - 2 - 2 * mat, ih = Y - 2 - 2 * mat
        let collage = iw >= 10
        let photoW = collage ? (iw - 1) / 2 : iw
        let shirts = [P.navy, P.rust, P.sage, P.mustard, P.blush]
        let pick = Int(seed % 5)
        let frameDark = shade(frameC, 0.9)
        func photo(_ px: Int, _ py: Int, _ w: Int, _ h: Int, _ k: Int) -> Int {
            let u = (D(px) + 0.5) / D(max(1, w)), v = (D(py) + 0.5) / D(max(1, h))
            // two people standing side by side
            let people = w >= 4 ? [w / 3, (2 * w) / 3] : [w / 2]
            for (n, cxp) in people.enumerated() where px == cxp || (w >= 8 && px == cxp + 1) {
                let bodyTop = max(1, rd(D(h) * 0.5))
                if py < bodyTop { return shirts[(pick + n + k) % shirts.count] }
                if py == bodyTop || (h >= 10 && py == bodyTop + 1) { return 0xE3B796 } // face
                if py == bodyTop + 1 + (h >= 10 ? 1 : 0) && h >= 6 { return 0x4A3324 } // hair
            }
            if v < 0.22 { return k % 2 == 0 ? 0x9AAB83 : 0xD8C7A8 } // grass or sand
            if (u - 0.8) * (u - 0.8) + (v - 0.85) * (v - 0.85) < 0.02 { return 0xF2C46D } // sun
            return mix(0xCFE0EA, 0x8FB3C9, v)
        }
        box(0, 0, 0, X, Y, t) { x, y, z in
            if x == 0 || x == X - 1 || y == 0 || y == Y - 1 { return (x + y) % 3 == 0 ? frameDark : frameC }
            if z != zf { return P.kraft }
            let lx = x - ix0, ly = y - iy0
            if lx < 0 || ly < 0 || lx >= iw || ly >= ih { return 0xF4EFE4 } // mat
            if collage {
                if lx == photoW { return 0xF4EFE4 } // mat between the two photos
                return lx < photoW ? photo(lx, ly, photoW, ih, 0) : photo(lx - photoW - 1, ly, iw - photoW - 1, ih, 1)
            }
            return photo(lx, ly, iw, ih, 0)
        }
    }

    // MARK: quilt rack

    /// Wooden quilt rack: two trestle ends joined by three rails, a patchwork quilt draped over the
    /// top rail and hanging down the front (+z) and back.
    func quiltRack(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let w = colorFromName(name, P.walnut)
        let zc = Z / 2
        // trestle ends
        for ex in [0, X - 1] {
            wood(ex, 0, 0, ex + 1, 1, Z, shade(w, 0.9), .z) // foot
            wood(ex, 1, zc, ex + 1, Y - 1, zc + 1, w, .y) // upright
            if Z >= 5 { // splayed braces
                line(D(ex), D(Y) * 0.25, D(zc), D(ex), 1, 0, shade(w, 0.92))
                line(D(ex), D(Y) * 0.25, D(zc), D(ex), 1, D(Z - 1), shade(w, 0.92))
            }
            set(ex, Y - 1, zc, shade(w, 1.08)) // turned finial
        }
        // rails
        let railTop = Y - 2
        for ry in [railTop, rd(D(Y) * 0.55), rd(D(Y) * 0.22)] { wood(1, ry, zc, X - 1, ry + 1, zc + 1, w, .x) }

        // quilt
        let qx0 = X >= 8 ? 2 : 1, qx1 = X >= 8 ? X - 2 : X - 1
        let ps = X >= 16 ? 3 : 2
        let patches = [P.sage, P.blush, P.mustard, P.navy, P.cream, P.rust, 0x7E95A8, P.terracotta]
        let binding = shade(P.rust, 0.9)
        let s = seed
        let frontBottom = max(1, rd(D(Y) * 0.3)), backBottom = max(1, rd(D(Y) * 0.45))
        func quiltColor(_ x: Int, _ u: Int, _ side: Int, _ bottom: Bool) -> Int {
            if x == qx0 || x == qx1 - 1 || bottom { return binding }
            let h = hash3(x / ps, u / ps, side, s)
            return patches[min(patches.count - 1, Int(h * D(patches.count)))]
        }
        // over the top rail
        for x in upTo(qx0, qx1) {
            for z in thru(zc - 1, zc + 1) { set(x, Y - 1, z, quiltColor(x, 0, 0, false)) }
        }
        guard zc + 1 < Z else { return }
        // front drop with soft folds near the hem
        for y in upTo(frontBottom, Y - 1) {
            for x in upTo(qx0, qx1) {
                let fold = y < frontBottom + 2 && (x / (ps * 2)) % 2 == 0 && zc + 2 < Z ? 1 : 0
                set(x, y, zc + 1 + fold, quiltColor(x, Y - 1 - y, 0, y == frontBottom))
            }
        }
        // back drop
        if zc - 1 >= 0 {
            for y in upTo(backBottom, Y - 1) {
                for x in upTo(qx0, qx1) { set(x, y, zc - 1, quiltColor(x, Y - 1 - y, 1, y == backBottom)) }
            }
        }
    }
}
