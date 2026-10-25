import Foundation
import Testing
@testable import MooveKit

@Suite struct ItemReclassifyTests {
    private func item(_ name: String, _ category: String, status: AgentStage? = nil, photos: [String] = []) -> Item {
        Item(id: 1, owner: "me", roomId: 1, name: name, category: category,
             widthM: 1.0, heightM: 0.66, depthM: 0.95, photoUrls: photos, detailsStatus: status)
    }

    @Test func marksAPhotoUrlOnce() {
        let url = "https://abc.trycloudflare.com/files/3f2b8c1e.jpg"
        let marked = ItemReclassify.marking(url)
        #expect(marked == url + "?reclassify=1")
        #expect(ItemReclassify.marking(marked) == marked)
        #expect(ItemReclassify.isMarked(marked))
        #expect(!ItemReclassify.isMarked(url))
        #expect(!ItemReclassify.isMarked(url + "?reclassify=0"))
        #expect(ItemReclassify.marking("https://x.com/a.jpg?v=2") == "https://x.com/a.jpg?v=2&reclassify=1")
        // offline demo photos are file URLs; the query doesn't change the path that's read
        let file = ItemReclassify.marking("file:///var/mobile/Documents/item-1.jpg")
        #expect(URL(string: file)?.path == "/var/mobile/Documents/item-1.jpg")
    }

    @Test func menuTitleNamesTheCategory() {
        #expect(ItemReclassify.menuTitle(for: item("vacuum", "vacuum")) == "Not a vacuum? Take a photo")
        #expect(ItemReclassify.menuTitle(for: item("Oven", "oven")) == "Not an oven? Take a photo")
        #expect(ItemReclassify.menuTitle(for: item("Other", "other")) == "Wrong item? Take a photo")
        #expect(ItemReclassify.menuTitle(for: item("Thing", "")) == "Wrong item? Take a photo")
    }

    @Test func statusFollowsVision() {
        let retake = ["https://w/files/crop.jpg", "https://w/files/new.jpg?reclassify=1"]
        #expect(ItemReclassify.status(for: item("vacuum", "vacuum", status: .done, photos: ["https://w/files/crop.jpg"]), offline: false) == nil)
        for stage in [AgentStage.pending, .running] {
            let it = item("vacuum", "vacuum", status: stage, photos: retake)
            #expect(ItemReclassify.isReclassifying(it))
            #expect(ItemReclassify.status(for: it, offline: false) == "Reclassifying from your photo…")
        }
        #expect(ItemReclassify.status(for: item("vacuum", "vacuum", status: .pending, photos: retake), offline: true)!.contains("offline demo"))
        let done = item("black Segway Ninebot e-scooter", "scooter", status: .done, photos: retake)
        #expect(!ItemReclassify.isReclassifying(done))
        #expect(ItemReclassify.status(for: done, offline: false) == "Reclassified from your photo.")
        #expect(ItemReclassify.status(for: item("vacuum", "vacuum", status: .failed, photos: retake), offline: false)!.hasPrefix("Couldn't reclassify"))
        // a later ordinary photo is an ordinary re-identify
        #expect(ItemReclassify.status(for: item("x", "x", status: .pending, photos: retake + ["https://w/files/c.jpg"]), offline: false) == nil)
    }

    @Test func fixtureKeepsTheRetakeAndQueuesIt() async throws {
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Hall", objects: [
            ScanObject(scanObjectId: "s", category: "vacuum", widthM: 1.0, heightM: 0.66, depthM: 0.95,
                       photoUrl: "file:///tmp/crop.jpg", name: "vacuum"),
        ]))
        var snapshots = backend.snapshots().makeAsyncIterator()
        let id = try #require(await snapshots.next()?.items.first?.id)
        try await backend.addItemPhoto(itemId: id, url: "file:///tmp/plain.jpg")
        #expect(await snapshots.next()?.items.first?.detailsStatus == nil, "an ordinary photo offline changes no status")
        try await backend.addItemPhoto(itemId: id, url: ItemReclassify.marking("file:///tmp/retake.jpg"))
        let item = try #require(await snapshots.next()?.items.first)
        #expect(item.photoUrls.count == 3)
        #expect(ItemReclassify.isReclassifying(item))
        #expect(item.name == "vacuum")
    }
}
