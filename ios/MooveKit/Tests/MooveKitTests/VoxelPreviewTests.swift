import Foundation
import Testing
@testable import MooveKit

/// Writes PNG previews of voxel models when `VOXEL_PREVIEW_DIR` is set (a no-op otherwise, so CI
/// skips it). One PNG per piece (front-right and front-left views) plus `contact-sheet.png`.
///
///     VOXEL_PREVIEW_DIR=/out swift test --filter VoxelPreviewTests
///
/// `VOXEL_PREVIEW_SET`: `scan9` (default: Lisa's scan-9 objects at their scanned sizes plus the
/// detector's extra props), `kinds` (every kind at its default size), or `all`.
/// `VOXEL_PREVIEW_ONLY`: comma-separated substrings of names to keep.
struct VoxelPreviewTests {
    struct Piece {
        var file: String
        var spec: VoxelItemSpec
    }

    static func pieces(_ set: String) -> [Piece] {
        var out: [Piece] = []
        if set == "scan9" || set == "all" {
            for (i, o) in Scan9VoxelTests.objects.enumerated() {
                out.append(Piece(file: String(format: "%02d-", i + 1) + o.label.replacingOccurrences(of: " ", with: "-"), spec: o.spec))
            }
            for (cat, name, w, d, h) in Scan9VoxelTests.extraProps {
                out.append(Piece(file: "x-" + name.lowercased().replacingOccurrences(of: " ", with: "-"),
                                 spec: VoxelItemSpec(category: cat, name: name, widthM: w, depthM: d, heightM: h, id: name)))
            }
        }
        if set == "kinds" || set == "all" {
            for k in VoxelModels.Kind.allCases {
                let (cat, name) = RenderBudgetTests.kindSamples[k] ?? (k.rawValue, k.rawValue)
                out.append(Piece(file: "kind-" + k.rawValue, spec: VoxelItemSpec(category: cat, name: name, widthM: 0, depthM: 0, heightM: 0)))
            }
        }
        return out
    }

    @Test func writePreviews() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["VOXEL_PREVIEW_DIR"], !dir.isEmpty else { return }
        let only = (env["VOXEL_PREVIEW_ONLY"] ?? "").split(separator: ",").map { String($0).lowercased() }
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var tiles: [(w: Int, h: Int, px: [UInt32])] = []
        var index: [String] = []
        for p in Self.pieces(env["VOXEL_PREVIEW_SET"] ?? "scan9") where only.isEmpty || only.contains(where: { p.file.contains($0) }) {
            let kind = VoxelModels.kind(p.spec)
            let grid = VoxelModels.build(p.spec)
            let tris = VoxelMesher.mesh(grid).triangleCount
            let sub = "\(kind.rawValue) \(grid.nx)X\(grid.ny)X\(grid.nz) \(tris)T"
            let t = VoxelPreview.tile(grid, title: p.file, subtitle: sub)
            tiles.append(t)
            try VoxelPreview.png(width: t.w, height: t.h, pixels: t.px).write(to: url.appendingPathComponent(p.file + ".png"))
            index.append("\(p.file)\t\(p.spec.category)/\(p.spec.name)\t\(kind.rawValue)\t\(tris) tri")
        }
        let sheet = VoxelPreview.sheet(tiles, columns: 4)
        try VoxelPreview.png(width: sheet.w, height: sheet.h, pixels: sheet.px).write(to: url.appendingPathComponent("contact-sheet.png"))
        try index.joined(separator: "\n").write(to: url.appendingPathComponent("index.tsv"), atomically: true, encoding: .utf8)
    }
}
