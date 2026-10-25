import Foundation

/// Objects the module skipped while importing a scan (#177): impossible sizes or
/// labels. The rest of the room imports, and one `agent_event` (agent `scan`,
/// kind `error`, ref `scan`/<scan id>) lists them in `data_json` as `[{id, why}]`.
public struct ScanSkips: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Decodable {
        /// The object's `scan_object_id` (RoomPlan's UUID), cut to 64 characters.
        public var id: String
        /// What failed, e.g. "width_m=NaN" or "name too long".
        public var why: String

        public init(id: String, why: String) {
            self.id = id
            self.why = why
        }

        /// "width_m=40" -> "width 40 m", "height_m=NaN" -> "height not a number"; other reasons as is.
        public var readable: String {
            let parts = why.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasSuffix("_m") else { return why }
            let what = parts[0].dropLast(2)
            guard let v = Double(parts[1]), v.isFinite else { return "\(what) not a number" }
            return "\(what) \(v.formatted(.number.precision(.fractionLength(0...2)))) m"
        }
    }

    /// The event's own count; `entries` holds at most the first 50.
    public var count: Int
    public var entries: [Entry]
    public var message: String

    /// The notice for `event`, or nil if it isn't a scan-skip event.
    public init?(_ event: AgentEvent) {
        guard event.agent == "scan", event.kind == .error, event.refTable == "scan" else { return nil }
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(event.dataJson.utf8))) ?? []
        // "Skipped 3 scanned object(s) …": the count in the message covers more than 50.
        let digits = event.message.drop { !$0.isNumber }.prefix { $0.isNumber }
        count = Int(digits) ?? entries.count
        message = event.message
    }

    /// Objects the app itself left out before the import (`ObjectRecheck` rejects).
    public init(local entries: [Entry]) {
        count = entries.count
        self.entries = entries
        message = "Skipped \(entries.count) scanned object(s) on the device"
    }

    /// The module's skips plus the app's own (`local`), as one notice; nil when there are none.
    public static func combined(_ module: ScanSkips?, local: [Entry]) -> ScanSkips? {
        guard var out = module else { return local.isEmpty ? nil : ScanSkips(local: local) }
        out.count += local.count
        out.entries = local + out.entries
        return out
    }

    /// "2 objects looked wrong and were skipped".
    public var summary: String {
        "\(count) object\(count == 1 ? "" : "s") looked wrong and \(count == 1 ? "was" : "were") skipped"
    }
}

extension SyncSnapshot {
    /// What the module skipped when importing scan `scanId`, if anything.
    public func skips(forScan scanId: UInt64) -> ScanSkips? {
        agentEvents.filter { $0.refId == scanId }.lazy.compactMap(ScanSkips.init).first
    }
}
