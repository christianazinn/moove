import Foundation
import Testing
@testable import MooveKit

@Suite struct ScanSkipsTests {
    @Test func parsesTheModulesEvent() throws {
        // As `noteSkipped` in spacetime/src/index.ts writes it.
        let event = AgentEvent(id: 9, owner: "me", agent: "scan", kind: .error,
                               message: "Skipped 2 scanned object(s) with impossible sizes or labels: width_m=NaN, name too long",
                               refTable: "scan", refId: 4, dataJson: #"[{"id":"A1","why":"width_m=NaN"},{"id":"B2","why":"name too long"}]"#)
        let skips = try #require(ScanSkips(event))
        #expect(skips.count == 2)
        #expect(skips.entries.map(\.why) == ["width_m=NaN", "name too long"])
        #expect(skips.summary == "2 objects looked wrong and were skipped")
        #expect(skips.entries.map(\.readable) == ["width not a number", "name too long"])
        #expect(ScanSkips.Entry(id: "x", why: "depth_m=40").readable == "depth 40 m")
    }

    @Test func ignoresOtherEvents() {
        #expect(ScanSkips(AgentEvent(id: 1, owner: "me", agent: "vision", kind: .error, message: "x", refTable: "item", refId: 4)) == nil)
        #expect(ScanSkips(AgentEvent(id: 1, owner: "me", agent: "scan", kind: .result, message: "x", refTable: "scan", refId: 4)) == nil)
    }

    @Test func fixtureSkipsImpossibleObjectsAndSaysSo() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Bedroom", objects: [
            ScanObject(scanObjectId: "ok", category: "chair", widthM: 0.5, heightM: 0.9, depthM: 0.5),
            ScanObject(scanObjectId: "nan", category: "table", widthM: .nan, heightM: 0.7, depthM: 0.6),
            ScanObject(scanObjectId: "huge", category: "storage", widthM: 40, heightM: 2, depthM: 0.4),
        ]))
        let snap = await firstSnapshot(backend)
        #expect(snap.items.map(\.scanObjectId) == ["ok"])
        let skips = try #require(snap.skips(forScan: snap.scans[0].id))
        #expect(skips.count == 2)
        #expect(skips.entries.map(\.id) == ["nan", "huge"])
    }

    @Test func nothingWhenEverythingImports() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Bedroom", objects: [
            ScanObject(scanObjectId: "ok", category: "chair", widthM: 0.5, heightM: 0.9, depthM: 0.5),
        ]))
        let snap = await firstSnapshot(backend)
        #expect(snap.skips(forScan: snap.scans[0].id) == nil)
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }
}
