import Foundation

// "Import from a listing" (#89), the pure-Swift part:
// - `ListingLink.parse` reads the site, street address and listing id out of a
//   pasted listing link by string parsing only. Nothing is fetched (terms-safe).
// - `EstimatedFloorPlan.build` makes a plausible plan from beds/baths/sqft when
//   no floor plan was found. Ported from MoveWise `backend/homes.py`.

// MARK: - Listing links

public struct ListingLink: Sendable, Hashable {
    /// zillow | redfin | realtor | apartments | streeteasy | other
    public var site: String
    /// Street address read from the link, nil when the link only carries an id.
    public var address: String?
    public var listingId: String?
    /// The link, with tracking query/fragment dropped for known sites.
    public var url: String

    public init(site: String, address: String? = nil, listingId: String? = nil, url: String) {
        self.site = site
        self.address = address
        self.listingId = listingId
        self.url = url
    }

    public static let knownSites = ["zillow", "redfin", "realtor", "apartments", "streeteasy"]

    /// Parses pasted text (a bare link, a link without a scheme, or a link inside
    /// other text). Returns nil when the text doesn't contain a link at all.
    public static func parse(_ text: String) -> ListingLink? {
        guard let raw = findURL(in: text),
              let comps = URLComponents(string: raw) ?? URLComponents(string: raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw),
              let rawHost = comps.host, !rawHost.isEmpty
        else { return nil }
        let host = rawHost.lowercased()
        let parts = comps.percentEncodedPath.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }

        var link: ListingLink
        if host.contains("zillow.") {
            link = zillow(parts)
        } else if host.contains("redfin.") {
            link = redfin(parts)
        } else if host.contains("realtor.") {
            link = realtor(parts)
        } else if host.contains("apartments.com") {
            link = apartments(parts)
        } else if host.contains("streeteasy.") {
            link = streeteasy(parts)
        } else {
            return ListingLink(site: "other", url: raw)
        }
        var clean = comps
        clean.query = nil
        clean.fragment = nil
        clean.scheme = "https"
        link.url = clean.string ?? raw
        if link.address?.isEmpty == true { link.address = nil }
        return link
    }

    // MARK: Finding the link in pasted text

    private static func findURL(in text: String) -> String? {
        let trim = CharacterSet(charactersIn: "<>()[]{}\"'`,;.!?")
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map {
            String($0).trimmingCharacters(in: trim)
        }
        let pick = tokens.first { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
            ?? tokens.first(where: looksLikeHost)
        guard var url = pick, !url.isEmpty else { return nil }
        if url.range(of: "://") == nil { url = "https://" + url }
        return url
    }

    private static func looksLikeHost(_ token: String) -> Bool {
        let host = token.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let tld = labels.last, tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        return host.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
    }

    // MARK: Sites

    private static func zillow(_ parts: [String]) -> ListingLink {
        var out = ListingLink(site: "zillow", url: "")
        out.listingId = parts.first { $0.hasSuffix("_zpid") }.map { String($0.dropLast(5)) }
        if let i = parts.firstIndex(of: "homedetails"), i + 1 < parts.count {
            let slug = parts[i + 1]
            if !slug.hasSuffix("_zpid") { out.address = Slug.addressFromDashed(slug) }
        } else if parts.first == "b", parts.count > 1 {
            // /b/<building-name-city-st>/<id>/
            out.address = Slug.nameCityState(parts[1]).address
            if parts.count > 2 { out.listingId = parts[2] }
        } else if parts.first == "apartments", parts.count > 2 {
            // /apartments/<city-st>/<building>/<id>/
            var cityTok = Slug.tokens(parts[1])
            let st = cityTok.last.flatMap { Slug.isState($0) ? $0.uppercased() : nil }
            if st != nil { cityTok.removeLast() }
            let building = Slug.title(Slug.tokens(parts[2]))
            out.address = [building, Slug.title(cityTok), st ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
            if parts.count > 3 { out.listingId = parts[3] }
        }
        return out
    }

    private static func redfin(_ parts: [String]) -> ListingLink {
        var out = ListingLink(site: "redfin", url: "")
        if let i = parts.firstIndex(of: "home"), i + 1 < parts.count { out.listingId = parts[i + 1] }
        // /<ST>/<City>/<street-zip>[/unit-<u>]/home/<id>
        guard parts.count >= 3, Slug.isState(parts[0]) else { return out }
        let st = parts[0].uppercased()
        let city = Slug.title(Slug.tokens(parts[1]))
        guard !["home", "apartment"].contains(parts[2].lowercased()) else { return out }
        var tok = Slug.tokens(parts[2])
        let zip = tok.last.flatMap { Slug.isZip($0) ? $0 : nil }
        if zip != nil { tok.removeLast() }
        var unit: String?
        if parts.count > 3, parts[3].lowercased().hasPrefix("unit-") { unit = String(parts[3].dropFirst(5)) }
        guard !tok.isEmpty else { return out }
        out.address = Slug.formatAddress(tok + (unit.map { ["unit", $0] } ?? []), city: city, state: st, zip: zip)
        return out
    }

    private static func realtor(_ parts: [String]) -> ListingLink {
        var out = ListingLink(site: "realtor", url: "")
        guard let i = parts.firstIndex(where: { $0.hasPrefix("realestateandhomes-detail") || $0.hasPrefix("rentals") }),
              i + 1 < parts.count
        else { return out }
        var segs = parts[i + 1].split(separator: "_").map(String.init)
        if let id = segs.last(where: Slug.isRealtorId) { out.listingId = id }
        segs.removeAll(where: Slug.isRealtorId)
        if segs.count >= 4 {
            out.address = Slug.formatAddress(Slug.tokens(segs[0]), city: Slug.title(Slug.tokens(segs[1])),
                                             state: segs[2], zip: Slug.isZip(segs[3]) ? segs[3] : nil)
        } else if segs.count == 3 {
            out.address = Slug.formatAddress(Slug.tokens(segs[0]), city: Slug.title(Slug.tokens(segs[1])), state: segs[2], zip: nil)
        }
        return out
    }

    private static func apartments(_ parts: [String]) -> ListingLink {
        var out = ListingLink(site: "apartments", url: "")
        guard let slug = parts.first else { return out }
        if parts.count > 1 { out.listingId = parts[1] }
        if let first = Slug.tokens(slug).first, Slug.isHouseNumber(first) {
            out.address = Slug.addressFromDashed(slug)
        } else {
            out.address = Slug.nameCityState(slug).address
        }
        return out
    }

    private static func streeteasy(_ parts: [String]) -> ListingLink {
        var out = ListingLink(site: "streeteasy", url: "")
        if parts.count >= 2, parts[0] == "building" {
            var slug = parts[1].lowercased()
            let unit = parts.count > 2 ? parts[2].uppercased() : nil
            var borough = "New York"
            for (key, name) in Slug.boroughs where slug.hasSuffix("-" + key) {
                borough = name
                slug = String(slug.dropLast(key.count + 1))
                break
            }
            let tok = Slug.tokens(slug)
            if let first = tok.first, first.allSatisfy({ $0.isASCII && $0.isNumber }) {
                out.address = Slug.formatAddress(tok + (unit.map { ["#" + $0] } ?? []), city: borough, state: "NY", zip: nil)
            } else if !tok.isEmpty {
                out.address = "\(Slug.title(tok))\(unit.map { " #" + $0 } ?? ""), \(borough), NY"
            }
        } else if parts.count >= 2, ["rental", "sale"].contains(parts[0]) {
            out.listingId = parts[1]
        }
        return out
    }
}

// MARK: - Slug helpers (MoveWise `_slug_tokens`, `_cap`, `_title`, `_split_street_city`, ...)

enum Slug {
    static let states: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "DC", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY",
        "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND", "OH",
        "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "PR",
    ]
    static let streetSuffixes: Set<String> = [
        "st", "street", "ave", "av", "avenue", "rd", "road", "blvd", "boulevard", "dr", "drive", "ln", "lane", "ct", "court",
        "pl", "place", "way", "ter", "terrace", "pkwy", "parkway", "hwy", "highway", "cir", "circle", "sq", "square",
        "trl", "trail", "loop", "row", "aly", "alley", "plz", "plaza", "pt", "point", "xing", "crossing", "walk", "path",
        "pike", "run", "bnd", "bend", "cv", "cove", "hts", "heights", "ests", "mall", "park", "broadway", "bowery",
    ]
    static let unitWords: Set<String> = ["apt", "unit", "ste", "suite", "#", "fl", "floor", "ph", "rm", "bldg", "lot"]
    static let directions: Set<String> = ["n", "s", "e", "w", "ne", "nw", "se", "sw"]
    /// First words of common multi-word city names, for when the street/city split is ambiguous.
    static let cityPrefixes: Set<String> = [
        "san", "los", "las", "new", "st", "saint", "fort", "ft", "salt", "santa", "el", "palo", "long",
        "north", "south", "east", "west", "jersey", "kansas", "oklahoma", "virginia", "grand", "baton",
        "corpus", "colorado", "little", "white", "mount", "mt", "cape", "port", "del", "la",
    ]
    /// Longest keys first so "the_bronx" wins over "bronx".
    static let boroughs: [(String, String)] = [
        ("staten_island", "Staten Island"), ("the_bronx", "Bronx"), ("manhattan", "New York"), ("new_york", "New York"),
        ("brooklyn", "Brooklyn"), ("queens", "Queens"), ("bronx", "Bronx"),
    ]

    static func tokens(_ slug: String) -> [String] {
        let s = slug.removingPercentEncoding ?? slug
        return s.split(whereSeparator: { $0 == "-" || $0 == "+" || $0.isWhitespace }).map(String.init)
    }

    static func isDigits(_ s: Substring) -> Bool { !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber } }
    static func isZip(_ s: String) -> Bool { s.count == 5 && isDigits(Substring(s)) }
    static func isState(_ s: String) -> Bool { s.count == 2 && states.contains(s.uppercased()) }
    /// "123", "12a": a leading house number.
    static func isHouseNumber(_ s: String) -> Bool {
        let digits = s.prefix { $0.isASCII && $0.isNumber }
        let rest = s.dropFirst(digits.count)
        return !digits.isEmpty && rest.count <= 1 && rest.allSatisfy { $0.isASCII && $0.isLetter }
    }
    /// Realtor.com property ids look like "M12345-67890".
    static func isRealtorId(_ s: String) -> Bool {
        s.hasPrefix("M") && s.count > 1 && s.dropFirst().allSatisfy { ($0.isASCII && $0.isNumber) || $0 == "-" }
    }

    static func cap(_ word: String) -> String {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard let first = w.first else { return w }
        if first == "#" { return w.uppercased() }
        let lw = w.lowercased()
        if directions.contains(lw) { return w.uppercased() }
        let digits = lw.prefix { $0.isASCII && $0.isNumber }
        let rest = lw.dropFirst(digits.count)
        if !digits.isEmpty, rest.count <= 2, rest.allSatisfy({ $0.isASCII && $0.isLetter }) {
            return rest.count == 1 ? lw.uppercased() : lw // 4B, but 50th / 12
        }
        if lw.hasPrefix("mc"), lw.count > 2 { return "Mc" + capFirst(String(lw.dropFirst(2))) }
        return capFirst(lw)
    }

    private static func capFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst()
    }

    static func title(_ words: [String]) -> String {
        words.filter { !$0.isEmpty }.map(cap).joined(separator: " ")
    }

    /// ["123","main","st","apt","4b","seattle"] -> (street tokens, city tokens).
    static func splitStreetCity(_ tokens: [String]) -> (street: [String], city: [String]) {
        var last = -1
        var i = 0
        while i < tokens.count {
            let t = tokens[i].lowercased()
            if streetSuffixes.contains(t), i > 0 {
                last = i
                // a trailing direction ("Main St NW") belongs to the street
                if i + 2 < tokens.count, directions.contains(tokens[i + 1].lowercased()) { last = i + 1 }
            } else if unitWords.contains(t), i > 0, i + 1 < tokens.count {
                last = i + 1
                i += 1
            }
            i += 1
        }
        if last >= 0, last < tokens.count - 1 {
            return (Array(tokens[...last]), Array(tokens[(last + 1)...]))
        }
        // No suffix found: guess the city is the last 1 (or 2 with a known prefix) tokens.
        if tokens.count >= 3, cityPrefixes.contains(tokens[tokens.count - 2].lowercased()) {
            return (Array(tokens.dropLast(2)), Array(tokens.suffix(2)))
        }
        if tokens.count >= 2 { return (Array(tokens.dropLast()), Array(tokens.suffix(1))) }
        return (tokens, [])
    }

    static func formatAddress(_ street: [String], city: String, state: String?, zip: String?) -> String {
        let s = title(street).replacingOccurrences(of: " # ", with: " #")
        let tail = [(state ?? "").uppercased(), zip ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return [s, city, tail].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// "123-Main-St-APT-4B-Seattle-WA-98101" -> "123 Main St Apt 4B, Seattle, WA 98101".
    static func addressFromDashed(_ slug: String) -> String? {
        var tok = tokens(slug)
        let zip = tok.last.flatMap { isZip($0) ? $0 : nil }
        if zip != nil { tok.removeLast() }
        let st = tok.last.flatMap { isState($0) ? $0.uppercased() : nil }
        if st != nil { tok.removeLast() }
        guard !tok.isEmpty else { return nil }
        let (street, city) = splitStreetCity(tok)
        return formatAddress(street, city: title(city), state: st, zip: zip)
    }

    /// "the-addison-seattle-wa" -> ("The Addison", "The Addison, Seattle, WA").
    static func nameCityState(_ slug: String) -> (name: String?, address: String?) {
        var tok = tokens(slug)
        if let last = tok.last, !isState(last), last.contains(where: \.isNumber), last.contains(where: \.isLetter) {
            tok.removeLast() // trailing listing id, e.g. "the-addison-seattle-wa-5xjvq9"
        }
        let st = tok.last.flatMap { isState($0) ? $0.uppercased() : nil }
        if st != nil { tok.removeLast() }
        guard !tok.isEmpty else { return (nil, nil) }
        let name: [String], city: [String]
        if tok.count >= 3, cityPrefixes.contains(tok[tok.count - 2].lowercased()) {
            name = Array(tok.dropLast(2)); city = Array(tok.suffix(2))
        } else if tok.count >= 2 {
            name = Array(tok.dropLast()); city = Array(tok.suffix(1))
        } else {
            name = tok; city = []
        }
        let n = title(name)
        return (n, [n, title(city), st ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

// MARK: - Estimated floor plan

/// A plausible plan from beds/baths/sqft, for imports where no floor plan was
/// found. Two bands of rooms facing a hallway: bedrooms and bathrooms on one
/// side, living / dining / kitchen on the other (big homes move some bedrooms
/// across so the plan doesn't become a long corridor). Every room has a door
/// onto the hallway; living spaces get a window on each exterior wall.
/// Deterministic: the same inputs give the same plan.
public enum EstimatedFloorPlan {
    public static let hallwayDepthM = 1.2
    public static let doorWidthM = 0.85
    static let sqftToM2 = 0.09290304
    /// Share of the listed square footage that ends up as room floor (walls, closets, stairs take the rest).
    static let netShare = 0.85

    /// Typical size when the listing doesn't say (MoveWise `default_sqft`).
    public static func defaultSqft(beds: Int, baths: Double) -> Double {
        let b = max(0, beds)
        let base: Double = [0: 520, 1: 720, 2: 950, 3: 1300, 4: 1750][b] ?? 1750 + 400 * Double(b - 4)
        let extraBaths = max(0, (baths.isFinite ? baths : 1) - Double(max(1, b)))
        return base + extraBaths * 60
    }

    /// Room floor area the estimate aims for, in square meters.
    public static func targetAreaM2(sqft: Double) -> Double { sqft * sqftToM2 * netShare }

    public static func build(beds: Int, baths: Double, sqft: Double?) -> FloorPlan {
        let beds = max(0, beds)
        let baths = baths.isFinite ? max(1, baths) : 1
        let sqft = sqft.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? defaultSqft(beds: beds, baths: baths)
        let net = targetAreaM2(sqft: sqft)

        let fullBaths = Int(baths.rounded(.down))
        let halfBath = baths - Double(fullBaths) >= 0.5
        let bathSizes: [(w: Double, d: Double)] = Array(repeating: (2.2, 2.4), count: fullBaths) + (halfBath ? [(1.6, 1.8)] : [])
        let bathArea = bathSizes.reduce(0) { $0 + $1.w * $1.d }

        // Starting sizes (MoveWise `estimate_room_list`), then everything but the
        // bathrooms scales together so the rooms add up to the target area.
        let baseBeds: [Double] = (0..<beds).map { $0 == 0 ? 14.5 : 11.0 }
        let baseKitchen = net < 55 ? 9.0 : (net < 110 ? 11.0 : 13.0)
        let baseDining = beds >= 3 ? 10.0 : 0
        let baseLiving = beds == 0 ? 18.0 : 16.0 + 2 * Double(beds)
        let minBedArea = 2.8 * 2.6

        // The hallway's area depends on the plan's length, which depends on the
        // room areas: a few rounds of fixed-point iteration settle it.
        var hallArea = 0.0
        var layout = Layout(rooms: [], width: 0, hallY: 0)
        for _ in 0..<10 {
            let base = baseBeds.reduce(0, +) + baseKitchen + baseDining + baseLiving
            let k = min(1.6, max(0.72, (net - bathArea - hallArea) / base))
            let bedAreas = baseBeds.map { max(minBedArea, $0 * k) }
            let kitchen = max(6, baseKitchen * k)
            let dining = baseDining * k
            let living = max(baseLiving * 0.6, net - bathArea - hallArea - bedAreas.reduce(0, +) - kitchen - dining)
            layout = arrange(bedAreas: bedAreas, bathSizes: bathSizes, living: living, dining: dining, kitchen: kitchen)
            hallArea = layout.width * hallwayDepthM
        }
        return layout.plan()
    }

    // MARK: Layout

    struct Box {
        var name: String
        var kind: RoomKind
        var x: Double, y: Double, w: Double, d: Double
        var x1: Double { x + w }
        var y1: Double { y + d }
    }

    struct Layout {
        var rooms: [Box]
        var width: Double
        var hallY: Double

        func plan() -> FloorPlan {
            func r(_ v: Double) -> Double { (v * 100).rounded() / 100 }
            let boxes = rooms.map { b -> Box in
                var c = b
                c.x = r(b.x); c.y = r(b.y); c.w = r(b.x1) - c.x; c.d = r(b.y1) - c.y
                return c
            }
            let planRooms = boxes.map { FloorPlanRoom.rectangle($0.name, kind: $0.kind, x: $0.x, y: $0.y, width: $0.w, depth: $0.d) }
            guard let hall = boxes.first(where: { $0.kind == .hallway }) else { return FloorPlan(rooms: planRooms) }

            var doors: [WallOpening] = []
            for b in boxes where b.kind != .hallway {
                let onHall = abs(b.y1 - hall.y) < 1e-6 ? hall.y : (abs(b.y - hall.y1) < 1e-6 ? hall.y1 : nil)
                guard let y = onHall else { continue }
                let w = min(doorWidthM, b.w * 0.6)
                let cx = b.kind == .bedroom ? b.x1 - 0.3 - w / 2 : b.x + b.w / 2
                doors.append(WallOpening(from: PlanPoint(r(cx - w / 2), y), to: PlanPoint(r(cx + w / 2), y)))
            }
            // Front door at the hallway's west end.
            let fw = min(0.95, hall.d - 0.2)
            doors.append(WallOpening(from: PlanPoint(hall.x, r(hall.y + (hall.d - fw) / 2)), to: PlanPoint(hall.x, r(hall.y + (hall.d + fw) / 2))))
            // Wide openings between neighboring living / dining / kitchen.
            let open: Set<RoomKind> = [.living, .dining, .kitchen]
            for a in boxes where open.contains(a.kind) {
                for b in boxes where open.contains(b.kind) && abs(a.x1 - b.x) < 1e-6 {
                    let shared = min(a.y1, b.y1) - max(a.y, b.y)
                    guard shared > 0 else { continue }
                    let ow = min(1.4, shared - 0.6)
                    guard ow >= 0.8 else { continue }
                    let y0 = max(a.y, b.y) + (shared - ow) / 2
                    doors.append(WallOpening(from: PlanPoint(b.x, r(y0)), to: PlanPoint(b.x, r(y0 + ow))))
                }
            }

            var windows: [WallOpening] = []
            let lit: Set<RoomKind> = [.bedroom, .living, .dining, .kitchen]
            for b in boxes where lit.contains(b.kind) {
                for edge in edges(of: b) {
                    let others = boxes.filter { $0.name != b.name }
                    guard let free = longestFree(edge, others), free.1 - free.0 >= 1.5 else { continue }
                    let len = free.1 - free.0
                    let ww = min(b.kind == .kitchen ? 1.2 : 1.8, max(0.9, len * 0.45))
                    let s = free.0 + (len - ww) / 2
                    windows.append(edge.horizontal
                        ? WallOpening(from: PlanPoint(r(s), edge.at), to: PlanPoint(r(s + ww), edge.at))
                        : WallOpening(from: PlanPoint(edge.at, r(s)), to: PlanPoint(edge.at, r(s + ww))))
                }
            }
            return FloorPlan(rooms: planRooms, doors: doors, windows: windows)
        }
    }

    /// An axis-aligned wall: `horizontal` walls sit at y = `at` and span x in lo...hi.
    struct Edge { var horizontal: Bool; var at: Double; var lo: Double; var hi: Double }

    static func edges(of b: Box) -> [Edge] {
        [Edge(horizontal: true, at: b.y, lo: b.x, hi: b.x1), Edge(horizontal: true, at: b.y1, lo: b.x, hi: b.x1),
         Edge(horizontal: false, at: b.x, lo: b.y, hi: b.y1), Edge(horizontal: false, at: b.x1, lo: b.y, hi: b.y1)]
    }

    /// The longest stretch of `edge` not shared with any other room (an exterior wall), as (lo, hi).
    static func longestFree(_ edge: Edge, _ others: [Box]) -> (Double, Double)? {
        var covered: [(Double, Double)] = []
        for o in others {
            for e in edges(of: o) where e.horizontal == edge.horizontal && abs(e.at - edge.at) < 1e-6 {
                let s = max(e.lo, edge.lo), t = min(e.hi, edge.hi)
                if t > s { covered.append((s, t)) }
            }
        }
        covered.sort { $0.0 < $1.0 }
        var best: (Double, Double)?
        var cursor = edge.lo
        for (s, t) in covered {
            if s > cursor, s - cursor > (best.map { $0.1 - $0.0 } ?? 0) { best = (cursor, s) }
            cursor = max(cursor, t)
        }
        if edge.hi > cursor, edge.hi - cursor > (best.map { $0.1 - $0.0 } ?? 0) { best = (cursor, edge.hi) }
        return best
    }

    /// One room waiting to be placed along the hallway.
    struct Slot {
        var name: String
        var kind: RoomKind
        var w: Double
        var d: Double
    }

    static func arrange(bedAreas: [Double], bathSizes: [(w: Double, d: Double)], living: Double, dining: Double,
                        kitchen: Double) -> Layout {
        // Bedrooms share one depth (about 1.15:1 rooms), shallow enough that each is >= 2.8 m wide.
        let avgBed = bedAreas.isEmpty ? 0 : bedAreas.reduce(0, +) / Double(bedAreas.count)
        let minBed = bedAreas.min() ?? 0
        let dBed = bedAreas.isEmpty ? 0 : max(2.6, min((avgBed / 1.15).squareRoot(), minBed / 2.8, 4.4))
        // Living / dining / kitchen share one deeper band, deeper for bigger living rooms.
        let dPub = max(3.4, min(6.0, (living / 1.4).squareRoot()))

        var pub: [Slot] = [Slot(name: "Living room", kind: .living, w: living / dPub, d: dPub)]
        if dining > 0 { pub.append(Slot(name: "Dining room", kind: .dining, w: dining / dPub, d: dPub)) }
        pub.append(Slot(name: "Kitchen", kind: .kitchen, w: kitchen / dPub, d: dPub))

        let bedNames = bedAreas.indices.map { $0 == 0 ? "Bedroom" : "Bedroom \($0 + 1)" }
        var privBeds = zip(bedNames, bedAreas).map { Slot(name: $0, kind: .bedroom, w: $1 / dBed, d: dBed) }
        let baths = bathSizes.enumerated().map {
            Slot(name: $0.offset == 0 ? "Bathroom" : "Bathroom \($0.offset + 1)", kind: .bathroom, w: $0.element.w, d: $0.element.d)
        }
        func width(_ slots: [Slot]) -> Double { slots.reduce(0) { $0 + $1.w } }

        // Balance the two sides: move trailing bedrooms across while that shortens the plan.
        var moved: [Slot] = []
        while privBeds.count > 1, let last = privBeds.last {
            let privW = width(privBeds) + width(baths), pubW = width(pub) + width(moved)
            guard max(privW - last.w, pubW + last.w) < max(privW, pubW) - 0.01 else { break }
            moved.insert(privBeds.removeLast(), at: 0)
        }
        pub += moved
        // Studio: the kitchen sits beside the bathroom if that shortens the plan.
        var privExtra: [Slot] = []
        if bedAreas.isEmpty, let ki = pub.firstIndex(where: { $0.kind == .kitchen }) {
            let k = pub[ki]
            if max(width(baths) + k.w, width(pub) - k.w) < max(width(baths), width(pub)) { privExtra.append(pub.remove(at: ki)) }
        }

        // Private side: bed, bath, bed, bath..., leftover baths at the end.
        var priv: [Slot] = []
        var bathQueue = baths
        for (i, b) in privBeds.enumerated() {
            priv.append(b)
            if !bathQueue.isEmpty, i == 0 || bathQueue.count > privBeds.count - i - 1 { priv.append(bathQueue.removeFirst()) }
        }
        priv += bathQueue + privExtra

        // Rooms hang off both sides of the hallway, so every room's hallway wall is flush.
        let hallY = priv.map(\.d).max() ?? 0
        var boxes: [Box] = []
        var x = 0.0
        for p in priv {
            boxes.append(Box(name: p.name, kind: p.kind, x: x, y: hallY - p.d, w: p.w, d: p.d))
            x += p.w
        }
        let hallLen = max(x, width(pub))
        boxes.append(Box(name: "Hallway", kind: .hallway, x: 0, y: hallY, w: hallLen, d: hallwayDepthM))
        x = 0
        let pubY = hallY + hallwayDepthM
        for p in pub {
            boxes.append(Box(name: p.name, kind: p.kind, x: x, y: pubY, w: p.w, d: p.d))
            x += p.w
        }
        return Layout(rooms: boxes, width: hallLen, hallY: hallY)
    }
}
