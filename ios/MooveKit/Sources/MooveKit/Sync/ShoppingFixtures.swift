import Foundation

/// Offline demo for the Shopping screen (#15): what the new home still needs, the buy agent's
/// replayed deals (labeled "sample data", like the worker's fixture deal source), one purchase
/// waiting on approval, one simulated Visa checkout that already settled, and one that was declined.
///
/// Ids stay below the inventory fixture's max so `FixtureBackend` never reuses them for new rows.
extension DemoFixtures {
    /// The full offline demo: inventory plus shopping.
    public static func demo(owner: IdentityHex) -> SyncSnapshot {
        var s = inventory(owner: owner)
        addShopping(to: &s, owner: owner)
        return s
    }

    /// Appends the shopping rows (never replaces rows other fixtures seeded).
    public static func addShopping(to s: inout SyncSnapshot, owner: IdentityHex, now: Date = .now) {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        func deal(_ id: UInt64, _ itemId: UInt64, _ source: String, _ title: String, _ cents: Int64, _ url: String,
                  _ seller: String, fraud: Double? = nil, ai: Double? = nil, reasons: [String] = []) -> Deal {
            Deal(id: id, owner: owner, shoppingItemId: itemId, source: source, title: title, priceCents: cents, url: url,
                 sellerInfo: "\(seller) · sample data", fraudScore: fraud, aiTextScore: ai, fraudReasons: reasons,
                 createdAt: ago(30))
        }

        s.shoppingItems += [
            ShoppingItem(id: 50, owner: owner, name: "Mattress", category: "bed",
                         reason: "Your queen bed frame is coming with you, but no mattress was scanned.",
                         status: .bought, chosenDealId: 62, createdAt: ago(40)),
            ShoppingItem(id: 51, owner: owner, name: "Sofa", category: "sofa",
                         reason: "The new living room has no seating, and the bean bag is being sold.",
                         status: .found, chosenDealId: 71, createdAt: ago(39)),
            ShoppingItem(id: 52, owner: owner, name: "Desk chair", category: "chair",
                         reason: "You're selling the Aeron, and the new desk nook still needs a chair.",
                         status: .found, createdAt: ago(38)),
            ShoppingItem(id: 53, owner: owner, name: "Dining table", category: "table",
                         reason: "The new home has a dining area and nothing from the old place fits it.",
                         status: .found, chosenDealId: 79, createdAt: ago(37)),
            // A checkout that failed: the simulated Visa hold was declined, nothing was charged,
            // and the user can pick another deal.
            ShoppingItem(id: 54, owner: owner, name: "Area rug", category: "decor",
                         reason: "The new living room has bare wood floors.",
                         status: .found, chosenDealId: 80, createdAt: ago(36)),
        ]

        s.deals += [
            deal(60, 50, "ikea", "VESTERÖY pocket spring mattress, firm, Full", 24_900,
                 "https://www.ikea.com/us/en/search/?q=vesteroy", "IKEA · new · ships · Visa checkout · score 0.71",
                 fraud: 0.02, ai: 0.10),
            deal(61, 50, "amazon", "10 inch hybrid mattress in a box, Full", 21_999,
                 "https://www.amazon.com/s?k=hybrid+mattress+full", "Amazon · new · ships · Visa checkout · score 0.74",
                 fraud: 0.04, ai: 0.22),
            deal(62, 50, "target", "8\" memory foam mattress, Full", 17_999,
                 "https://www.target.com/s?searchTerm=memory+foam+mattress", "Target · new · ships · Visa checkout · score 0.82",
                 fraud: 0.03, ai: 0.12),

            deal(70, 51, "ikea", "KIVIK sofa, Tibbleby beige/gray", 69_900,
                 "https://www.ikea.com/us/en/search/?q=kivik%20sofa", "IKEA · new · ships · Visa checkout · score 0.52",
                 fraud: 0.02, ai: 0.08),
            deal(71, 51, "wayfair", "78\" upholstered sofa, gray", 42_999,
                 "https://www.wayfair.com/keyword.php?keyword=sofa", "Wayfair · new · ships · Visa checkout · score 0.69",
                 fraud: 0.06, ai: 0.31),
            deal(72, 51, "fb", "Gray 3-seat couch, pet free home", 15_000,
                 "https://www.facebook.com/marketplace/search/?query=couch",
                 "Marketplace seller, Albany (4.9 stars) · good · 4 mi · message seller · score 0.77",
                 fraud: 0.34, ai: 0.58, reasons: ["Listing text reads as AI-generated"]),

            deal(74, 52, "target", "Mesh task chair with arms, black", 7_999,
                 "https://www.target.com/s?searchTerm=task+chair", "Target · new · ships · Visa checkout · score 0.80",
                 fraud: 0.03, ai: 0.15),
            deal(75, 52, "ikea", "MARKUS office chair, Vissle dark gray", 22_999,
                 "https://www.ikea.com/us/en/search/?q=markus", "IKEA · new · ships · Visa checkout · score 0.61"),
            // The planted demo scam, same as the worker's (agents/fixtures/deals.json, "planted": true),
            // with the score and reasons its real fraud rules give it, so offline and live tell one story.
            // Like the worker's, its seller info has no rank score, so 0.85 is the only score shown.
            deal(76, 52, "craigslist", "Herman Miller Aeron, brand new, $95, Zelle only, ship only", 9_500,
                 "https://example.invalid/moove-demo/planted-scam-aeron",
                 "Planted demo scam (not a real listing) · new · ships · message seller",
                 fraud: 0.85,
                 reasons: ["asks for payment by Zelle", "shipping only, no meetup"]),

            deal(77, 53, "ikea", "LISABO table, ash veneer, 140x78 cm", 19_999,
                 "https://www.ikea.com/us/en/search/?q=lisabo%20table", "IKEA · new · ships · Visa checkout · score 0.66",
                 fraud: 0.02, ai: 0.09),
            deal(78, 53, "target", "Round dining table, 42\", natural wood", 14_999,
                 "https://www.target.com/s?searchTerm=round+dining+table", "Target · new · ships · Visa checkout · score 0.70",
                 fraud: 0.03, ai: 0.18),
            deal(79, 53, "craigslist", "Farmhouse dining table + 4 chairs", 12_000,
                 "https://sfbay.craigslist.org/search/fua?query=dining+table",
                 "Craigslist, El Cerrito · good · 7 mi · message seller · score 0.73",
                 fraud: 0.12, ai: 0.20),

            deal(80, 54, "target", "5x7 flatweave area rug, cream/gray", 8_999,
                 "https://www.target.com/s?searchTerm=5x7+area+rug", "Target · new · ships · Visa checkout · score 0.75",
                 fraud: 0.03, ai: 0.11),
            deal(81, 54, "ikea", "LOHALS flatwoven rug, natural, 5'3\"x7'7\"", 9_999,
                 "https://www.ikea.com/us/en/search/?q=lohals", "IKEA · new · ships · Visa checkout · score 0.71",
                 fraud: 0.02, ai: 0.07),
            deal(82, 54, "amazon", "Washable 5x7 boho area rug", 6_499,
                 "https://www.amazon.com/s?k=washable+5x7+rug", "Amazon · new · ships · Visa checkout · score 0.68",
                 fraud: 0.05, ai: 0.41),
        ]

        // The sofa is over the approval threshold, so the buy agent asked first.
        s.approvals += [
            Approval(id: 85, owner: owner, kind: .purchase, refId: 71, amountCents: 42_999,
                     summary: "Buy \"78\" upholstered sofa, gray\" from wayfair for $429.99", requestedAt: ago(4)),
        ]

        // The mattress was under the threshold and checked out through the simulated Visa rail.
        s.payments += [
            Payment(id: 90, owner: owner, agent: "buy", rail: .visa, purpose: "Mattress: 8\" memory foam mattress, Full",
                    payee: "simulated merchant", amountUsdMicros: 17_999 * 10_000, status: .settled, simulated: true,
                    refTable: "deal", refId: 62, createdAt: ago(20)),
            Payment(id: 91, owner: owner, agent: "buy", rail: .visa, purpose: "Area rug: 5x7 flatweave area rug, cream/gray",
                    payee: "simulated merchant", amountUsdMicros: 8_999 * 10_000, status: .failed, simulated: true,
                    refTable: "deal", refId: 80, createdAt: ago(15)),
        ]

        // What the buy agent said about that failure (same wording as agents/src/agents/buy.ts).
        s.agentEvents += [
            AgentEvent(id: 630, owner: owner, agent: "buy", kind: .plan,
                       message: "Checking out \"5x7 flatweave area rug, cream/gray\" for $89.99 via Visa, under the $100 approval threshold.",
                       refTable: "deal", refId: 80, createdAt: ago(15.2)),
            AgentEvent(id: 631, owner: owner, agent: "buy", kind: .result,
                       message: "Did not buy \"5x7 flatweave area rug, cream/gray\": declined (card declined by the issuer, simulated)",
                       refTable: "deal", refId: 80, dataJson: #"{"provider":"simulated","simulated":true}"#, createdAt: ago(15)),
        ]
    }
}
