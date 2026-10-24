import Foundation

/// Hand-written demo inventory for previews and the offline demo.
/// Replace with the real #3 scan (agents/fixtures/demo-room/) once it's recorded.
public enum DemoFixtures {
    public static func inventory(owner: IdentityHex) -> SyncSnapshot {
        var s = SyncSnapshot(me: owner)
        s.users = [User(identity: owner, name: "Demo Mover", email: "demo@moove.app")]
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

        s.items = [
            item(10, "Queen bed frame", "bed", (1.6, 0.4, 2.1), material: "oak", brand: "IKEA", condition: 4, value: 12_000, .keep, reason: "Needed in the new bedroom; costs more to replace than to move."),
            item(11, "Office chair", "chair", (0.7, 1.1, 0.7), material: "mesh", brand: "Herman Miller", condition: 4, value: 42_000, .sell, reason: "Resells well ($380-$460 comps); new place has a built-in desk nook.",
                 attributes: ["ChairType.swivel", "ChairArmType.existing", "ChairBackType.existing", "ChairLegType.star"],
                 colors: ItemColors(primary: 0x3A3D42, secondary: 0x1E1F21)),
            item(12, "Desk", "table", (1.4, 0.75, 0.7), material: "laminate", brand: "IKEA", condition: 3, value: 4_000, .sell, reason: "Low value but easy to sell locally.",
                 attributes: ["TableShapeType.rectangular"], colors: ItemColors(primary: 0xF2F0EB)),
            item(13, "Bookshelf", "storage", (0.8, 1.8, 0.3), material: "particleboard", brand: "IKEA", condition: 2, value: 1_500, .donate, reason: "Worth less than moving it; usable, so donate rather than trash.",
                 attributes: ["StorageType.shelf"]),
            item(14, "Floor lamp", "lamp", (0.3, 1.6, 0.3), material: "metal", condition: 4, value: 2_500, .keep, reason: "Small and light; cheap to move.", fragile: true),
            item(15, "Nightstand", "storage", (0.45, 0.55, 0.4), material: "pine", condition: 3, value: 3_000, .keep, reason: "Pairs with the bed.", attributes: ["StorageType.cabinet"]),
            item(16, "Box fan", "appliance", (0.5, 0.5, 0.2), condition: 2, value: 800, .donate, reason: "New place has central air."),
            item(17, "Broken mirror", "decor", (0.6, 0.9, 0.05), condition: 1, value: 0, .trash, reason: "Cracked; not safe to sell or donate.", fragile: true),
            item(18, "Grandma's quilt rack", "decor", (0.9, 0.9, 0.3), material: "walnut", condition: 3, value: 6_000, .undecided, reason: "Handmade and old; left for you to decide.", sentimental: true),
            item(19, "Framed photos", "decor", (0.4, 0.5, 0.05), condition: 4, .undecided, reason: "Personal photos; left for you to decide.", fragile: true, sentimental: true),
            item(20, "Bean bag", "sofa", (0.9, 0.7, 0.9), material: "fabric", condition: 3, value: 2_000, .sell, reason: "Bulky for its value."),
            item(21, "Mini fridge", "appliance", (0.5, 0.85, 0.5), brand: "Frigidaire", condition: 4, value: 7_500, .sell, reason: "New kitchen has a full fridge."),
        ]
        s.comps = [
            Comp(id: 100, itemId: 11, source: "ebay", title: "Herman Miller Aeron size B", priceCents: 45_000, url: "https://www.ebay.com/"),
            Comp(id: 101, itemId: 11, source: "craigslist", title: "Aeron chair, good condition", priceCents: 38_000, url: "https://sfbay.craigslist.org/"),
            Comp(id: 102, itemId: 11, source: "fb", title: "Herman Miller office chair", priceCents: 42_500, url: "https://www.facebook.com/marketplace/"),
        ]
        // As if the listing agent (#11) had run. All simulated: the demo never posts to eBay.
        s.listings = [
            Listing(id: 200, owner: owner, itemId: 11, title: "Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition",
                    description: "Fully adjustable Aeron in size B with lumbar support. Mesh seat and back are intact with no tears.\n\nLight wear on the armrests. Smoke-free home.\n\nLocal pickup in SF, or I can ship.",
                    priceCents: 41_000, status: .awaitingApproval),
            Listing(id: 201, owner: owner, itemId: 12, title: "IKEA Laminate Desk, 140 x 70 cm, White - Good Condition",
                    description: "Simple, sturdy desk with plenty of room for a monitor and laptop.\n\nSome surface scratches, nothing structural. Disassembles for transport.",
                    priceCents: 3_500, status: .posted, externalId: "395718204163"),
            Listing(id: 202, owner: owner, itemId: 20, title: "Large Fabric Bean Bag Chair, Gray - Clean, Comfortable",
                    description: "Oversized bean bag with a removable, washable cover.\n\nCover was washed last month. Pickup only, it's bulky.",
                    priceCents: 1_800, status: .sold, externalId: "395718209877"),
            Listing(id: 203, owner: owner, itemId: 21, title: "Frigidaire Compact Mini Fridge 3.2 cu ft, Black - Works Great",
                    description: "Quiet compact fridge with a small freezer section. Clean inside, adjustable thermostat.\n\nPerfect for a dorm or office.",
                    priceCents: 7_000, status: .draft),
        ]
        // Approval gate (#12): the Aeron listing is over the $100 default threshold.
        // Purchase approvals point at deals (#15) that the demo doesn't seed.
        let now = Date.now
        s.approvals = [
            Approval(id: 300, owner: owner, kind: .listing, refId: 200, amountCents: 41_000,
                     summary: "Sell \"Herman Miller Aeron Office Chair, Size B, Graphite - Great Condition\" for $410",
                     requestedAt: now.addingTimeInterval(-6 * 60)),
            Approval(id: 301, owner: owner, kind: .purchase, refId: 310, amountCents: 24_000,
                     summary: "Buy a queen mattress (Casper, like new) from Craigslist for $240",
                     requestedAt: now.addingTimeInterval(-2 * 60)),
            Approval(id: 302, owner: owner, kind: .purchase, refId: 311, amountCents: 18_900,
                     summary: "Buy a 3-seat sofa from FB Marketplace for $189", status: .denied,
                     requestedAt: now.addingTimeInterval(-3 * 3600), updatedAt: now.addingTimeInterval(-170 * 60)),
            Approval(id: 303, owner: owner, kind: .purchase, refId: 312, amountCents: 12_500,
                     summary: "Buy a dresser from Craigslist for $125", status: .approved,
                     requestedAt: now.addingTimeInterval(-26 * 3600), updatedAt: now.addingTimeInterval(-25 * 3600)),
        ]
        s.payments = payments(owner: owner)
        s.agentEvents = paymentEvents(owner: owner)
        return s
    }

    /// The one real Base Sepolia x402 payment verified end to end in #7 ($0.01 USDC).
    public static let realX402TxHash = "0xc7942646380456c56dde204434aeb6115338b521b6e91a0901ec05dde1fe136c"
    public static let realX402Payee = "0x6644b110fd0b1671599e36db749d09b1eaeef952"

    /// As if the pricing and shopping agents had paid for data over x402 (#7):
    /// one real settled testnet payment, simulated ones (labeled), and a failure.
    public static func payments(owner: IdentityHex, now: Date = .now) -> [Payment] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return [
            Payment(id: 500, owner: owner, agent: "pricing", purpose: "Premium comps for \"Herman Miller Aeron\"",
                    payee: realX402Payee, amountUsdMicros: 10_000, txHash: realX402TxHash, status: .settled,
                    simulated: false, refTable: "item", refId: 11, createdAt: ago(25)),
            Payment(id: 501, owner: owner, agent: "pricing", purpose: "Premium comps for \"IKEA laminate desk\"",
                    payee: "simulated", amountUsdMicros: 10_000, status: .settled, simulated: true,
                    refTable: "item", refId: 12, createdAt: ago(18)),
            Payment(id: 502, owner: owner, agent: "pricing", purpose: "Price history for \"Frigidaire mini fridge\"",
                    payee: "simulated", amountUsdMicros: 5_000, status: .settled, simulated: true,
                    refTable: "item", refId: 21, createdAt: ago(12)),
            Payment(id: 503, owner: owner, agent: "shopping", purpose: "Seller report for a used dresser",
                    payee: realX402Payee, amountUsdMicros: 20_000, status: .failed, simulated: false,
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
                       message: "[SIMULATED] Paid $0.01 USDC for premium comps for \"IKEA laminate desk\"", refTable: "item", refId: 12,
                       dataJson: #"{\#(rail("settled", remaining: 4_980_000, simulated: true)),"payee":"simulated","amountUsdMicros":"10000"}"#,
                       createdAt: ago(18)),
            AgentEvent(id: 606, owner: owner, agent: "pricing", kind: .payment,
                       message: "[SIMULATED] Paid $0.005 USDC for price history for \"Frigidaire mini fridge\"", refTable: "item", refId: 21,
                       dataJson: #"{\#(rail("settled", remaining: 4_975_000, simulated: true)),"payee":"simulated","amountUsdMicros":"5000"}"#,
                       createdAt: ago(12)),
            // Failed after the 402 round-trip: comes with failed payment 503, so the log shows it once.
            AgentEvent(id: 603, owner: owner, agent: "shopping", kind: .error,
                       message: "x402 payment for seller report for a used dresser failed (HTTP 402, insufficient_funds)",
                       dataJson: #"{\#(rail("failed", remaining: 5_000_000)),"payee":"\#(realX402Payee)","amountUsdMicros":"20000","url":"https://moove.example/x402/seller-report"}"#,
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
}
