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
    /// While (re)subscribing, rows fill this instead, and screens keep showing the
    /// last complete snapshot. Swapped into `cache` once the subscription is applied,
    /// so a reconnect never shows a half-empty room (which would also tear down,
    /// e.g., an Object Capture presented from a screen whose item vanished).
    private var staging: [String: [AnyHashable: Any]]?
    private var publishScheduled = false
    private var me: IdentityHex?
    private var tasks: [Task<Void, Never>] = []
    private var snapshotContinuations: [UUID: AsyncStream<SyncSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private var lastStatus: SyncStatus = .disconnected
    /// Bumped on every connect/disconnect. A cancelled task from an older connection can still
    /// run its exit path after a reconnect; tagging events with their generation keeps it from
    /// setting `.failed` (or touching rows) while the new connection is fine.
    private var generation = ConnectionGeneration()

    init(host: String, db: String) {
        self.host = host
        self.db = db
    }

    // MARK: Connection

    func connect(token: String?) async throws -> (identity: IdentityHex, token: String) {
        await disconnect()
        let gen = lock.withLock { generation.advance() }
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
                    self.apply(event, table: table, generation: gen)
                }
            })
        }
        lock.withLock { self.client = client }

        // The SDK's auto-reconnect only reconnects when a delegate is set (we use event streams),
        // so it would just count "reconnecting" for minutes and give up. Report the drop instead
        // and let the app reconnect (`AuthGate`, `SyncStatus.needsReconnect`).
        try await client.connect(token: token.map(AuthenticationToken.init(rawValue:)), enableAutoReconnect: false)

        return try await withCheckedThrowingContinuation { continuation in
            track(Task { [weak self] in
                var pending: CheckedContinuation<(identity: IdentityHex, token: String), Error>? = continuation
                func fail(_ why: String) {
                    // A superseded connection says nothing; its caller gets a cancellation.
                    let current = self?.broadcast(status: .failed(why), from: gen) ?? false
                    pending?.resume(throwing: current ? Failure.connectFailed(why) : CancellationError())
                    pending = nil
                }
                for await event in connectionEvents {
                    guard let self, !Task.isCancelled else { break }
                    switch event {
                    case let .connected(identity, _, newToken):
                        // Also fires after each auto-reconnect. The SDK doesn't
                        // replay subscriptions, so drop the cache and resubscribe.
                        let hex = identity.description
                        let current = self.lock.withLock { () -> Bool in
                            guard self.generation.isCurrent(gen) else { return false }
                            self.me = hex
                            self.staging = [:]
                            return true
                        }
                        guard current else { break }
                        do {
                            try await self.subscribe(client, me: hex, generation: gen)
                            self.broadcast(status: .connected, from: gen)
                            pending?.resume(returning: (hex, newToken))
                            pending = nil
                        } catch {
                            fail("subscribe failed: \(error)")
                        }
                    case let .reconnecting(attempt):
                        self.broadcast(status: .reconnecting(attempt: attempt), from: gen)
                    case let .disconnected(reason):
                        fail(reason ?? "disconnected")
                    case let .error(error):
                        // The SDK's only error event: it gave up auto-reconnecting. Without
                        // this the status would stay "reconnecting" forever.
                        if pending != nil { fail("\(error)") } else { self.broadcast(status: .failed("\(error)")) }
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
                self.staging = nil
                self.me = nil
                self.generation.advance()
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

    private func subscribe(_ client: SpacetimeDBClient, me: IdentityHex, generation gen: UInt64) async throws {
        let handle = try await client.subscribe(Self.subscriptionQueries(me: me))
        try await handle.applied()
        // Initial rows reach `apply` through per-table row streams, which can lag
        // the applied() callback a little; let them drain before the swap.
        try? await Task.sleep(for: .milliseconds(250))
        let current = lock.withLock { () -> Bool in
            guard generation.isCurrent(gen) else { return false }
            if let staged = staging { cache = staged }
            staging = nil
            return true
        }
        if current { publish() }
        // Views a module may not have yet (#254). Their own subscription, so if the server
        // rejects them only this one fails; rows land in the cache like any other update.
        if current { _ = try? await client.subscribe(Self.optionalSubscriptionQueries) }
    }

    private func apply(_ event: RowEvent, table: String, generation gen: UInt64) {
        let syncing = lock.withLock { () -> Bool? in
            guard generation.isCurrent(gen) else { return nil }
            func write(_ target: inout [String: [AnyHashable: Any]]) {
                switch event {
                case let .inserted(row), let .updated(_, row):
                    if let key = Self.primaryKey(of: row) { target[table, default: [:]][key] = row }
                case let .deleted(row):
                    if let key = Self.primaryKey(of: row) { target[table]?.removeValue(forKey: key) }
                }
            }
            if staging != nil {
                write(&staging!)
                return true
            }
            write(&cache)
            return false
        }
        if syncing == false { schedulePublish() }
    }

    /// Coalesces bursts (a reducer touching many rows, agents writing) into at
    /// most one snapshot rebuild every 50 ms instead of one per row.
    private func schedulePublish() {
        let first = lock.withLock { () -> Bool in
            if publishScheduled { return false }
            publishScheduled = true
            return true
        }
        guard first else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.publishScheduled = false }
            self.publish()
        }
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

    /// Broadcasts only if `gen` is still the live connection. Returns whether it was.
    @discardableResult
    private func broadcast(status: SyncStatus, from gen: UInt64) -> Bool {
        lock.withLock {
            guard generation.isCurrent(gen) else { return false }
            lastStatus = status
            for c in statusContinuations.values { c.yield(status) }
            return true
        }
    }

    /// The connected identity (hex), for reducers that take the owner as an argument.
    var currentIdentity: IdentityHex? { lock.withLock { me } }

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
