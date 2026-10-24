import Foundation
import MooveKit
import SpacetimeDB

// Contract-specific glue: which tables to subscribe to, how generated rows map
// to MooveKit models, and which reducer each intent calls.
//
// PENDING #2: the module isn't published yet. Once it is, regenerate
// `Sync/Generated/` (see Sync/README.md), then fill in the tables and
// reducers below. Until then, use the "Offline demo" backend.

extension SpacetimeBackend {
    static let tableNames: [String] = []

    static var subscriptionQueries: [String] { tableNames.map { "SELECT * FROM \($0)" } }

    static let tableDecoders: [@Sendable (SpacetimeDBClient) async -> Void] = []

    static func primaryKey(of row: Any) -> AnyHashable? {
        nil
    }

    static func makeSnapshot(cache: [String: [AnyHashable: Any]], me: IdentityHex?) -> SyncSnapshot {
        SyncSnapshot(me: me)
    }

    func registerUser(name: String, email: String?, auth0Sub: String?) async throws {
        throw Failure.reducerFailed("registerUser: waiting on the SpacetimeDB module (#2)")
    }

    func importScan(_ scan: ScanImport) async throws {
        throw Failure.reducerFailed("importScan: waiting on the SpacetimeDB module (#2)")
    }

    func addItemPhoto(itemId: UInt64, url: String) async throws {
        throw Failure.reducerFailed("addItemPhoto: waiting on the SpacetimeDB module (#2)")
    }

    func setDisposition(itemId: UInt64, disposition: Disposition) async throws {
        throw Failure.reducerFailed("setDisposition: waiting on the SpacetimeDB module (#2)")
    }

    func setSentimental(itemId: UInt64, maybeSentimental: Bool) async throws {
        throw Failure.reducerFailed("setSentimental: waiting on the SpacetimeDB module (#2)")
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
        throw Failure.reducerFailed("createNewHome: waiting on the SpacetimeDB module (#2)")
    }

    func saveLayout(newHomeId: UInt64, name: String, placementsJson: String) async throws {
        throw Failure.reducerFailed("saveLayout: waiting on the SpacetimeDB module (#2)")
    }

    func decideApproval(approvalId: UInt64, status: ApprovalStatus) async throws {
        throw Failure.reducerFailed("decideApproval: waiting on the SpacetimeDB module (#2)")
    }
}
