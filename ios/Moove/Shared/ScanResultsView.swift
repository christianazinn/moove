import SwiftUI
import MooveKit

/// What a scan found, MoveWise style: the room as a voxel dollhouse with every item in it,
/// then an inventory ledger with a voxel thumbnail, size, condition and value range per item.
/// Takes plain inputs so the Scan page can drop it in with one line.
///
/// Items don't carry scanned positions yet, so the room is a single rectangle sized to hold
/// them and the layout solver places them; the caption says so.
struct ScanResultsView: View {
    var room: Room?
    var items: [Item]
    var comps: [Comp]
    var onSelect: (Item) -> Void
    /// The scan's real room (walls, doors, windows, object positions). Nil: estimate a room.
    var geometry: RoomGeometry?
    /// Real colors sampled from the scan's photos: furniture uses them over its keyword palette.
    /// `colors?.wallColor` / `floorColor` are for the dollhouse shell (VoxelHouse) once it takes them.
    var colors: ScanColors?

    init(room: Room?, items: [Item], comps: [Comp], geometry: RoomGeometry? = nil, colors: ScanColors? = nil,
         onSelect: @escaping (Item) -> Void = { _ in }) {
        self.room = room
        self.items = items
        self.comps = comps
        self.geometry = geometry
        self.colors = colors
        self.onSelect = onSelect
    }

    @State private var model: EstimatedRoom?
    @State private var flyInToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            stage
            inventory.padding(.top, 40)
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

            HStack(spacing: 10) {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(caption).monoText(13.5).foregroundStyle(Theme.text)
            }
            .padding(.top, 14)
            if let model, model.scanned, model.estimatedCount > 0 {
                Text("\(model.estimatedCount) placed by estimate")
                    .monoMeta()
                    .padding(.top, 4)
                    .padding(.leading, 18)
            }
            if model?.scanned != true {
                Text("Estimated layout, not scanned positions.")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .padding(.leading, 18)
            }
        }
    }

    private var caption: String {
        let objects = "\(items.count) object\(items.count == 1 ? "" : "s")"
        guard let model else { return objects }
        return "\(objects) · \(String(format: "%.1f × %.1f m", model.widthM, model.depthM))"
    }

    // MARK: Inventory

    private var inventory: some View {
        let ranges: [UInt64: ValueRange] = Dictionary(
            items.compactMap { item in ValueRange.of(item, comps: comps).map { (item.id, $0) } },
            uniquingKeysWith: { a, _ in a }
        )
        let priced = Array(ranges.values)
        let total = priced.isEmpty ? nil : ValueRange(low: priced.reduce(0) { $0 + $1.low }, high: priced.reduce(0) { $0 + $1.high })
        return VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Inventory", count: "\(items.count)") {
                if let total { Text("est. \(total.text)").monoText(13).foregroundStyle(Theme.muted) }
            }
            if items.isEmpty {
                Text("Nothing found yet.").monoMeta().padding(.vertical, 28).frame(maxWidth: .infinity, alignment: .leading).ruled()
            }
            ForEach(items) { item in
                Button { onSelect(item) } label: {
                    LedgerRow(
                        title: item.name,
                        meta: Self.meta(item),
                        value: ranges[item.id]?.text ?? "pricing…",
                        valueTint: ranges[item.id] == nil ? Theme.muted : Theme.text,
                        chevron: true
                    ) {
                        VoxelThumbnail(spec: Self.spec(item, colors: colors))
                    } trailing: {
                        if item.maybeSentimental { MonoTag(text: "Needs you", tone: Theme.ochreInk) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
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

/// A low–high value in whole dollars.
struct ValueRange: Equatable {
    var low: Int
    var high: Int

    /// From the item's comps (min–max) when there are any, else its estimate ±20%; nil if neither.
    static func of(_ item: Item, comps: [Comp]) -> ValueRange? {
        let prices = comps.filter { $0.itemId == item.id && $0.priceCents > 0 }.map(\.priceCents)
        if let lo = prices.min(), let hi = prices.max() {
            return ValueRange(low: roundDown(Double(lo) / 100), high: roundUp(Double(hi) / 100))
        }
        guard let est = item.estValueCents, est > 0 else { return nil }
        let dollars = Double(est) / 100
        return ValueRange(low: roundDown(dollars * 0.8), high: roundUp(dollars * 1.2))
    }

    /// "$80–$140", or one figure when both ends match.
    var text: String {
        let lo = Self.usd(low), hi = Self.usd(high)
        return low == high ? lo : "\(lo)–\(hi)"
    }

    private static func step(_ dollars: Double) -> Double { dollars >= 100 ? 10 : dollars >= 20 ? 5 : 1 }
    private static func roundDown(_ d: Double) -> Int { Int((d / step(d)).rounded(.down) * step(d)) }
    private static func roundUp(_ d: Double) -> Int { Int((d / step(d)).rounded(.up) * step(d)) }
    private static func usd(_ dollars: Int) -> String {
        dollars.formatted(.currency(code: "USD").precision(.fractionLength(0)))
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
        ScanResultsView(room: snap.rooms.first, items: snap.items, comps: snap.comps)
            .padding(.horizontal, Theme.gutter)
            .padding(.vertical, 24)
    }
    .mooveScreen()
}
