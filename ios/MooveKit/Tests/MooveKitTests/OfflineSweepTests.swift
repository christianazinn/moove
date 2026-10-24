import Foundation
import Testing
@testable import MooveKit

@Suite struct OfflineSweepTests {
    @Test func demoSweepRunsAndAddsAPhotoItem() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(DemoFixtures.scanImport())
        var it = backend.snapshots().makeAsyncIterator()
        let before = await it.next()!
        let scan = try #require(before.scans.last)
        try await backend.simulateSweep(scanId: scan.id, step: .milliseconds(1))
        let after = await it.next()!
        #expect(after.scans.last?.sweepStatus == .done)
        let found = try #require(after.items.first { $0.scanObjectId == "photo:\(scan.id)" })
        #expect(found.name == "Acoustic guitar" && found.roomId == scan.roomId)
        // Running it again doesn't add a second guitar.
        try await backend.simulateSweep(scanId: scan.id, step: .milliseconds(1))
        let again = backend.snapshots()
        var it2 = again.makeAsyncIterator()
        #expect(await it2.next()!.items.filter { $0.scanObjectId == "photo:\(scan.id)" }.count == 1)
    }
}
