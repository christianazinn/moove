import SwiftUI
import MooveKit

/// A small isometric voxel drawing of one piece on a rounded tile, for list rows
/// (the prototype's 56 pt `.thumb`). The sprite is built once per spec and cached.
@MainActor
struct VoxelThumbnail: View {
    var spec: VoxelItemSpec
    var size: CGFloat = 56

    init(spec: VoxelItemSpec, size: CGFloat = 56) {
        self.spec = spec
        self.size = size
    }

    init(_ item: LayoutItem, size: CGFloat = 56) {
        self.init(spec: VoxelItemSpec(item), size: size)
    }

    /// With the item's attributes, material and stored colors (`item.colors`); a demo bedroom
    /// item with none stored uses the demo room's fixture colors.
    init(_ item: Item, size: CGFloat = 56) {
        var spec = VoxelItemSpec(item)
        if item.colors == nil, DemoFixtures.isDemoItem(item), let c = DemoFixtures.scanColors().colors(for: item) {
            spec.primaryColor = c.primary
            spec.secondaryColor = c.secondary
        }
        self.init(spec: spec, size: size)
    }

    var body: some View {
        let sprite = VoxelSpriteCache.sprite(for: spec)
        Canvas { ctx, canvasSize in
            let inset = canvasSize.width * 0.14
            let side = min(canvasSize.width, canvasSize.height) - inset * 2
            let ox = (canvasSize.width - side) / 2, oy = (canvasSize.height - side) / 2
            for face in sprite.faces where face.points.count >= 3 {
                var path = Path()
                path.addLines(face.points.map { CGPoint(x: ox + CGFloat($0.x) * side, y: oy + CGFloat($0.y) * side) })
                path.closeSubpath()
                let color = GraphicsContext.Shading.color(Theme.color(face.color))
                ctx.fill(path, with: color)
                // A hairline in the same color hides the seams between neighboring faces.
                ctx.stroke(path, with: color, lineWidth: 0.5)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMedium, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Sprites by spec. Building a voxel model and projecting it is cheap but not free,
/// and lists redraw often, so each spec is rendered once per launch.
@MainActor
enum VoxelSpriteCache {
    private static var sprites: [VoxelItemSpec: IsoSprite] = [:]

    static func sprite(for spec: VoxelItemSpec) -> IsoSprite {
        if let cached = sprites[spec] { return cached }
        let sprite = IsoSprite.render(VoxelModels.build(spec))
        if sprites.count > 400 { sprites.removeAll() }
        sprites[spec] = sprite
        return sprite
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(DemoFixtures.inventory(owner: "demo").items.prefix(4)) { item in
            VoxelThumbnail(item)
        }
    }
    .padding()
    .background(Theme.bg)
}

#Preview("Extra categories (#183)") {
    let specs: [(String, String)] = [
        ("guitar", "Acoustic guitar"), ("guitar", "Electric guitar"), ("piano", "Upright piano"), ("piano", "Grand piano"),
        ("keyboard instrument", "Keyboard"), ("drums", "Drum kit"), ("vacuum", "Upright vacuum"), ("vacuum", "Robot vacuum"),
        ("monitor", "Monitor"), ("scooter", "Kick scooter"), ("scooter", "Electric scooter"), ("bag", "Backpack"),
        ("bag", "Duffel bag"), ("golf clubs", "Golf bag"), ("treadmill", "Treadmill"), ("exercise bike", "Exercise bike"),
        ("skateboard", "Skateboard"), ("surfboard", "Surfboard"), ("air purifier", "Air purifier"), ("bicycle", "Bicycle"),
    ]
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(60)), count: 5), spacing: 8) {
        ForEach(specs.indices, id: \.self) { i in
            VoxelThumbnail(spec: VoxelItemSpec(category: specs[i].0, name: specs[i].1, widthM: 0, depthM: 0, heightM: 0))
        }
    }
    .padding()
    .background(Theme.bg)
}
