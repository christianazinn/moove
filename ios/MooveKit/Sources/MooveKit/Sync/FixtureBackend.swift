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
    }

    private let lock = NSLock()
    private var state: SyncSnapshot
    private var nextId: UInt64
    private var snapshotContinuations: [UUID: AsyncStream<SyncSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private let identity: IdentityHex

    public init(identity: IdentityHex = "fixture-user", seed: SyncSnapshot = SyncSnapshot()) {
        self.identity = identity
        self.state = seed
        let ids: [[UInt64]] = [
            seed.rooms.map(\.id), seed.scans.map(\.id), seed.items.map(\.id), seed.comps.map(\.id),
            seed.newHomes.map(\.id), seed.layouts.map(\.id), seed.listings.map(\.id), seed.approvals.map(\.id),
            seed.payments.map(\.id), seed.agentEvents.map(\.id),
        ]
        let maxId = ids.joined().max() ?? 0
        self.nextId = maxId + 1
    }

    /// The bundled demo inventory (already priced and sorted, as if the agents had run).
    public static func demo(identity: IdentityHex = "fixture-user") -> FixtureBackend {
        FixtureBackend(identity: identity, seed: DemoFixtures.demo(owner: identity))
    }

    // MARK: Connection

    public func connect(token: String?) async throws -> (identity: IdentityHex, token: String) {
        mutate { $0.me = identity }
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
        try mutateAuthed { s, me in
            let roomId = takeId()
            s.rooms.append(Room(id: roomId, owner: me, name: scan.roomName))
            s.scans.append(Scan(id: takeId(), owner: me, roomId: roomId, usdzUrl: scan.usdzUrl, capturedRoomJsonUrl: scan.capturedRoomJsonUrl))
            for (object, attributes) in zip(scan.objects, attributes) {
                s.items.append(Item(
                    id: takeId(), owner: me, roomId: roomId, scanObjectId: object.scanObjectId,
                    name: object.category.capitalized, category: object.category,
                    widthM: object.widthM, heightM: object.heightM, depthM: object.depthM,
                    photoUrls: object.photoUrl.map { [$0] } ?? [], attributes: attributes
                ))
            }
        }
    }

    public func addItemPhoto(itemId: UInt64, url: String) async throws {
        try updateOwnedItem(itemId) { $0.photoUrls.append(url) }
    }

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
            guard s.items[i].owner == me else { throw Failure.unauthorized }
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
