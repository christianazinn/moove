import Foundation
import MooveKit
import SpacetimeDB
import BSATN

/// `SyncBackend` over the community Swift SDK. Keeps a local row cache per
/// table (keyed by primary key) and turns it into a `SyncSnapshot` after every
/// transaction. Table- and reducer-specific code lives in
/// `SpacetimeBackend+Contract.swift`, which is regenerated with the module.
final class SpacetimeBackend: SyncBackend, @unchecked Sendable {
    enum Failure: Error, LocalizedError {
        case notConnected
        case connectFailed(String)
        case reducerFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: "Not connected to SpacetimeDB"
            case .connectFailed(let why): "Couldn't connect to SpacetimeDB: \(why)"
            case .reducerFailed(let why): why
            }
        }
    }

    private let host: String
    private let db: String
    private let lock = NSLock()
    private var client: SpacetimeDBClient?
    private var cache: [String: [AnyHashable: Any]] = [:]
    private var me: IdentityHex?
    private var tasks: [Task<Void, Never>] = []
    private var snapshotContinuations: [UUID: AsyncStream<SyncSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private var lastStatus: SyncStatus = .disconnected

    init(host: String, db: String) {
        self.host = host
        self.db = db
    }

    // MARK: Connection

    func connect(token: String?) async throws -> (identity: IdentityHex, token: String) {
        await disconnect()
        broadcast(status: .connecting)

        let client = try SpacetimeDBClient(host: host, db: db)
        for register in Self.tableDecoders { await register(client) }
        let connectionEvents = await client.connectionEvents
        // Row streams must exist before Subscribe so initial rows aren't missed.
        // They outlive reconnects, so register them once per client.
        for table in Self.tableNames {
            let events = await client.rowEvents(table: table)
            track(Task { [weak self] in
                for await event in events {
                    guard let self, !Task.isCancelled else { return }
                    self.apply(event, table: table)
                }
            })
        }
        lock.withLock { self.client = client }

        try await client.connect(token: token.map(AuthenticationToken.init(rawValue:)))

        return try await withCheckedThrowingContinuation { continuation in
            track(Task { [weak self] in
                var pending: CheckedContinuation<(identity: IdentityHex, token: String), Error>? = continuation
                func fail(_ why: String) {
                    self?.broadcast(status: .failed(why))
                    pending?.resume(throwing: Failure.connectFailed(why))
                    pending = nil
                }
                for await event in connectionEvents {
                    guard let self, !Task.isCancelled else { break }
                    switch event {
                    case let .connected(identity, _, newToken):
                        // Also fires after each auto-reconnect. The SDK doesn't
                        // replay subscriptions, so drop the cache and resubscribe.
                        let hex = identity.description
                        self.lock.withLock {
                            self.me = hex
                            self.cache = [:]
                        }
                        do {
                            try await self.subscribe(client, me: hex)
                            self.broadcast(status: .connected)
                            pending?.resume(returning: (hex, newToken))
                            pending = nil
                        } catch {
                            fail("subscribe failed: \(error)")
                        }
                    case let .reconnecting(attempt):
                        self.broadcast(status: .reconnecting(attempt: attempt))
                    case let .disconnected(reason):
                        fail(reason ?? "disconnected")
                    case let .error(error):
                        if pending != nil { fail("\(error)") }
                    }
                }
                fail("connection closed")
            })
        }
    }

    func disconnect() async {
        let (client, tasks) = lock.withLock { () -> (SpacetimeDBClient?, [Task<Void, Never>]) in
            defer {
                self.client = nil
                self.tasks = []
                self.cache = [:]
                self.me = nil
            }
            return (self.client, self.tasks)
        }
        tasks.forEach { $0.cancel() }
        if let client { await client.disconnect() }
        publish()
        broadcast(status: .disconnected)
    }

    private func track(_ task: Task<Void, Never>) {
        lock.withLock { tasks.append(task) }
    }

    private func subscribe(_ client: SpacetimeDBClient, me: IdentityHex) async throws {
        let handle = try await client.subscribe(Self.subscriptionQueries(me: me))
        try await handle.applied()
        publish()
    }

    private func apply(_ event: RowEvent, table: String) {
        lock.withLock {
            switch event {
            case let .inserted(row):
                if let key = Self.primaryKey(of: row) { cache[table, default: [:]][key] = row }
            case let .deleted(row):
                if let key = Self.primaryKey(of: row) { cache[table]?.removeValue(forKey: key) }
            case let .updated(_, row):
                if let key = Self.primaryKey(of: row) { cache[table, default: [:]][key] = row }
            }
        }
        publish()
    }

    // MARK: Streams

    func snapshots() -> AsyncStream<SyncSnapshot> {
        let (stream, continuation) = AsyncStream<SyncSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let key = UUID()
        lock.withLock {
            snapshotContinuations[key] = continuation
            continuation.yield(Self.makeSnapshot(cache: cache, me: me))
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.snapshotContinuations.removeValue(forKey: key) }
        }
        return stream
    }

    func statusUpdates() -> AsyncStream<SyncStatus> {
        let (stream, continuation) = AsyncStream<SyncStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let key = UUID()
        lock.withLock {
            statusContinuations[key] = continuation
            continuation.yield(lastStatus)
        }
        continuation.onTermination = { [weak self] _ in
            self?.lock.withLock { _ = self?.statusContinuations.removeValue(forKey: key) }
        }
        return stream
    }

    private func publish() {
        lock.withLock {
            let snapshot = Self.makeSnapshot(cache: cache, me: me)
            for c in snapshotContinuations.values { c.yield(snapshot) }
        }
    }

    private func broadcast(status: SyncStatus) {
        lock.withLock {
            lastStatus = status
            for c in statusContinuations.values { c.yield(status) }
        }
    }

    // MARK: Reducers

    func call<R: Reducer>(_ reducer: R) async throws {
        guard let client = lock.withLock({ self.client }) else { throw Failure.notConnected }
        do {
            _ = try await client.callReducer(reducer)
        } catch ReducerCallError.executionError(let payload) {
            // TS reducers throw SenderError(message); the payload is a BSATN string.
            let message = (try? BSATNReader(data: payload).readString()) ?? "\(payload.count) bytes"
            throw Failure.reducerFailed("\(reducer.name) rejected: \(message)")
        }
    }
}
