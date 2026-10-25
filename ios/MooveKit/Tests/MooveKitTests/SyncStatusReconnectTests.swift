import Testing
@testable import MooveKit

@Suite struct SyncStatusReconnectTests {
    @Test func reconnectsADroppedConnection() {
        #expect(SyncStatus.failed("Software caused connection abort").needsReconnect)
        #expect(SyncStatus.reconnecting(attempt: 1).needsReconnect, "the SDK's auto-reconnect is off: the app does it")
        #expect(!SyncStatus.connected.needsReconnect)
        #expect(!SyncStatus.connecting.needsReconnect)
        #expect(!SyncStatus.disconnected.needsReconnect, "signed out or switching backends: leave it")
    }

    @Test func backsOffThenRetriesEvery15Seconds() {
        #expect((1...7).map { SyncStatus.reconnectDelay(attempt: $0) } == [1, 2, 4, 8, 15, 15, 15])
    }
}
