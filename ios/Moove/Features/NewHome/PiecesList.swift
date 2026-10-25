import SwiftUI
import MooveKit

/// The placed pieces of the shown layout, in plan room order, then the ones that didn't fit.
/// Folded at the bottom of Move. Rows say where each piece goes; they aren't buttons.
struct PiecesList: View {
    var plan: FloorPlan
    var furniture: Furniture
    /// The layout on the stage (nil while it's arranging).
    var layout: LayoutOption?

    struct Row: Identifiable {
        var item: LayoutItem
        var room: String?
        /// An extra bed kept out of the layout (more beds than bedrooms).
        var stored = false
        /// A mattress laid on this bed frame (drawn as part of the bed).
        var onBed: String? = nil
        var id: UInt64 { item.id }
    }

    /// Placed pieces in plan room order, then the ones that didn't fit.
    static func rows(plan: FloorPlan, furniture: Furniture, layout: LayoutOption?) -> [Row] {
        let placements = layout?.placements ?? []
        let byId = Dictionary(furniture.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let order = Dictionary(plan.rooms.enumerated().map { ($0.element.name, $0.offset) }, uniquingKeysWith: { a, _ in a })
        let onBed = Dictionary(placements.compactMap { p in p.onTopOf.map { (p.itemId, $0) } }, uniquingKeysWith: { a, _ in a })
        let mattresses = MattressPairing.drawnWithBed(placements, items: furniture.items)
        let placed: [Row] = placements
            .compactMap { p in byId[p.itemId].map { item in
                Row(item: item, room: p.room, onBed: mattresses.contains(p.itemId) ? onBed[p.itemId].flatMap { byId[$0]?.name } : nil)
            } }
            .sorted { a, b in
                let ra = order[a.room ?? ""] ?? .max, rb = order[b.room ?? ""] ?? .max
                return ra != rb ? ra < rb : a.item.name < b.item.name
            }
        let stored = Set(layout?.stored ?? [])
        let unplaced = (layout?.unplaced ?? []).compactMap { byId[$0] }.map { Row(item: $0, room: nil, stored: stored.contains($0.id)) }
        return placed + unplaced
    }

    var body: some View {
        let rows = Self.rows(plan: plan, furniture: furniture, layout: layout)
        VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                EmptyState(title: furniture.items.isEmpty ? "Nothing to place yet" : "Arranging…",
                           detail: "Kept items land here.", ruledTop: false)
            }
            ForEach(rows) { row in
                if let room = row.room {
                    placedRow(row, room: room)
                } else {
                    unplacedRow(row)
                }
            }
        }
    }

    private func placedRow(_ row: Row, room: String) -> some View {
        LedgerRow(title: row.item.name, meta: [row.onBed.map { "on the \($0)" }, room].compactMap { $0 }.joined(separator: " · ")) {
            VoxelThumbnail(row.item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.item.name)\(row.onBed.map { ", on the \($0)" } ?? ""), \(room)")
    }

    private func unplacedRow(_ row: Row) -> some View {
        LedgerRow(title: row.item.name, value: row.stored ? "Storage" : "Didn't fit",
                  valueTint: row.stored ? Theme.muted : Theme.danger) {
            VoxelThumbnail(row.item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.item.name), \(row.stored ? "extra bed, to storage" : "didn't fit")")
    }
}
