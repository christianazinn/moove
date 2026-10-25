import Foundation

/// Inventory can focus on some scanned rooms ("sometimes I just want to think about the items
/// in one or two of the scans"). Unlike hiding a room, this only narrows the Inventory screen;
/// Review, the new home and the totals elsewhere still see every visible room.
public enum InventoryFocus {
    public static let defaultsKey = "moove.inventory.focusRooms"

    public static func decode(_ s: String) -> Set<UInt64> {
        Set(s.split(separator: ",").compactMap { UInt64($0) })
    }

    public static func encode(_ ids: Set<UInt64>) -> String {
        ids.sorted().map(String.init).joined(separator: ",")
    }

    /// The focused rooms that still exist (a deleted or hidden room drops out). Empty means all.
    public static func active(_ focus: Set<UInt64>, rooms: [Room]) -> Set<UInt64> {
        focus.intersection(rooms.map(\.id))
    }

    /// The items Inventory shows: all of them with no focus, else only the focused rooms'.
    public static func items(_ items: [Item], focus: Set<UInt64>) -> [Item] {
        focus.isEmpty ? items : items.filter { focus.contains($0.roomId) }
    }

    /// Focus with `room` added or removed.
    public static func toggling(_ room: UInt64, in focus: Set<UInt64>) -> Set<UInt64> {
        focus.contains(room) ? focus.subtracting([room]) : focus.union([room])
    }
}
