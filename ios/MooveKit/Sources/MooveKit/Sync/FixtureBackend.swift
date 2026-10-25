import Foundation

/// In-memory backend with the same reducer semantics as the SpacetimeDB module.
/// Used for SwiftUI previews, unit tests, and the "offline demo" debug toggle.
public final class FixtureBackend: SyncBackend, @unchecked Sendable {
    public enum Failure: Error, Equatable {
        case notConnected
        case noSuchItem
        case noSuchNewHome
        case noSuchApproval
        case alreadyDecided
        case invalidStatus
        case unauthorized
        case noSuchShoppingItem
        case dealDoesNotMatchItem
        case invalidAttribute
        case invalidColors
        case noSuchRoomCode
        case noSuchRoom
        case noSuchScan
        case invalidUrl
        case tooManyPhotos
        case nameTooLong
        case emptyName
    }

    private let lock = NSLock()
    private var state: SyncSnapshot
    private var nextId: UInt64
    private var scanPhotoCounts: [UInt64: Int] = [:]
    private var snapshotContinuations: [UUID: AsyncStream<SyncSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private let identity: IdentityHex
    /// Other people's rooms (with their scans, items and owners) that only
    /// appear once the user joins them by code, like `room_member` rows live.
    private var joinable: SyncSnapshot
    /// Rooms the user has joined (the `room_member` table, for this one identity).
    private var memberRoomIds: Set<UInt64> = []

    public init(identity: IdentityHex = "fixture-user", seed: SyncSnapshot = SyncSnapshot(), joinable: SyncSnapshot = SyncSnapshot()) {
        self.identity = identity
        self.state = seed
        self.joinable = joinable
        for i in state.rooms.indices where state.rooms[i].joinCode == nil {
            state.rooms[i].joinCode = Self.joinCode(forRoomId: state.rooms[i].id)
        }
        for i in self.joinable.rooms.indices where self.joinable.rooms[i].joinCode == nil {
            self.joinable.rooms[i].joinCode = Self.joinCode(forRoomId: self.joinable.rooms[i].id)
        }
        let ids: [[UInt64]] = [
            seed.rooms.map(\.id), seed.scans.map(\.id), seed.items.map(\.id), seed.comps.map(\.id),
            seed.newHomes.map(\.id), seed.layouts.map(\.id), seed.listings.map(\.id), seed.approvals.map(\.id),
            seed.payments.map(\.id), seed.agentEvents.map(\.id),
            joinable.rooms.map(\.id), joinable.scans.map(\.id), joinable.items.map(\.id),
        ]
        let maxId = ids.joined().max() ?? 0
        self.nextId = maxId + 1
    }

    /// The bundled demo inventory (already priced and sorted, as if the agents had run),
    /// plus a roommate's room the user can join with `DemoFixtures.roommateJoinCode`.
    public static func demo(identity: IdentityHex = "fixture-user") -> FixtureBackend {
        FixtureBackend(identity: identity, seed: DemoFixtures.demo(owner: identity), joinable: DemoFixtures.roommateRoom())
    }

    /// A stable 6-character code for a room id, from the module's alphabet (no I, O, 0, 1).
    /// Multiplying by an odd constant mod 32^6 is a bijection, so ids below 32^6 never collide.
    public static func joinCode(forRoomId id: UInt64) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var n = (id &* 0x9E37_79B1) & ((1 << 30) - 1)
        var code = ""
        for _ in 0..<6 {
            code.append(alphabet[Int(n & 31)])
            n >>= 5
        }
        return code
    }

    // MARK: Connection

    public func connect(token: String?) async throws -> (identity: IdentityHex, token: String) {
        mutate {
            $0.me = identity
            // What a live worker announces about today's budget (#221), so Settings shows it offline too.
            if $0.serviceConfig.values["spend_today"] == nil { $0.serviceConfig.values["spend_today"] = Self.sampleSpendToday() }
            // The offline demo never pays anyone, so it reports the simulated Visa rail (#191).
            if $0.serviceConfig.values["visa_checkout"] == nil { $0.serviceConfig.values["visa_checkout"] = VisaCheckoutMode.simulated.rawValue }
        }
        broadcast(status: .connected)
        return (identity, token ?? "fixture-token")
    }

    public func disconnect() async {
        mutate { $0.me = nil }
        broadcast(status: .disconnected)
    }

    public func snapshots() -> AsyncStream<SyncSnapshot> {
        let (stream, continuation) = AsyncStream<SyncSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let key = UUID()
        lock.sync {
            snapshotContinuations[key] = continuation
            continuation.yield(state)
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.sync { _ = self?.snapshotContinuations.removeValue(forKey: key) }
        }
        return stream
    }

    public func statusUpdates() -> AsyncStream<SyncStatus> {
        let (stream, continuation) = AsyncStream<SyncStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let key = UUID()
        lock.sync {
            statusContinuations[key] = continuation
            continuation.yield(state.me == nil ? .disconnected : .connected)
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.sync { _ = self?.statusContinuations.removeValue(forKey: key) }
        }
        return stream
    }

    // MARK: Reducers

    public func registerUser(name: String, email: String?, auth0Sub: String?) async throws {
        try mutateAuthed { s, me in
            if let i = s.users.firstIndex(where: { $0.identity == me }) {
                s.users[i].name = name
                s.users[i].email = email
                s.users[i].auth0Sub = auth0Sub
            } else {
                s.users.append(User(identity: me, auth0Sub: auth0Sub, name: name, email: email))
            }
        }
    }

    public func importScan(_ scan: ScanImport) async throws {
        // import_scan_v2: validate every object's attributes before writing anything, de-duplicate.
        let attributes = try scan.objects.map { object -> [String] in
            guard object.attributes.count <= ScanObject.maxAttributes,
                  object.attributes.allSatisfy(ScanObject.isValidAttribute) else { throw Failure.invalidAttribute }
            var seen = Set<String>()
            return object.attributes.filter { seen.insert($0).inserted }
        }
        let demo = Dictionary(DemoFixtures.inventory(owner: "demo").items.compactMap { item in item.scanObjectId.map { ($0, item) } },
                              uniquingKeysWith: { a, _ in a })
        try mutateAuthed { s, me in
            let roomId = takeId(), scanId = takeId()
            s.rooms.append(Room(id: roomId, owner: me, name: scan.roomName, joinCode: Self.joinCode(forRoomId: roomId)))
            s.scans.append(Scan(id: scanId, owner: me, roomId: roomId, usdzUrl: scan.usdzUrl, capturedRoomJsonUrl: scan.capturedRoomJsonUrl))
            var skipped: [ScanSkips.Entry] = []
            for (object, attributes) in zip(scan.objects, attributes) {
                // Like the module (#177): skip impossible objects, import the rest.
                if let why = Self.unimportable(object) {
                    skipped.append(ScanSkips.Entry(id: String(object.scanObjectId.prefix(64)), why: why))
                    continue
                }
                var item = Item(
                    id: takeId(), owner: me, roomId: roomId, scanObjectId: object.scanObjectId,
                    name: object.name ?? object.category.capitalized, category: object.category,
                    widthM: object.widthM, heightM: object.heightM, depthM: object.depthM,
                    photoUrls: object.photoUrl.map { [$0] } ?? [], attributes: attributes
                )
                if let template = demo[object.scanObjectId] {
                    Self.identifyDemo(&item, as: template)
                    // The stand-in vision never replaces a name the user gave it in the checklist.
                    if let name = object.name { item.name = name }
                }
                s.items.append(item)
            }
            if !skipped.isEmpty {
                let json = (try? JSONEncoder().encode(skipped.prefix(50).map { ["id": $0.id, "why": $0.why] }))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                s.agentEvents.append(AgentEvent(
                    id: takeId(), owner: me, agent: "scan", kind: .error,
                    message: "Skipped \(skipped.count) scanned object(s) with impossible sizes or labels: "
                        + skipped.prefix(5).map(\.why).joined(separator: ", "),
                    refTable: "scan", refId: scanId, dataJson: json))
            }
        }
    }

    /// `importable` in the module: sizes must be finite, 0...30 m; names ≤120, ids ≤64.
    static func unimportable(_ o: ScanObject) -> String? {
        for (k, v) in [("width_m", o.widthM), ("height_m", o.heightM), ("depth_m", o.depthM)] where !v.isFinite || v < 0 || v > 30 {
            return "\(k)=\(v)"
        }
        if (o.name ?? o.category).count > 120 || o.category.count > 120 { return "name too long" }
        if o.scanObjectId.count > 64 { return "scan_object_id too long" }
        return nil
    }

    /// Stand-in for the vision, pricing and sorting agents on the demo bedroom ("Load demo scan"
    /// offline): an object whose scan id is a demo item's ("demo-<id>") gets that item's name,
    /// details, value and disposition, as if the agents had run. Sentimental items stay undecided.
    /// Colors are not copied: they arrive through `set_item_colors`, like a real scan's.
    private static func identifyDemo(_ item: inout Item, as t: Item) {
        item.name = t.name
        item.material = t.material
        item.brand = t.brand
        item.condition = t.condition
        item.estValueCents = t.estValueCents
        item.disposition = t.disposition
        item.dispositionReason = t.dispositionReason
        item.fragile = t.fragile
        item.maybeSentimental = t.maybeSentimental
    }

    public func addItemPhoto(itemId: UInt64, url: String) async throws {
        try updateOwnedItem(itemId) {
            $0.photoUrls.append(url)
            // A reclassify retake (`ItemReclassify`) queues vision like `add_item_photo`. There's no
            // worker offline, so it stays pending and Item detail says it's waiting to reclassify.
            if ItemReclassify.isMarked(url) { $0.detailsStatus = .pending }
        }
    }

    /// Same checks and status change as `add_scan_photo`. There's no sweep agent
    /// offline, so the scan stays `pending`; the count enforces the module's cap.
    public func addScanPhoto(scanId: UInt64, url: String) async throws {
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") else { throw Failure.invalidUrl }
        try mutateAuthed { s, me in
            guard let i = s.scans.firstIndex(where: { $0.id == scanId }) else { throw Failure.noSuchScan }
            let scan = s.scans[i]
            guard scan.owner == me || memberRoomIds.contains(scan.roomId) else { throw Failure.unauthorized }
            guard scanPhotoCounts[scanId, default: 0] < Self.maxScanPhotos else { throw Failure.tooManyPhotos }
            scanPhotoCounts[scanId, default: 0] += 1
            s.scans[i].sweepStatus = .pending
        }
    }

    /// Offline stand-in for the worker's photo sweep (#92/#181) on the demo bedroom: the scan
    /// goes `pending` → `running` → `done`, and the sweep "finds" one thing RoomPlan missed,
    /// added the way `add_sweep_item` adds it (`scan_object_id = "photo:<scan id>"`, no box,
    /// so it's listed in Items but not placed in the 3D room). `step` paces the statuses.
    public func simulateSweep(scanId: UInt64, step: Duration = .milliseconds(1200)) async throws {
        func set(_ status: Scan.SweepStatus) throws {
            try mutateAuthed { s, _ in
                guard let i = s.scans.firstIndex(where: { $0.id == scanId }) else { throw Failure.noSuchScan }
                s.scans[i].sweepStatus = status
            }
        }
        try set(.pending)
        try await Task.sleep(for: step)
        try set(.running)
        try await Task.sleep(for: step * 2)
        try mutateAuthed { s, me in
            guard let i = s.scans.firstIndex(where: { $0.id == scanId }) else { throw Failure.noSuchScan }
            s.scans[i].sweepStatus = .done
            let found = DemoFixtures.sweepFind
            guard !s.items.contains(where: { $0.scanObjectId == "photo:\(scanId)" && $0.name == found.name }) else { return }
            var item = found
            item.id = takeId()
            item.owner = me
            item.roomId = s.scans[i].roomId
            item.scanObjectId = "photo:\(scanId)"
            s.items.append(item)
        }
    }

    /// `MAX_SCAN_PHOTOS` in the module.
    public static let maxScanPhotos = 12

    public func setDisposition(itemId: UInt64, disposition: Disposition) async throws {
        try updateOwnedItem(itemId) {
            $0.disposition = disposition
            $0.dispositionSource = .user
            $0.dispositionReason = nil
        }
    }

    public func setSentimental(itemId: UInt64, maybeSentimental: Bool) async throws {
        try updateOwnedItem(itemId) { $0.maybeSentimental = maybeSentimental }
    }

    public func setItemColors(itemId: UInt64, colors: ItemColors?) async throws {
        guard colors?.isValid ?? true else { throw Failure.invalidColors }
        try await setItemColors(itemId: itemId, colorsJson: colors?.json ?? "")
    }

    /// `set_item_colors` with the raw `colors_json`, validated like the module: '' clears,
    /// otherwise only `primary` / `secondary` "#RRGGBB" strings, stored uppercase.
    public func setItemColors(itemId: UInt64, colorsJson: String) async throws {
        guard let json = ItemColors.normalizedJson(colorsJson) else { throw Failure.invalidColors }
        try updateOwnedItem(itemId) { $0.colors = ItemColors(json: json) }
    }

    // MARK: Fix-it (rename_item, delete_item, set_item_attributes)

    /// `MAX_NAME` in the module.
    public static let maxNameLength = 120

    public func renameItem(itemId: UInt64, name: String) async throws {
        guard name.count <= Self.maxNameLength else { throw Failure.nameTooLong }
        try updateOwnedItem(itemId) { $0.name = name }
    }

    /// Same as the proposed `rename_room` (#370): the owner renames a room; the name is trimmed,
    /// at most `maxNameLength`, never empty.
    public func renameRoom(roomId: UInt64, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.emptyName }
        guard trimmed.count <= Self.maxNameLength else { throw Failure.nameTooLong }
        try mutateAuthed { s, me in
            guard let i = s.rooms.firstIndex(where: { $0.id == roomId }) else { throw Failure.noSuchRoom }
            guard s.rooms[i].owner == me else { throw Failure.unauthorized }
            s.rooms[i].name = trimmed
        }
    }

    public func deleteItem(itemId: UInt64) async throws {
        try mutateAuthed { s, me in
            guard let i = s.items.firstIndex(where: { $0.id == itemId }) else { throw Failure.noSuchItem }
            guard s.items[i].owner == me || memberRoomIds.contains(s.items[i].roomId) else { throw Failure.unauthorized }
            s.items.remove(at: i)
        }
    }

    /// Same as `add_item`: a hand-added item (no scan object) in a room the caller can edit.
    public func addItem(roomId: UInt64, name: String, category: String, widthM: Double, heightM: Double, depthM: Double, photoUrl: String?) async throws {
        try mutateAuthed { s, me in
            guard let room = s.rooms.first(where: { $0.id == roomId }) else { throw Failure.noSuchRoom }
            guard room.owner == me || memberRoomIds.contains(roomId) else { throw Failure.unauthorized }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            s.items.append(Item(id: takeId(), owner: room.owner, roomId: roomId, name: trimmed.isEmpty ? category : trimmed,
                                category: category, widthM: widthM, heightM: heightM, depthM: depthM,
                                photoUrls: photoUrl.map { [$0] } ?? []))
        }
    }

    /// Validated and de-duplicated like the module's `attributesJsonOf`.
    public func setItemAttributes(itemId: UInt64, attributes: [String]) async throws {
        guard attributes.count <= ScanObject.maxAttributes, attributes.allSatisfy(ScanObject.isValidAttribute) else {
            throw Failure.invalidAttribute
        }
        var seen = Set<String>()
        let unique = attributes.filter { seen.insert($0).inserted }
        try updateOwnedItem(itemId) { $0.attributes = unique }
    }

    public func joinRoom(code: String) async throws {
        let code = Room.normalizeJoinCode(code)
        try mutateAuthed { s, me in
            if let room = s.rooms.first(where: { $0.joinCode == code }) {
                // Already visible: your own room or one you joined is a no-op, as in the module.
                if room.owner != me { memberRoomIds.insert(room.id) }
                return
            }
            guard let room = joinable.rooms.first(where: { $0.joinCode == code }) else { throw Failure.noSuchRoomCode }
            memberRoomIds.insert(room.id)
            s.rooms.append(room)
            s.scans += joinable.scans.filter { $0.roomId == room.id }
            s.items += joinable.items.filter { $0.roomId == room.id }
            s.users += joinable.users.filter { u in u.identity == room.owner && !s.users.contains { $0.identity == u.identity } }
            joinable.rooms.removeAll { $0.id == room.id }
        }
    }

    // MARK: Shopping (#15)

    public func addShoppingItem(name: String, category: String, reason: String) async throws {
        try mutateAuthed { s, me in
            s.shoppingItems.append(ShoppingItem(id: takeId(), owner: me, name: name, category: category, reason: reason))
        }
    }

    public func removeShoppingItem(shoppingItemId: UInt64) async throws {
        try mutateAuthed { s, me in
            guard let i = s.shoppingItems.firstIndex(where: { $0.id == shoppingItemId }) else { return }
            guard s.shoppingItems[i].owner == me else { throw Failure.unauthorized }
            s.shoppingItems.remove(at: i)
        }
    }

    public func chooseDeal(shoppingItemId: UInt64, dealId: UInt64) async throws {
        try mutateAuthed { s, me in
            guard let i = s.shoppingItems.firstIndex(where: { $0.id == shoppingItemId }) else { throw Failure.noSuchShoppingItem }
            guard s.shoppingItems[i].owner == me else { throw Failure.unauthorized }
            guard s.deals.contains(where: { $0.id == dealId && $0.shoppingItemId == shoppingItemId }) else {
                throw Failure.dealDoesNotMatchItem
            }
            s.shoppingItems[i].chosenDealId = dealId
            runBuyAgent(&s, shoppingItemId: shoppingItemId, me: me)
        }
    }

    /// Stand-in for the worker's buy agent (agents/src/agents/buy.ts), always simulated: for the
    /// chosen card-checkout deal, ask for approval above the owner's threshold, otherwise (or once
    /// approved at the same price) record a settled simulated Visa payment and mark the item bought.
    private func runBuyAgent(_ s: inout SyncSnapshot, shoppingItemId: UInt64, me: IdentityHex) {
        guard let i = s.shoppingItems.firstIndex(where: { $0.id == shoppingItemId }),
              s.shoppingItems[i].status != .bought,
              let deal = s.chosenDeal(for: s.shoppingItems[i]),
              deal.supportsCardCheckout, !deal.isFraudBlocked,
              !s.visaPayments(for: deal.id).contains(where: { $0.status != .failed })
        else { return }
        let threshold = s.users.first { $0.identity == me }?.approvalThresholdCents ?? 10_000
        if threshold < 0 || deal.priceCents > threshold {
            let approval = s.purchaseApproval(for: deal.id)
            guard approval?.status == .approved, approval?.amountCents == deal.priceCents else {
                // Ask once; a denial stands. A stale approval (price changed) asks again.
                if approval == nil || (approval?.status == .approved && approval?.amountCents != deal.priceCents) {
                    s.approvals.append(Approval(
                        id: takeId(), owner: me, kind: .purchase, refId: deal.id, amountCents: deal.priceCents,
                        summary: "Buy \"\(deal.title)\" from \(deal.source) for \(Self.dollars(deal.priceCents))"))
                }
                return
            }
        }
        let item = s.shoppingItems[i]
        s.payments.append(Payment(
            id: takeId(), owner: me, agent: "buy", rail: .visa, purpose: "\(item.name): \(deal.title)",
            payee: "simulated merchant", amountUsdMicros: deal.priceCents * 10_000, status: .settled, simulated: true,
            refTable: "deal", refId: deal.id))
        s.shoppingItems[i].status = .bought
    }

    private static func dollars(_ cents: Int64) -> String {
        let c = cents % 100
        return "$\(cents / 100).\(c < 10 ? "0" : "")\(c)"
    }

    public func createNewHome(name: String, source: NewHomeSource, floorPlanJson: String) async throws {
        try mutateAuthed { s, me in
            s.newHomes.append(NewHome(id: takeId(), owner: me, name: name, source: source, floorPlanJson: floorPlanJson))
        }
    }

    public func saveLayout(newHomeId: UInt64, name: String, placementsJson: String) async throws {
        try mutateAuthed { s, me in
            guard let home = s.newHomes.first(where: { $0.id == newHomeId }) else { throw Failure.noSuchNewHome }
            guard home.owner == me else { throw Failure.unauthorized }
            s.layouts.append(Layout(id: takeId(), owner: me, newHomeId: newHomeId, name: name, placementsJson: placementsJson))
        }
    }

    public func decideApproval(approvalId: UInt64, status: ApprovalStatus) async throws {
        try mutateAuthed { s, me in
            guard let i = s.approvals.firstIndex(where: { $0.id == approvalId }) else { throw Failure.noSuchApproval }
            guard s.approvals[i].owner == me else { throw Failure.unauthorized }
            guard s.approvals[i].isPending else { throw Failure.alreadyDecided }
            guard ApprovalStatus.decisions.contains(status) else { throw Failure.invalidStatus }
            let now = Date.now
            s.approvals[i].status = status
            s.approvals[i].updatedAt = now
            // Stand-in for the listing agent (#11): post on approval if the price
            // still matches, otherwise reject. Fixture listings are all simulated.
            let a = s.approvals[i]
            if a.kind == .listing, let l = s.listings.firstIndex(where: { $0.id == a.refId && $0.status == .awaitingApproval }) {
                if status == .approved, s.listings[l].priceCents == a.amountCents {
                    s.listings[l].status = .posted
                    s.listings[l].externalId = String(395_718_200_000 + a.refId)
                } else {
                    s.listings[l].status = .rejected
                }
                s.listings[l].updatedAt = now
            }
            // Stand-in for the buy agent (#15): an approved purchase checks out (simulated).
            if a.kind == .purchase, status == .approved,
               let item = s.shoppingItems.first(where: { $0.chosenDealId == a.refId }) {
                runBuyAgent(&s, shoppingItemId: item.id, me: me)
            }
        }
    }

    /// Worker-side reducer, exposed so tests can check user overrides survive an agent re-run.
    public func setAutoDisposition(itemId: UInt64, disposition: Disposition, reason: String) throws {
        try mutate { s in
            guard let i = s.items.firstIndex(where: { $0.id == itemId }) else { throw Failure.noSuchItem }
            guard s.items[i].dispositionSource != .user, !s.items[i].maybeSentimental else { return }
            s.items[i].disposition = disposition
            s.items[i].dispositionReason = reason
            s.items[i].updatedAt = .now
        }
    }

    // MARK: Internals

    private func takeId() -> UInt64 {
        defer { nextId += 1 }
        return nextId
    }

    private func updateOwnedItem(_ itemId: UInt64, _ change: (inout Item) -> Void) throws {
        try mutateAuthed { s, me in
            guard let i = s.items.firstIndex(where: { $0.id == itemId }) else { throw Failure.noSuchItem }
            // Owners and room members can edit a room's items.
            guard s.items[i].owner == me || memberRoomIds.contains(s.items[i].roomId) else { throw Failure.unauthorized }
            change(&s.items[i])
            s.items[i].updatedAt = .now
        }
    }

    private func mutateAuthed(_ change: (inout SyncSnapshot, IdentityHex) throws -> Void) throws {
        try mutate { s in
            guard let me = s.me else { throw Failure.notConnected }
            try change(&s, me)
        }
    }

    private func mutate(_ change: (inout SyncSnapshot) throws -> Void) rethrows {
        try lock.sync {
            var copy = state
            try change(&copy)
            state = copy
            for c in snapshotContinuations.values { c.yield(copy) }
        }
    }

    private func broadcast(status: SyncStatus) {
        lock.sync {
            for c in statusContinuations.values { c.yield(status) }
        }
    }
}

extension NSLock {
    /// `withLock` isn't in every Linux Foundation, so roll our own.
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
