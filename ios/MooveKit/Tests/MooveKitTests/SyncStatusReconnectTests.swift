import Testing
@testable import MooveKit

@Suite struct SyncStatusReconnectTests {
    @Test func reconnectsOnlyADeadConnection() {
        #expect(SyncStatus.failed("Software caused connection abort").needsReconnect)
        #expect(SyncStatus.reconnecting(attempt: 3).needsReconnect)
        #expect(!SyncStatus.reconnecting(attempt: 1).needsReconnect, "the SDK's own first retries get a chance")
        #expect(!SyncStatus.connected.needsReconnect)
        #expect(!SyncStatus.connecting.needsReconnect)
        #expect(!SyncStatus.disconnected.needsReconnect, "signed out or switching backends: leave it")
    }
}
