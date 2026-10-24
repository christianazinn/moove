import Foundation
import Testing
@testable import MooveKit

@Suite struct FixtureBackendTests {
    @Test func importScanCreatesRoomScanAndItems() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Bedroom", objects: [
            ScanObject(scanObjectId: "a", category: "chair", widthM: 0.5, heightM: 1, depthM: 0.5, photoUrl: "http://x/a.jpg"),
            ScanObject(scanObjectId: "b", category: "table", widthM: 1, heightM: 0.7, depthM: 0.6),
        ]))
        let snap = await firstSnapshot(backend)
        #expect(snap.rooms.count == 1)
        #expect(snap.scans.first?.roomId == snap.rooms.first?.id)
        #expect(snap.items.map(\.scanObjectId) == ["a", "b"])
        #expect(snap.items.allSatisfy { $0.disposition == .undecided && $0.roomId == snap.rooms[0].id })
        #expect(snap.items[0].photoUrls == ["http://x/a.jpg"])
    }

    @Test func userOverrideSurvivesAgentRerun() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.setDisposition(itemId: 11, disposition: .keep)
        try backend.setAutoDisposition(itemId: 11, disposition: .sell, reason: "rerun")
        let item = await firstSnapshot(backend).items.first { $0.id == 11 }
        #expect(item?.disposition == .keep)
        #expect(item?.dispositionSource == .user)
    }

    @Test func agentNeverDecidesSentimentalItems() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try backend.setAutoDisposition(itemId: 18, disposition: .donate, reason: "rerun")
        #expect(await firstSnapshot(backend).items.first { $0.id == 18 }?.disposition == .undecided)
    }

    @Test func cannotEditSomeoneElsesItem() async throws {
        var seed = DemoFixtures.inventory(owner: "alice")
        seed.me = nil
        let backend = FixtureBackend(identity: "mallory", seed: seed)
        _ = try await backend.connect(token: nil)
        await #expect(throws: FixtureBackend.Failure.unauthorized) {
            try await backend.setDisposition(itemId: 11, disposition: .trash)
        }
    }

    @Test func snapshotsStreamLiveChanges() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        var iterator = backend.snapshots().makeAsyncIterator()
        _ = await iterator.next()
        try await backend.setDisposition(itemId: 12, disposition: .donate)
        let next = await iterator.next()
        #expect(next?.items.first { $0.id == 12 }?.disposition == .donate)
    }

    @Test func demoHasSentimentalItemsNeedingUser() {
        let snap = DemoFixtures.inventory(owner: "me")
        #expect(snap.items.count >= 10)
        #expect(snap.items.filter(\.maybeSentimental).allSatisfy { $0.needsUser })
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }
}

@Suite struct ItemModelTests {
    @Test func captureBeatsSam3d() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.setItemModel(itemId: 11, url: "https://x/a.glb", source: .sam3d)
        try await backend.setItemModel(itemId: 11, url: "https://x/a.usdz", source: .capture)
        try await backend.setItemModel(itemId: 11, url: "https://x/b.glb", source: .sam3d)
        var it = backend.snapshots().makeAsyncIterator()
        let item = await it.next()!.items.first { $0.id == 11 }
        #expect(item?.modelUrl == "https://x/a.usdz")
        #expect(item?.modelSource == .capture)
    }

    @Test func newPhotoRequeuesSam3dButNotCapture() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.setItemModel(itemId: 11, url: "https://x/a.glb", source: .sam3d)
        try await backend.addItemPhoto(itemId: 11, url: "https://x/new.jpg")
        var it = backend.snapshots().makeAsyncIterator()
        var item = await it.next()!.items.first { $0.id == 11 }
        #expect(item?.modelStatus == .pending)
        #expect(item?.photoUrls.last == "https://x/new.jpg")

        try await backend.setItemModel(itemId: 11, url: "https://x/a.usdz", source: .capture)
        try await backend.addItemPhoto(itemId: 11, url: "https://x/newer.jpg")
        it = backend.snapshots().makeAsyncIterator()
        item = await it.next()!.items.first { $0.id == 11 }
        #expect(item?.modelStatus == .done)
    }
}

@Suite struct ModelProgressTests {
    private func item(photos: [String] = ["https://x/1.jpg"], url: String? = nil, source: ModelSource? = nil, status: ModelStatus = .pending) -> Item {
        Item(id: 1, owner: "me", roomId: 1, name: "Chair", category: "chair", widthM: 0.5, heightM: 1, depthM: 0.5,
             photoUrls: photos, modelUrl: url, modelSource: source, modelStatus: status)
    }

    @Test func states() {
        #expect(item(url: "https://x/m.glb", source: .sam3d, status: .done).modelProgress() == .ready(.sam3d))
        #expect(item(photos: [], status: .pending).modelProgress(hasLocalModel: true) == .ready(.capture))
        #expect(item(status: .running).modelProgress() == .building)
        #expect(item(status: .pending).modelProgress() == .queued)
        #expect(item(status: .failed).modelProgress() == .failed)
        #expect(item(photos: [], status: .pending).modelProgress() == .needsPhotos)
        // A newer photo re-queues even a ready SAM 3D model, but the old model still shows.
        #expect(item(url: "https://x/m.glb", source: .sam3d, status: .pending).modelProgress() == .ready(.sam3d))
    }
}
