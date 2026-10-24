import Foundation

/// Demo inventory for previews and the offline demo. Its Bedroom matches the seeded Demo
/// backend room (`agents/scripts/demo-room.ts`, docs/demo.md), item for item.
public enum DemoFixtures {
    public static func inventory(owner: IdentityHex) -> SyncSnapshot {
        var s = SyncSnapshot(me: owner)
        // $100 approval threshold, the module default (docs/data-model.md); the docs and screens quote it.
        s.users = [User(identity: owner, name: "Demo Mover", email: "demo@moove.app", approvalThresholdCents: 10_000)]
        s.rooms = [Room(id: 1, owner: owner, name: "Bedroom")]
        s.scans = [Scan(id: 2, owner: owner, roomId: 1)]

        func item(_ id: UInt64, _ name: String, _ category: String, _ dims: (Double, Double, Double),
                  material: String? = nil, brand: String? = nil, condition: Int? = nil, value: Int64? = nil,
                  _ disposition: Disposition, reason: String? = nil, fragile: Bool = false, sentimental: Bool = false,
                  attributes: [String] = [], colors: ItemColors? = nil) -> Item {
            Item(id: id, owner: owner, roomId: 1, scanObjectId: "demo-\(id)", name: name, category: category,
                 widthM: dims.0, heightM: dims.1, depthM: dims.2, material: material, brand: brand, condition: condition,
                 estValueCents: value, disposition: disposition, dispositionReason: reason,
                 fragile: fragile, maybeSentimental: sentimental, attributes: attributes, colors: colors)
        }

        // The 9 seeded Bedroom items (agents/scripts/demo-room.ts, the Demo backend's join code
        // 4RZ9G8), with the live estimates from docs/demo.md and the sort agent's decisions and
        // reasons for them (agents/src/agents/sort.ts). Seeded items have no photos, so no brand,
        // material or condition; the guitar is flagged sentimental. Nothing is added or set to sell
        // by hand: the listings below are only for what the sort agent sells (today just the mesh
        // chair). DemoSeedTests checks this list against the seed.
        s.items = [
            item(10, "Full size metal bed frame", "bed", (1.4, 0.36, 1.95), value: 7_700, .keep, reason: "Beds rarely resell (~$77); ~$59 to move: keep"),
            item(12, "IKEA Micke desk", "table", (1.05, 0.75, 0.5), value: 6_000, .keep, reason: "Worth ~$60, ~$24 to move: keep",
                 attributes: ["TableShapeType.rectangular"]),
            item(13, "IKEA Kallax shelf", "storage", (0.77, 1.47, 0.39), value: 5_000, .keep, reason: "Worth ~$50, ~$26 to move: keep",
                 attributes: ["StorageType.shelf"]),
            item(14, "Floor lamp", "lamp", (0.3, 1.7, 0.3), value: 6_000, .keep, reason: "Worth ~$60, ~$9 to move: keep"),
            item(15, "TCL 32 inch TV", "television", (0.73, 0.48, 0.18), value: 5_500, .keep, reason: "Worth ~$55, ~$4 to move: keep"),
            item(16, "Dell 27 inch monitor", "electronics", (0.61, 0.45, 0.18), value: 10_000, .keep, reason: "Worth ~$100, ~$3 to move: keep"),
            item(17, "Mesh office chair", "chair", (0.64, 1.02, 0.62), value: 3_000, .sell, reason: "Worth ~$30, ~$24 to move: barely worth moving, sell",
                 attributes: ["ChairType.swivel", "ChairArmType.existing", "ChairBackType.existing", "ChairLegType.star"]),
            item(18, "Yamaha acoustic guitar", "instrument", (0.38, 1.02, 0.12), value: 10_900, .undecided, reason: "possibly sentimental - your call", sentimental: true),
            item(21, "Mini fridge", "refrigerator", (0.48, 0.85, 0.5), value: 3_800, .keep, reason: "Worth ~$38, ~$12 to move: keep"),
        ]
        // Three of the mesh chair's real cached comps (agents/fixtures/comps/mesh-office-chair.json).
        s.comps = [
            Comp(id: 100, itemId: 17, source: "fb", title: "Mesh Ergonomic Office Chair", priceCents: 3_000,
                 url: "https://www.facebook.com/marketplace/item/2615122692300842"),
            Comp(id: 101, itemId: 17, source: "fb", title: "Mesh Back Ergonomic Office Chair", priceCents: 4_000,
                 url: "https://www.facebook.com/marketplace/item/1614255130478432"),
            Comp(id: 102, itemId: 17, source: "ebay", title: "Gray Mesh High-Back Office/Desk Chair, Headrest, Armrests, White Frame",
                 priceCents: 1_900, url: "https://www.ebay.com/itm/800628282566"),
        ]
        // As if the listing agent (#11) had run on the one item the sort agent sells. Simulated: the
        // demo never posts to eBay. At $30 it's under the $100 approval threshold, so it posted
        // without asking and there are no listing approvals. Purchase approvals point at deals, so
        // they're seeded with the shopping rows (`addShopping`).
        s.listings = [
            Listing(id: 201, owner: owner, itemId: 17, title: "Mesh Office Chair with Arms, Black - Good Condition",
                    description: "Swivel desk chair with a breathable mesh back, armrests and adjustable height.\n\nLight wear on the seat, nothing torn. Local pickup.",
                    priceCents: 3_000, status: .posted, externalId: "395718204163", updatedAt: Date.now.addingTimeInterval(-40 * 60)),
        ]
        s.payments = payments(owner: owner)
        s.agentEvents = paymentEvents(owner: owner) + listingEvents(owner: owner)
        return s
    }

    /// The one real Base Sepolia x402 payment verified end to end in #7 ($0.01 USDC).
    public static let realX402TxHash = "0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c"
    public static let realX402Payee = "0x6644b110fd0b1671599e36db749d09b1eaeef952"

    /// As if the pricing and shopping agents had paid for data over x402 (#7):
    /// one real settled testnet payment, simulated ones (labeled), and a simulated failure.
    /// Row 500 is the only non-simulated payment in the whole offline demo.
    public static func payments(owner: IdentityHex, now: Date = .now) -> [Payment] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            Payment(id: 500, owner: owner, agent: "pricing", purpose: "Premium comps for \"Mesh office chair\"",
                    payee: realX402Payee, amountUsdMicros: 10_000, txHash: realX402TxHash, status: .settled,
                    simulated: false, refTable: "item", refId: 17, createdAt: ago(25)),
            Payment(id: 501, owner: owner, agent: "pricing", purpose: "Premium comps for \"IKEA Micke desk\"",
                    payee: "simulated", amountUsdMicros: 10_000, status: .settled, simulated: true,
                    refTable: "item", refId: 12, createdAt: ago(18)),
            Payment(id: 502, owner: owner, agent: "pricing", purpose: "Price history for \"Mini fridge\"",
                    payee: "simulated", amountUsdMicros: 5_000, status: .settled, simulated: true,
                    refTable: "item", refId: 21, createdAt: ago(12)),
            Payment(id: 503, owner: owner, agent: "shopping", purpose: "Seller report for a used dresser",
                    payee: "simulated", amountUsdMicros: 20_000, status: .failed, simulated: true,
                    createdAt: ago(6)),
        ]
    }

    /// The agent steps behind those payments, including a spend-cap refusal.
    public static func paymentEvents(owner: IdentityHex, now: Date = .now) -> [AgentEvent] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let explorer = BaseSepolia.explorerTxPrefix + realX402TxHash
        // Every x402 event carries the rail fields from #45: rail, outcome, simulated, and the
        // worker ledger's remaining budget and cap after that step.
        func rail(_ outcome: String, remaining: Int64, simulated: Bool = false) -> String {
            #""rail":"x402","outcome":"\#(outcome)","simulated":\#(simulated),"remainingUsdMicros":"\#(remaining)","capUsdMicros":"5000000""#
        }
        return [
            AgentEvent(id: 600, owner: owner, agent: "pricing", kind: .toolCall,
                       message: "Paying $0.01 for premium comps for \"Mesh office chair\"", refTable: "item", refId: 17,
                       dataJson: #"{\#(rail("paying", remaining: 4_990_000)),"payee":"\#(realX402Payee)","amountUsdMicros":"10000"}"#,
                       createdAt: ago(25.1)),
            AgentEvent(id: 601, owner: owner, agent: "pricing", kind: .payment,
                       message: "Paid $0.01 USDC for premium comps for \"Mesh office chair\"", refTable: "item", refId: 17,
                       dataJson: #"{\#(rail("settled", remaining: 4_990_000)),"payee":"\#(realX402Payee)","amountUsdMicros":"10000","txHash":"\#(realX402TxHash)","network":"base-sepolia","explorer":"\#(explorer)"}"#,
                       createdAt: ago(25)),
            AgentEvent(id: 602, owner: owner, agent: "pricing", kind: .payment,
                       message: "[SIMULATED] Paid $0.01 USDC for premium comps for \"IKEA Micke desk\"", refTable: "item", refId: 12,
                       dataJson: #"{\#(rail("settled", remaining: 4_980_000, simulated: true)),"payee":"simulated","amountUsdMicros":"10000"}"#,
                       createdAt: ago(18)),
            AgentEvent(id: 606, owner: owner, agent: "pricing", kind: .payment,
                       message: "[SIMULATED] Paid $0.005 USDC for price history for \"Mini fridge\"", refTable: "item", refId: 21,
                       dataJson: #"{\#(rail("settled", remaining: 4_975_000, simulated: true)),"payee":"simulated","amountUsdMicros":"5000"}"#,
                       createdAt: ago(12)),
            // Failed after the 402 round-trip: comes with failed payment 503, so the log shows it once.
            AgentEvent(id: 603, owner: owner, agent: "shopping", kind: .error,
                       message: "x402 payment for seller report for a used dresser failed (HTTP 402, insufficient_funds)",
                       dataJson: #"{\#(rail("failed", remaining: 5_000_000, simulated: true)),"payee":"simulated","amountUsdMicros":"20000","url":"https://moove.example/x402/seller-report"}"#,
                       createdAt: ago(6)),
            AgentEvent(id: 604, owner: owner, agent: "shopping", kind: .error,
                       message: "Refused x402 payment for a premium deal scan: $0.25 is over the per-call max of $0.10",
                       dataJson: #"{\#(rail("refused", remaining: 5_000_000)),"payee":"\#(realX402Payee)","amountUsdMicros":"250000"}"#,
                       createdAt: ago(3)),
            // Failed before any payment row was written, so it shows as a failed attempt.
            AgentEvent(id: 605, owner: owner, agent: "pricing", kind: .error,
                       message: "No USDC payment option on Base Sepolia for https://comps.example/x402/report",
                       dataJson: #"{\#(rail("failed", remaining: 4_975_000)),"url":"https://comps.example/x402/report"}"#,
                       createdAt: ago(9)),
        ]
    }
}

extension DemoFixtures {
    /// The listing agent's steps for the mesh chair's listing (201): under the threshold, so it
    /// posted without an approval. Same wording as agents/src/agents/listing.ts.
    public static func listingEvents(owner: IdentityHex, now: Date = .now) -> [AgentEvent] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            AgentEvent(id: 622, owner: owner, agent: "listing", kind: .plan,
                       message: "Posting \"Mesh Office Chair with Arms, Black - Good Condition\" to eBay at $30 (simulated)",
                       refTable: "listing", refId: 201, createdAt: ago(41)),
            AgentEvent(id: 623, owner: owner, agent: "listing", kind: .result,
                       message: "Live as item #395718204163 (simulated)",
                       refTable: "listing", refId: 201, dataJson: #"{"simulated":true}"#, createdAt: ago(40)),
        ]
    }
}

extension DemoFixtures {
    /// The demo bedroom as a scan import, for the "Load demo scan" fallback.
    /// It goes through the same `importScan` reducer as a real scan.
    public static func scanImport() -> ScanImport {
        let items = inventory(owner: "demo").items
        return ScanImport(
            roomName: "Demo bedroom",
            objects: items.map {
                ScanObject(scanObjectId: $0.scanObjectId ?? "demo-\($0.id)", category: $0.category,
                           widthM: $0.widthM, heightM: $0.heightM, depthM: $0.depthM, photoUrl: $0.photoUrls.first,
                           attributes: $0.attributes)
            }
        )
    }

    /// What the offline photo sweep "finds" in the demo bedroom (#181): an item RoomPlan
    /// has no category for, with an estimated size, priced and sorted as if the agents ran.
    /// (Not the guitar: that's one of the seeded Bedroom's scan objects now, #243.)
    public static let sweepFind = Item(
        id: 0, owner: "demo", roomId: 0, name: "Potted monstera", category: "plant",
        widthM: 0.5, heightM: 1.1, depthM: 0.5, material: "ceramic", condition: 4,
        estValueCents: 2_500, disposition: .keep, dispositionReason: "Found in the room photos; easy to carry, worth keeping.",
        fragile: true
    )

    /// Code for the roommate's room in the offline demo (#10): enter it in "Join a room".
    public static let roommateJoinCode = "DEMO42"

    /// A roommate's room the demo user can join by code, as if a second phone had scanned it.
    public static func roommateRoom(owner: IdentityHex = "fixture-roommate") -> SyncSnapshot {
        var s = SyncSnapshot()
        s.users = [User(identity: owner, name: "Sam")]
        s.rooms = [Room(id: 900, owner: owner, name: "Living room", joinCode: roommateJoinCode)]
        s.scans = [Scan(id: 901, owner: owner, roomId: 900)]
        s.items = [
            Item(id: 910, owner: owner, roomId: 900, scanObjectId: "demo-910", name: "Sofa", category: "sofa",
                 widthM: 2.1, heightM: 0.85, depthM: 0.9, material: "fabric", condition: 3, estValueCents: 25_000,
                 disposition: .keep, dispositionReason: "Fits the new living room."),
            Item(id: 911, owner: owner, roomId: 900, scanObjectId: "demo-911", name: "TV stand", category: "storage",
                 widthM: 1.5, heightM: 0.5, depthM: 0.4, material: "laminate", condition: 3, estValueCents: 3_500,
                 disposition: .sell, dispositionReason: "New place has a wall mount."),
            Item(id: 912, owner: owner, roomId: 900, scanObjectId: "demo-912", name: "Rug", category: "decor",
                 widthM: 2.0, heightM: 0.02, depthM: 1.4, condition: 2, estValueCents: 2_000, disposition: .undecided),
        ]
        return s
    }
}
