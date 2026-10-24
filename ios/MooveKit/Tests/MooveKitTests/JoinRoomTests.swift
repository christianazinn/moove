import Foundation
import Testing
@testable import MooveKit

/// Sharing a room with a second phone (#10): join codes and `joinRoom`.
@Suite struct JoinRoomTests {
    @Test func joinCodesAreStableUniqueAndWellFormed() {
        let codes = (1...2_000).map { FixtureBackend.joinCode(forRoomId: UInt64($0)) }
        #expect(Set(codes).count == codes.count)
        #expect(codes.allSatisfy { $0.count == 6 && $0 == $0.uppercased() && !$0.contains("O") && !$0.contains("I") })
        #expect(FixtureBackend.joinCode(forRoomId: 7) == FixtureBackend.joinCode(forRoomId: 7))
    }

    @Test func normalizeTrimsAndUppercases() {
        #expect(Room.normalizeJoinCode("  abc123\n") == "ABC123")
    }

    @Test func roomsGetCodesFromSeedAndImport() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(ScanImport(roomName: "Kitchen", objects: []))
        let rooms = await firstSnapshot(backend).rooms
        #expect(rooms.count == 2)
        #expect(rooms.allSatisfy { $0.joinCode == FixtureBackend.joinCode(forRoomId: $0.id) })
    }

    @Test func joiningByCodeShowsTheRoomAndLetsMembersEdit() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        #expect(await firstSnapshot(backend).rooms.allSatisfy { $0.owner == "fixture-user" })

        try await backend.joinRoom(code: "  demo42\n")
        let snap = await firstSnapshot(backend)
        let shared = try #require(snap.rooms.first { $0.joinCode == DemoFixtures.roommateJoinCode })
        #expect(shared.owner == "fixture-roommate")
        #expect(snap.scans.contains { $0.roomId == shared.id })
        #expect(snap.items.filter { $0.roomId == shared.id }.count == 3)
        #expect(snap.users.contains { $0.identity == shared.owner && $0.name == "Sam" })

        try await backend.setDisposition(itemId: 912, disposition: .donate)
        #expect(await firstSnapshot(backend).items.first { $0.id == 912 }?.disposition == .donate)
    }

    @Test func joiningTwiceOrYourOwnRoomIsANoOp() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        let before = await firstSnapshot(backend)
        try await backend.joinRoom(code: try #require(before.rooms.first?.joinCode))
        #expect(await firstSnapshot(backend) == before)

        try await backend.joinRoom(code: DemoFixtures.roommateJoinCode)
        let joined = await firstSnapshot(backend)
        try await backend.joinRoom(code: DemoFixtures.roommateJoinCode)
        #expect(await firstSnapshot(backend) == joined)
    }

    @Test func unknownCodeThrows() async throws {
        let backend = FixtureBackend.demo()
        _ = try await backend.connect(token: nil)
        await #expect(throws: FixtureBackend.Failure.noSuchRoomCode) {
            try await backend.joinRoom(code: "ZZZZZZ")
        }
    }

    @Test func joinNeedsAConnection() async {
        let backend = FixtureBackend(joinable: DemoFixtures.roommateRoom())
        await #expect(throws: FixtureBackend.Failure.notConnected) {
            try await backend.joinRoom(code: DemoFixtures.roommateJoinCode)
        }
    }

    private func firstSnapshot(_ backend: FixtureBackend) async -> SyncSnapshot {
        var it = backend.snapshots().makeAsyncIterator()
        return await it.next()!
    }
}
