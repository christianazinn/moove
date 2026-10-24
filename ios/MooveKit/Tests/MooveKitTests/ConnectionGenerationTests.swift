import Testing
@testable import MooveKit

@Suite struct ConnectionGenerationTests {
    /// Replays the reconnect race: the old connection's cancelled task fails after the new
    /// connection is up. Only the current generation's events may change the status.
    private struct StatusModel {
        var generation = ConnectionGeneration()
        var status: SyncStatus = .disconnected

        mutating func connect() -> UInt64 {
            generation.advance() // disconnect() of the previous connection
            status = .connecting
            return generation.advance()
        }

        mutating func event(_ s: SyncStatus, from g: UInt64) {
            if generation.isCurrent(g) { status = s }
        }
    }

    @Test func lateFailureFromAnOldConnectionIsIgnored() {
        var m = StatusModel()
        let first = m.connect()
        m.event(.connected, from: first)
        let second = m.connect()
        m.event(.connected, from: second)
        m.event(.failed("connection closed"), from: first)
        #expect(m.status == .connected)
    }

    @Test func currentConnectionStillReportsFailuresAndReconnects() {
        var m = StatusModel()
        let g = m.connect()
        m.event(.reconnecting(attempt: 1), from: g)
        #expect(m.status == .reconnecting(attempt: 1))
        m.event(.failed("timed out"), from: g)
        #expect(m.status == .failed("timed out"))
    }

    @Test func disconnectMakesEveryEarlierGenerationStale() {
        var gen = ConnectionGeneration()
        let a = gen.advance()
        #expect(gen.isCurrent(a))
        let b = gen.advance()
        #expect(!gen.isCurrent(a))
        #expect(gen.isCurrent(b))
        #expect(b > a)
    }
}
