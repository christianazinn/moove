import SwiftUI
import MooveKit

// Move's "Getting there" part (#19): which truck, how many movers and what it costs (with the
// loaded truck in 3D), every box drawn as a kraft moving box in its room's color grouped by
// destination room with printable labels, things bought for the new home (delivered there, not
// packed), and, folded, furniture take-apart notes, supplies and a short schedule. `MoveView`
// stacks these and re-plans whenever `PackInputs` change: the kept items (hidden rooms excluded),
// the "Moving from" room picks, the purchases or the saved new-home layout.

/// What the packing plan is made from.
struct PackInputs: Equatable {
    var items: [Item]
    var rooms: [UInt64: String]
    var bought: [BoughtPiece]
    /// Nothing kept yet: the plan uses demo items.
    var demo: Bool
    /// The "Moving from" rooms (empty for the demo items).
    var choices: [MovingRooms.Choice] = []

    /// Move's one item set (`MooveStore.moveItems`, MooveKit `MoveItems`): Review's Keep pile plus
    /// the sentimental things still waiting on you, from the rooms that are moving (hidden rooms
    /// and older re-scans stay out), plus what was bought (shown as "Delivered"), with destination
    /// rooms from the newest saved layout of the user's new home. The demo's set until there's
    /// anything of the user's, the same one the layout uses.
    @MainActor static func current(_ store: MooveStore, move: MoveItems) -> PackInputs {
        let snap = store.snapshot
        let demo = move.isDemo
        let items = move.packed
        var rooms: [UInt64: String] = [:]
        if let home = snap.myNewHome,
           let layout = snap.layouts(for: home.id).max(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }) {
            for p in layout.placements { rooms[p.itemId] = p.room }
        }
        return PackInputs(items: items, rooms: rooms, bought: move.bought, demo: demo, choices: demo ? [] : store.movingChoices)
    }

    var itemsById: [UInt64: Item] { Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
}

/// Box check-offs (`moove.pack.checked`, keys "boxId:lineIndex"), shared by the box cards, the
/// schedule and the box sheet.
enum PackSeal {
    static func packed(_ box: MovingBox, in set: Set<String>) -> Int {
        box.contents.indices.filter { set.contains(PackChecks.key(box: box.id, line: $0)) }.count
    }

    static func isSealed(_ box: MovingBox, in set: Set<String>) -> Bool {
        !box.contents.isEmpty && packed(box, in: set) == box.contents.count
    }
}

// MARK: - Truck

/// The loaded truck in 3D (no gestures, so the page scrolls; tap it for the full-screen truck),
/// Load the truck, then just the truck's size. Cost, crew and the size note are in VoiceOver.
struct TruckCard: View {
    var plan: PackingPlan
    var load: TruckLoad?
    var items: [Item]
    /// One small "Demo" tag on the 3D when these aren't the user's things.
    var demoTag = false
    /// Bumped by "Load the truck" to replay its fly-in.
    @State private var flyIn = 0

    /// The truck the 3D shows (a size up when shapes don't fit the volume estimate).
    private var truckLabel: String {
        let t = plan.truck
        let size = load?.truck.label ?? t.truck.label
        return t.trucks > 1 ? "\(t.trucks) × \(size)" : size
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let load { scene(load) }
            Text(truckLabel)
                .blockTitle()
                .accessibilityLabel(spoken)
            buttons
        }
    }

    /// Tapping the truck opens it full screen (orbit it, tap pieces); no separate button.
    private func scene(_ load: TruckLoad) -> some View {
        NavigationLink { TruckView(plan: plan, items: items, load: load) } label: {
            TruckSceneView(load: load, items: items, flyInToken: flyIn, selected: .constant(nil), interactive: false)
                .allowsHitTesting(false)
                .frame(height: 240)
                .overlay(alignment: .topLeading) {
                    if demoTag { MonoTag(text: "Demo").padding(12).accessibilityHidden(true) }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityLabel(TruckView.summary(load) + (demoTag ? ", demo items" : ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the truck full screen: turn it and tap pieces to see what they are")
        .accessibilityIdentifier("pack.truck3D")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button { flyIn += 1 } label: {
                Label("Load the truck", systemImage: "shippingbox")
            }
            .buttonStyle(.pill(.primary, compact: true))
        }
    }

    /// The detail the screen no longer prints, for VoiceOver.
    private var spoken: String {
        let t = plan.truck
        var parts = [truckLabel, "\(t.movers) movers", "about \(t.costLowCents.usd) to \(t.costHighCents.usd), a rough estimate"]
        if let note = load?.sizeNote(planned: t.truck) { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Boxes

/// Every box as a big card, "Open first" on top, then one heading per destination room (with its
/// tape color), and Print labels.
struct BoxesSection: View {
    var boxes: [MovingBox]
    var onOpen: (MovingBox) -> Void
    @AppStorage("moove.pack.checked") private var checkedRaw = ""

    struct BoxGroup: Identifiable {
        var id: String
        var title: String
        var boxes: [MovingBox]
        var isFirst: Bool { id == "first" }
        /// Boxes holding something from the scan, then the ones that are only an estimate.
        var ordered: [MovingBox] { isFirst ? boxes : boxes.filter { !$0.estimatedOnly } + boxes.filter(\.estimatedOnly) }
    }

    /// "Open first" (keep-with-you boxes leading) on top, then one group per destination room in plan order.
    static func groups(_ boxes: [MovingBox]) -> [BoxGroup] {
        func priority(_ b: MovingBox) -> Bool { b.keepWithYou || b.openFirst }
        var out: [BoxGroup] = []
        let first = boxes.filter(priority).sorted { ($0.keepWithYou ? 0 : 1, $0.id) < ($1.keepWithYou ? 0 : 1, $1.id) }
        if !first.isEmpty { out.append(BoxGroup(id: "first", title: "Open first", boxes: first)) }
        var order: [String] = []
        var byRoom: [String: [MovingBox]] = [:]
        for b in boxes where !priority(b) {
            if byRoom[b.roomName] == nil { order.append(b.roomName) }
            byRoom[b.roomName, default: []].append(b)
        }
        out += order.map { BoxGroup(id: "room:\($0)", title: $0, boxes: byRoom[$0] ?? []) }
        return out
    }

    var body: some View {
        let set = PackChecks.decode(checkedRaw)
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(Self.groups(boxes)) { group in
                VStack(alignment: .leading, spacing: 12) {
                    groupHeader(group)
                    grid(group.ordered, checked: set)
                }
                .padding(.top, 28)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoveHeading(title: "Boxes")
            if boxes.isEmpty {
                Text("No boxes").monoMeta().padding(.top, 14)
            } else {
                PrintLabelsMenu(boxes: boxes) {
                    Label("Print labels", systemImage: "printer")
                }
                .buttonStyle(.pill(.outline, compact: true))
                .accessibilityHint("Makes a PDF of every box label to print or save")
                .accessibilityIdentifier("pack.printLabels")
                .padding(.top, 4)
            }
        }
    }

    private func groupHeader(_ group: BoxGroup) -> some View {
        HStack(spacing: 8) {
            if !group.isFirst {
                Circle()
                    .fill(BoxPalette.tape(for: group.title))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(group.title).monoText(13.5, weight: .bold).foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityIdentifier("pack.room.\(group.isFirst ? "openFirst" : group.title)")
    }

    private func grid(_ boxes: [MovingBox], checked set: Set<String>) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(boxes) { box in
                MovingBoxCard(box: box, packed: PackSeal.packed(box, in: set)) { onOpen(box) }
                    .accessibilityIdentifier("pack.box.\(box.id)")
            }
        }
    }
}

// MARK: - Delivered

/// Bought for the new home: it ships there, so it's not boxed and not on the truck. Name and price.
struct DeliveredSection: View {
    var pieces: [DeliveredItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MoveHeading(title: "Delivered")
            CollapsedList(data: pieces, id: "pack.delivered") { piece in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(piece.name).sansText(16).frame(maxWidth: .infinity, alignment: .leading)
                    if let cents = piece.priceCents { Text(cents.usd).monoText(14).foregroundStyle(Theme.muted) }
                }
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([piece.title, piece.priceCents?.usd, piece.seller, "delivered to \(piece.room)", piece.reason]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
                .accessibilityIdentifier("pack.delivered.\(piece.id)")
            }
        }
    }
}
