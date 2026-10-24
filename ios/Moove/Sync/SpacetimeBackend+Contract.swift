import Foundation
import MooveKit
import SpacetimeDB
import MooveBindings

// Contract-specific glue for the module in spacetime/src/index.ts (see
// docs/data-model.md): which rows to subscribe to, how generated rows map to
// MooveKit models, and which reducer each intent calls. Regenerate the
// MooveBindings package after any contract change (Sync/README.md).
//
// Wire conventions: snake_case names, string "enums", and sentinels instead of
// options ('' = none, -1 = unknown).

extension SpacetimeBackend {
    static let tableNames = [
        "user", "room", "room_member", "scan", "item", "comp",
        "new_home", "layout", "listing", "approval",
    ]

    /// Everything the signed-in identity can see: its own rows, plus rooms,
    /// scans and items shared with it through `room_member` (#10).
    /// Tables are public, so the WHERE clauses are what keeps this per-user.
    static func subscriptionQueries(me: IdentityHex) -> [String] {
        let id = "0x\(me)"
        let shared = "JOIN room_member ON %1$@ = room_member.room_id WHERE room_member.member = \(id)"
        return [
            "SELECT * FROM user WHERE identity = \(id)",
            "SELECT * FROM room_member WHERE member = \(id)",
            "SELECT * FROM room WHERE owner = \(id)",
            "SELECT room.* FROM room " + String(format: shared, "room.id"),
            "SELECT * FROM scan WHERE owner = \(id)",
            "SELECT scan.* FROM scan " + String(format: shared, "scan.room_id"),
            "SELECT * FROM item WHERE owner = \(id)",
            "SELECT item.* FROM item " + String(format: shared, "item.room_id"),
            "SELECT comp.* FROM comp JOIN item ON comp.item_id = item.id WHERE item.owner = \(id)",
            "SELECT * FROM new_home WHERE owner = \(id)",
            "SELECT * FROM layout WHERE owner = \(id)",
            "SELECT * FROM listing WHERE owner = \(id)",
            "SELECT * FROM approval WHERE owner = \(id)",
        ]
    }

    static let tableDecoders: [@Sendable (SpacetimeDBClient) async -> Void] = [
        { await $0.registerTableRowDecoder(MooveBindings.UserRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.RoomRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.RoomMemberRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.ScanRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.ItemRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.CompRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.NewHomeRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.LayoutRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.ListingRow.self) },
        { await $0.registerTableRowDecoder(MooveBindings.ApprovalRow.self) },
    ]

    static func primaryKey(of row: Any) -> AnyHashable? {
        guard let row = row as? any BSATNTableWithPrimaryKey else { return nil }
        return AnyHashable(row.primaryKey)
    }

    static func makeSnapshot(cache: [String: [AnyHashable: Any]], me: IdentityHex?) -> SyncSnapshot {
        func rows<R>(_ table: String, _: R.Type) -> [R] { cache[table]?.values.compactMap { $0 as? R } ?? [] }
        var s = SyncSnapshot(me: me)
        s.users = rows("user", MooveBindings.UserRow.self).map(User.init)
        s.rooms = rows("room", MooveBindings.RoomRow.self).map(Room.init).sorted { $0.id < $1.id }
        s.scans = rows("scan", MooveBindings.ScanRow.self).map(Scan.init).sorted { $0.id < $1.id }
        s.items = rows("item", MooveBindings.ItemRow.self).map(Item.init).sorted { $0.id < $1.id }
        s.comps = rows("comp", MooveBindings.CompRow.self).map(Comp.init).sorted { $0.id < $1.id }
        s.newHomes = rows("new_home", MooveBindings.NewHomeRow.self).compactMap(NewHome.init).sorted { $0.id < $1.id }
        s.layouts = rows("layout", MooveBindings.LayoutRow.self).map(Layout.init).sorted { $0.id < $1.id }
        s.listings = rows("listing", MooveBindings.ListingRow.self).compactMap(Listing.init).sorted { $0.id < $1.id }
        s.approvals = rows("approval", MooveBindings.ApprovalRow.self).compactMap(Approval.init).sorted { $0.id < $1.id }
        return s
    }

    // MARK: Reducers

    func registerUser(name: String, email: String?, auth0Sub: String?) async throws {
        try await call(RegisterUserReducer(auth0sub: auth0Sub ?? "", nameArg: name, email: email ?? ""))
    }

    func importScan(_ scan: ScanImport) async throws {
        try await call(ImportScanReducer(
            roomname: scan.roomName,
            home: Home.old.rawValue,
            usdzurl: scan.usdzUrl ?? "",
            capturedroomjsonurl: scan.capturedRoomJsonUrl ?? "",
            objects: scan.objects.map {
                // name '' = the module names it from the category until vision runs.
                ScanObjectInput(scanObjectId: $0.scanObjectId, name: "", category: $0.category,
                                widthM: $0.widthM, heightM: $0.heightM, depthM: $0.depthM, photoUrl: $0.photoUrl ?? "")
            }
        ))
    }

    func addItemPhoto(itemId: UInt64, url: String) async throws {
        try await call(AddItemPhotoReducer(itemid: itemId, url: url))
    }

    func setDisposition(itemId: UInt64, disposition: Disposition) async throws {
        try await call(SetDispositionReducer(itemid: itemId, disposition: disposition.rawValue))
    }

    func setSentimental(itemId: UInt64, maybeSentimental: Bool) async throws {
        try await call(SetSentimentalReducer(itemid: itemId, value: maybeSentimental))
    }

    // Shopping (#15). Once bindings exist: add_shopping_item(owner: me, name, category, reason),
    // remove_shopping_item(shopping_item_id), choose_deal(shopping_item_id, deal_id); and subscribe to
    // shopping_item / deal (ShoppingItem(chosenDealId: 0 -> nil), Deal(url: "" -> nil, fraud_score: -1 -> nil)).

    func addShoppingItem(name: String, category: String, reason: String) async throws {
        throw Failure.reducerFailed("addShoppingItem: waiting on the SpacetimeDB module (#2)")
    }

    func removeShoppingItem(shoppingItemId: UInt64) async throws {
        throw Failure.reducerFailed("removeShoppingItem: waiting on the SpacetimeDB module (#2)")
    }

    func chooseDeal(shoppingItemId: UInt64, dealId: UInt64) async throws {
        throw Failure.reducerFailed("chooseDeal: waiting on the SpacetimeDB module (#2)")
    }

    func createNewHome(name: String, source: NewHomeSource, floorPlanJson: String) async throws {
        try await call(CreateNewHomeReducer(nameArg: name, source: source.rawValue, floorplanjson: floorPlanJson))
    }

    func saveLayout(newHomeId: UInt64, name: String, placementsJson: String) async throws {
        try await call(SaveLayoutReducer(newhomeid: newHomeId, nameArg: name, placementsjson: placementsJson))
    }

    func decideApproval(approvalId: UInt64, status: ApprovalStatus) async throws {
        try await call(DecideApprovalReducer(approvalid: approvalId, status: status.rawValue))
    }
}

// MARK: - Row → model mapping

private func optional(_ s: String) -> String? { s.isEmpty ? nil : s }
private func optional(_ cents: Int64) -> Int64? { cents < 0 ? nil : cents }

private extension User {
    init(_ r: MooveBindings.UserRow) {
        self.init(identity: r.identity.description, auth0Sub: optional(r.auth0Sub), name: r.name,
                  email: optional(r.email), approvalThresholdCents: r.approvalThresholdCents)
    }
}

private extension Room {
    init(_ r: MooveBindings.RoomRow) {
        self.init(id: r.id, owner: r.owner.description, name: r.name, home: Home(rawValue: r.home) ?? .old)
    }
}

private extension Scan {
    init(_ r: MooveBindings.ScanRow) {
        self.init(id: r.id, owner: r.owner.description, roomId: r.roomId, usdzUrl: optional(r.usdzUrl),
                  capturedRoomJsonUrl: optional(r.capturedRoomJsonUrl), createdAt: r.createdAt.date)
    }
}

private extension Item {
    init(_ r: MooveBindings.ItemRow) {
        self.init(
            id: r.id, owner: r.owner.description, roomId: r.roomId, scanObjectId: optional(r.scanObjectId),
            name: r.name, category: r.category, widthM: r.widthM, heightM: r.heightM, depthM: r.depthM,
            photoUrls: r.photoUrls, material: optional(r.material), brand: optional(r.brand),
            condition: Self.conditionScore(r.condition), estValueCents: optional(r.estValueCents),
            disposition: Disposition(rawValue: r.disposition) ?? .undecided,
            dispositionSource: DispositionSource(rawValue: r.dispositionSource) ?? .auto,
            dispositionReason: optional(r.dispositionReason),
            fragile: r.fragile, maybeSentimental: r.maybeSentimental, updatedAt: r.updatedAt.date
        )
    }

    /// The vision agent writes new / like_new / good / fair / poor; screens show 1-5.
    static func conditionScore(_ s: String) -> Int? {
        switch s {
        case "new": 5
        case "like_new": 4
        case "good": 3
        case "fair": 2
        case "poor": 1
        default: Int(s)
        }
    }
}

private extension Comp {
    init(_ r: MooveBindings.CompRow) {
        self.init(id: r.id, itemId: r.itemId, source: r.source, title: r.title, priceCents: r.priceCents, url: r.url)
    }
}

private extension NewHome {
    init?(_ r: MooveBindings.NewHomeRow) {
        guard let source = NewHomeSource(rawValue: r.source) else { return nil }
        self.init(id: r.id, owner: r.owner.description, name: r.name, source: source,
                  floorPlanJson: r.floorPlanJson, createdAt: r.createdAt.date)
    }
}

private extension Layout {
    init(_ r: MooveBindings.LayoutRow) {
        self.init(id: r.id, owner: r.owner.description, newHomeId: r.newHomeId, name: r.name,
                  placementsJson: r.placementsJson, createdAt: r.createdAt.date)
    }
}

private extension Listing {
    init?(_ r: MooveBindings.ListingRow) {
        guard let status = ListingStatus(rawValue: r.status) else { return nil }
        self.init(id: r.id, owner: r.owner.description, itemId: r.itemId, platform: r.platform, title: r.title,
                  description: r.description, priceCents: r.priceCents, status: status,
                  externalId: optional(r.externalId), url: optional(r.url), simulated: r.simulated,
                  updatedAt: r.updatedAt.date)
    }
}

private extension Approval {
    init?(_ r: MooveBindings.ApprovalRow) {
        guard let kind = ApprovalKind(rawValue: r.kind), let status = ApprovalStatus(rawValue: r.status) else { return nil }
        self.init(id: r.id, owner: r.owner.description, kind: kind, refId: r.refId, amountCents: r.amountCents,
                  summary: r.summary, status: status, requestedAt: r.requestedAt.date, updatedAt: r.updatedAt.date)
    }
}
