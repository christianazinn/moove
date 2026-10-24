import Foundation
import Testing
@testable import MooveKit

@Suite struct ScanSubmissionTests {
    @Test func onlyHTTPURLsAreSyncable() {
        #expect(ScanSubmission.isSyncableURL("https://worker.example/u/a.jpg"))
        #expect(ScanSubmission.isSyncableURL("HTTP://10.0.0.5:8787/u/a.usdz"))
        #expect(!ScanSubmission.isSyncableURL("file:///var/mobile/Documents/scans/x/room.usdz"))
        #expect(!ScanSubmission.isSyncableURL("/var/mobile/room.json"))
        #expect(!ScanSubmission.isSyncableURL("https://"))
        #expect(!ScanSubmission.isSyncableURL(""))
        #expect(!ScanSubmission.isSyncableURL(nil))
    }

    @Test func syncableDropsLocalURLs() {
        let scan = ScanImport(
            roomName: "Bedroom",
            usdzUrl: "file:///scans/x/room.usdz",
            capturedRoomJsonUrl: "https://w/u/room.json",
            objects: [
                ScanObject(scanObjectId: "a", category: "chair", widthM: 1, heightM: 1, depthM: 1, photoUrl: "file:///a.jpg"),
                ScanObject(scanObjectId: "b", category: "bed", widthM: 1, heightM: 1, depthM: 1, photoUrl: "https://w/u/b.jpg"),
            ]
        )
        #expect(scan.hasLocalOnlyRoomFiles)
        let synced = scan.syncable()
        #expect(synced.usdzUrl == nil)
        #expect(synced.capturedRoomJsonUrl == "https://w/u/room.json")
        #expect(synced.objects.map(\.photoUrl) == [nil, "https://w/u/b.jpg"])
        #expect(synced.hasLocalOnlyRoomFiles)
        #expect(!ScanImport(roomName: "R", usdzUrl: "https://w/a", capturedRoomJsonUrl: "https://w/b", objects: []).hasLocalOnlyRoomFiles)
    }

    @Test func blocksReentryWhileSubmitting() {
        var s = ScanSubmission()
        #expect(s.canSubmit)
        let first = s.begin()
        let second = s.begin()
        #expect(first)
        #expect(!second)
        #expect(!s.canSubmit)
        #expect(s.state == .submitting)
    }

    @Test func failedAttemptCanRetryButImportedCannot() {
        var s = ScanSubmission()
        _ = s.begin()
        s.finish(error: "timeout")
        #expect(s.state == .failed("timeout"))
        #expect(s.canSubmit)
        let retry = s.begin()
        #expect(retry)
        s.finish(error: nil)
        #expect(s.isImported)
        #expect(!s.canSubmit)
        let again = s.begin()
        #expect(!again)
        s.finish(error: "late error")  // no attempt running: ignored
        #expect(s.isImported)
    }

    @Test func keepsUploadedURLsAcrossAttempts() {
        var s = ScanSubmission()
        let file = URL(fileURLWithPath: "/scans/x/room.usdz")
        _ = s.begin()
        s.recordUpload(file, url: "https://w/u/room.usdz")
        s.finish(error: "import failed")
        #expect(s.uploaded[file] == "https://w/u/room.usdz")
        s.forgetUpload(file)
        #expect(s.uploaded[file] == nil)
    }
}
