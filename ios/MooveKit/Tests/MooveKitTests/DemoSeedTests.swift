import Foundation
import Testing
@testable import MooveKit

/// The Offline demo's Bedroom matches the seeded Demo backend Bedroom (#243), so judges who see
/// both (Offline demo, and Demo `moove-demo` joined with 4RZ9G8) get the same names, prices and
/// decisions. If `agents/scripts/demo-room.ts` or the docs/demo.md estimates change, update the
/// list below and `DemoFixtures.inventory` together.
@Suite struct DemoSeedTests {
    struct Seeded {
        let name: String, category: String
        let dims: (Double, Double, Double)  // width, height, depth (m)
        let estimateCents: Int64
        let disposition: Disposition
        var sentimental = false
    }

    /// Copied from `DEMO_OBJECTS` in agents/scripts/demo-room.ts, with the estimates from the
    /// docs/demo.md table and the decision agents/src/agents/sort.ts makes for each (no condition,
    /// not fragile; the guitar is flagged sentimental, so it's left to the user).
    static let seed: [Seeded] = [
        .init(name: "Full size metal bed frame", category: "bed", dims: (1.4, 0.36, 1.95), estimateCents: 7_700, disposition: .keep),
        .init(name: "IKEA Micke desk", category: "table", dims: (1.05, 0.75, 0.5), estimateCents: 6_000, disposition: .keep),
        .init(name: "Mesh office chair", category: "chair", dims: (0.64, 1.02, 0.62), estimateCents: 3_000, disposition: .sell),
        .init(name: "IKEA Kallax shelf", category: "storage", dims: (0.77, 1.47, 0.39), estimateCents: 5_000, disposition: .keep),
        .init(name: "Mini fridge", category: "refrigerator", dims: (0.48, 0.85, 0.5), estimateCents: 3_800, disposition: .keep),
        .init(name: "TCL 32 inch TV", category: "television", dims: (0.73, 0.48, 0.18), estimateCents: 5_500, disposition: .keep),
        .init(name: "Dell 27 inch monitor", category: "electronics", dims: (0.61, 0.45, 0.18), estimateCents: 10_000, disposition: .keep),
        .init(name: "Floor lamp", category: "lamp", dims: (0.3, 1.7, 0.3), estimateCents: 6_000, disposition: .keep),
        .init(name: "Yamaha acoustic guitar", category: "instrument", dims: (0.38, 1.02, 0.12), estimateCents: 10_900, disposition: .undecided, sentimental: true),
    ]

    /// Offline-only items that carry the commerce story (listings, the approval, the sold bean bag).
    /// The Aeron is the seed's opt-in SEED_COMMERCE chair.
    static let commerceOnly: Set<String> = ["Office chair", "Nightstand", "Bean bag"]

    let items = DemoFixtures.inventory(owner: "me").items

    @Test func everySeededItemIsInTheOfflineBedroom() {
        for s in Self.seed {
            let matches = items.filter { $0.name == s.name }
            #expect(matches.count == 1, "\(s.name)")
            guard let it = matches.first else { continue }
            #expect(it.category == s.category, "\(s.name) category")
            #expect(it.widthM == s.dims.0 && it.heightM == s.dims.1 && it.depthM == s.dims.2, "\(s.name) size")
            #expect(it.estValueCents == s.estimateCents, "\(s.name) estimate")
            #expect(it.disposition == s.disposition, "\(s.name) decision")
            #expect(it.maybeSentimental == s.sentimental, "\(s.name) sentimental")
            // Seeded items have no photos, so vision never adds a brand, material or condition.
            #expect(it.brand == nil && it.material == nil && it.condition == nil, "\(s.name) details")
        }
    }

    @Test func everythingElseIsTheCommerceStory() {
        let seeded = Set(Self.seed.map(\.name))
        let extra = Set(items.map(\.name)).subtracting(seeded)
        #expect(extra == Self.commerceOnly)
        #expect(items.count == Self.seed.count + Self.commerceOnly.count)
        // Each extra is set to sell and has a listing, so it's in the demo for the commerce screens.
        let s = DemoFixtures.inventory(owner: "me")
        for it in items where extra.contains(it.name) {
            #expect(it.disposition == .sell, "\(it.name)")
            #expect(s.listings.contains { $0.itemId == it.id }, "\(it.name) has no listing")
        }
    }

    @Test func seededTotalsAgreeWithTheDemoBackend() {
        // What the seeded Bedroom's summary counts on Demo: 9 items, 7 keep, 1 sell, 1 left to you.
        let seeded = items.filter { item in Self.seed.contains { $0.name == item.name } }
        let summary = MoveSummary(snapshot: { var s = SyncSnapshot(me: "me"); s.items = seeded; return s }())
        #expect(summary.itemCount == 9)
        #expect(summary.counts[.keep] == 7)
        #expect(summary.counts[.sell] == 1)
        #expect(summary.counts[.undecided] == 1)
        #expect(summary.needsYou == 1)
        #expect(seeded.compactMap(\.estValueCents).reduce(0, +) == 57_900)  // $579, the docs/demo.md column
    }

    @Test func demoScanUsesTheSeededNames() async throws {
        // "Load demo scan" names its objects from the same template.
        let backend = FixtureBackend()
        _ = try await backend.connect(token: nil)
        try await backend.importScan(DemoFixtures.scanImport())
        var it = backend.snapshots().makeAsyncIterator()
        let snap = try #require(await it.next())
        for s in Self.seed {
            #expect(snap.items.contains { $0.name == s.name && $0.category == s.category }, "\(s.name)")
        }
    }
}
