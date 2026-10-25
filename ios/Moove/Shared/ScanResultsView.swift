import SwiftUI
import MooveKit

/// What a scan found, MoveWise style: the room as a voxel dollhouse with every item in it,
/// then a quiet ledger: voxel thumbnail, name and value range per item (size and condition are
/// in the VoiceOver label only).
/// Takes plain inputs so the Scan page can drop it in with one line.
///
/// Items don't carry scanned positions yet, so the room is a single rectangle sized to hold
/// them and the layout solver places them; the caption says so.
struct ScanResultsView: View {
    var room: Room?
    var items: [Item]
    var onSelect: (Item) -> Void
    /// The scan's real room (walls, doors, windows, object positions). Nil: estimate a room.
    var geometry: RoomGeometry?
    /// Real colors sampled from the scan's photos: furniture uses them over its keyword palette.
    /// `colors?.wallColor` / `floorColor` are for the dollhouse shell (VoxelHouse) once it takes them.
    var colors: ScanColors?

    init(room: Room?, items: [Item], geometry: RoomGeometry? = nil, colors: ScanColors? = nil,
         onSelect: @escaping (Item) -> Void = { _ in }) {
        self.room = room
        self.items = items
        self.geometry = geometry
        self.colors = colors
        self.onSelect = onSelect
    }

    @State private var model: EstimatedRoom?
    @State private var flyInToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
            inventory.padding(.top, Theme.Space.xl)
        }
        .onChange(of: ModelKey(name: roomName, items: items.map { LayoutItem($0, colors: colors) }, geometry: geometry), initial: true) { _, key in
            if let geometry = key.geometry {
                model = EstimatedRoom.scanned(name: key.name, geometry: geometry, items: items, layoutItems: key.items)
            } else {
                model = EstimatedRoom.build(name: key.name, items: key.items)
            }
            flyInToken += 1
        }
    }

    private var roomName: String { room?.name ?? "Room" }

    private struct ModelKey: Equatable {
        var name: String
        var items: [LayoutItem]
        var geometry: RoomGeometry?
    }

    // MARK: Dollhouse

    private var stage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let model {
                    FloorPlan3DView(plan: model.plan, focusRoom: nil, items: model.items, placements: model.placements, flyInToken: flyInToken,
                                    wallColor: colors?.wallColor, floorColor: colors?.floorColor)
                        .accessibilityElement()
                        .accessibilityLabel("3D view of \(roomName) with \(items.count) objects")
                        .accessibilityHint("Drag to orbit, pinch to zoom, double-tap to reset")
                } else {
                    Theme.surface
                }
            }
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))

        }
    }

    // MARK: Inventory

    private var inventory: some View {
        return VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text("Nothing found yet.").monoMeta().padding(.vertical, 28).frame(maxWidth: .infinity, alignment: .leading).ruled()
            }
            ForEach(items) { item in
                Button { onSelect(item) } label: {
                    LedgerRow(
                        title: item.name,
                        value: item.saleValueCents == nil ? "…" : item.priceText,
                        valueTint: item.saleValueCents == nil ? Theme.muted : Theme.text
                    ) {
                        VoxelThumbnail(spec: Self.spec(item, colors: colors), size: 44)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spokenRow(item))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    /// The thumbnail spec (attributes, material, condition), with the item's scanned colors when
    /// there are any, else the colors it stores (`set_item_colors`).
    static func spec(_ item: Item, colors: ScanColors?) -> VoxelItemSpec {
        var spec = VoxelItemSpec(item)
        if let c = colors?.colors(for: item) {
            spec.primaryColor = c.primary
            spec.secondaryColor = c.secondary
        }
        return spec
    }

    /// The row's full detail for VoiceOver: name, value, size, condition, "needs you".
    static func spokenRow(_ item: Item) -> String {
        var parts = [item.name, item.saleValueCents == nil ? "pricing" : item.priceText, meta(item)]
        if item.maybeSentimental { parts.append("needs you") }
        return parts.joined(separator: ", ")
    }

    static func meta(_ item: Item) -> String {
        let size = String(format: "%.1f × %.1f m", item.widthM, item.depthM)
        guard let word = conditionWord(item.condition) else { return size }
        return "\(size) · \(word)"
    }

    static func conditionWord(_ condition: Int?) -> String? {
        switch condition {
        case 1?: "broken"
        case 2?: "worn"
        case 3?: "fair"
        case 4?: "good"
        case 5?: "like new"
        default: nil
        }
    }
}

/// A one-room plan big enough for the items, with them placed in it.
struct EstimatedRoom {
    var plan: FloorPlan
    var items: [LayoutItem]
    var placements: [Placement]
    var widthM: Double
    var depthM: Double
    /// True when the room and positions come from the scan rather than an estimate.
    var scanned = false
    /// Scanned rooms: items shown without a scanned position (spots from the layout solver, or
    /// small things / wall pieces put on the scanned furniture and walls).
    var estimatedCount = 0

    /// The scanned room with each item where the scan found it. Unmatched small things and
    /// wall pieces (added by photo, no RoomPlan object) go on the scanned furniture / walls;
    /// other unmatched items get a floor spot from `LayoutSolver` around the scanned pieces
    /// (`estimatedCount` of them). Ones that don't fit stay in the list only.
    /// `layoutItems` are `items` as layout items (with their scanned colors); defaults to plain ones.
    static func scanned(name: String, geometry: RoomGeometry, items: [Item], layoutItems: [LayoutItem]? = nil) -> EstimatedRoom {
        let result = geometry.dollhouse(roomName: name, items: items)
        let b = result.plan.bounds
        let layoutItems = layoutItems ?? items.map(LayoutItem.init)
        // Unmatched furniture (the photo sweep's finds): estimated spots that avoid the scanned pieces.
        let matched = Set(result.placements.map(\.itemId))
        let unmatchedFurniture = layoutItems.filter {
            !matched.contains($0.id) && PropPlacer.role(of: VoxelItemSpec($0)) == .furniture
        }
        var placements = result.placements
        if !unmatchedFurniture.isEmpty {
            placements = LayoutSolver(plan: result.plan)
                .solve(unmatchedFurniture, style: .byFunction, around: result.placements, fixedItems: layoutItems)
                .placements
        }
        // Small things and wall pieces RoomPlan didn't locate go on the scanned furniture and
        // walls so the room looks lived-in. Scanned ones (`matched`) keep their scanned spot:
        // a scanned lamp only goes up onto furniture whose top is where it was seen.
        placements = PropPlacer(plan: result.plan).place(placements, items: layoutItems, extraRoom: name, scanned: matched)
        let estimatedCount = placements.filter { !matched.contains($0.itemId) }.count
        return EstimatedRoom(plan: result.plan, items: layoutItems, placements: placements,
                             widthM: b.width, depthM: b.depth, scanned: true, estimatedCount: estimatedCount)
    }

    static func build(name: String, items: [LayoutItem]) -> EstimatedRoom {
        let footprint = items.reduce(0) { $0 + $1.widthM * $1.depthM }
        let longest = items.map { max($0.widthM, $0.depthM) }.max() ?? 0
        var area = max(footprint * 2.2, 9)
        var best: EstimatedRoom?
        // Grow the room a little until everything fits (or give up after a few tries).
        for _ in 0..<4 {
            let depth = max(3, (area / 1.15).squareRoot(), longest + 0.6)
            let width = max(3, depth * 1.15)
            let w = (width * 10).rounded() / 10, d = (depth * 10).rounded() / 10
            let plan = FloorPlan(
                rooms: [.rectangle(name, kind: RoomKind.guess(from: name), x: 0, y: 0, width: w, depth: d)],
                doors: [WallOpening(from: PlanPoint(0.4, d), to: PlanPoint(1.3, d))],
                windows: [WallOpening(from: PlanPoint(w / 2 - 0.7, 0), to: PlanPoint(w / 2 + 0.7, 0))]
            )
            let option = LayoutSolver(plan: plan).solve(items, style: .byFunction)
            let placements = PropPlacer(plan: plan).place(option.placements, items: items)
            best = EstimatedRoom(plan: plan, items: items, placements: placements, widthM: w, depthM: d)
            if option.unplaced.isEmpty { break }
            area *= 1.25
        }
        return best!
    }
}

#Preview {
    let snap = DemoFixtures.inventory(owner: "me")
    return ScrollView {
        ScanResultsView(room: snap.rooms.first, items: snap.items)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 24)
    }
    .mooveScreen()
}
