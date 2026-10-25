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

    /// Kept items plus undecided sentimental ones (those may well come along) from the rooms that
    /// are moving (the "Moving from" picks, `MooveStore.movingItems`: hidden rooms and older
    /// re-scans stay out), plus what was bought for the new home (purchased only, not
    /// still-shopping, shown as "Delivered"), with destination rooms from the newest saved layout
    /// of the user's new home. Demo fixtures until anything is kept.
    @MainActor static func current(_ store: MooveStore) -> PackInputs {
        let snap = store.snapshot
        func packable(_ item: Item) -> Bool { item.disposition == .keep || (item.disposition == .undecided && item.maybeSentimental) }
        let demo = !store.visibleItems.contains(where: packable)
        let items = demo ? DemoFixtures.inventory(owner: snap.me ?? "demo").items.filter(packable) : store.movingItems(where: packable)
        var rooms: [UInt64: String] = [:]
        if let home = snap.myNewHome,
           let layout = snap.layouts(for: home.id).max(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }) {
            for p in layout.placements { rooms[p.itemId] = p.room }
        }
        return PackInputs(items: items, rooms: rooms, bought: snap.boughtPieces, demo: demo, choices: demo ? [] : store.movingChoices)
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

/// Nothing kept yet: the plan uses demo items. Points at where to keep things.
struct PackDemoNotice: View {
    @AppStorage("moove.tab") private var tab = "move"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing kept yet. This plan uses demo items.")
                .sansText(15)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose what to keep") { tab = "review" }
                .buttonStyle(.pill(.outline, compact: true))
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled(.top)
        .ruled()
    }
}

// MARK: - Truck

/// The truck and crew: the loaded truck in 3D right on the card (no gestures, so the page
/// scrolls) with "Load the truck" to replay the fly-in and Full screen to orbit it and tap
/// pieces, then the estimate.
struct TruckCard: View {
    var plan: PackingPlan
    var load: TruckLoad?
    var items: [Item]
    /// Bumped by "Load the truck" to replay its fly-in.
    @State private var flyIn = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let load { inlineTruck(load) }
            TruckStats(estimate: plan.truck)
            if let note = load?.sizeNote(planned: plan.truck.truck) { Text(note).monoMeta().foregroundStyle(Theme.ochreInk) }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }

    private func inlineTruck(_ load: TruckLoad) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TruckSceneView(load: load, items: items, flyInToken: flyIn, selected: .constant(nil), interactive: false)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel(TruckView.summary(load))
                .accessibilityAddTraits(.isImage)
                .accessibilityIdentifier("pack.truck3D")
            HStack(spacing: 10) {
                Button { flyIn += 1 } label: {
                    Label("Load the truck", systemImage: "shippingbox")
                }
                .buttonStyle(.pill(.primary, compact: true))
                NavigationLink { TruckView(plan: plan, items: items, load: load) } label: {
                    Label("Full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.pill(.outline, compact: true))
                .accessibilityHint("Turn the truck and tap pieces to see what they are")
            }
        }
    }
}

/// Truck, load, movers and cost, then how full the truck is.
private struct TruckStats: View {
    var estimate: TruckEstimate
    private var t: TruckEstimate { estimate }

    private var fill: Double {
        let capacity = Double(t.truck.capacityM3) * Double(max(t.trucks, 1))
        return capacity > 0 ? min(t.loadM3 / capacity, 1) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 18) {
                GridRow {
                    StatFigure(label: "Truck", value: t.trucks > 1 ? "\(t.trucks) × \(t.truck.label)" : t.truck.label)
                        .accessibilityLabel("Truck, \(t.truck.label)\(t.trucks > 1 ? ", \(t.trucks) of them" : "")")
                    StatFigure(label: "Load", value: "\(t.loadM3.formatted(.number.precision(.fractionLength(1)))) m³")
                        .accessibilityLabel("Load, \(Spoken.volume(t.loadM3))")
                }
                GridRow {
                    StatFigure(label: "Movers", value: "\(t.movers) × \(hours) h")
                        .accessibilityLabel("\(t.movers) movers, \(hours) hours each")
                    StatFigure(label: "Cost", value: "\(t.costLowCents.usd)–\(t.costHighCents.usd)", tint: Theme.accentStrong)
                        .accessibilityLabel("Cost, \(t.costLowCents.usd) to \(t.costHighCents.usd)")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(Theme.accent).frame(width: max(6, geo.size.width * fill))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
                // Box and furniture counts are on their own sections below.
                Text("\(Int((fill * 100).rounded()))% full · rough estimate, ask movers for a quote")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hours: String { t.moverHours.formatted(.number.precision(.fractionLength(0...1))) }
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
            header(set)
            ForEach(Self.groups(boxes)) { group in
                VStack(alignment: .leading, spacing: 14) {
                    groupHeader(group)
                    grid(group.ordered, checked: set)
                }
                .padding(.top, Theme.Space.xl)
            }
        }
    }

    private func header(_ set: Set<String>) -> some View {
        let sealedCount = boxes.filter { PackSeal.isSealed($0, in: set) }.count
        let estimateCount = boxes.filter { $0.estimatedOnly && !$0.openFirst && !$0.keepWithYou }.count
        return VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Boxes", count: "\(boxes.count)") {
                Text("\(sealedCount) sealed").monoMeta()
            }
            if boxes.isEmpty {
                EmptyState(title: "No boxes needed", detail: "It's all furniture.").padding(.top, 14)
            } else {
                if estimateCount > 0 {
                    Text("\(estimateCount) of everyday stuff (an estimate)")
                        .monoMeta()
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrintLabelsMenu(boxes: boxes) {
                    Label("Print labels", systemImage: "printer")
                }
                .buttonStyle(.pill(.outline, compact: true))
                .accessibilityHint("Makes a PDF of every box label to print or save")
                .accessibilityIdentifier("pack.printLabels")
                .padding(.top, 14)
            }
        }
    }

    private func groupHeader(_ group: BoxGroup) -> some View {
        ListHeader(title: group.title, count: "\(group.boxes.count)") {
            if !group.isFirst {
                RoundedRectangle(cornerRadius: Theme.Radius.tag)
                    .fill(BoxPalette.tape(for: group.title))
                    .frame(width: 18, height: 10)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("pack.room.\(group.isFirst ? "openFirst" : group.title)")
    }

    private func grid(_ boxes: [MovingBox], checked set: Set<String>) -> some View {
        let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(boxes) { box in
                MovingBoxCard(box: box, packed: PackSeal.packed(box, in: set)) { onOpen(box) }
                    .accessibilityIdentifier("pack.box.\(box.id)")
            }
        }
    }
}

// MARK: - Delivered

/// Bought for the new home: it ships there, so it's not boxed and not on the truck.
struct DeliveredSection: View {
    var pieces: [DeliveredItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header and each row's "Bought" tag say it: it ships there, nothing to pack.
            ListHeader(title: "Delivered to your new home", count: "\(pieces.count)")
            CollapsedList(data: pieces, id: "pack.delivered") { piece in
                LedgerRow(
                    title: piece.title,
                    meta: [piece.seller, "→ \(piece.room)"].filter { !$0.isEmpty }.joined(separator: " · ")
                ) {
                    VoxelThumbnail(spec: piece.voxelSpec, size: 56)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(BoxPalette.tape(for: piece.room)).frame(width: 26, height: 4).padding(.bottom, 4)
                        }
                } trailing: {
                    MonoTag(text: "Bought", tone: Theme.accentStrong)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([piece.title, piece.seller, piece.reason, piece.roomReason].filter { !$0.isEmpty }.joined(separator: ", "))
                .accessibilityIdentifier("pack.delivered.\(piece.id)")
            }
        }
    }
}

// MARK: - Furniture notes

/// Take-apart notes per piece; each row opens to its steps. Folded on Move, so no header here.
struct FurnitureNotesList: View {
    var notes: [FurnitureNote]
    @State private var expanded: Set<UInt64> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 0) {
                    row(note, open: expanded.contains(note.id))
                    if expanded.contains(note.id) { steps(note) }
                }
            }
        }
    }

    private func row(_ note: FurnitureNote, open: Bool) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                if open { expanded.remove(note.id) } else { expanded.insert(note.id) }
            }
        } label: {
            LedgerRow(
                title: note.name,
                meta: [note.reason, "\(note.room.isEmpty ? "Any room" : note.room) · \(note.steps.count) \(note.steps.count == 1 ? "step" : "steps")"]
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            ) {
                IconTile(systemName: note.room == "Keep with you" ? "car.fill" : "wrench.and.screwdriver", size: 44)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(BoxPalette.tape(for: note.room)).frame(width: 24, height: 4).padding(.bottom, 4)
                    }
            } trailing: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .accessibilityHint(open ? "Hides the steps" : "Shows the steps")
    }

    private func steps(_ note: FurnitureNote) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !note.roomReason.isEmpty {
                Text(note.roomReason).monoMeta().fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(note.steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(i + 1 < 10 ? "0\(i + 1)" : "\(i + 1)")
                        .monoText(13.5, weight: .bold)
                        .foregroundStyle(Theme.accentStrong)
                    Text(step).sansText(15).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(i + 1), \(step)")
            }
        }
        .padding(.leading, 60)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ruled()
        .transition(.opacity)
    }
}

// MARK: - Supplies

/// Tape, boxes and the rest, checked off as you get them (`moove.pack.supplies`).
struct SuppliesList: View {
    var lines: [SupplyLine]
    @AppStorage("moove.pack.supplies") private var suppliesRaw = ""

    /// "3 of 7", for the fold's header.
    static func progress(_ lines: [SupplyLine], raw: String) -> String {
        let done = PackChecks.decode(raw)
        return "\(lines.filter { done.contains($0.name) }.count) of \(lines.count)"
    }

    var body: some View {
        let done = PackChecks.decode(suppliesRaw)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines, id: \.name) { line in
                row(line, have: done.contains(line.name), done: done)
            }
        }
    }

    private func row(_ line: SupplyLine, have: Bool, done: Set<String>) -> some View {
        Button {
            var next = done
            if have { next.remove(line.name) } else { next.insert(line.name) }
            suppliesRaw = PackChecks.encode(next)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: have ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(have ? Theme.accentStrong : Theme.muted)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(line.name)
                    .monoText(14.5, weight: .bold)
                    .foregroundStyle(have ? Theme.muted : Theme.text)
                    .strikethrough(have, color: Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("× \(line.quantity)").rowValue()
            }
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .ruled()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.name), \(line.quantity) needed")
        .accessibilityValue(have ? "Got it" : "Still need")
        .accessibilityAddTraits(have ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Schedule

/// The countdown to moving day; each step's boxes open their sheet, and a step's dot fills once
/// all its boxes are sealed.
struct ScheduleList: View {
    var steps: [PackingStep]
    var boxes: [MovingBox]
    var onOpen: (MovingBox) -> Void
    @AppStorage("moove.pack.checked") private var checkedRaw = ""

    var body: some View {
        let set = PackChecks.decode(checkedRaw)
        let byId = Dictionary(boxes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = steps.sorted { $0.daysBeforeMove > $1.daysBeforeMove }
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 16)
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, step in
                StepRow(step: step, boxes: step.boxIds.compactMap { byId[$0] }, checked: set,
                        last: index == ordered.count - 1, onOpen: onOpen)
            }
        }
    }

    private struct StepRow: View {
        var step: PackingStep
        var boxes: [MovingBox]
        var checked: Set<String>
        var last: Bool
        var onOpen: (MovingBox) -> Void

        var body: some View {
            let allSealed = !boxes.isEmpty && boxes.allSatisfy { PackSeal.isSealed($0, in: checked) }
            HStack(alignment: .top, spacing: 14) {
                rail(allSealed)
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ScheduleList.when(step.daysBeforeMove)).monoText(13.5).foregroundStyle(Theme.muted)
                        Text(step.title).blockTitle().fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    if !boxes.isEmpty { badges }
                }
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        /// Timeline rail and dot.
        private func rail(_ allSealed: Bool) -> some View {
            VStack(spacing: 0) {
                Circle()
                    .fill(allSealed ? Theme.accent : Theme.bg)
                    .overlay(Circle().strokeBorder(allSealed ? Theme.accent : Theme.lineStrong, lineWidth: 1.5))
                    .frame(width: 12, height: 12)
                    .padding(.top, 4)
                if !last {
                    Rectangle().fill(Theme.line).frame(width: 1).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            .accessibilityHidden(true)
        }

        private var badges: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(boxes) { box in
                        let sealed = PackSeal.isSealed(box, in: checked)
                        Button { onOpen(box) } label: {
                            BoxBadge(box: box, sealed: sealed)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Box \(box.id), \(box.title)\(sealed ? ", sealed" : "")")
                        .accessibilityHint("Opens the box's contents")
                    }
                }
            }
            .padding(.leading, -6)
        }
    }

    static func when(_ days: Int) -> String {
        switch days {
        case ..<0: days == -1 ? "The day after" : "\(-days) days after"
        case 0: "Moving day"
        case 1: "The day before"
        case 7: "A week before"
        case 14: "Two weeks before"
        default: "\(days) days before"
        }
    }
}
