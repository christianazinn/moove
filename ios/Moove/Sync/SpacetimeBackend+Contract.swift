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
}
