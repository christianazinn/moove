import Foundation
@testable import MooveKit

/// Eyeball voxel models without a device: rasterizes `IsoSprite` thumbnails (the same drawing
/// `VoxelThumbnail` shows in the app) to PNG with a tiny pure-Swift encoder, so it runs on Linux
/// CI / Docker too. Two views per piece: front-right (the app's thumbnail) and front-left (the
/// grid mirrored in x). See `VoxelPreviewTests` and ios/CLAUDE.md (ios-newhome).
enum VoxelPreview {
    static let background: UInt32 = 0xF4F1EA

    /// The grid mirrored left-right (shows the piece from the front-left).
    static func mirrored(_ g: VoxelGrid) -> VoxelGrid {
        var out = VoxelGrid(nx: g.nx, ny: g.ny, nz: g.nz)
        for y in 0..<g.ny { for z in 0..<g.nz { for x in 0..<g.nx { out[g.nx - 1 - x, y, z] = g[x, y, z] } } }
        return out
    }

    /// A `size`² RGB image of the sprite (0xRRGGBB pixels, row major).
    static func raster(_ sprite: IsoSprite, size: Int, pad: Int = 6) -> [UInt32] {
        var px = [UInt32](repeating: background, count: size * size)
        let s = Float(size - 2 * pad)
        for face in sprite.faces {
            let pts = face.points.map { SIMD2<Float>($0.x * s + Float(pad), $0.y * s + Float(pad)) }
            guard pts.count >= 3 else { continue }
            let lo = pts.reduce(pts[0]) { pointwiseMin($0, $1) }, hi = pts.reduce(pts[0]) { pointwiseMax($0, $1) }
            let x0 = max(0, Int(lo.x.rounded(.down))), x1 = min(size - 1, Int(hi.x.rounded(.up)))
            let y0 = max(0, Int(lo.y.rounded(.down))), y1 = min(size - 1, Int(hi.y.rounded(.up)))
            guard x0 <= x1, y0 <= y1 else { continue }
            // convex polygon: inside when every edge's cross product has one sign (with a hair of slack, no seams)
            var area: Float = 0
            for i in pts.indices { let a = pts[i], b = pts[(i + 1) % pts.count]; area += a.x * b.y - b.x * a.y }
            let sign: Float = area >= 0 ? 1 : -1
            for y in y0...y1 {
                for x in x0...x1 {
                    let p = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5)
                    var inside = true
                    for i in pts.indices {
                        let a = pts[i], b = pts[(i + 1) % pts.count]
                        let e = b - a, len = max(1e-6, (e.x * e.x + e.y * e.y).squareRoot())
                        if sign * (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / len < -0.35 { inside = false; break }
                    }
                    if inside { px[y * size + x] = face.color }
                }
            }
        }
        return px
    }

    /// Draws `text` (A-Z, 0-9, a few marks) with a 3x5 pixel font, `scale` px per font pixel.
    static func label(_ text: String, into px: inout [UInt32], width: Int, x: Int, y: Int, scale: Int = 2, color: UInt32 = 0x34322F) {
        var cx = x
        for ch in text.uppercased() {
            if let rows = glyphs[ch] {
                for (r, row) in rows.enumerated() {
                    for (c, bit) in row.enumerated() where bit == "1" {
                        for dy in 0..<scale {
                            for dx in 0..<scale {
                                let xx = cx + c * scale + dx, yy = y + r * scale + dy
                                if xx >= 0, xx < width, yy >= 0, yy * width + xx < px.count { px[yy * width + xx] = color }
                            }
                        }
                    }
                }
            }
            cx += 4 * scale
        }
    }

    /// One tile: both views side by side, `title` and `subtitle` underneath.
    static func tile(_ grid: VoxelGrid, title: String, subtitle: String, size: Int = 220) -> (w: Int, h: Int, px: [UInt32]) {
        let w = size * 2, h = size + 34
        var px = [UInt32](repeating: background, count: w * h)
        for (i, g) in [grid, mirrored(grid)].enumerated() {
            let r = raster(IsoSprite.render(g), size: size)
            for y in 0..<size { for x in 0..<size { px[y * w + i * size + x] = r[y * size + x] } }
        }
        label(title, into: &px, width: w, x: 6, y: size + 4)
        label(subtitle, into: &px, width: w, x: 6, y: size + 20, color: 0x8F8D88)
        return (w, h, px)
    }

    /// Tiles laid out `columns` wide.
    static func sheet(_ tiles: [(w: Int, h: Int, px: [UInt32])], columns: Int) -> (w: Int, h: Int, px: [UInt32]) {
        guard let first = tiles.first else { return (1, 1, [background]) }
        let tw = first.w + 8, th = first.h + 8
        let rows = (tiles.count + columns - 1) / columns
        let w = tw * min(columns, tiles.count), h = th * rows
        var px = [UInt32](repeating: 0xFFFFFF, count: w * h)
        for (i, t) in tiles.enumerated() {
            let ox = (i % columns) * tw + 4, oy = (i / columns) * th + 4
            for y in 0..<t.h { for x in 0..<t.w { px[(oy + y) * w + ox + x] = t.px[y * t.w + x] } }
        }
        return (w, h, px)
    }

    // MARK: PNG (8-bit RGB, stored deflate blocks)

    static func png(width: Int, height: Int, pixels: [UInt32]) -> Data {
        var raw: [UInt8] = []
        raw.reserveCapacity(height * (width * 3 + 1))
        for y in 0..<height {
            raw.append(0)
            for x in 0..<width {
                let c = pixels[y * width + x]
                raw.append(UInt8((c >> 16) & 255)); raw.append(UInt8((c >> 8) & 255)); raw.append(UInt8(c & 255))
            }
        }
        var z: [UInt8] = [0x78, 0x01]
        var i = 0
        repeat {
            let n = min(65535, raw.count - i)
            z.append(i + n >= raw.count ? 1 : 0)
            z += [UInt8(n & 255), UInt8(n >> 8), UInt8(~n & 255), UInt8((~n >> 8) & 255)]
            z += raw[i..<(i + n)]
            i += n
        } while i < raw.count
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in raw { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        z += be((b << 16) | a)

        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        func chunk(_ type: String, _ data: [UInt8]) {
            out += be(UInt32(data.count))
            let body = Array(type.utf8) + data
            out += body
            out += be(crc32(body))
        }
        chunk("IHDR", be(UInt32(width)) + be(UInt32(height)) + [8, 2, 0, 0, 0])
        chunk("IDAT", z)
        chunk("IEND", [])
        return Data(out)
    }

    private static func be(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)] }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for byte in bytes { c = crcTable[Int((c ^ UInt32(byte)) & 255)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    private static let glyphs: [Character: [String]] = {
        let src: [(Character, String)] = [
            ("A", "010101111101101"), ("B", "110101110101110"), ("C", "011100100100011"), ("D", "110101101101110"),
            ("E", "111100110100111"), ("F", "111100110100100"), ("G", "011100101101011"), ("H", "101101111101101"),
            ("I", "111010010010111"), ("J", "001001001101010"), ("K", "101101110101101"), ("L", "100100100100111"),
            ("M", "101111111101101"), ("N", "110101101101101"), ("O", "010101101101010"), ("P", "110101110100100"),
            ("Q", "010101101110011"), ("R", "110101110101101"), ("S", "011100010001110"), ("T", "111010010010010"),
            ("U", "101101101101111"), ("V", "101101101101010"), ("W", "101101111111101"), ("X", "101101010101101"),
            ("Y", "101101010010010"), ("Z", "111001010100111"), ("0", "111101101101111"), ("1", "010110010010111"),
            ("2", "110001010100111"), ("3", "110001010001110"), ("4", "101101111001001"), ("5", "111100110001110"),
            ("6", "011100111101111"), ("7", "111001010010010"), ("8", "111101111101111"), ("9", "111101111001110"),
            ("-", "000000111000000"), (".", "000000000000010"), (">", "100010001010100"), ("/", "001001010100100"),
            ("X", "101101010101101"), ("(", "010100100100010"), (")", "010001001001010"), (":", "000010000010000"),
        ]
        var out: [Character: [String]] = [:]
        for (c, bits) in src {
            let a = Array(bits)
            out[c] = (0..<5).map { String(a[($0 * 3)..<($0 * 3 + 3)]) }
        }
        return out
    }()
}
