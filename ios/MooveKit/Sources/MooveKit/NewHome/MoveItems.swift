import Foundation

/// The one set of things Move works with, so the layout, the fly-in, the truck and the boxes all
/// show the items Review shows under **Keep** (#335):
/// - `kept`: Review's Keep pile (`ReviewSection.of == .keep`) from the rooms picked in "Moving
///   from" (`MovingRooms.items`: older re-scans of a room are left out). New Home lays these out,
///   and the truck and boxes carry them.
/// - `withYou`: sentimental things still waiting on you (Review's Needs you, not sold or thrown
///   out). Never auto-decided, so they aren't laid out; Pack puts them in "Keep with you".
/// - `bought`: purchased shopping items, delivered to the new home (not packed, not on the truck).
/// Pass the visible snapshot (hidden rooms and built-ins already out, like Inventory and Review).
/// With nothing kept, sentimental or bought yet, Move shows the offline demo's set instead
/// (`isDemo`), worked out the same way.
public struct MoveItems: Sendable, Equatable {
    public var kept: [Item]
    public var withYou: [Item]
    public var bought: [BoughtPiece]
    public var boughtLayout: [LayoutItem]
    /// True when these are the demo fixture's, because the user has nothing yet.
    public var isDemo: Bool

    /// Everything Pack plans for: kept, then the sentimental ones, in id order.
    public var packed: [Item] { (kept + withYou).sorted { $0.id < $1.id } }

    /// Review's Keep pile.
    public static func keep(_ items: [Item]) -> [Item] {
        items.filter { ReviewSection.of($0) == .keep }
    }

    /// Sentimental items Review still asks you about (kept or undecided by an agent).
    public static func waitingSentimental(_ items: [Item]) -> [Item] {
        items.filter { $0.maybeSentimental && ReviewSection.of($0) == .needsYou && ($0.disposition == .keep || $0.disposition == .undecided) }
    }

    /// - Parameters:
    ///   - visible: the snapshot without hidden rooms and built-ins.
    ///   - overrides: the user's "Moving from" picks (`MovingRooms`).
    ///   - demo: the fixture to fall back on when there's nothing of the user's.
    public static func of(_ visible: SyncSnapshot, overrides: [UInt64: Bool], demo: @autoclosure () -> SyncSnapshot) -> MoveItems {
        let mine = resolve(visible, overrides: overrides, isDemo: false)
        if !mine.packed.isEmpty || !mine.bought.isEmpty { return mine }
        return resolve(demo().withoutBuiltIns(), overrides: [:], isDemo: true)
    }

    static func resolve(_ snapshot: SyncSnapshot, overrides: [UInt64: Bool], isDemo: Bool) -> MoveItems {
        let keep = keep(snapshot.items)
        let choices = MovingRooms.choices(snapshot, keptItems: keep, overrides: overrides)
        return MoveItems(
            kept: MovingRooms.items(keep, choices: choices),
            withYou: MovingRooms.items(waitingSentimental(snapshot.items), choices: choices),
            bought: snapshot.boughtPieces,
            boughtLayout: snapshot.boughtLayoutItems,
            isDemo: isDemo
        )
    }
}
