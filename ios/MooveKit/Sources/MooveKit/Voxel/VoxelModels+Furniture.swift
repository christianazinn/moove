import Foundation

// OWNER: voxel-models agent. Large furniture, ported line by line from models.js
// (buildSofa, buildBed, buildMattress, buildDesk, buildOfficeChair, buildDiningChair,
// buildTable, buildDresser, buildBookshelf, buildTV, buildLamp).

extension Canvas {
    func sofa(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let fab = colorFromName(name, P.linen)
        let under = shade(fab, 0.78)
        let crease = shade(fab, 0.8)
        let legC = name.word("metal", "black") ? P.black : P.walnut
        // RoomPlan's SofaType wins, then name keywords, then the scanned size
        let single = attr("sofatype.singleseat"), lAttr = attr("sofatype.lshaped"), rect = attr("sofatype.rectangular")
        let seatsAsked = single ? 1 : name.number(before: ["seat", "person"], multiDigit: false)
        // a deep, wide scan is a sectional even when the name doesn't say so
        let isL = lAttr ? (X >= 16 && Z >= 14)
            : !rect && !single && (name.has("sectional", "l-shape", "l shape", "lshape", "corner", "chaise") || name.word("l")
                || (D(Z) * voxelM >= 1.4 && D(X) * voxelM >= 2.0)) && X >= 20 && Z >= 16
        // under ~1.15 m wide it is an armchair: one seat, chunkier arms
        let arm = single || (!rect && !lAttr && (name.has("armchair", "accent chair", "club chair", "lounge chair") || (D(X) * voxelM < 1.15 && seatsAsked == nil)))
        // leather / mid-century / chesterfield: tight back (one upholstered panel), no throw pillows
        let tight = name.has("leather", "tight back", "tight-back", "mid-century", "midcentury", "chesterfield", "tufted")
        let tufted = name.has("tufted", "chesterfield")
        let skirted = name.has("skirted", "slipcover", "skirt")

        let legH = skirted ? 0 : clamp(rd(D(Y) * 0.12), 1, 3)
        let baseTop = min(Y - 3, legH + max(1, rd(D(Y) * 0.14)))
        let seatTop = clamp(rd(D(Y) * 0.52), baseTop + 1, Y - 2)
        let armTop = clamp(rd(D(Y) * 0.74), seatTop + 1, Y - 1)
        let A = clamp(rd(D(X) * (arm ? 0.16 : 0.08)), 1, 4)
        let B = clamp(rd(D(Z) * 0.18), 1, 4)
        let bc = clamp(rd(D(Z) * 0.15), 1, 4)
        let mainD = isL ? clamp(max(vox(0.95), rd(D(Z) * 0.55)), B + bc + 4, Z - 3) : Z
        let chaiseW = isL ? clamp(rd(D(X) * 0.34), 6, X - 8) : 0
        let cx0 = X - chaiseW // chaise start x

        let foot = { (x: Int, z: Int) -> Bool in z < mainD || x >= cx0 }

        // legs (short, dark wood) at the corners of each footprint rectangle
        var legs = [(1, 1), (X - 2, 1), (1, mainD - 2), (X - 2, Z - 2)]
        if isL { legs += [(cx0 + 1, Z - 2), (cx0 - 2, mainD - 2)] } else { legs.append((X - 2, mainD - 2)) }
        if X > 34 && !isL { legs += [(X / 2, 1), (X / 2, Z - 2)] }
        if !skirted { for (lx, lz) in legs { box(lx, 0, lz, lx + 1, legH, lz + 1, legC) } }

        // base / frame
        box(0, legH, 0, X, baseTop, Z) { x, _, z in foot(x, z) ? under : nil }

        // back frame (full width), slightly lower than back cushions
        let backTop = clamp(rd(D(Y) * 0.84), armTop + 1, Y)
        box(0, legH, 0, X, backTop, B, fab)
        // round the back's top outer corners
        clear(0, backTop - 1, 0); clear(X - 1, backTop - 1, 0)

        // arms
        let armHi = shade(fab, 1.04), armFace = shade(fab, 0.93)
        let armFn: (Int, Int, Int) -> Int? = { _, y, _ in y == armTop - 1 ? armHi : fab }
        box(0, legH, 0, A, armTop, mainD, armFn)
        box(X - A, legH, 0, X, armTop, Z, armFn)
        // arm front faces: piping line
        box(0, legH, mainD - 1, A, armTop, mainD) { _, y, _ in y == armTop - 1 ? crease : armFace }
        box(X - A, legH, Z - 1, X, armTop, Z) { _, y, _ in y == armTop - 1 ? crease : armFace }
        // rounded arm tops (soft outer edge)
        for z in upTo(0, Z) {
            if z < mainD { clear(0, armTop - 1, z) }
            clear(X - 1, armTop - 1, z)
        }

        // seats
        let innerEnd = isL ? cx0 : X - A
        let innerW = innerEnd - A
        var nSeats = seatsAsked ?? max(1, rd(D(innerW) * voxelM / 0.62))
        if isL { nSeats = max(1, nSeats - 1) }
        nSeats = clamp(nSeats, 1, max(1, fdiv(innerW, 4)))
        var seatRanges: [(Int, Int, Int, Int)] = []
        for i in 0..<nSeats {
            seatRanges.append((A + rd(D(innerW * i) / D(nSeats)), A + rd(D(innerW * (i + 1)) / D(nSeats)), B, mainD))
        }
        if isL { seatRanges.append((cx0, X - A, B, Z)) }

        let cushion = shade(fab, 1.03), piping = shade(fab, 0.92)
        for (x0, x1, z0, z1) in seatRanges {
            box(x0, baseTop, z0, x1, seatTop, z1) { x, y, z in
                let edge = x == x0 || x == x1 - 1
                if y == seatTop - 1 && edge { return crease } // seam
                if z == z1 - 1 && y == seatTop - 1 { return piping } // front piping
                if z == z1 - 1 && y == baseTop { return crease }
                return cushion
            }
            // soft rounded front corners
            clear(x0, seatTop - 1, z1 - 1); clear(x1 - 1, seatTop - 1, z1 - 1)
        }
        // a worn sofa's most-used cushion sags
        if wear >= 1.5 && !seatRanges.isEmpty {
            let mid = seatRanges[seatRanges.count > 2 ? 1 : 0]
            if mid.1 - mid.0 >= 4 { box(mid.0 + 1, seatTop - 1, mid.2, mid.1 - 1, seatTop, mid.3 - 1, -1) }
        }

        if tight {
            // one continuous back panel, buttoned if tufted
            let bx1 = isL ? X - A : innerEnd
            box(A, seatTop, B, bx1, Y, B + bc) { x, y, z in
                if y == Y - 1 && z == B + bc - 1 { return nil }
                if tufted && z == B + bc - 1 && (x - A) % 3 == 1 && (y - seatTop) % 3 == 1 { return crease }
                return cushion
            }
            if tufted {
                // buttons on the arms' inner faces too
                for y in stride(from: seatTop + 1, to: armTop - 1, by: 3) { set(A - 1, y, mainD / 2, crease); set(X - A, y, mainD / 2, crease) }
            }
            return
        }

        // back cushions (one per seat)
        for (x0, x1, _, _) in seatRanges {
            box(x0, seatTop, B, x1, Y, B + bc) { x, y, z in
                if x == x0 || x == x1 - 1 { return y >= Y - 1 ? nil : crease }
                if y == Y - 1 && z == B + bc - 1 { return nil } // rounded top front
                return y < seatTop + 2 && z == B + bc - 1 ? crease : cushion
            }
        }

        // throw pillows
        let pw = clamp(rd(D(X) * 0.15), 2, 9)
        let ph = clamp(rd(D(Y - seatTop) * 0.85), 2, 9)
        let pz = B + bc
        func pillow(_ x0: Int, _ col: Int) {
            let edgeC = shade(col, 0.9)
            box(x0, seatTop, pz, x0 + pw, seatTop + ph, pz + 2) { x, y, z in
                let cx = x == x0 || x == x0 + pw - 1, cy = y == seatTop + ph - 1
                if cx && cy { return nil }
                if z == pz + 1 && (cx || cy || y == seatTop) { return edgeC }
                return col
            }
            // pillow piping/center tuft
            set(x0 + (pw >> 1), seatTop + (ph >> 1), pz + 1, shade(col, 0.82))
        }
        // pillow colors are a per-item detail (seeded), never the same as the fabric
        let (c1, c2) = accentPair(avoiding: fab)
        if innerW >= pw + 2 {
            pillow(A, c1)
            if isL { pillow(cx0 + 1, c2) } else if nSeats >= 2 { pillow(X - A - pw, c2) }
        }
    }

    func bed(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, _ topLimit: Int) {
        // frame style from the name / material: upholstered, metal, platform, plain wood (models.js)
        let upholstered = name.has("upholster", "fabric", "tufted", "velvet", "padded", "linen")
        let metal = !upholstered && name.has("metal", "iron", "steel", "brass")
        let platform = name.has("platform", "low profile", "low-profile", "floor bed", "japanese", "tatami")
        let footboard = name.has("footboard", "sleigh", "four poster", "four-poster", "canopy")
        let frameC = upholstered ? colorFromName(name, P.linen)
            : metal ? (name.word("brass", "gold") ? P.brass : name.word("white") ? 0xE4E1DA : 0x2B2A28)
            : colorFromName(name, P.oak)
        let top = topLimit // top of the duvet (voxel layer index above which pillows sit)
        let legH = platform ? 0 : clamp(rd(D(top) * 0.12), 1, 2)
        let railTop = clamp(rd(D(top) * 0.5), legH + 1, top - 2)
        let hb = upholstered ? clamp(rd(D(Z) * 0.06), 2, 3) : metal ? 1 : clamp(rd(D(Z) * 0.04), 1, 2)
        let sheet = 0xF3EEE4
        let duvet = name.word("grey", "gray") ? 0xB8B6B0 : 0xD9CCB6
        let throwC = accentPair(avoiding: duvet).0

        // legs
        if upholstered {
            for (lx, lz) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { box(lx, 0, lz, lx + 1, max(1, legH), lz + 1, P.walnut) }
        } else {
            for (lx, lz) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { box(lx, 0, lz, lx + 1, railTop, lz + 1, shade(frameC, 0.85)) }
        }
        // side + foot rails
        wood(0, legH, 0, 1, railTop, Z, frameC, .z)
        wood(X - 1, legH, 0, X, railTop, Z, frameC, .z)
        wood(0, legH, Z - 1, X, railTop, Z, frameC, .x)
        // slats (visible from below/sides)
        for z in stride(from: hb + 1, to: Z - 1, by: 3) { wood(1, railTop - 1, z, X - 1, railTop, z + 2, shade(frameC, 0.92), .x) }

        // headboard at the back (z = 0)
        let H = Y
        if upholstered {
            // padded panel with rounded shoulders, buttoned when tufted, channel seams otherwise
            let seam = shade(frameC, 0.82)
            let tufted = name.has("tufted")
            box(0, legH, 0, X, H, hb) { x, y, z in
                if y >= H - 1 && (x == 0 || x == X - 1) { return nil }
                if z == hb - 1 && y > railTop + 1 && y < H - 1 {
                    if tufted && x % 3 == 1 && (y - railTop) % 3 == 0 { return seam }
                    if !tufted && x % 4 == 0 && x > 0 && x < X - 1 { return seam }
                }
                return frameC
            }
        } else if metal {
            // posts, two rails and thin vertical bars
            let barC = shade(frameC, 0.9)
            box(0, 0, 0, 1, H, 1, frameC); box(X - 1, 0, 0, X, H, 1, frameC)
            box(0, H - 1, 0, X, H, 1, frameC); box(0, railTop + 1, 0, X, railTop + 2, 1, frameC)
            for x in stride(from: 2, to: X - 1, by: 2) where !worn(x, 1, 0, 0.3) { box(x, railTop + 2, 0, x + 1, H - 1, 1, barC) }
            set(0, H - 1, 0, P.brass); set(X - 1, H - 1, 0, P.brass) // finials
        } else {
            // framed wooden panel with vertical slats (a worn bed has lost one)
            wood(0, 0, 0, X, H, hb, frameC, .y)
            box(0, H - 1, 0, X, H, hb, shade(frameC, 1.05))
            for x in upTo(2, X - 2) where x % 3 == 0 {
                box(x, railTop + 1, hb - 1, x + 1, H - 2, hb, worn(x, 0, 0, 0.25) ? shade(frameC, 0.55) : shade(frameC, 0.8))
            }
            clear(0, H - 1, 0); clear(X - 1, H - 1, 0)
            if hb > 1 { clear(0, H - 1, 1); clear(X - 1, H - 1, 1) }
        }

        // mattress (white sheet)
        box(1, railTop - 1, hb, X - 1, top - 1, Z - 1) { _, y, _ in y == railTop - 1 ? 0xD8D2C6 : sheet }

        // pillows
        let pd = clamp(rd(D(Z) * 0.15), 2, 7)
        let gap = 1
        // a twin (under 1.1 m) gets one pillow; wider beds two
        let twin = D(X) * voxelM < 1.1
        let pwid = twin ? max(2, X - 6) : max(2, fdiv(X - 4 - gap, 2))
        for px in twin ? [3] : [2, 2 + pwid + gap] {
            box(px, top - 1, hb + 1, px + pwid, top + 1, hb + 1 + pd) { x, y, z in
                let ex = x == px || x == px + pwid - 1, ez = z == hb + 1 || z == hb + pd
                if y == top && (ex || ez) { return ex && ez ? nil : 0xE4DED2 }
                return 0xFBF8F1
            }
        }

        // duvet: from below the pillows to the foot, draping over the sides
        let dz = min(Z - 2, hb + 1 + pd + 1)
        let drape = max(railTop, top - 3)
        let bandStart = Z - max(3, rd(D(Z) * 0.18)), bandEnd = Z - 1 - rd(D(Z) * 0.04)
        let throwDark = shade(throwC, 0.9), duvetEdge = shade(duvet, 0.9)
        let duvFn: (Int, Int, Int) -> Int? = { x, y, z in
            let throwBand = z >= bandStart && z < bandEnd
            var c = throwBand ? throwC : duvet
            if throwBand && (x + z) % 4 == 0 { c = throwDark }
            if !throwBand && (x == 1 || x == X - 2) && y == top - 1 { c = duvetEdge } // edge crease
            return c
        }
        box(0, top - 1, dz, X, top, Z, duvFn) // top layer
        box(0, drape, dz, 1, top - 1, Z, duvFn) // left drape
        box(X - 1, drape, dz, X, top - 1, Z, duvFn) // right drape
        box(0, drape, Z - 1, X, top - 1, Z, duvFn) // foot drape
        // folded-back sheet + duvet fold line at the head end
        let fold = min(3, max(1, rd(D(Z) * 0.06)))
        let sheetEdge = shade(sheet, 0.94), foldLo = shade(duvet, 0.92), foldHi = shade(duvet, 1.04)
        box(0, top - 1, dz, X, top, dz + fold) { x, _, _ in x == 0 || x == X - 1 ? sheetEdge : sheet }
        box(1, top, dz, X - 1, top + 1, dz + fold) { _, _, z in z == dz + fold - 1 ? foldLo : foldHi }
        box(0, top - 1, dz + fold, X, top, dz + fold + 1, shade(duvet, 0.8)) // crease line
        // a few soft wrinkles
        for _ in 0..<4 {
            let wz = dz + fold + 3 + fl(rand() * D(max(1, Z - dz - fold - 8)))
            let wx = 2 + fl(rand() * D(max(1, X - 10)))
            let wl = 3 + fl(rand() * 5)
            box(wx, top - 1, wz, wx + wl, top, wz + 1, foldLo)
        }
        // footboard (sleigh / four-poster): a panel at the foot rising just above the duvet
        if footboard {
            wood(0, legH, Z - 1, X, top + 1, Z, frameC, .x)
            box(0, top + 1, Z - 1, 1, top + 2, Z, shade(frameC, 1.05)); box(X - 1, top + 1, Z - 1, X, top + 2, Z, shade(frameC, 1.05))
        }
    }

    /// Two decks on four posts, a guard rail around the top and a ladder on the side.
    /// Metal (dark) unless the name says wood. Tall RoomPlan "bed" boxes route here.
    func bunkBed(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let wooden = name.has("wood", "oak", "pine", "walnut", "birch")
        let frameC = wooden ? colorFromName(name, P.oak) : name.word("white") ? 0xE4E1DA : colorFromName(name, 0x4A4744)
        let sheet = 0xF3EEE4, duvet = name.word("grey", "gray") ? 0xB8B6B0 : 0xD9CCB6
        let mat = clamp(vox(0.15), 2, 4)
        let lowDeck = clamp(vox(0.25), 2, Y / 3)
        let rail = clamp(vox(0.3), 3, 7)  // guard rail height above the top mattress
        let highDeck = max(lowDeck + mat + vox(0.6), Y - rail - mat - 1)
        let post = 1
        // posts
        for (px, pz) in [(0, 0), (X - post, 0), (0, Z - post), (X - post, Z - post)] {
            box(px, 0, pz, px + post, Y, pz + post, frameC)
        }
        // a deck: rails round the frame, slats, mattress, pillow, duvet
        func deck(_ y: Int) {
            box(0, y, 0, X, y + 1, 1, frameC); box(0, y, Z - 1, X, y + 1, Z, frameC)
            box(0, y, 0, 1, y + 1, Z, frameC); box(X - 1, y, 0, X, y + 1, Z, frameC)
            for z in stride(from: 2, to: Z - 1, by: 3) { box(1, y, z, X - 1, y + 1, z + 1, shade(frameC, 0.9)) }
            box(1, y + 1, 1, X - 1, y + 1 + mat, Z - 1, sheet)
            let pd = clamp(rd(D(Z) * 0.13), 2, 6)
            box(3, y + 1 + mat, 2, X - 3, y + 2 + mat, 2 + pd, 0xFBF8F1)
            box(1, y + mat, 3 + pd, X - 1, y + 1 + mat, Z - 1, duvet)
        }
        deck(lowDeck)
        deck(highDeck)
        // head and foot panels above each deck
        for z in [0, Z - 1] {
            box(0, lowDeck + mat + 1, z, X, lowDeck + mat + 2, z + 1, frameC)
            box(0, Y - 1, z, X, Y, z + 1, frameC)
        }
        // guard rail along both sides of the top bunk, open where the ladder comes up
        let ladderZ0 = Z - post - clamp(vox(0.45), 4, Z / 3), ladderZ1 = Z - post - 1
        for x in [0, X - 1] {
            for z in 0..<Z where !(x == X - 1 && z >= ladderZ0 && z <= ladderZ1) {
                set(x, Y - 1, z, frameC)
            }
        }
        // ladder on the open side, near the foot: two uprights and rungs every ~25 cm
        let lx = X - 1
        box(lx, 0, ladderZ0, lx + 1, highDeck + 1, ladderZ0 + 1, frameC)
        box(lx, 0, ladderZ1, lx + 1, highDeck + 1, ladderZ1 + 1, frameC)
        for y in stride(from: vox(0.25), through: highDeck, by: max(3, vox(0.25))) {
            box(lx, y, ladderZ0, lx + 1, y + 1, ladderZ1 + 1, shade(frameC, 1.1))
        }
    }

    func mattress(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let c = colorFromName(name, 0xEEEAE2)
        let side = name.has("foam", "memory") ? 0xB9B4AB : shade(c, 0.9)
        let piping = shade(c, 0.88), tuft = shade(c, 0.84), bottom = shade(c, 0.85)
        box(0, 0, 0, X, Y, Z) { x, y, z in
            let outer = x == 0 || x == X - 1 || z == 0 || z == Z - 1
            if y == Y - 1 {
                if outer { return piping }
                return x % 4 == 2 && z % 4 == 2 ? tuft : c // quilting tufts
            }
            if y == 0 { return bottom }
            if outer && Y > 3 && y < (Y + 1) / 2 { return side } // foam base band
            return c
        }
        for (x, z) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { clear(x, Y - 1, z) }
    }

    func drawerFront(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ zf: Int, _ body: Int, _ knob: Int, _ twoKnobs: Bool) {
        let seam = shade(body, 0.78)
        box(x0, y0, zf, x1, y1, zf + 1) { x, y, _ in x == x0 || y == y0 ? seam : body }
        let ky = rd(D(y0 + 1 + y1) / 2 - 0.5)
        // a worn piece is missing the odd knob (a lighter screw hole shows instead)
        let knobAt: (Int) -> Void = { kx in self.set(kx, ky, zf + (self.worn(kx, ky, zf, 0.3) ? 0 : 1), self.worn(kx, ky, zf, 0.3) ? shade(body, 0.6) : knob) }
        if twoKnobs {
            knobAt(x0 + rd(D(x1 - x0) * 0.28))
            knobAt(x0 + rd(D(x1 - x0) * 0.72))
        } else {
            knobAt(rd(D(x0 + x1 - 1) / 2))
        }
    }

    func desk(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, lShape lForced: Bool = false) {
        let body = colorFromName(name, P.oak)
        let isWhite = body == 0xEBE6DC
        let standing = name.has("standing", "sit-stand", "sit stand", "adjustable")
        let glass = name.word("glass")
        let metalFrame = standing || glass || name.has("metal", "steel", "industrial", "hairpin")
        let lShape = (lForced && X >= 14 && Z >= 12) || (name.has("l-shaped", "l shaped", "corner desk", "l-desk") && X >= 24 && Z >= 18)
        let frameC = name.word("white") || isWhite ? 0xE4E1DA : 0x2B2A28
        let legC = metalFrame ? frameC : isWhite ? shade(body, 0.95) : shade(body, 0.85)
        let knob = isWhite ? P.brass : P.charcoal
        let ty = Y - 1
        // desk types from name words; the original styles (L-shaped, standing, glass) win and keep
        // their exact output. See `deskStyle` for the precedence.
        let style: DeskStyle = lShape || standing || glass ? .plain : deskStyle(X, Y, Z, name)
        switch style {
        case .vanity: vanityDesk(X, Y, Z, name); return
        case .hutch: hutchDesk(X, Y, Z, name, legC: legC, knob: knob); return
        case .gaming: gamingDesk(X, Y, Z, name); return
        case .pedestal: pedestalDesk(X, Y, Z, name, knob: knob); return
        case .writing: writingDesk(X, Y, Z, name, legC: metalFrame ? frameC : nil, knob: knob); return
        case .computer, .plain: break
        }
        // top: glass (flat, see-through blue) or wood grain; an L-desk adds a return wing on the right
        let mainD = lShape ? min(Z - 2, max(5, rd(D(Z) * 0.5))) : Z
        let wing = lShape ? clamp(rd(D(X) * 0.3), 4, X - 6) : 0
        let onTop: (Int, Int) -> Bool = { x, z in z < mainD || x >= X - wing }
        if glass {
            box(0, ty, 0, X, Y, Z, flat: true) { x, _, z in onTop(x, z) ? (x == 0 || x == X - 1 || z == Z - 1 ? 0xB8D2E2 : P.glass) : nil }
        } else {
            wood(0, ty, 0, X, Y, mainD, body, .x)
            if lShape { wood(X - wing, ty, mainD, X, Y, Z, body, .z) }
            box(0, ty, mainD - 1, lShape ? X - wing : X, Y, mainD, shade(body, 0.93)) // front edge
            if lShape { box(X - wing, ty, Z - 1, X, Y, Z, shade(body, 0.93)) }
        }
        surface(0, 0, X, mainD, Y)
        if lShape { surface(X - wing, mainD, X, Z, Y) }
        if standing {
            // sit-stand frame: two T-legs (column + foot), a crossbar, the keypad under the front edge
            let zc = mainD / 2
            for lx in [1, X - 2] {
                box(lx, 1, zc, lx + 1, ty, zc + 1, frameC)
                box(lx, 0, 1, lx + 1, 1, mainD - 1, frameC)
                box(lx, ty - 1, 1, lx + 1, ty, mainD - 1, frameC)
            }
            box(2, ty - 1, zc, X - 2, ty, zc + 1, frameC)
            if X >= 8 { set(X - 4, ty - 1, mainD - 1, 0x1C1C1E); set(X - 5, ty - 1, mainD - 1, 0x7FC4E8, flat: true) }
            return
        }
        if lShape {
            for (lx, lz) in [(0, 0), (0, mainD - 1), (X - 1, 0), (X - 1, Z - 1), (X - wing, Z - 1)] { box(lx, 0, lz, lx + 1, ty, lz + 1, legC) }
            box(1, ty - 1, 0, X - 1, ty, 1, shade(body, 0.9))
            if Y >= 10 { box(1, ty - rd(D(Y) * 0.35), 0, X - wing, ty - 1, 1, shade(body, 0.86)) } // modesty panel
            return
        }
        // drawer pedestal when the desk is wide enough to have one (>= 1.1 m) or the name says so
        let hasUnit = !glass && !metalFrame && X >= 14 && Y >= 8 && Z >= 6 && (D(X) * voxelM >= 1.1 || name.has("drawer"))
        let dw = hasUnit ? clamp(rd(D(X) * 0.3), 4, 10) : 0
        // legs (2 wide on long or metal-framed desks)
        let lw = !metalFrame && X > 30 ? 2 : 1
        for lx in hasUnit ? [0] : [0, X - lw] {
            box(lx, 0, 0, lx + lw, ty, 1, legC)
            box(lx, 0, Z - 1, lx + lw, ty, Z, legC)
        }
        // apron + back panel
        let apronEnd = hasUnit ? X - dw : X
        let apronC = metalFrame ? frameC : shade(body, 0.9)
        box(1, ty - 1, 0, apronEnd, ty, 1, apronC)
        box(1, ty - 1, Z - 2, apronEnd, ty, Z - 1, metalFrame ? frameC : shade(body, 0.95))
        if metalFrame { box(0, ty - 1, 1, 1, ty, Z - 1, frameC); box(X - 1, ty - 1, 1, X, ty, Z - 1, frameC) }
        if Y >= 10 && Z >= 6 && !metalFrame { box(1, ty - rd(D(Y) * 0.35), 0, apronEnd - (hasUnit ? 0 : 1), ty - 1, 1, shade(body, 0.86)) } // modesty panel
        // center pencil drawer
        if X >= 16 && !metalFrame {
            let px0 = rd(D(apronEnd) * 0.3), px1 = rd(D(apronEnd) * 0.75)
            box(px0, ty - 1, 1, px1, ty, Z - 1, body)
            if !worn(px0, ty, 1, 0.5) { set(rd(D(px0 + px1) / 2), ty - 1, Z - 1, knob) }
        }
        if hasUnit {
            box(X - dw, 0, 0, X, ty, Z - 1, shade(body, 0.97))
            // drawer rows from the desk's height (~22 cm each)
            let n = clamp(rd(D(ty) * voxelM / 0.22), 2, 4)
            let base = 1
            for i in 0..<n {
                let y0 = base + rd(D((ty - base) * i) / D(n)), y1 = base + rd(D((ty - base) * (i + 1)) / D(n))
                drawerFront(X - dw, X, y0, y1, Z - 2, body, knob, false)
            }
            box(X - dw, 0, Z - 2, X, 1, Z - 1, shade(body, 0.7)) // plinth
        }
        if style == .computer { keyboardTray(X, Y, Z, apronEnd: apronEnd, trayC: metalFrame ? frameC : shade(body, 0.92), railC: metalFrame ? shade(frameC, 0.8) : 0x3A3936) }
    }

    /// Desk types beyond the original plain / metal / white / drawer-pedestal desk.
    enum DeskStyle { case plain, vanity, hutch, gaming, pedestal, computer, writing }

    /// Precedence, first match wins (L-shaped, standing and glass desks never get here):
    ///  1. vanity: "vanity", "dressing table", "makeup"
    ///  2. hutch: "secretary", "hutch", "roll top", "rolltop", "computer armoire"
    ///     (the hutch itself only when the scan is >= 1.1 m tall; shorter ones are the plain desk)
    ///  3. gaming: "gaming"
    ///  4. pedestal: "executive", "pedestal", or "office desk" at least 1.4 m wide
    ///  5. computer: "computer desk", "keyboard tray" (the plain desk plus a pull-out tray)
    ///  6. writing: "writing", "console desk", "mid-century", "midcentury"
    func deskStyle(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) -> DeskStyle {
        if name.word("vanity") || name.has("dressing table", "makeup") { return .vanity }
        if name.has("secretary", "hutch", "roll top", "rolltop", "roll-top", "computer armoire") {
            return D(Y) * voxelM >= 1.1 && Y >= 12 ? .hutch : .plain
        }
        if name.word("gaming") { return .gaming }
        if name.has("executive", "pedestal") || (name.has("office desk") && D(X) * voxelM >= 1.4) { return .pedestal }
        if name.has("computer desk", "keyboard tray") { return .computer }
        if name.word("writing") || name.has("console desk", "mid-century", "midcentury") { return .writing }
        return .plain
    }

    /// A pull-out keyboard tray hanging on two rails under the front of the top, keys showing.
    private func keyboardTray(_ X: Int, _ Y: Int, _ Z: Int, apronEnd: Int, trayC: Int, railC: Int) {
        let ty = Y - 1
        let tyT = ty >= 3 ? ty - 2 : max(0, ty - 1)
        let tx0 = clamp(rd(D(apronEnd) * 0.22), 1, max(1, apronEnd - 2))
        let tx1 = clamp(rd(D(apronEnd) * 0.72), tx0 + 1, max(tx0 + 1, apronEnd - 1))
        let tz0 = clamp(Z - max(2, rd(D(Z) * 0.45)), 1, max(1, Z - 1))
        // rails from the back to the front, hung from the underside of the top
        for rx in [tx0 - 1, tx1] {
            box(rx, tyT, 1, rx + 1, tyT + 1, Z - 1, railC)
            if tyT < ty - 1 { box(rx, tyT + 1, 1, rx + 1, ty, 2, railC) }
        }
        box(tx0, tyT, tz0, tx1, tyT + 1, Z, trayC)
        // keyboard: a dark slab with lighter key rows, flush with the tray
        if tx1 - tx0 >= 3 && Z - tz0 >= 3 {
            box(tx0 + 1, tyT, tz0 + 1, tx1 - 1, tyT + 1, Z - 1, flat: true) { x, _, z in (x + z) % 3 == 0 ? 0x55575C : 0x2A2B2E }
        } else {
            set(tx0, tyT, Z - 1, 0x2A2B2E, flat: true)
        }
    }

    /// Simple four-leg base with an apron for a desk top at `ty` (used by the hutch and vanity).
    private func deskLegs(_ X: Int, _ ty: Int, _ Z: Int, _ legC: Int, _ apronC: Int, inset: Int = 0) {
        guard ty > 0 else { return }
        let i = min(inset, max(0, (X - 2) / 2)), k = min(inset, max(0, (Z - 2) / 2))
        for (lx, lz) in [(i, k), (X - 1 - i, k), (i, Z - 1 - k), (X - 1 - i, Z - 1 - k)] { box(lx, 0, lz, lx + 1, ty, lz + 1, legC) }
        if ty >= 3 {
            box(i, ty - 1, k, X - i, ty, k + 1, apronC)
            box(i, ty - 1, Z - 1 - k, X - i, ty, Z - k, apronC)
            box(i, ty - 1, k, i + 1, ty, Z - k, apronC)
            box(X - 1 - i, ty - 1, k, X - i, ty, Z - k, apronC)
        }
    }

    /// Vanity / dressing table: slim legs, two shallow drawers flanking the knee space, and (when
    /// the scan is tall enough, >= 1.1 m) a framed mirror standing on the back edge.
    private func vanityDesk(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, P.white)
        let knob = P.brass
        let tall = D(Y) * voxelM >= 1.1 && Y >= 12
        let deskH = tall ? clamp(vox(0.76), 3, Y - 6) : Y
        let ty = deskH - 1
        wood(0, ty, 0, X, deskH, Z, body, .x)
        box(0, ty, Z - 1, X, deskH, Z, shade(body, 0.93)) // front edge
        // tapered legs: full at the top, thinner (set back) at the foot
        let legC = shade(body, 0.9)
        for (lx, lz) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] { box(lx, 0, lz, lx + 1, ty, lz + 1, legC) }
        if ty >= 2 {
            // apron with a drawer on each side of the knee space (or one centered on a narrow table)
            box(1, ty - 1, 0, X - 1, ty, 1, shade(body, 0.95))
            let fronts: [(Int, Int)] = X >= 10 ? [(1, rd(D(X) * 0.36)), (X - rd(D(X) * 0.36), X - 1)] : [(1, max(2, X - 1))]
            for (x0, x1) in fronts where x1 > x0 {
                box(x0, ty - 1, 1, x1, ty, Z - 1, body)
                box(x0, ty - 1, Z - 1, x1, ty, Z) { x, _, _ in x == x0 ? shade(body, 0.78) : body }
                set(rd(D(x0 + x1 - 1) / 2), ty - 1, Z - 1, knob)
            }
            if X >= 10 { box(rd(D(X) * 0.36), ty - 1, Z - 1, X - rd(D(X) * 0.36), ty, Z, shade(body, 0.86)) } // knee-space rail
        }
        guard tall else { surface(0, 0, X, Z, deskH); return }
        // mirror: a thin frame on the back edge, light-blue reflective glass with a highlight streak
        let mx0 = X >= 8 ? rd(D(X) * 0.18) : 0, mx1 = X - mx0
        let frame = name.has("gold", "brass") ? P.brass : shade(body, 0.88)
        let glassC = 0xBFDCEB, hi = 0xE6F3FA
        box(mx0, deskH, 0, mx1, Y, 1) { x, y, _ in
            if x == mx0 || x == mx1 - 1 || y == deskH || y == Y - 1 { return frame }
            return nil
        }
        box(mx0 + 1, deskH + 1, 0, mx1 - 1, Y - 1, 1, flat: true) { x, y, _ in
            let d = (x - mx0) - (y - deskH)
            return d >= 1 && d <= 2 ? hi : glassC
        }
        // hollywood bulbs around the frame
        if name.has("lighted", "lights", "hollywood", "led") {
            for y in stride(from: deskH + 2, to: Y - 1, by: 3) { set(mx0, y, 1, P.bulb, flat: true); set(mx1 - 1, y, 1, P.bulb, flat: true) }
        }
        surface(0, 1, X, Z, deskH)
    }

    /// Secretary / hutch desk: a work surface at desk height with a shelved cubby hutch on the back
    /// half rising to the scanned height. Only called when the scan is tall (see `deskStyle`).
    private func hutchDesk(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, legC: Int, knob: Int) {
        let body = colorFromName(name, name.has("secretary", "roll top", "rolltop", "roll-top") ? P.walnut : P.oak)
        let deskH = clamp(vox(0.75), 3, Y - 6)
        let ty = deskH - 1
        let hz = clamp(rd(D(Z) * 0.4), 1, max(1, Z - 1))
        // the desk: top, legs, a drawer pedestal on the right when wide enough
        wood(0, ty, 0, X, deskH, Z, body, .x)
        box(0, ty, Z - 1, X, deskH, Z, shade(body, 0.93))
        let ped = X >= 14 && ty >= 4 ? clamp(rd(D(X) * 0.3), 4, 10) : 0
        deskLegs(ped > 0 ? X - ped + 1 : X, ty, Z, legC, shade(body, 0.9))
        if ped > 0 {
            box(X - ped, 0, 0, X, ty, Z - 1, shade(body, 0.97))
            let n = clamp(rd(D(ty) * voxelM / 0.22), 2, 3)
            for i in 0..<n {
                let y0 = 1 + rd(D((ty - 1) * i) / D(n)), y1 = 1 + rd(D((ty - 1) * (i + 1)) / D(n))
                drawerFront(X - ped, X, y0, y1, Z - 2, body, knob, false)
            }
        }
        surface(0, hz, X, Z, deskH) // the work surface in front of the hutch
        // the hutch: sides, back, top, shelves; cubby dividers in the lowest row
        let side = shade(body, 0.95)
        box(0, deskH, 0, 1, Y, hz, side)
        box(X - 1, deskH, 0, X, Y, hz, side)
        box(0, deskH, 0, X, Y, 1, shade(body, 0.85))
        wood(0, Y - 1, 0, X, Y, hz, body, .x)
        let inner = Y - 1 - deskH
        let rows = clamp(rd(D(inner) * voxelM / 0.25), 1, 4)
        var boards = [ty]
        for r in 1..<rows {
            let by = deskH + rd(D(inner * r) / D(rows))
            if by > boards.last! + 1 && by < Y - 2 { wood(1, by, 1, X - 1, by + 1, hz, body, .x); boards.append(by) }
        }
        boards.append(Y - 1)
        // cubbies in the lowest row: dividers every ~25 cm
        let lowTop = boards[1]
        let cubbies = clamp(rd(D(X - 2) * voxelM / 0.25), 1, 6)
        if cubbies > 1 { for k in 1..<cubbies { let dx = 1 + rd(D((X - 2) * k) / D(cubbies)); box(dx, deskH, 1, dx + 1, lowTop, hz, side) } }
        // roll-top: a slatted tambour hood across the hutch's lower front
        if name.has("roll top", "rolltop", "roll-top") && hz < Z {
            box(0, deskH, hz, X, min(lowTop, deskH + 2), hz + 1) { x, y, _ in y % 2 == 0 ? shade(body, 0.82) : body }
        }
        for i in 0..<(boards.count - 1) {
            let y = boards[i] + 1, clear = boards[i + 1] - y
            if clear > 0 { surface(1, 1, X - 1, hz, y, clearance: clear) }
        }
        surface(0, 0, X, hz, Y)
    }

    /// Gaming desk: black carbon-weave top with a red (or RGB) strip on the front edge, Z-shaped
    /// metal side legs, a headphone hook on the left and a cup holder on the right.
    private func gamingDesk(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let ty = Y - 1
        let carbonA = 0x1C1C1E, carbonB = 0x2B2B2F, frame = 0x232325
        let accent = name.has("blue") ? 0x2E7BEF : name.has("green") ? 0x2ECC71 : 0xD7263D
        let rgb = name.has("rgb", "led")
        let rgbs = [0xFF3B5C, 0xFFB03B, 0x3BFF8A, 0x3BC8FF, 0x8A5BFF]
        box(0, ty, 0, X, Y, Z, flat: true) { x, _, z in (x + z) % 2 == 0 ? carbonA : carbonB }
        box(0, ty, Z - 1, X, Y, Z, flat: true) { x, _, _ in rgb ? rgbs[(x / 2) % rgbs.count] : accent }
        surface(0, 0, X, Z, Y)
        guard ty >= 1 else { return }
        // Z-legs: a rail under the top, a diagonal down to the back, a foot along the floor
        let fx = X >= 8 ? [1, X - 2] : [0, X - 1]
        for lx in fx {
            box(lx, max(0, ty - 1), 0, lx + 1, ty, Z, frame)
            box(lx, 0, 0, lx + 1, 1, Z, frame)
            if ty >= 3 { line(lx, ty - 1, Z - 2, lx, 1, 1, frame) }
            set(lx, 0, Z - 1, accent); set(lx, 0, 0, accent) // foot caps
        }
        if ty >= 3 { box(fx[0], ty - 1, 1, fx[1], ty, 2, frame) } // back crossbar
        if Y >= 8 { let cy = rd(D(Y) * 0.3); box(fx[0], cy, 1, fx[1], cy + 1, 2, frame) }
        guard ty >= 3 else { return }
        // headphone hook (left) and cup holder (right) under the top
        let zc = Z / 2
        let hx = X >= 8 ? 0 : fx[0]
        set(hx, ty - 1, zc, frame); set(hx, ty - 2, zc, frame); set(hx, ty - 2, zc + 1, accent)
        let cx = X >= 8 ? X - 1 : fx[1]
        box(cx, ty - 2, max(0, Z - 4), cx + 1, ty - 1, Z - 1, carbonB)
        set(cx, ty - 1, max(0, Z - 3), 0x8B8D91) // the cup's rim
    }

    /// Pedestal / executive desk: a drawer pedestal on each side, a modesty panel across the back,
    /// a thick top (with a leather writing inlay on wide executive desks).
    private func pedestalDesk(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, knob: Int) {
        let body = colorFromName(name, name.has("executive") ? P.walnut : P.oak)
        let ty = Y - 1
        let thick = Y >= 10
        wood(0, ty, 0, X, Y, Z, body, .x)
        if thick { box(0, ty - 1, 0, X, ty, Z, shade(body, 0.9)) }
        let under = thick ? ty - 1 : ty
        if name.has("executive") && X >= 16 && Z >= 8 {
            box(rd(D(X) * 0.25), ty, 2, X - rd(D(X) * 0.25), Y, Z - 2, flat: true) { _, _, _ in 0x2F4A3A }
        }
        surface(0, 0, X, Z, Y)
        guard under >= 1 else { return }
        let pw = clamp(rd(D(X) * 0.28), 1, max(1, (X - 1) / 2))
        let zf = max(0, Z - 2)
        for px in [0, X - pw] {
            box(px, 0, 0, px + pw, under, max(1, Z - 1), shade(body, 0.96))
            let n = clamp(rd(D(under) * voxelM / 0.2), 1, 4)
            for i in 0..<n where under >= 2 {
                let y0 = 1 + rd(D((under - 1) * i) / D(n)), y1 = 1 + rd(D((under - 1) * (i + 1)) / D(n))
                if y1 > y0 { drawerFront(px, px + pw, y0, y1, zf, body, knob, pw >= 8) }
            }
            box(px, 0, zf, px + pw, 1, zf + 1, shade(body, 0.7)) // plinth
        }
        // modesty panel at the back between the pedestals, plus a center drawer under the top
        let my0 = max(0, rd(D(under) * 0.25))
        box(pw, my0, 0, X - pw, under, 1, shade(body, 0.86))
        if X - 2 * pw >= 4 && thick {
            box(pw, under - 1, 1, X - pw, under, Z - 1, body)
            set(rd(D(X - 1) / 2), under - 1, Z - 1, knob)
        }
    }

    /// Writing desk (mid-century / console): a slim top, one shallow drawer centered under it,
    /// and four tapered legs splaying out to the corners.
    private func writingDesk(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, legC metalC: Int?, knob: Int) {
        let mcm = name.has("mid-century", "midcentury")
        let body = colorFromName(name, mcm ? P.walnut : P.oak)
        let legC = metalC ?? shade(body, 0.85)
        let ty = Y - 1
        wood(0, ty, 0, X, Y, Z, body, .x)
        box(0, ty, Z - 1, X, Y, Z, shade(body, 0.93))
        surface(0, 0, X, Z, Y)
        guard ty >= 1 else { return }
        let ix = max(1, X / 8), iz = max(1, Z / 8)
        // splayed legs: thick under the apron, tapering to a point at the corners
        for (tx, tz, fx, fz) in [(ix, iz, 0, 0), (X - 1 - ix, iz, X - 1, 0), (ix, Z - 1 - iz, 0, Z - 1), (X - 1 - ix, Z - 1 - iz, X - 1, Z - 1)] {
            set(tx, ty - 1, tz, legC)
            let mx = D(tx + fx) / 2, mz = D(tz + fz) / 2, my = D(ty - 1) / 2
            if Y >= 12 && X >= 12 {
                line(D(tx), D(ty - 1), D(tz), mx, my, mz, legC, thick: true)
                line(mx, my, mz, D(fx), 0, D(fz), legC)
            } else {
                line(D(tx), D(ty - 1), D(tz), D(fx), 0, D(fz), legC)
            }
        }
        guard ty >= 2 else { return }
        // apron ring and the single shallow drawer centered at the front
        box(ix, ty - 1, iz, X - ix, ty, Z - iz) { x, _, z in x == ix || x == X - ix - 1 || z == iz || z == Z - iz - 1 ? shade(body, 0.82) : nil }
        let dx0 = clamp(rd(D(X) * 0.3), ix, X - 1), dx1 = clamp(rd(D(X) * 0.7), dx0 + 1, X - ix)
        box(dx0, ty - 1, iz + 1, dx1, ty, Z - iz) { x, _, z in z == Z - iz - 1 && x == dx0 ? shade(body, 0.78) : body }
        set(rd(D(dx0 + dx1 - 1) / 2), ty - 1, min(Z - 1, Z - iz), knob)
    }

    func officeChair(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let fab = colorFromName(name, P.charcoal)
        let frame = shade(fab, 0.72)
        let metal = name.word("black") ? 0x2A2A2A : 0x6C6F72
        let wheel = 0x1A1A1A
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        let seatY = clamp(vox(0.46), 3, Y - 4)
        let R = D(min(X, Z)) / 2 - 0.7
        // 5-star base
        for k in 0..<5 {
            let a = Double.pi / 2 + D(k) * 2 * Double.pi / 5
            let ex = cx + cos(a) * R, ez = cz + sin(a) * R
            line(cx, 1, cz, ex, 1, ez, metal)
            set(rd(ex), 0, rd(ez), wheel)
            set(rd(ex), 1, rd(ez), metal)
        }
        // hub + gas cylinder
        let c0 = fl(cx), c1 = ce(cx) + 1, z0 = fl(cz), z1 = ce(cz) + 1
        box(c0, 1, z0, c1, 2, z1, metal)
        box(rd(cx), 2, rd(cz), rd(cx) + 1, seatY - 1, rd(cz) + 1, 0x9A9FA3)
        box(c0, seatY - 1, z0, c1, seatY, z1, frame) // mechanism
        // seat
        let rx = D(X) * 0.44, rz = D(Z) * 0.42, scz = cz + 0.5
        let sh = max(1, min(2, Y - seatY - 3))
        let rim = shade(fab, 0.88)
        for z in upTo(0, Z) {
            for x in upTo(0, X) {
                let dx = (D(x) - cx) / rx, dz = (D(z) - scz) / rz
                let d = dx * dx + dz * dz
                if d > 1 { continue }
                box(x, seatY, z, x + 1, seatY + sh, z + 1) { _, y, _ in d > 0.7 && y == seatY + sh - 1 ? rim : y == seatY ? frame : fab }
            }
        }
        // backrest at the back (low z): mesh with a solid frame, slightly reclined via stepped z
        let bx0 = rd(D(X) * 0.14), bx1 = X - bx0
        let by0 = seatY + sh + 1
        let bz = max(0, rd(scz - rz) - 1)
        let meshDark = shade(fab, 0.8)
        for y in upTo(by0, Y) {
            let t = D(y - by0) / D(max(1, Y - by0))
            let zz = max(0, bz - (t > 0.6 ? 1 : 0))
            let inset = t > 0.85 ? 1 : 0 // tapered shoulders
            for x in upTo(bx0 + inset, bx1 - inset) {
                let border = x == bx0 + inset || x == bx1 - inset - 1 || y == by0 || y == Y - 1
                set(x, y, zz, border ? frame : ((x + y) % 2 == 0 ? fab : meshDark))
            }
        }
        // lumbar spine connecting seat to back
        box(rd(cx), seatY, max(0, bz), rd(cx) + 1, by0 + 1, max(1, bz + 1), frame)
        // armrests
        if attr("chairarmtype.existing") || (!attr("chairarmtype.missing") && X >= 8) {
            let ay = min(Y - 2, seatY + sh + 3)
            let az0 = rd(cz - 1), az1 = rd(cz + 3)
            for ax in [0, X - 1] {
                box(ax, seatY + sh - 1, rd(cz), ax + 1, ay, rd(cz) + 1, frame)
                box(ax, ay, az0, ax + 1, ay + 1, az1, shade(fab, 0.9))
            }
        }
    }

    func diningChair(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        // style from the name / material: stool, metal cafe, upholstered, spindle (Windsor), slat back (models.js)
        // RoomPlan: ChairType.stool / ChairBackType.missing mean no back
        let stool = attr("chairtype.stool") || attr("chairbacktype.missing") || (!attr("chairbacktype.existing") && !attr("chairtype.dining") && name.has("stool"))
        let metal = name.has("metal", "steel", "iron", "bistro", "cafe", "tolix", "industrial")
        let upholstered = !metal && name.has("upholster", "fabric", "velvet", "parsons", "padded", "linen", "cushion", "leather")
        let spindle = name.has("windsor", "spindle")
        let w = metal ? colorFromName(name, 0x2B2A28) : colorFromName(name.removingWords("velvet", "linen", "fabric", "leather"), P.oak)
        let seatY = stool ? clamp(Y - 1, 2, Y - 1) : clamp(vox(0.44), 2, Y - 3)
        let legC = metal ? w : shade(w, 0.9)
        for (lx, lz) in [(0, 0), (X - 1, 0), (0, Z - 1), (X - 1, Z - 1)] {
            if metal { box(lx, 0, lz, lx + 1, seatY, lz + 1, legC) } else { wood(lx, 0, lz, lx + 1, seatY, lz + 1, legC, .y) }
        }
        let fabric = upholstered ? colorFromName(name, P.linen) : w
        let seatC = upholstered ? fabric : w
        if name.has("round") && stool {
            cyl(D(X - 1) / 2, D(Z - 1) / 2, D(min(X, Z)) / 2, seatY, seatY + 1, seatC)
        } else if upholstered {
            box(0, seatY, 0, X, seatY + 1, Z, shade(w, 0.85)) // frame
            box(0, seatY + 1, 0, X, seatY + 2, Z) { x, _, z in x == 0 || x == X - 1 || z == Z - 1 ? shade(fabric, 0.9) : fabric } // cushion
        } else if metal {
            box(0, seatY, 0, X, seatY + 1, Z, seatC)
        } else {
            wood(0, seatY, 0, X, seatY + 1, Z, seatC, .x)
        }
        // stretchers (a footrest ring on bar-height stools)
        let footY = D(seatY) * voxelM >= 0.55 ? rd(D(seatY) * 0.35) : 2
        box(0, footY, 1, 1, footY + 1, Z - 1, shade(legC, 0.9))
        box(X - 1, footY, 1, X, footY + 1, Z - 1, shade(legC, 0.9))
        if stool || D(seatY) * voxelM >= 0.55 {
            box(1, footY, 0, X - 1, footY + 1, 1, shade(legC, 0.9))
            box(1, footY, Z - 1, X - 1, footY + 1, Z, shade(legC, 0.9))
        }
        if stool { return }
        // armrests when the scan saw them
        if attr("chairarmtype.existing") {
            let ay = min(Y - 2, seatY + rd(D(Y - seatY) * 0.45))
            for ax in [0, X - 1] {
                box(ax, seatY + 1, Z - 2, ax + 1, ay, Z - 1, legC)
                box(ax, ay, 1, ax + 1, ay + 1, Z, w)
            }
        }
        let by0 = seatY + (upholstered ? 2 : 1)
        if upholstered {
            // solid padded back with the frame showing at the sides
            box(0, by0, 0, X, Y, 2) { x, y, z in
                if x == 0 || x == X - 1 { return z == 0 ? shade(w, 0.85) : nil }
                if y == Y - 1 && (x == 1 || x == X - 2) { return nil }
                return z == 1 && y == Y - 1 ? shade(fabric, 1.04) : fabric
            }
            return
        }
        // back posts + top rail (back at z = 0)
        if metal {
            box(0, seatY + 1, 0, 1, Y, 1, w); box(X - 1, seatY + 1, 0, X, Y, 1, w)
            // horizontal bars
            for y in stride(from: seatY + 2, to: Y, by: 2) { box(1, y, 0, X - 1, y + 1, 1, w) }
            return
        }
        wood(0, seatY + 1, 0, 1, Y, 1, w, .y)
        wood(X - 1, seatY + 1, 0, X, Y, 1, w, .y)
        if spindle {
            // curved crest rail and thin spindles
            wood(1, Y - 1, 0, X - 1, Y, 1, w, .x)
            clear(0, Y - 1, 0); clear(X - 1, Y - 1, 0)
            box(1, Y - 2, 0, 2, Y - 1, 1, w); box(X - 2, Y - 2, 0, X - 1, Y - 1, 1, w)
            for x in stride(from: 2, to: X - 2, by: 2) where !worn(x, 2, 0, 0.3) { box(x, seatY + 1, 0, x + 1, Y - 1, 1, shade(w, 0.95)) }
            return
        }
        // slat back (a worn chair is missing a slat)
        wood(0, Y - 2, 0, X, Y, 1, w, .x)
        for x in stride(from: 2, to: X - 2, by: 2) where !worn(x, 1, 0, 0.3) { box(x, seatY + 1, 0, x + 1, Y - 2, 1, shade(w, 0.95)) }
    }

    func table(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let hM = D(Y) * voxelM
        let glass = name.word("glass")
        let metalLegs = glass || name.has("metal", "steel", "iron", "industrial", "hairpin")
        let w = colorFromName(name.removingWords("glass"), P.oak)
        let legMetal = name.word("white", "brass", "gold") ? colorFromName(name, 0x2B2A28) : 0x2B2A28
        let legC = metalLegs ? legMetal : shade(w, 0.88)
        let ty = Y - 1
        // the top: glass panes are flat (no jitter) and see-through blue
        func top(_ fill: (Int, Int) -> Bool) {
            if glass {
                box(0, ty, 0, X, Y, Z, flat: true) { x, _, z in fill(x, z) ? (x == 0 || z == 0 || x == X - 1 || z == Z - 1 ? 0xB8D2E2 : P.glass) : nil }
            }
        }
        // round / pedestal (models.js): a disc on a column
        let round = attr("tableshapetype.circularelliptic") || (!attr("tableshapetype.rectangular") && name.has("round", "circular", "oval", "bistro", "pedestal", "tulip"))
        if round {
            // elliptic top filling the scanned footprint (a circle when it is square)
            let cx = D(X - 1) / 2, cz = D(Z - 1) / 2, r = D(min(X, Z)) / 2
            let ex = D(X) / 2, ez = D(Z) / 2
            let grain = shade(w, 0.9)
            box(0, ty, 0, X, Y, Z, flat: glass) { x, _, z in
                let dx = (D(x) - cx) / ex, dz = (D(z) - cz) / ez
                if dx * dx + dz * dz > 1 { return nil }
                return glass ? P.glass : (z + (x >> 2)) % 5 == 0 ? grain : w
            }
            cyl(cx, cz, max(1, r * 0.12), 1, ty, metalLegs ? legC : shade(w, 0.85))
            cyl(cx, cz, max(1.5, r * 0.45), 0, 1, metalLegs ? legC : shade(w, 0.8))
            // the square inscribed in the ellipse (half sides ex / √2, ez / √2)
            let sx = max(0, fl(ex * 0.7)), sz = max(0, fl(ez * 0.7))
            surface(rd(cx) - sx + (X % 2 == 0 ? 1 : 0), rd(cz) - sz + (Z % 2 == 0 ? 1 : 0), rd(cx) + sx, rd(cz) + sz, Y)
            return
        }
        if glass { top { _, _ in true } } else { wood(0, ty, 0, X, Y, Z, w, X >= Z ? .x : .z) }
        surface(0, 0, X, Z, Y)
        // a coffee table (under ~0.6 m) gets a thicker top and chunkier legs
        let coffee = attr("tabletype.coffee") || (!attr("tabletype.dining") && hM < 0.6)
        if coffee && !glass && Y >= 6 { wood(0, ty - 1, 0, X, ty, Z, shade(w, 0.94), X >= Z ? .x : .z) }
        let tyLeg = coffee && !glass && Y >= 6 ? ty - 1 : ty
        if name.has("trestle", "farmhouse", "refectory") && X >= 16 {
            // trestle: two end supports with feet and a stretcher
            let zc = Z / 2
            for px in [rd(D(X) * 0.12), X - 1 - rd(D(X) * 0.12)] {
                wood(px - 1, 1, zc - 1, px + 1, tyLeg, zc + 1, legC, .y)
                wood(px - 1, 0, 1, px + 1, 1, Z - 1, shade(legC, 0.92), .z)
                wood(px - 1, tyLeg - 1, 1, px + 1, tyLeg, Z - 1, shade(legC, 0.92), .z)
            }
            wood(rd(D(X) * 0.12), rd(D(Y) * 0.3), zc - 1, X - rd(D(X) * 0.12), rd(D(Y) * 0.3) + 1, zc, shade(legC, 0.95), .x)
            return
        }
        if name.has("mid-century", "midcentury", "tapered", "splayed", "scandi", "danish", "mcm") {
            // tapered legs splaying out from under the apron
            let ix = max(1, X / 8), iz = max(1, Z / 8)
            for (tx, tz, fx, fz) in [(ix, iz, 0, 0), (X - 1 - ix, iz, X - 1, 0), (ix, Z - 1 - iz, 0, Z - 1), (X - 1 - ix, Z - 1 - iz, X - 1, Z - 1)] {
                line(D(tx), D(tyLeg - 1), D(tz), D(fx), 0, D(fz), legC)
                set(tx, tyLeg - 1, tz, legC)
            }
            if Y > 6 { box(ix, tyLeg - 1, iz, X - ix, tyLeg, Z - iz) { x, _, z in x == ix || x == X - ix - 1 || z == iz || z == Z - iz - 1 ? shade(w, 0.82) : nil } }
            return
        }
        // four square legs set in under an overhanging top; overhang and leg thickness scale
        // with the table (a side table's legs sit near the edge, a dining table's 10-15 cm in)
        let span = min(X, Z)
        let oh = span >= 6 ? clamp(rd(D(span) * 0.07), 1, 3) : 0
        let lw = (span >= 16 && Y >= 12) || (coffee && span >= 12) || X > 30 ? 2 : 1
        let lx0 = oh, lx1 = X - oh - lw, lz0 = oh, lz1 = Z - oh - lw
        let foot = metalLegs ? legC : shade(legC, 0.82)
        for (lx, lz) in [(lx0, lz0), (lx1, lz0), (lx0, lz1), (lx1, lz1)] {
            if metalLegs { box(lx, 0, lz, lx + lw, tyLeg, lz + lw, legC) } else { wood(lx, 1, lz, lx + lw, tyLeg, lz + lw, legC, .y) }
            box(lx, 0, lz, lx + lw, 1, lz + lw, foot)
        }
        if Y > 6 && lx1 > lx0 && lz1 > lz0 {
            // apron: a rail joining the legs' tops, deeper on a tall table
            let apron = metalLegs ? legC : shade(w, 0.82)
            let ah = Y >= 14 && !metalLegs ? 2 : 1
            let ay0 = tyLeg - ah
            box(lx0, ay0, lz0, lx1 + lw, tyLeg, lz0 + 1, apron)
            box(lx0, ay0, lz1 + lw - 1, lx1 + lw, tyLeg, lz1 + lw, apron)
            box(lx0, ay0, lz0, lx0 + 1, tyLeg, lz1 + lw, apron)
            box(lx1 + lw - 1, ay0, lz0, lx1 + lw, tyLeg, lz1 + lw, apron)
            // the top's edge band reads darker than its face
            if !glass { box(0, ty, Z - 1, X, Y, Z, shade(w, 0.93)) }
        }
        // coffee tables with a shelf / storage, and bar-height tables' footrest stretchers
        if coffee && name.has("shelf", "storage", "drawer") && Y >= 6 { wood(lx0 + lw, 1, lz0 + lw, lx1, 2, lz1, shade(w, 0.92), .x) }
        if hM >= 0.95 {
            let fy = rd(D(Y) * 0.3)
            box(lx0, fy, lz0, lx1 + lw, fy + 1, lz0 + lw, legC); box(lx0, fy, lz1, lx1 + lw, fy + 1, lz1 + lw, legC)
            box(lx0, fy, lz0, lx0 + lw, fy + 1, lz1 + lw, legC); box(lx1, fy, lz0, lx1 + lw, fy + 1, lz1 + lw, legC)
        }
    }

    func dresser(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let body = colorFromName(name, P.walnut)
        let knob = body == 0xEBE6DC ? P.brass : (name.has("walnut", "brown", "black") || body == P.walnut) ? P.brass : P.charcoal
        // what kind of case piece, from the name and its scanned size
        let nightstand = name.has("nightstand", "night stand", "bedside") || (X <= 13 && Y <= 15 && Z <= 12)
        let wardrobe = name.has("wardrobe", "armoire")
        let doorsStyle = !wardrobe && (attr("storagetype.cabinet") || name.has("sideboard", "credenza", "buffet", "cabinet", "console", "media"))
        let midCentury = name.has("mid-century", "midcentury", "mcm")
        let legH = (midCentury || nightstand) && Y >= 10 ? 2 : Y >= 8 ? 1 : 0
        // short legs
        if legH > 0 { for (lx, lz) in [(0, 0), (X - 1, 0), (0, Z - 2), (X - 1, Z - 2)] { box(lx, 0, lz, lx + 1, legH, lz + 1, shade(body, 0.75)) } }
        wood(0, legH, 0, X, Y - 1, max(1, Z - 1), shade(body, 0.95), .x)
        wood(0, Y - 1, 0, X, Y, Z, body, .x) // top with overhang
        if !wardrobe { surface(0, 0, X, Z, Y) }
        let zf = max(0, Z - 2)
        let y0 = legH + 1, y1 = Y - 1
        box(0, legH, zf, X, legH + 1, zf + 1, shade(body, 0.7)) // kick rail
        if wardrobe {
            // two tall doors, handles by the center seam, a crown on top
            let mid = X / 2
            box(0, y0, zf, X, y1, zf + 1) { x, y, _ in x == 0 || x == mid || y == y0 ? shade(body, 0.78) : body }
            let hy = rd(D(y0 + y1) * 0.5)
            for hx in [mid - 1, mid + 1] { box(hx, hy - 1, zf + 1, hx + 1, hy + 2, zf + 2, knob) }
            box(0, Y - 1, 0, X, Y, Z, shade(body, 1.06))
            return
        }
        // drawer rows from the height (~20 cm each), one or two columns from the width
        var rows = clamp(rd(D(Y - 1 - legH) * voxelM / 0.2), 1, 6)
        let cols = D(X) * voxelM > 0.95 ? 2 : 1
        var doorTop = y0
        if doorsStyle {
            // sideboard: a drawer row on top, cabinet doors below (count from the width)
            let doors = clamp(rd(D(X) * voxelM / 0.45), 2, 4)
            doorTop = Y >= 12 ? y1 - max(2, rd(D(y1 - y0) * 0.28)) : y1
            for k in 0..<doors {
                let x0 = rd(D(X * k) / D(doors)), x1 = rd(D(X * (k + 1)) / D(doors))
                // shaker doors: a frame around a slightly darker recessed panel when there is room
                let panel = x1 - x0 >= 5 && doorTop - y0 >= 6
                box(x0, y0, zf, x1, doorTop, zf + 1) { x, y, _ in
                    if x == x0 || y == y0 { return shade(body, 0.78) }
                    if panel && x > x0 + 1 && x < x1 - 2 && y > y0 + 1 && y < doorTop - 2 { return shade(body, 0.9) }
                    return body
                }
                let kx = k % 2 == 0 ? x1 - 2 : x0 + 1
                if !worn(kx, doorTop, zf, 0.3) { box(kx, rd(D(y0 + doorTop) * 0.55), zf + 1, kx + 1, rd(D(y0 + doorTop) * 0.55) + 2, zf + 2, knob) }
            }
            rows = doorTop < y1 ? 1 : 0
        } else if nightstand && name.has("open", "shelf") && Y >= 8 {
            // nightstand with an open cubby under the drawers
            doorTop = y0 + rd(D(y1 - y0) * 0.45)
            box(1, y0, 1, X - 1, doorTop, Z - 1, -1)
            box(1, doorTop, 1, X - 1, doorTop + 1, Z - 1, body)
            rows = max(1, rows - 1)
            doorTop += 1
        }
        for r in 0..<rows {
            let ry0 = doorTop + rd(D((y1 - doorTop) * r) / D(rows)), ry1 = doorTop + rd(D((y1 - doorTop) * (r + 1)) / D(rows))
            let c = r == rows - 1 && cols == 2 && rows > 2 ? 2 : (doorsStyle ? clamp(rd(D(X) * voxelM / 0.45), 2, 4) : cols)
            for k in 0..<c {
                let x0 = rd(D(X * k) / D(c)), x1 = rd(D(X * (k + 1)) / D(c))
                drawerFront(x0, x1, ry0, ry1, zf, body, knob, c == 1 && X >= 12)
            }
        }
    }

    func bookshelf(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let w = colorFromName(name, name.has("ikea") ? P.birch : P.oak)
        if name.has("ladder", "leaning") { ladderShelf(X, Y, Z, w); return }
        surface(0, 0, X, Z, Y)
        if name.has("cube", "kallax", "cubby", "cubbies", "expedit") { cubeShelf(X, Y, Z, w); return }
        let doors = name.has("doors", "cabinet", "hutch", "with door")
        let back = shade(w, 0.82)
        let plinth = min(2, max(1, rd(D(Y) * 0.05)))
        wood(0, 0, 0, 1, Y, Z, w, .y)
        wood(X - 1, 0, 0, X, Y, Z, w, .y)
        wood(0, Y - 1, 0, X, Y, Z, w, .x)
        wood(1, 0, 0, X - 1, plinth, Z, shade(w, 0.9), .x)
        box(1, plinth, 0, X - 1, Y - 1, 1, back) // back panel at z = 0, open toward +z
        let asked = name.number(before: ["shelf", "shelves", "tier"], multiDigit: true)
        let nComp = clamp(asked ?? rd(D(Y) * voxelM / 0.36), 1, max(1, fdiv(Y - plinth - 1, 3)))
        let yTop = Y - 1
        var bounds: [Int] = []
        for i in 0...nComp { bounds.append(plinth + rd(D((yTop - plinth) * i) / D(nComp))) }
        // boards at bounds[1..nComp-1] (board occupies the layer at that y)
        for i in upTo(1, nComp) { wood(1, bounds[i], 0, X - 1, bounds[i] + 1, Z, w, .x) }
        let zFront = Z - 1
        let closedBelow = doors && nComp >= 2 ? 1 : 0
        for i in closedBelow..<max(closedBelow, nComp) {
            let yb = i == 0 ? plinth : bounds[i] + 1 // first free layer
            let yt = bounds[i + 1] // exclusive
            let gapH = yt - yb
            if gapH < 1 { continue }
            // leave a free slot on some shelves for props / a plant
            let freeRight = i % 2 == 1 || i == nComp - 1
            let endX = freeRight ? 1 + rd(D(X - 2) * 0.62) : X - 1
            var x = 1
            while x < endX {
                let roll = rand()
                if roll < 0.07 && x > 1 { x += 1; continue } // gap
                if roll < 0.15 && endX - x >= 4 && gapH >= 3 {
                    // horizontal stack
                    let n = 1 + fl(rand() * 3)
                    var k = 0
                    while k < n && k < gapH - 1 {
                        let c = bookColors[min(bookColors.count - 1, fl(rand() * D(bookColors.count)))]
                        box(x, yb + k, 1, x + 3 + (k % 2), yb + k + 1, zFront - (k % 2), c)
                        k += 1
                    }
                    x += 4
                    continue
                }
                let bw = rand() < 0.2 ? 2 : 1
                let bh = clamp(rd(D(gapH) * (0.55 + rand() * 0.4)), 1, gapH)
                let c = bookColors[min(bookColors.count - 1, fl(rand() * D(bookColors.count)))]
                let zd = zFront - (rand() < 0.35 ? 1 : 0)
                box(x, yb, 1, min(endX, x + bw), yb + bh, zd, c)
                // spine band / label
                if bh >= 3 && rand() < 0.6 {
                    let f = rand() < 0.5 ? 1.25 : 0.7
                    box(x, yb + bh - 2, zd - 1, min(endX, x + bw), yb + bh - 1, zd, shade(c, f))
                }
                x += bw
            }
            if freeRight {
                let sx0 = endX + 1, sx1 = X - 1
                if i == nComp - 1 && sx1 - sx0 >= 2 && gapH >= 4 {
                    // small potted plant on the top shelf
                    let px = rd(D(sx0 + sx1 - 1) / 2), pz = rd(D(Z) / 2)
                    box(px - 1, yb, pz - 1, px + 1, yb + 2, pz + 1, P.terracotta)
                    ellipsoid(D(px) - 0.5, D(yb + 2) + D(min(2, gapH - 3)) * 0.6, D(pz) - 0.5, 1.8, min(1.6, D(gapH - 2) / 2), 1.6) { _, yy, _, _ in
                        yy > yb + 3 ? 0x7FA262 : 0x4F7A3F
                    }
                } else if sx1 - sx0 >= 2 {
                    // the free end of the shelf (back panel at z = 0), under the next board
                    surface(sx0, 1, sx1, Z, yb, clearance: gapH)
                }
            }
        }
        // a wide case (>= 1.1 m) has a center divider
        if X >= 22 { wood(X / 2, plinth, 1, X / 2 + 1, Y - 1, Z, w, .y) }
        // cabinet doors over the bottom compartment
        if closedBelow == 1 {
            let yt = bounds[1]
            let nd = X >= 10 ? 2 : 1
            for k in 0..<nd {
                let x0 = 1 + rd(D((X - 2) * k) / D(nd)), x1 = 1 + rd(D((X - 2) * (k + 1)) / D(nd))
                box(x0, plinth, zFront, x1, yt, Z) { x, y, _ in x == x0 || y == plinth ? shade(w, 0.8) : shade(w, 0.97) }
                let kx = k == 0 && nd == 2 ? x1 - 2 : x0 + 1
                if !worn(kx, yt, zFront, 0.3) { set(kx, (plinth + yt) / 2, zFront, P.brass) }
            }
        }
    }

    /// Leaning ladder shelf: side rails lean against the wall (top at z = 0), shelves get
    /// shallower toward the top, a few books and props on each.
    func ladderShelf(_ X: Int, _ Y: Int, _ Z: Int, _ w: Int) {
        let railZ: (Int) -> Int = { y in rd(D(Z - 1) * (1 - D(y) / D(max(1, Y - 1)))) }
        for x in [0, X - 1] { line(D(x), 0, D(Z - 1), D(x), D(Y - 1), 0, w) }
        let n = clamp(rd(D(Y) * voxelM / 0.35), 2, 7)
        for i in 0..<n {
            let y = rd(D(Y - 2) * D(i) / D(n))
            let zf = railZ(y)
            let depth = max(2, rd(D(Z) * 0.85 * (1 - D(i) / D(n + 1))))
            wood(1, y, max(0, zf - depth + 1), X - 1, y + 1, zf + 1, w, .x)
            // books standing on it
            var x = 1 + fl(rand() * 2)
            let gap = rd(D(Y - 2) / D(n)) - 1
            while x < X - 2 && gap >= 2 {
                if rand() < 0.25 { x += 2; continue }
                let c = bookColors[min(bookColors.count - 1, fl(rand() * D(bookColors.count)))]
                let bh = clamp(rd(D(gap) * (0.5 + rand() * 0.4)), 1, gap)
                box(x, y + 1, max(0, zf - depth + 1), x + 1, y + 1 + bh, zf, c)
                x += 1
            }
        }
    }

    /// Cube storage (Kallax-style): a grid of square cubbies from the scanned size, some with
    /// fabric bins, some with books (the mix is a per-item detail).
    func cubeShelf(_ X: Int, _ Y: Int, _ Z: Int, _ w: Int) {
        let cols = max(1, rd(D(X) * voxelM / 0.37)), rows = max(1, rd(D(Y) * voxelM / 0.37))
        box(0, 0, 0, X, Y, Z) { x, y, _ in x == 0 || x == X - 1 || y == 0 || y == Y - 1 ? w : nil }
        box(1, 1, 0, X - 1, Y - 1, 1, shade(w, 0.85)) // back
        var xs: [Int] = [], ys: [Int] = []
        for c in 0...cols { xs.append(rd(D((X - 1) * c) / D(cols))) }
        for r in 0...rows { ys.append(rd(D((Y - 1) * r) / D(rows))) }
        for x in xs.dropFirst().dropLast() { box(x, 0, 0, x + 1, Y, Z, w) }
        for y in ys.dropFirst().dropLast() { box(0, y, 0, X, y + 1, Z, w) }
        let bins = [P.sage, P.linen, P.navy, P.charcoal, P.blush, P.oatmeal]
        let binC = bins[Int(seed % UInt32(bins.count))]
        for c in 0..<cols {
            for r in 0..<rows {
                let x0 = xs[c] + 1, x1 = xs[c + 1], yb = ys[r] + 1, yt = ys[r + 1]
                if x1 - x0 < 2 || yt - yb < 2 { continue }
                let pick = hash3(c, r, 7, seed)
                if pick < 0.35 {
                    // fabric bin with a hand hole
                    box(x0, yb, 1, x1, yt - (yt - yb > 3 ? 1 : 0), Z) { x, y, z in
                        z == Z - 1 && x == (x0 + x1) / 2 && y == yt - 2 ? shade(binC, 0.5) : binC
                    }
                } else if pick < 0.75 {
                    for x in upTo(x0, x1) where hash3(x, r, 11, seed) < 0.85 {
                        let c2 = bookColors[Int(hash3(x, r, 5, seed) * D(bookColors.count)) % bookColors.count]
                        box(x, yb, 1, x + 1, yb + clamp(rd(D(yt - yb) * (0.6 + 0.35 * hash3(x, r, 3, seed))), 1, yt - yb), Z - 1, c2)
                    }
                }
            }
        }
    }

    func tv(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName, wall: Bool) {
        let bezel = 0x1C1C1E
        let onStand = !wall && D(Y) * voxelM > 0.7
        var y0 = 0, x0 = 0, x1 = X
        if onStand {
            let cH = clamp(rd(D(Y) * 0.36), 3, Y - 6)
            let w = colorFromName(name, P.walnut)
            for (lx, lz) in [(1, 0), (X - 2, 0), (1, Z - 1), (X - 2, Z - 1)] { box(lx, 0, lz, lx + 1, 1, lz + 1, P.black) }
            wood(0, 1, 0, X, cH, Z, shade(w, 0.95), .x)
            wood(0, cH - 1, 0, X, cH, Z, w, .x)
            let doors = clamp(rd(D(X) / 10), 2, 4)
            for k in 0..<doors {
                let dx0 = rd(D(X * k) / D(doors)), dx1 = rd(D(X * (k + 1)) / D(doors))
                box(dx0, 1, Z - 1, dx0 + 1, cH - 1, Z, shade(w, 0.75))
                set(dx1 - 2, rd(D(cH) / 2), Z - 1, P.brass)
            }
            y0 = cH
            x0 = rd(D(X) * 0.07); x1 = X - x0
            // the console's front strip, in front of the panel's stand
            surface(0, min(Z - 1, Z / 2 + 2), X, Z, cH)
        }
        let zc = Z >= 3 ? Z / 2 : Z - 1
        let standH = wall ? 0 : clamp(rd(D(Y - y0) * 0.1), 1, 3)
        let standC = 0x2A2A2C
        // stand: two feet (or center pedestal on a console); wall-mounted panels get a bracket instead
        if wall {
            if zc > 0 { box(X / 2 - 1, Y / 2 - 1, 0, X / 2 + 1, Y / 2 + 1, zc, standC) }
        } else if onStand {
            let mx = X / 2
            box(mx - 2, y0, max(0, zc - 1), mx + 2, y0 + 1, min(Z, zc + 2), standC)
            box(mx, y0, zc, mx + 1, y0 + standH, zc + 1, standC)
        } else {
            for fx in [x0 + rd(D(x1 - x0) * 0.15), x1 - 1 - rd(D(x1 - x0) * 0.15)] {
                box(fx, 0, 0, fx + 1, 1, Z, standC)
                box(fx, 1, zc, fx + 1, standH + 1, zc + 1, standC)
            }
        }
        let py0 = y0 + standH
        // back housing
        if zc > 0 { box(x0 + rd(D(x1 - x0) * 0.2), py0 + 2, zc - 1, x1 - rd(D(x1 - x0) * 0.2), Y - 2, zc, 0x26262A) }
        // panel: bezel + dark screen with a faint diagonal reflection, facing +z
        let pw = D(x1 - x0), phh = D(Y - py0)
        box(x0, py0, zc, x1, Y, zc + 1, flat: true) { x, y, _ in
            if x == x0 || x == x1 - 1 || y == py0 || y == Y - 1 { return bezel }
            let d = D(x - x0) - D(y - py0) * 1.2
            let band = d > pw * 0.45 && d < pw * 0.6
            return band ? 0x262C36 : D(y - py0) > phh * 0.6 ? 0x1A1E25 : P.screen
        }
        // standby LED + logo
        set((x0 + x1) / 2, py0, zc, 0x6A6A70, flat: true)
        if zc + 1 < Z { set(x1 - 3, py0, zc + 1, 0xC0392B, flat: true) }
        // a badly worn screen is cracked
        if wear >= 2.5 && x1 - x0 >= 6 && Y - py0 >= 5 {
            let ix = x0 + rd(D(x1 - x0) * 0.35), iy = py0 + rd(D(Y - py0) * 0.6)
            for (dx, dy) in [(1.0, 0.35), (-1.0, 0.5), (0.4, -1.0), (-0.6, -0.8)] {
                var x = D(ix), y = D(iy)
                while true {
                    x += dx; y += dy
                    let px = rd(x), py = rd(y)
                    if px <= x0 || px >= x1 - 1 || py <= py0 || py >= Y - 1 { break }
                    set(px, py, zc, 0x9AA3AD, flat: true)
                }
            }
        }
    }

    func lamp(_ X: Int, _ Y: Int, _ Z: Int, _ name: VName) {
        let shadeC = colorFromName(name.removingWords("metal", "steel", "brass"), P.cream)
        let poleC = name.word("black") ? P.black : name.word("metal", "steel", "chrome", "silver", "nickel") ? P.metal : P.brass
        let cx = D(X - 1) / 2, cz = D(Z - 1) / 2
        let R = D(min(X, Z)) / 2
        let floor = D(Y) * voxelM > 0.9
        if floor && (name.word("arc") || name.has("arched", "arching")) {
            // marble block base at one side, arching pole to a dome shade hanging on the other
            let bx = 1, bz = rd(cz)
            box(0, 0, max(0, bz - 1), 3, 2, min(Z, bz + 2), 0xE7E2D8)
            // the dome fills the scanned depth
            let dr = clampD(D(Z) / 2 - 0.3, 1.5, 8)
            let rr = max(2, rd(min(D(X) - 1 - dr + 0.5, D(X - 3)) - D(bx)))
            let tipY = Y - 1
            let poleTop = tipY - rr
            box(bx, 2, bz, bx + 1, poleTop + 1, bz + 1, poleC)
            var px = D(bx), py = D(poleTop)
            for i in 1...16 {
                let th = D(i) / 16 * (Double.pi / 2)
                let ax = D(bx + rr) - D(rr) * cos(th), ay = D(poleTop) + D(rr) * sin(th)
                line(px, py, D(bz), ax, ay, D(bz), poleC)
                px = ax; py = ay
            }
            // dome shade hanging under the tip (upper hemisphere shell, open at the bottom)
            let dcx = min(X - 1, bx + rr), dc = tipY - 1 - rd(dr)
            box(dcx, dc + rd(dr), bz, dcx + 1, tipY, bz + 1, poleC)
            var y = dc
            while D(y) <= D(dc) + dr {
                for z in thru(fl(cz - dr), ce(cz + dr)) {
                    for x in thru(fl(D(dcx) - dr), ce(D(dcx) + dr)) {
                        let d2 = D((x - dcx) * (x - dcx) + (y - dc) * (y - dc)) + (D(z) - cz) * (D(z) - cz)
                        if d2 > dr * dr + 0.5 || d2 < (dr - 1.1) * (dr - 1.1) { continue }
                        set(x, y, z, y == dc ? 0xF6DEAC : shadeC, flat: y == dc)
                    }
                }
                y += 1
            }
            set(dcx, dc, rd(cz), P.bulb, flat: true)
            set(dcx, dc + 1, rd(cz), 0xFFE7B0, flat: true)
            return
        }
        if floor && name.has("torchiere", "torchière", "uplight") {
            // torchiere: slim pole to an upturned glowing bowl
            cyl(cx, cz, max(1, R * 0.6), 0, 1, P.charcoal)
            box(rd(cx), 1, rd(cz), rd(cx) + 1, Y - 2, rd(cz) + 1, poleC)
            cyl(cx, cz, max(1, R * 0.45), Y - 3, Y - 2, poleC)
            cyl(cx, cz, max(1, R - 0.3), Y - 2, Y, shadeC, hollow: true)
            cyl(cx, cz, max(0.8, R - 1.3), Y - 2, Y - 1, P.bulb, flat: true)
            return
        }
        if floor && name.has("tripod") {
            // tripod legs meeting under a drum shade
            let sh = clamp(rd(D(Y) * 0.22), 3, 7)
            let sb = Y - sh
            for k in 0..<3 {
                let a = D(k) * 2 * Double.pi / 3 + Double.pi / 2
                line(cx, D(sb - 1), cz, cx + cos(a) * (R - 0.5), 0, cz + sin(a) * (R - 0.5), colorFromName(name.removingWords("linen", "fabric"), P.walnut))
            }
            for y in upTo(sb, Y) { cyl(cx, cz, max(1, R - 0.3), y, y + 1, y == sb ? shade(shadeC, 0.9) : shadeC, hollow: true) }
            set(rd(cx), sb + 1, rd(cz), P.bulb, flat: true)
            return
        }
        if !floor && name.has("desk lamp", "task", "architect", "swing arm", "banker") {
            // desk lamp: round base at the back, an elbowed arm, a cone head pointing down at the front
            let baseC = colorFromName(name, P.black)
            cyl(cx, 1.5, max(1, R * 0.6), 0, 1, baseC)
            let ex = cx, ey = D(Y) * 0.7, ez = 1.0
            line(cx, 1, 1.5, ex, ey, ez, baseC)
            let hx = cx, hy = D(Y - 2), hz = D(Z - 2)
            line(ex, ey, ez, hx, hy, hz, baseC)
            box(rd(hx) - 1, Y - 2, rd(hz) - 1, rd(hx) + 1, Y, rd(hz) + 1, baseC)
            set(rd(hx), Y - 3, rd(hz), P.bulb, flat: true)
            return
        }
        if floor {
            // shade about a fifth of the height but never much taller than it is wide; a weighted
            // disc base with a hub, a thin pole up into the shade
            let sh = clamp(rd(D(Y) * 0.2), 3, max(3, min(8, rd(R * 2.4))))
            let sb = Y - sh
            cyl(cx, cz, max(1, R * 0.62), 0, 1, P.charcoal)
            if Y >= 20 { cyl(cx, cz, max(1, R * 0.3), 1, 2, shade(poleC, 0.85)) }
            box(rd(cx), 1, rd(cz), rd(cx) + 1, sb + 2, rd(cz) + 1, poleC)
            let shadeLo = shade(shadeC, 0.9), shadeAlt = shade(shadeC, 0.96)
            for y in upTo(sb, Y) {
                let t = D(y - sb) / D(max(1, sh - 1))
                let r = max(1, R - 0.3 - t * R * 0.3)
                cyl(cx, cz, r, y, y + 1, y == sb ? shadeLo : (y % 2 == 1 ? shadeC : shadeAlt), hollow: true)
            }
            set(rd(cx), sb + 1, rd(cz), P.bulb, flat: true)
            set(rd(cx), sb, rd(cz), 0xFFE7B0, flat: true)
            // warm-lit inner rim (models.js wrote black into the middle here; we skip it instead)
            let inner = (R - 1.6) * (R - 1.6)
            cyl(cx, cz, max(1, R - 0.3), sb, sb + 1, flat: true) { _, _, _, d2 in d2 > inner ? 0xF6DEAC : nil }
            return
        }
        // table lamp: ceramic base, neck, drum shade
        let bh = max(2, rd(D(Y) * 0.4))
        let baseC = colorFromName(name, P.sage)
        let baseLo = shade(baseC, 0.8)
        ellipsoid(cx, D(bh) / 2, cz, max(1, R * 0.55), D(bh) / 2, max(1, R * 0.55)) { _, y, _, _ in y == 0 ? baseLo : baseC }
        let sb = max(bh + 1, rd(D(Y) * 0.55))
        box(rd(cx), bh, rd(cz), rd(cx) + 1, sb + 1, rd(cz) + 1, P.brass)
        for y in upTo(sb, Y) { cyl(cx, cz, max(1, R - 0.2 - D(y - sb) / D(max(1, Y - sb)) * 0.8), y, y + 1, P.cream, hollow: true) }
        set(rd(cx), sb + 1, rd(cz), P.bulb, flat: true)
    }
}
