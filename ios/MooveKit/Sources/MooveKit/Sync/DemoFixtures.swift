import Foundation

/// Demo inventory for previews and the offline demo. Its Bedroom matches the seeded Demo
/// backend room (`agents/scripts/demo-room.ts`, docs/demo.md) plus three commerce-only items.
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
        // material or condition; the guitar is flagged sentimental. Ids 11, 19 and 20 are extra,
        // offline-only items that carry the commerce story: the Aeron (the seed's opt-in
        // SEED_COMMERCE chair), a nightstand and a bean bag, set to sell as if by the user.
        // DemoSeedTests checks the seeded part against the seed list.
        s.items = [
            item(10, "Full size metal bed frame", "bed", (1.4, 0.36, 1.95), value: 7_700, .keep, reason: "Beds rarely resell (~$77); ~$59 to move: keep"),
            item(11, "Office chair", "chair", (0.7, 1.1, 0.7), material: "mesh", brand: "Herman Miller", condition: 4, value: 42_000, .sell, reason: "Resells well ($380-$460 comps); new place has a built-in desk nook.",
                 attributes: ["ChairType.swivel", "ChairArmType.existing", "ChairBackType.existing", "ChairLegType.star"],
                 colors: ItemColors(primary: 0x3A3D42, secondary: 0x1E1F21)),
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
            item(19, "Nightstand", "storage", (0.45, 0.55, 0.4), material: "pine", condition: 3, value: 3_000, .sell, reason: "The new bedroom has built-in shelves; easy to sell locally.",
                 attributes: ["StorageType.cabinet"]),
            item(20, "Bean bag", "sofa", (0.9, 0.7, 0.9), material: "fabric", condition: 3, value: 2_000, .sell, reason: "Bulky for its value."),
            item(21, "Mini fridge", "refrigerator", (0.48, 0.85, 0.5), value: 3_800, .keep, reason: "Worth ~$38, ~$12 to move: keep"),
        ]
        s.comps = [
            Comp(id: 100, itemId: 11, source: "ebay", title: "Herman Miller Aeron size B", priceCents: 45_000, url: "https://www.ebay.com/"),
            Comp(id: 101, itemId: 11, source: "craigslist", title: "Aeron chair, good condition", priceCents: 38_000, url: "https://sfbay.craigslist.org/"),
            Comp(id: 102, itemId: 11, source: "fb", title: "Herman Miller office chair", priceCents: 42_500, url: "https://www.facebook.com/marketplace/"),
        ]
        // As if the listing agent (#11) had run. All simulated: the demo never posts to eBay.
        // 198 and 199 are earlier attempts the agent replaced (200 and 203 are the current ones):
        // one the user denied, one whose post failed, so the "Not posted" group has real rows.
        s.listings = [
            Listing(id: 198, owner: owner, itemId: 11, title: "Herman Miller Aeron Chair Size B - Excellent",
                    description: "Size B Aeron, fully loaded.\n\nFirst draft, priced at the top of the comps.",
                    priceCents: 48_000, status: .rejected, updatedAt: Date.now.addingTimeInterval(-50 * 60)),
            Listing(id: 199, owner: owner, itemId: 19, title: "Pine Nightstand with Drawer",
                    description: "Solid pine nightstand with one drawer.",
                    priceCents: 3_000, status: .failed, updatedAt: Date.now.addingTimeInterval(-40 * 60)),
            Listing(id: 200, owner: owner, itemId: 11, title: "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition",
                    description: "Fully adjustable Aeron in size B with lumbar support. Mesh seat and back are intact with no tears.\n\nLight wear on the armrests. Smoke-free home.\n\nLocal pickup in SF, or I can ship.",
                    priceCents: 41_000, status: .awaitingApproval),
            Listing(id: 201, owner: owner, itemId: 17, title: "Mesh Office Chair with Arms, Black - Good Condition",
                    description: "Swivel desk chair with a breathable mesh back, armrests and adjustable height.\n\nLight wear on the seat, nothing torn. Local pickup.",
                    priceCents: 3_000, status: .posted, externalId: "395718204163"),
            Listing(id: 202, owner: owner, itemId: 20, title: "Large Fabric Bean Bag Chair, Gray - Clean, Comfortable",
                    description: "Oversized bean bag with a removable, washable cover.\n\nCover was washed last month. Pickup only, it's bulky.",
                    priceCents: 1_800, status: .sold, externalId: "395718209877"),
            Listing(id: 203, owner: owner, itemId: 19, title: "Solid Pine Nightstand, 1 Drawer - Good Condition",
                    description: "Sturdy pine nightstand with a drawer and an open shelf. A few small dings on the top.\n\nPerfect for a dorm or bedroom.",
                    priceCents: 3_000, status: .draft),
        ]
        // Approval gate (#12): the Aeron listing is over the $100 default threshold.
        // Purchase approvals point at deals, so they're seeded with the shopping rows (`addShopping`).
        let now = Date.now
        s.approvals = [
            Approval(id: 300, owner: owner, kind: .listing, refId: 200, amountCents: 41_000,
                     summary: "Sell \"Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition\" for $410",
                     requestedAt: now.addingTimeInterval(-6 * 60)),
            // The user turned down the first, pricier Aeron draft; the agent re-priced it (listing 200).
            Approval(id: 301, owner: owner, kind: .listing, refId: 198, amountCents: 48_000,
                     summary: "Sell \"Herman Miller Aeron Chair Size B - Excellent\" for $480", status: .denied,
                     requestedAt: now.addingTimeInterval(-55 * 60), updatedAt: now.addingTimeInterval(-50 * 60)),
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
            Payment(id: 500, owner: owner, agent: "pricing", purpose: "Premium comps for \"Herman Miller Aeron\"",
                    payee: realX402Payee, amountUsdMicros: 10_000, txHash: realX402TxHash, status: .settled,
                    simulated: false, refTable: "item", refId: 11, createdAt: ago(25)),
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
                       message: "Paying $0.01 for premium comps for \"Herman Miller Aeron\"", refTable: "item", refId: 11,
                       dataJson: #"{\#(rail("paying", remaining: 4_990_000)),"payee":"\#(realX402Payee)","amountUsdMicros":"10000"}"#,
                       createdAt: ago(25.1)),
            AgentEvent(id: 601, owner: owner, agent: "pricing", kind: .payment,
                       message: "Paid $0.01 USDC for premium comps for \"Herman Miller Aeron\"", refTable: "item", refId: 11,
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
    /// The listing agent's notes on the two listings that didn't post (198 denied, 199 failed),
    /// so the Listings screen can say why. Same wording as agents/src/agents/listing.ts.
    public static func listingEvents(owner: IdentityHex, now: Date = .now) -> [AgentEvent] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            AgentEvent(id: 620, owner: owner, agent: "listing", kind: .approval,
                       message: "$480 is over the $100 threshold, asking for approval", refTable: "listing", refId: 198,
                       createdAt: ago(55)),
            AgentEvent(id: 621, owner: owner, agent: "listing", kind: .approval,
                       message: "Not posting: denied", refTable: "listing", refId: 198, createdAt: ago(50)),
            AgentEvent(id: 622, owner: owner, agent: "listing", kind: .plan,
                       message: "Posting \"Pine Nightstand with Drawer\" to eBay at $30 (simulated)",
                       refTable: "listing", refId: 199, createdAt: ago(41)),
            AgentEvent(id: 623, owner: owner, agent: "listing", kind: .error,
                       message: "Posting failed: eBay needs at least one public https photo URL (simulated)",
                       refTable: "listing", refId: 199, dataJson: #"{"simulated":true}"#, createdAt: ago(40)),
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

    /// Offline demo only (`FixtureBackend.simulateIdentify`): what "vision" names an item added by
    /// photo. Samples, not read from the photo; the item and its agent event say so.
    public static let photoAddSamples: [Item] = [
        Item(id: 0, owner: "demo", roomId: 0, name: "Desk lamp", category: "lamp",
             widthM: 0, heightM: 0, depthM: 0, material: "metal", brand: "IKEA", condition: 4, estValueCents: 1_500),
        Item(id: 0, owner: "demo", roomId: 0, name: "Ceramic vase", category: "decor",
             widthM: 0, heightM: 0, depthM: 0, material: "ceramic", condition: 4, estValueCents: 1_200, fragile: true),
        Item(id: 0, owner: "demo", roomId: 0, name: "Bluetooth speaker", category: "electronics",
             widthM: 0, heightM: 0, depthM: 0, material: "plastic", brand: "JBL", condition: 3, estValueCents: 4_000),
    ]

    /// The sample for an item id (stable, so a re-run names it the same).
    public static func photoAddSample(for itemId: UInt64) -> Item {
        photoAddSamples[Int(itemId % UInt64(photoAddSamples.count))]
    }

    public static let photoAddSampleNote = "Offline demo: a sample identification, not read from your photo."

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
