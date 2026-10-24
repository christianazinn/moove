import SwiftUI
import MooveKit

/// The packing plan (#19): which truck, how many movers and what it costs, every box drawn as a
/// kraft moving box grouped by destination room, furniture take-apart notes, supplies, and a short
/// schedule. Live: it re-plans whenever the kept items or the saved new-home layout change.
struct PackView: View {
    @Environment(MooveStore.self) private var store
    @State private var plan: PackingPlan?
    @State private var openBox: MovingBox?
    @State private var expandedFurniture: Set<UInt64> = []
    // Check-off state survives relaunches. Keys: "boxId:lineIndex" and supply names.
    @AppStorage("moove.pack.checked") private var checkedRaw = ""
    @AppStorage("moove.pack.supplies") private var suppliesRaw = ""

    var body: some View {
        let input = inputs
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(
                    eyebrow: "08 — Pack",
                    title: "Pack your move.",
                    lede: "A truck, a crew and a box for everything you're keeping, labeled by the room it's going to."
                )
                .padding(.top, 16)
                .padding(.bottom, 24)
                if let plan {
                    truckCard(plan.truck, plan: plan, demo: input.demo)
                    boxes(plan.boxes)
                    if !plan.furniture.isEmpty { furniture(plan.furniture) }
                    if !plan.supplies.isEmpty { supplies(plan.supplies) }
                    if !plan.schedule.isEmpty { schedule(plan.schedule, boxes: plan.boxes) }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 32)
        }
        .navigationTitle("Pack")
        .navigationBarTitleDisplayMode(.inline)
        .mooveScreen()
        .onChange(of: input, initial: true) { _, new in
            plan = PackingPlanner.plan(items: new.items, destinationRoom: new.rooms)
        }
        .sheet(item: $openBox) { box in
            // Look the box up again so a re-plan while the sheet is open shows fresh contents.
            BoxDetailView(box: plan?.boxes.first { $0.id == box.id } ?? box, checked: checkedBinding)
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Inputs

    private struct Inputs: Equatable {
        var items: [Item]
        var rooms: [UInt64: String]
        var demo: Bool
    }

    /// Kept items plus undecided sentimental ones (those may well come along), with destination
    /// rooms from the newest saved layout of the user's new home. Demo fixtures until anything is kept.
    private var inputs: Inputs {
        let snap = store.snapshot
        func packable(_ item: Item) -> Bool { item.disposition == .keep || (item.disposition == .undecided && item.maybeSentimental) }
        var items = snap.items.filter(packable)
        let demo = items.isEmpty
        if demo { items = DemoFixtures.inventory(owner: snap.me ?? "demo").items.filter(packable) }
        var rooms: [UInt64: String] = [:]
        if let home = snap.myNewHome,
           let layout = snap.layouts(for: home.id).max(by: { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }) {
            for p in layout.placements { rooms[p.itemId] = p.room }
        }
        return Inputs(items: items, rooms: rooms, demo: demo)
    }

    private var checked: Set<String> { PackChecks.decode(checkedRaw) }
    private var checkedBinding: Binding<Set<String>> {
        Binding(get: { PackChecks.decode(checkedRaw) }, set: { checkedRaw = PackChecks.encode($0) })
    }

    private func packed(_ box: MovingBox, in set: Set<String>) -> Int {
        box.contents.indices.filter { set.contains(PackChecks.key(box: box.id, line: $0)) }.count
    }

    private func isSealed(_ box: MovingBox, in set: Set<String>) -> Bool {
        !box.contents.isEmpty && packed(box, in: set) == box.contents.count
    }

    // MARK: Truck

    private func truckCard(_ t: TruckEstimate, plan: PackingPlan, demo: Bool) -> some View {
        let capacity = Double(t.truck.capacityM3) * Double(max(t.trucks, 1))
        let fill = capacity > 0 ? min(t.loadM3 / capacity, 1) : 0
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("Truck and crew").eyebrow()
                Spacer(minLength: 8)
                if demo { MonoTag(text: "Demo items", tone: Theme.ochreInk) }
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 18) {
                GridRow {
                    StatFigure(label: "Truck", value: t.trucks > 1 ? "\(t.trucks) × \(t.truck.label)" : t.truck.label)
                    StatFigure(label: "Load", value: "\(t.loadM3.formatted(.number.precision(.fractionLength(1)))) m³")
                }
                GridRow {
                    StatFigure(label: "Movers", value: "\(t.movers) × \(t.moverHours.formatted(.number.precision(.fractionLength(0...1)))) h")
                    StatFigure(label: "Cost", value: "\(t.costLowCents.usd)–\(t.costHighCents.usd)", tint: Theme.accentStrong)
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
                Text("\(Int((fill * 100).rounded()))% of the truck · \(plan.boxes.count) boxes, \(plan.furniture.count) furniture pieces")
                    .monoMeta()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Rough estimate from your items' volume. Ask movers for a real quote.")
                .monoMeta()
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLarge, style: .continuous))
    }

    // MARK: Boxes

    private struct BoxGroup: Identifiable {
        var id: String
        var title: String
        var boxes: [MovingBox]
    }

    /// "Open first" (keep-with-you boxes leading) on top, then one group per destination room in plan order.
    private func groups(_ boxes: [MovingBox]) -> [BoxGroup] {
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

    private func boxes(_ boxes: [MovingBox]) -> some View {
        let set = checked
        let sealedCount = boxes.filter { isSealed($0, in: set) }.count
        let columns = [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)]
        return VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Boxes", count: "\(boxes.count)") {
                Text("\(sealedCount) sealed").monoMeta()
            }
            if boxes.isEmpty {
                Text("No boxes needed: everything you're keeping is furniture.")
                    .monoMeta()
                    .padding(.top, 14)
            }
            ForEach(groups(boxes)) { group in
                VStack(alignment: .leading, spacing: 14) {
                    ListHeader(title: group.title, count: "\(group.boxes.count)") {
                        if group.id != "first" {
                            // Swatch of the room's tape color.
                            RoundedRectangle(cornerRadius: 2)
                                .fill(BoxPalette.tape(for: group.title))
                                .frame(width: 18, height: 10)
                                .accessibilityHidden(true)
                        }
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(group.boxes) { box in
                            MovingBoxCard(box: box, packed: packed(box, in: set)) { openBox = box }
                        }
                    }
                }
                .padding(.top, 24)
            }
        }
        .padding(.top, 36)
    }

    // MARK: Furniture

    private func furniture(_ notes: [FurnitureNote]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Furniture", count: "\(notes.count)")
            ForEach(notes) { note in
                let open = expandedFurniture.contains(note.id)
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if open { expandedFurniture.remove(note.id) } else { expandedFurniture.insert(note.id) }
                        }
                    } label: {
                        LedgerRow(
                            title: note.name,
                            meta: "\(note.room.isEmpty ? "Any room" : note.room) · \(note.steps.count) \(note.steps.count == 1 ? "step" : "steps")"
                        ) {
                            IconTile(systemName: "wrench.and.screwdriver", size: 44)
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
                    if open {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(note.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(i + 1 < 10 ? "0\(i + 1)" : "\(i + 1)")
                                        .monoText(12.5, weight: .bold)
                                        .foregroundStyle(Theme.accentStrong)
                                    Text(step).sansText(15).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.leading, 60)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ruled()
                        .transition(.opacity)
                    }
                }
            }
        }
        .padding(.top, 40)
    }

    // MARK: Supplies

    private func supplies(_ lines: [SupplyLine]) -> some View {
        let done = PackChecks.decode(suppliesRaw)
        return VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Supplies", count: "\(lines.filter { done.contains($0.name) }.count) of \(lines.count)")
            ForEach(lines, id: \.name) { line in
                let have = done.contains(line.name)
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
                        Text(line.name)
                            .monoText(14.5, weight: .bold)
                            .foregroundStyle(have ? Theme.muted : Theme.text)
                            .strikethrough(have, color: Theme.muted)
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
                .accessibilityLabel("\(line.name), \(line.quantity)")
                .accessibilityValue(have ? "Got it" : "Still need")
                .accessibilityAddTraits(have ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, 40)
    }

    // MARK: Schedule

    private func schedule(_ steps: [PackingStep], boxes: [MovingBox]) -> some View {
        let set = checked
        let byId = Dictionary(boxes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = steps.sorted { $0.daysBeforeMove > $1.daysBeforeMove }
        return VStack(alignment: .leading, spacing: 0) {
            ListHeader(title: "Schedule", count: "\(ordered.count) steps")
            Color.clear.frame(height: 16)
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, step in
                let stepBoxes = step.boxIds.compactMap { byId[$0] }
                let allSealed = !stepBoxes.isEmpty && stepBoxes.allSatisfy { isSealed($0, in: set) }
                HStack(alignment: .top, spacing: 14) {
                    // Timeline rail and dot.
                    VStack(spacing: 0) {
                        Circle()
                            .fill(allSealed ? Theme.accent : Theme.bg)
                            .overlay(Circle().strokeBorder(allSealed ? Theme.accent : Theme.lineStrong, lineWidth: 1.5))
                            .frame(width: 12, height: 12)
                            .padding(.top, 4)
                        if index < ordered.count - 1 {
                            Rectangle().fill(Theme.line).frame(width: 1).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 12)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.when(step.daysBeforeMove)).monoText(12.5).foregroundStyle(Theme.muted)
                        Text(step.title).blockTitle().fixedSize(horizontal: false, vertical: true)
                        if !stepBoxes.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 2) {
                                    ForEach(stepBoxes) { box in
                                        Button { openBox = box } label: {
                                            BoxBadge(box: box, sealed: isSealed(box, in: set))
                                                .frame(minWidth: 44, minHeight: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Box \(box.id), \(box.title)\(isSealed(box, in: set) ? ", sealed" : "")")
                                        .accessibilityHint("Opens the box's contents")
                                    }
                                }
                            }
                            .padding(.leading, -6)
                        }
                    }
                    .padding(.bottom, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 40)
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

#Preview {
    NavigationStack { PackView() }.environment(MooveStore.preview())
}
