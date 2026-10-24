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
                  _ disposition: Disposition, reason: String? = nil, fragile: Bool = false, sentimental: Bool = false) -> Item {
            Item(id: id, owner: owner, roomId: 1, scanObjectId: "demo-\(id)", name: name, category: category,
                 widthM: dims.0, heightM: dims.1, depthM: dims.2, material: material, brand: brand, condition: condition,
                 estValueCents: value, disposition: disposition, dispositionReason: reason,
                 fragile: fragile, maybeSentimental: sentimental)
        }

        s.items = [
            item(10, "Queen bed frame", "bed", (1.6, 0.4, 2.1), material: "oak", brand: "IKEA", condition: 4, value: 12_000, .keep, reason: "Needed in the new bedroom; costs more to replace than to move."),
            item(11, "Office chair", "chair", (0.7, 1.1, 0.7), material: "mesh", brand: "Herman Miller", condition: 4, value: 42_000, .sell, reason: "Resells well ($380-$460 comps); new place has a built-in desk nook."),
            item(12, "Desk", "table", (1.4, 0.75, 0.7), material: "laminate", brand: "IKEA", condition: 3, value: 4_000, .sell, reason: "Low value but easy to sell locally."),
            item(13, "Bookshelf", "storage", (0.8, 1.8, 0.3), material: "particleboard", brand: "IKEA", condition: 2, value: 1_500, .donate, reason: "Worth less than moving it; usable, so donate rather than trash."),
            item(14, "Floor lamp", "lamp", (0.3, 1.6, 0.3), material: "metal", condition: 4, value: 2_500, .keep, reason: "Small and light; cheap to move.", fragile: true),
            item(15, "Nightstand", "storage", (0.45, 0.55, 0.4), material: "pine", condition: 3, value: 3_000, .keep, reason: "Pairs with the bed."),
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
        return s
    }
}
