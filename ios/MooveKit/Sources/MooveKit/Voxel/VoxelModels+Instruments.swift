import Foundation

// OWNER: voxel-models agent (#183). Musical instruments in the house style (palette, jitter,
// front at +z): guitars (acoustic / electric / bowed / in a case) on a stand, upright and grand
// pianos, keyboards on an X-stand (or a digital-piano cabinet), and drum kits.

extension Canvas {
    // MARK: guitar

    /// Guitar standing on an A-frame stand, face toward +z: an acoustic (two bouts, sound hole,
    /// bridge), an electric ("electric", "strat", "les paul", "bass": a double-cutaway solid body
    /// with pickups and a pickguard), a bowed instrument ("violin", "cello": f-holes, a black
    /// fingerboard and a scroll) or a closed case ("case", "gig bag").
    func guitar(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let bowed = name.word("violin", "violins", "viola", "cello", "cellos", "fiddle") || name.has("double bass", "upright bass")
        let electric = !bowed && (name.has("electric", "strat", "les paul", "telecaster", "flying v", "stratocaster") || name.word("bass"))
        let cased = name.word("case", "gigbag") || name.has("gig bag", "hard case")
        let stand = !cased && Z >= 3
        let cx = D(X - 1) / 2
        let rMax = max(1.5, D(X) / 2)

        let bodyT = cased ? clamp(Z - (Z >= 3 ? 1 : 0), 1, 3) : electric ? 1 : clamp(rd(D(Z) * 0.4), 1, 3)
        let zg = stand ? clamp((Z - bodyT) / 2 + 1, 1, max(1, Z - bodyT)) : max(0, (Z - bodyT) / 2)
        let zf = min(Z - 1, zg + bodyT - 1) // front face
        let y0 = stand ? 1 : 0
        let headH = max(2, rd(D(Y) * (bowed ? 0.08 : 0.12)))
        let bodyH = max(4, rd(D(Y - y0) * (bowed && name.has("cello", "bass") ? 0.55 : electric ? 0.42 : 0.47)))
        let neckW = X >= 12 ? 2 : 1
        let nx0 = (X - neckW) / 2
        let neckTop = Y - headH

        // two bouts (acoustic / bowed) or one rounded slab with cutaway horns (electric)
        let yL = D(y0) + D(bodyH) * 0.3, ryL = D(bodyH) * 0.3 + 0.5
        let yU = D(y0) + D(bodyH) * 0.74, ryU = D(bodyH) * 0.26 + 0.3, rxU = rMax * (bowed ? 0.8 : 0.78)
        let yc = D(y0) + D(bodyH) * 0.45, ryC = D(bodyH) * 0.5 + 0.3
        func inBody(_ x: Int, _ y: Int) -> Bool {
            guard y >= y0 && y < y0 + bodyH && x >= 0 && x < X else { return false }
            let dx = D(x) - cx
            if electric {
                let e = (dx / rMax) * (dx / rMax) + ((D(y) - yc) / ryC) * ((D(y) - yc) / ryC)
                if e > 1 { return false }
                // the gap between the two horns, beside the neck
                if D(y) > yc + ryC * 0.35 && abs(dx) < rMax * 0.5 && abs(dx) > D(neckW) / 2 + 0.6 { return false }
                return true
            }
            let l = (dx / rMax) * (dx / rMax) + ((D(y) - yL) / ryL) * ((D(y) - yL) / ryL)
            let u = (dx / rxU) * (dx / rxU) + ((D(y) - yU) / ryU) * ((D(y) - yU) / ryU)
            return l <= 1 || u <= 1
        }

        if cased {
            // a hard case (or gig bag) in the instrument's outline, slightly fatter, with latches and a handle
            let caseC = colorFromName(name, 0x232220)
            let seamC = shade(caseC, 0.7)
            func inCase(_ x: Int, _ y: Int) -> Bool {
                if inBody(x, y) || inBody(x - 1, y) || inBody(x + 1, y) || inBody(x, y - 1) { return true }
                return y >= y0 && y < Y && x >= nx0 - 1 && x <= nx0 + neckW
            }
            for y in upTo(0, Y) {
                for x in upTo(0, X) where inCase(x, y) {
                    for z in upTo(zg, zg + bodyT) { set(x, y, z, z == zg + bodyT / 2 && bodyT >= 2 ? seamC : caseC) }
                }
            }
            for x in [rd(cx - rMax * 0.6), rd(cx + rMax * 0.6)] where inCase(x, y0 + 1) { set(x, y0 + 1, zf, P.metal) }
            let hy = rd(yU)
            if zf + 1 < Z { box(rd(cx) - 1, hy, zf + 1, rd(cx) + 2, hy + 1, zf + 2, P.black) }
            return
        }

        let paints = [0xB8282A, 0x1F1F21, 0xE9E3D2, 0x3D6FA8, 0xC77A2E]
        let topC: Int
        if bowed { topC = colorFromName(name, 0x8A4A22) } else if electric { topC = colorFromName(name, paints[Int(seed % UInt32(paints.count))]) } else { topC = colorFromName(name, 0xD9B47A) }
        let sunburst = !bowed && (name.has("sunburst") || (name.primary == nil && seed % 3 == 0))
        let sideC = bowed ? shade(topC, 0.85) : electric ? shade(topC, 0.85) : 0x7A4A2A
        let binding = bowed ? shade(topC, 0.7) : P.cream

        // body
        for y in upTo(y0, y0 + bodyH) {
            for x in upTo(0, X) where inBody(x, y) {
                let edge = !inBody(x - 1, y) || !inBody(x + 1, y) || !inBody(x, y - 1) || !inBody(x, y + 1)
                for z in upTo(zg, zf + 1) {
                    var c = z == zf ? topC : sideC
                    if z == zf && edge && !electric { c = binding }
                    if z == zf && !edge && sunburst {
                        // darker toward the rim
                        let dl = ((D(x) - cx) / rMax) * ((D(x) - cx) / rMax) + ((D(y) - (electric ? yc : yL)) / (electric ? ryC : ryL)) * ((D(y) - (electric ? yc : yL)) / (electric ? ryC : ryL))
                        c = mix(topC, 0x3A1E10, clampD(dl * 0.9 - 0.2, 0, 0.8))
                    }
                    set(x, y, z, c)
                }
            }
        }

        let neckStart: Int
        if electric {
            neckStart = rd(yc + ryC * 0.2)
            // pickguard on the lower half, two pickups across the neck line, bridge, knobs
            let guardC: Int? = name.has("les paul") ? nil : seed % 2 == 0 ? 0xEDE8DC : 0x1F1F21
            if let g = guardC {
                for y in thru(rd(yc - ryC * 0.55), rd(yc + ryC * 0.25)) {
                    for x in upTo(0, rd(cx) + 1) where inBody(x, y) && inBody(x - 1, y) && inBody(x, y - 1) && inBody(x, y + 1) { set(x, y, zf, g) }
                }
            }
            for py in [rd(yc - ryC * 0.05), rd(yc + ryC * 0.28)] { box(nx0 - 1, py, zf, nx0 + neckW + 1, py + 1, zf + 1, 0x1A1A1C) }
            box(nx0 - 1, rd(yc - ryC * 0.42), zf, nx0 + neckW + 1, rd(yc - ryC * 0.42) + 1, zf + 1, P.metal)
            let kx = clamp(rd(cx + rMax * 0.5), 0, X - 1)
            for ky in [rd(yc - ryC * 0.6), rd(yc - ryC * 0.35)] where inBody(kx, ky) { set(kx, ky, zf, 0xE4E1DA) }
        } else if bowed {
            neckStart = rd((yL + yU) / 2)
            // f-holes either side of the waist, tailpiece, a bridge standing proud
            for fx in [rd(cx - rMax * 0.45), rd(cx + rMax * 0.45)] {
                for y in thru(rd(yL), rd(yU - ryU * 0.3)) where inBody(fx, y) { set(fx, y, zf, 0x24180F, flat: true) }
            }
            box(nx0, y0 + 1, zf, nx0 + neckW, rd(yL), zf + 1, 0x1A1A1C)
            if zf + 1 < Z { box(nx0 - 1, rd(yL) + 1, zf + 1, nx0 + neckW + 1, rd(yL) + 2, zf + 2, P.cream) }
        } else {
            neckStart = rd(yU)
            // sound hole with a rosette, bridge below it
            let hy = yU - ryU * 0.25, hr = max(0.8, rxU * 0.38)
            for y in thru(fl(hy - hr - 1), ce(hy + hr + 1)) {
                for x in thru(fl(cx - hr - 1), ce(cx + hr + 1)) {
                    let d = ((D(x) - cx) * (D(x) - cx) + (D(y) - hy) * (D(y) - hy)).squareRoot()
                    if d < hr { set(x, y, zf, 0x24180F, flat: true) } else if d < hr + 0.7 && hr >= 1.2 && inBody(x, y) { set(x, y, zf, 0xC9A875) }
                }
            }
            box(rd(cx - rMax * 0.35), rd(yL), zf, rd(cx + rMax * 0.35) + 1, rd(yL) + 1, zf + 1, 0x2E2219)
        }

        // neck + fretboard (frets and inlays), headstock with tuners
        let boardC = bowed ? 0x1A1A1C : electric && name.has("maple", "strat", "telecaster") ? 0xD9BF94 : 0x2E2219
        let neckBackC = bowed ? shade(topC, 0.9) : 0xB98A5A
        for y in upTo(neckStart, neckTop) {
            let k = y - neckStart
            for x in upTo(nx0, nx0 + neckW) {
                var c = boardC
                if !bowed && k % 3 == 2 { c = 0x8F8D88 }
                if !bowed && k % 6 == 4 && x == nx0 { c = P.cream }
                set(x, y, zf, c)
                if zf - 1 >= zg && y >= y0 + bodyH { set(x, y, zf - 1, neckBackC) }
            }
        }
        let headC = bowed ? shade(topC, 0.9) : electric ? (boardC == 0xD9BF94 ? boardC : topC) : 0x3A2416
        box(max(0, nx0 - 1), neckTop, zf, min(X, nx0 + neckW + 1), Y, zf + 1, headC)
        if bowed {
            set(rd(cx), Y - 1, min(Z - 1, zf + 1), headC) // the scroll curls forward
        } else {
            for y in stride(from: neckTop, to: Y, by: 2) {
                set(nx0 - 2, y, zf, P.metal)
                if !electric { set(nx0 + neckW + 1, y, zf, P.metal) }
            }
        }
        // strings over the fretboard, standing proud of it
        if zf + 1 < Z {
            let sx = rd(cx)
            let sy0 = electric ? rd(yc - ryC * 0.42) : bowed ? rd(yL) + 1 : rd(yL)
            for y in upTo(sy0, neckTop) where !(bowed && y == rd(yL) + 1) { set(sx, y, zf + 1, 0xD8D8D0, flat: true) }
        }

        // A-frame stand: two feet, a cradle under the body and a post up the back to a yoke
        if stand {
            let blackC = P.black
            let fxA = clamp(rd(cx - rMax * 0.7), 0, X - 1), fxB = clamp(rd(cx + rMax * 0.7), 0, X - 1)
            for fx in [fxA, fxB] { box(fx, 0, 0, fx + 1, 1, Z, blackC) }
            box(fxA, 0, max(0, zg - 1), fxB + 1, 1, min(Z, zf + 2), blackC)
            let yokeY = clamp(rd(D(Y) * 0.66), y0 + 2, max(y0 + 2, neckTop - 1))
            line(D(rd(cx)), 0, 0, D(rd(cx)), D(yokeY), D(zg - 1), blackC)
            set(nx0 - 1, yokeY, zf, blackC)
            set(nx0 + neckW, yokeY, zf, blackC)
        }
    }

    // MARK: piano

    /// Upright piano: polished black case (or the name's wood / color), keys on a key bed that
    /// sticks out toward +z between two cheeks, the fallboard behind them, molded panels above
    /// and below, brass pedals and (sometimes) sheet music on the desk. The lid is a prop surface.
    /// "grand" (or a deep, square footprint) builds a grand piano instead.
    func piano(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("grand") || (Z >= 24 && D(Z) >= D(X) * 0.8 && !name.has("upright")) { grandPiano(X, Y, Z, name); return }
        let caseC = colorFromName(name, 0x1A1A1C)
        let trim = isDarkColor(caseC) ? mix(caseC, 0xFFFFFF, 0.12) : shade(caseC, 0.82)
        let zc = clamp(rd(D(Z) * 0.55), 2, Z - 2) // cabinet depth; the keys stick out in front
        let kb = clamp(vox(0.74), 3, Y - 4) // first layer above the keys

        // polished lacquer: flat color, no per-voxel jitter (keeps the mesh small too)
        box(0, 0, 0, X, Y, zc, caseC, flat: true)
        box(0, Y - 1, 0, X, Y, zc, shade(caseC, 1.06), flat: true) // lid
        // molded panels on the front, above and below the keys
        box(0, 1, zc - 1, X, Y - 1, zc) { x, y, _ in
            let upper = y > kb + 1 && y < Y - 1, lower = y < kb - 3 && y > 0
            if (upper && (y == kb + 2 || y == Y - 2)) || (lower && (y == 1 || y == kb - 4)) { return trim }
            if (upper || lower) && (x == 1 || x == X - 2) { return trim }
            return nil
        }
        // key bed, cheeks, toe blocks
        box(1, kb - 2, zc, X - 1, kb - 1, Z, caseC)
        for x in [0, X - 1] {
            box(x, kb - 3, zc, x + 1, kb + 1, Z, caseC)
            box(x, 0, zc, x + 1, 1, Z, caseC)
            if Z - zc >= 3 { box(x, 1, Z - 2, x + 1, kb - 3, Z - 1, caseC) } // front legs
        }
        pianoKeys(1, X - 1, kb - 1, zc, Z)
        box(1, kb, zc, X - 1, kb + 1, zc + 1, trim) // fallboard
        for dx in -1...1 { set(X / 2 + dx, kb, zc, P.brass, flat: true) }
        // pedals
        for dx in [-2, 0, 2] { set(X / 2 + dx, 0, zc, P.brass) }
        // music desk and sometimes a sheet of music
        if kb + 7 < Y - 1 {
            box(X / 4, kb + 3, zc, X - X / 4, kb + 4, zc + 1, caseC)
            if rand() < 0.6 {
                box(X / 2 - 2, kb + 4, zc, X / 2 + 2, kb + 7, zc + 1, flat: true) { x, y, _ in (x + y) % 3 == 0 ? 0x3A3835 : 0xF4F1EA }
            }
        }
        surface(0, 0, X, zc, Y)
    }

    /// One voxel per white key across [x0, x1) on layer y, from z0 to the front; black keys on the
    /// back half in the 2 + 3 pattern.
    func pianoKeys(_ x0: Int, _ x1: Int, _ y: Int, _ z0: Int, _ z1: Int) {
        let back = z0 + max(1, (z1 - z0) / 2)
        box(x0, y, z0, x1, y + 1, z1, flat: true) { x, _, z in
            let k = (x - x0) % 7
            if z < back && [1, 2, 4, 5, 6].contains(k) { return 0x161616 }
            return 0xF2EFE6
        }
    }

    /// Grand piano: the curved case (straight bass side at x = 0, the tail narrowing toward the
    /// back) on three legs, keys across the front (+z), a lyre with brass pedals underneath.
    func grandPiano(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let caseC = colorFromName(name, 0x1A1A1C)
        let lidC = shade(caseC, 1.06)
        let legH = clamp(rd(D(Y) * 0.6), 2, Y - 3)
        let topY = Y - 1
        let kd = clamp(rd(D(Z) * 0.16), 2, 5)
        let bodyZ1 = Z - kd
        func width(_ z: Int) -> Int {
            let t = D(z) / D(max(1, bodyZ1 - 1))
            return clamp(rd(D(X) * (0.38 + 0.62 * pow(t, 0.55))), 2, X)
        }
        for z in upTo(0, bodyZ1) {
            let w = width(z)
            box(0, legH, z, w, Y, z + 1, flat: true) { _, y, _ in y == topY ? lidC : caseC }
        }
        // keys at the front, between cheeks, with the fallboard against the case
        let kbY = min(topY - 1, legH + 2)
        box(0, legH, bodyZ1, X, kbY, Z, caseC)
        for x in [0, X - 1] { box(x, legH, bodyZ1, x + 1, kbY + 1, Z, caseC) }
        pianoKeys(1, X - 1, kbY, bodyZ1, Z)
        if kbY + 1 < Y { box(1, kbY + 1, bodyZ1, X - 1, kbY + 2, bodyZ1 + 1, mix(caseC, 0xFFFFFF, 0.12)) }
        // legs on brass casters
        let lw = X >= 24 ? 2 : 1
        let tailX = max(0, width(1) / 2 - 1)
        for (lx, lz) in [(0, bodyZ1 - 2), (X - lw, bodyZ1 - 2), (tailX, 1)] {
            box(lx, 1, lz, lx + lw, legH, lz + 1, caseC)
            set(lx, 0, lz, P.brass)
        }
        // lyre with three pedals
        let mx = X / 2
        for x in [mx - 1, mx + 1] { box(x, 1, bodyZ1 - 2, x + 1, legH, bodyZ1 - 1, caseC) }
        for dx in -1...1 { set(mx + dx, 1, bodyZ1 - 1, P.brass) }
    }

    // MARK: keyboard

    /// Keyboard on an X-stand: a slab with keys on the front of its top, a control strip behind
    /// them (screen, knobs on synths, speaker grilles on portable keyboards). Short items are just
    /// the keyboard; "digital piano" stands on its own side panels with pedals and a music rest.
    func keyboardInstrument(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let digital = name.has("digital piano", "console piano")
        let synth = name.has("synth", "moog", "korg", "nord", "workstation", "midi", "controller", "keytar")
        let caseC = colorFromName(name, name.has("nord") ? 0xB8282A : 0x1E1E20)
        let onStand = Y >= 6
        let kh = onStand ? (Y >= 8 ? 2 : 1) : min(Y, 3)
        let sy0 = digital ? min(Y - kh, clamp(vox(0.72), 1, Y - kh)) : onStand ? Y - kh : 0
        let sd = clamp(vox(0.32), min(3, Z), Z)
        let sz0 = (Z - sd) / 2, sz1 = sz0 + sd
        let topY = sy0 + kh - 1
        // on a table or the floor a keyboard stands on four rubber feet
        let feet = sy0 == 0 && kh >= 2
        box(0, feet ? 1 : sy0, sz0, X, sy0 + kh, sz1, caseC)
        if feet { for (fx, fz) in [(1, sz0), (X - 2, sz0), (1, sz1 - 1), (X - 2, sz1 - 1)] { set(fx, 0, fz, P.black) } }
        // controls at the back of the top, keys in front
        let cd = clamp(rd(D(sd) * 0.35), 1, 3)
        box(0, topY, sz0, X, topY + 1, sz0 + cd, shade(caseC, 0.85))
        pianoKeys(1, X - 1, topY, sz0 + cd, sz1)
        let mx = X / 2, cz = sz0 + cd / 2
        box(mx - 1, topY, cz, mx + 2, topY + 1, cz + 1, 0x7FC4E8, flat: true) // display
        if synth {
            for x in stride(from: 1, to: max(1, mx - 2), by: 2) { set(x, topY, cz, 0xC8CCD0) }
            set(1, topY, sz0 + cd, 0x3A3835) // pitch wheel
        } else if X >= 12 {
            for x in upTo(1, X / 5) where x % 2 == 1 { set(x, topY, cz, 0x111111); set(X - 1 - x, topY, cz, 0x111111) } // speaker grilles
        }
        guard sy0 > 0 else { return }
        let standC = P.charcoal
        if digital {
            // side panels to the floor with feet forward, a back panel, pedals, a music rest
            for x in [0, X - 1] {
                box(x, 0, sz0, x + 1, sy0, sz1, caseC)
                box(x, 0, sz0, x + 1, 1, Z, caseC)
            }
            box(1, 2, sz0, X - 1, sy0, sz0 + 1, shade(caseC, 0.9))
            for dx in [-1, 0, 1] { set(mx + dx, 1, sz0 + 1, P.brass) }
            if topY + 3 < Y { box(X / 4, topY + 1, sz0, X - X / 4, min(Y, topY + 4), sz0 + 1, caseC) }
            return
        }
        // X-stand: two crossed legs in the yz plane, support arms under the slab
        let xa = rd(D(X) * 0.22), xb = X - 1 - xa
        for x in [xa, xb] {
            line(D(x), 0, 0, D(x), D(sy0 - 1), D(Z - 1), standC)
            line(D(x), 0, D(Z - 1), D(x), D(sy0 - 1), 0, standC)
            set(x, 0, 0, P.black); set(x, 0, Z - 1, P.black)
            box(x, sy0 - 1, sz0, x + 1, sy0, sz1, standC)
        }
    }

    // MARK: drums

    /// Drum kit seen from the audience (+z): the bass drum with its logo head in front, two rack
    /// toms on top of it, the snare and hi-hat on the left, the floor tom and a crash cymbal on the
    /// right, the throne at the back. "electronic" builds a rack of pads instead.
    func drums(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        if name.has("electronic", "e-kit", "edrum", "e-drum", "digital", "v-drums", "roland", "alesis") { eDrums(X, Y, Z, name); return }
        let wraps = [0xA8282A, 0x1F1F21, 0xE9E3D2, 0x3D6FA8, 0x8A5A3A]
        let shell = colorFromName(name, wraps[Int(seed % UInt32(wraps.count))])
        let head = 0xEEEAE0, hoop = P.metal, brass = 0xC9A24A, standC = 0x7E8287
        let cx = D(X - 1) / 2

        // bass drum: a horizontal cylinder along z
        let R = clampD(D(min(X, Y)) * 0.22, 2, 6)
        let bz1 = Z - 1, bz0 = max(0, Z - 1 - clamp(rd(D(Z) * 0.35), 2, 8))
        let bcy = R - 0.5
        for y in thru(0, min(Y - 1, ce(2 * R))) {
            for x in thru(max(0, fl(cx - R)), min(X - 1, ce(cx + R))) {
                let d = ((D(x) - cx) * (D(x) - cx) + (D(y) - bcy) * (D(y) - bcy)).squareRoot()
                if d > R { continue }
                for z in thru(bz0, bz1) {
                    let end = z == bz0 || z == bz1
                    let c: Int
                    if d > R - 1 { c = end ? hoop : shell } else if z == bz1 { c = d > R * 0.35 && d < R * 0.6 ? shell : head } else { c = end ? head : shell }
                    set(x, y, z, c)
                }
            }
        }
        for s in [-1.0, 1.0] { line(cx + s * R, bcy, D(bz1 - 1), cx + s * (R + 1), 0, D(bz1), hoop) } // spurs

        func drum(_ dcx: Double, _ dcz: Double, _ r: Double, _ y0: Int, _ y1: Int) {
            cyl(dcx, dcz, r, y0, y1) { _, y, _, d2 in
                if y == y1 - 1 { return d2 > (r - 1) * (r - 1) ? hoop : head }
                return y == y0 ? hoop : shell
            }
        }
        func tripod(_ px: Double, _ pz: Double, _ top: Int, _ spread: Double) {
            line(px, D(top), pz, px, 0, pz, standC)
            line(px, D(top) * 0.3, pz, px - spread, 0, pz + spread * 0.5, standC)
            line(px, D(top) * 0.3, pz, px + spread, 0, pz + spread * 0.5, standC)
            line(px, D(top) * 0.3, pz, px, 0, pz - spread, standC)
        }
        func cymbal(_ px: Double, _ pz: Double, _ r: Double, _ y: Int) {
            guard y < Y else { return }
            tripod(px, pz, y - 1, max(1, r * 0.6))
            cyl(px, pz, r, y, y + 1, brass)
            if y + 1 < Y { set(rd(px), y + 1, rd(pz), brass) }
        }

        // rack toms on the bass drum
        let rt = max(1.2, R * 0.4)
        let ty0 = min(Y - 3, ce(2 * R))
        let tz = D(bz0 + bz1) / 2
        for s in [-1.0, 1.0] { drum(cx + s * R * 0.45, tz, rt, ty0, min(Y - 1, ty0 + max(2, rd(rt * 1.2)))) }
        // snare (left, toward the drummer) and floor tom (right)
        let rs = max(1.2, R * 0.45)
        let scx = max(rs, cx - R * 1.2), scz = max(rs, D(bz0) - rs * 0.5)
        let sy1 = min(Y - 2, vox(0.62)), sy0 = max(1, sy1 - max(2, rd(rs)))
        tripod(scx, scz, sy0, rs)
        drum(scx, scz, rs, sy0, sy1)
        let rf = max(1.5, R * 0.6)
        let fcx = min(D(X) - 1 - rf, cx + R + rf * 0.8), fcz = max(rf, D(bz0) - rf * 0.2)
        let fy1 = min(Y - 2, vox(0.55)), fy0 = max(1, fy1 - rd(rf * 1.6))
        for s in [-1.0, 1.0] { line(fcx + s * rf * 0.8, D(fy0), fcz, fcx + s * rf, 0, fcz, standC) }
        drum(fcx, fcz, rf, fy0, fy1)
        // hi-hat (two plates) on the left, crash on the right
        let rh = max(1.5, R * 0.55)
        let hx = max(rh, cx - R * 1.9), hz = max(rh, D(bz0) - rh)
        let hy = min(Y - 3, vox(0.85))
        cymbal(hx, hz, rh, hy)
        if hy + 2 < Y { cyl(hx, hz, rh, hy + 2, hy + 3, brass) }
        cymbal(min(D(X) - 1 - R * 0.75, cx + R * 1.4), max(R * 0.75, D(bz0) - 1), max(2, R * 0.75), min(Y - 2, vox(1.15)))
        // throne behind the kit
        if bz0 >= 5 {
            let tcz = 1.5, seatY = min(Y - 1, vox(0.5))
            tripod(cx, tcz, seatY - 1, 1.2)
            cyl(cx, tcz, 1.6, seatY, seatY + 1, P.black)
        }
    }

    /// Electronic kit: a pipe rack with black pads, cymbal pads above, a kick tower and a module.
    func eDrums(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let rackC = P.charcoal, pad = 0x232220, rim = 0x5A5E62
        let zr = Z / 2
        let barY = min(Y - 3, vox(0.75)), topBarY = min(Y - 1, vox(1.05))
        for x in [1, X - 2] {
            box(x, 0, max(0, zr - 2), x + 1, 1, min(Z, zr + 3), rackC)
            box(x, 1, zr, x + 1, topBarY + 1, zr + 1, rackC)
        }
        box(1, barY, zr, X - 1, barY + 1, zr + 1, rackC)
        box(1, topBarY, zr, X - 1, topBarY + 1, zr + 1, rackC)
        func padAt(_ px: Double, _ pz: Double, _ r: Double, _ y: Int) {
            guard y < Y else { return }
            cyl(px, pz, r, y, y + 1) { _, _, _, d2 in d2 > (r - 1) * (r - 1) ? rim : pad }
        }
        let n = max(2, min(4, X / 6))
        for i in 0..<n {
            let px = D(X) * (D(i) + 0.5) / D(n)
            padAt(px, D(zr) + 1.5, 1.6, barY + 1)
        }
        padAt(D(X) * 0.2, D(zr) - 1, 2, topBarY)
        padAt(D(X) * 0.8, D(zr) - 1, 2, topBarY)
        // kick tower in front, module on the rack
        box(X / 2 - 1, 0, min(Z - 2, zr + 2), X / 2 + 1, min(Y, 4), min(Z, zr + 4), pad)
        box(X - 4, barY + 1, zr, X - 2, barY + 3, zr + 1, 0x2A2A2C)
        set(X - 3, barY + 2, zr, 0x7FC4E8, flat: true)
    }
}
