import Foundation

/// Mover quotes for the Pack screen. The worker's `POST /moves/quotes` answers with `MoverQuotesResult`;
/// offline (or with no worker URL) the phone builds the same three rate-table estimates here.
///
/// This mirrors `agents/src/moves/rates.ts` number for number (both test suites check the same
/// golden values). Every quote is an **estimate** from typical published rates, never a booked quote:
/// - DIY truck: U-Haul in-town day rates ($19.95 van/10 ft, $29.95 15 ft, $39.95 20/26 ft) plus
///   $0.79–$1.59 a mile, fuel at 10 mpg and $3.50–$5.00/gal, $15–$30 damage protection.
/// - Labor-only crew (HireAHelper city rates): $35–$50 per mover-hour, 2 h minimum, plus the DIY truck.
/// - Full-service local movers (Bellhops, Taskrabbit, 2026 cost guides): $60–$90 per mover-hour with
///   the truck, 3 h minimum, plus 1 h travel.
/// Ranges are rounded to $10: low down, high up.
public enum MoverRates {
    public static let asOf = "2026-10-24"
    public static let note = "Estimates from published rates. Call to book."
    public static let defaultMiles = 25

    static func truckDayCents(_ t: TruckSize) -> Int64 {
        switch t {
        case .cargoVan, .ft10: return 1_995
        case .ft15: return 2_995
        case .ft20, .ft26: return 3_995
        }
    }
    static let mileCents: (Int64, Int64) = (79, 159)
    static let mpg: Int64 = 10
    static let fuelCentsPerGal: (Int64, Int64) = (350, 500)
    static let protectionCents: (Int64, Int64) = (1_500, 3_000)
    static let laborPerMoverHourCents: (Double, Double) = (3_500, 5_000)
    static let laborMinHours = 2.0
    static let fullPerMoverHourCents: (Double, Double) = (6_000, 9_000)
    static let fullMinHours = 3.0
    static let fullTravelHours = 1.0

    static let sources: [MoverQuote.Source] = [
        .init(name: "U-Haul in-town truck rates", url: "https://www.uhaul.com/Trucks"),
        .init(name: "HireAHelper labor-only rates", url: "https://www.hireahelper.com/movers/los-angeles_ca/move-help"),
        .init(name: "Taskrabbit mover cost guide", url: "https://www.taskrabbit.com/cost-guides/help-moving"),
    ]

    public static func roundLow(_ cents: Double) -> Int64 { Int64((cents / 1_000).rounded(.down)) * 1_000 }
    public static func roundHigh(_ cents: Double) -> Int64 { Int64((cents / 1_000).rounded(.up)) * 1_000 }

    /// DIY truck cost range in cents (unrounded), all trucks.
    public static func truckCostCents(_ r: MoverQuoteRequest) -> (low: Int64, high: Int64) {
        let miles = Int64(r.miles ?? defaultMiles)
        let n = Int64(max(1, r.trucks))
        let day = truckDayCents(r.truck)
        let low = day + miles * mileCents.0 + miles * fuelCentsPerGal.0 / mpg + protectionCents.0
        let high = day + miles * mileCents.1 + miles * fuelCentsPerGal.1 / mpg + protectionCents.1
        return (n * low, n * high)
    }

    /// The three rate-table estimates: DIY truck rental, labor-only movers, full-service local movers.
    public static func quotes(for r: MoverQuoteRequest) -> [MoverQuote] {
        let miles = r.miles ?? defaultMiles
        let n = max(1, r.trucks)
        let label = r.truck.label.prefix(1).lowercased() + r.truck.label.dropFirst()
        let truck = n > 1 ? "\(n) × \(label)" : label
        let t = truckCostCents(r)
        let milesNote = "\(miles) miles of driving" + (r.miles == nil ? " (assumed, local move)" : "")
        let laborH = max(r.hours, laborMinHours)
        let fullH = max(r.hours + fullTravelHours, fullMinHours)
        let crew = Double(r.crew)
        func h(_ x: Double) -> String { x.rounded() == x ? "\(Int(x)) h" : String(format: "%.1f h", x) }
        func usd(_ c: Double) -> String { "$\(Int(c / 100))" }
        return [
            MoverQuote(id: "estimate-diy", kind: .estimate, moverType: "diy", provider: "DIY truck rental",
                       lowCents: roundLow(Double(t.low)), highCents: roundHigh(Double(t.high)),
                       includes: ["\(truck) for a day", "Mileage, fuel and damage protection", "You load, drive and unload"],
                       assumptions: [milesNote, "$0.79-$1.59 a mile"], source: sources[0]),
            MoverQuote(id: "estimate-labor", kind: .estimate, moverType: "labor", provider: "Labor-only movers",
                       lowCents: roundLow(crew * laborH * laborPerMoverHourCents.0 + Double(t.low)),
                       highCents: roundHigh(crew * laborH * laborPerMoverHourCents.1 + Double(t.high)),
                       includes: ["\(r.crew) movers load and unload, ~\(h(laborH))", "\(truck) rental (you drive)"],
                       assumptions: ["\(usd(laborPerMoverHourCents.0))-\(usd(laborPerMoverHourCents.1)) per mover-hour, \(Int(laborMinHours)) h minimum", milesNote],
                       source: sources[1]),
            MoverQuote(id: "estimate-full", kind: .estimate, moverType: "full", provider: "Full-service local movers",
                       lowCents: roundLow(crew * fullH * fullPerMoverHourCents.0),
                       highCents: roundHigh(crew * fullH * fullPerMoverHourCents.1),
                       includes: ["\(r.crew) movers and their truck, ~\(h(fullH)) with travel", "Loading, driving, unloading", "Furniture pads and basic coverage"],
                       assumptions: ["\(usd(fullPerMoverHourCents.0))-\(usd(fullPerMoverHourCents.1)) per mover-hour, \(Int(fullMinHours)) h minimum", "\(Int(fullTravelHours)) h travel time"],
                       source: sources[2]),
        ]
    }

    /// The offline answer: the same estimates, worked out on the phone.
    public static func onDevice(_ r: MoverQuoteRequest) -> MoverQuotesResult {
        MoverQuotesResult(quotes: quotes(for: r), steps: nil, note: note, ratesAsOf: asOf, computedBy: "phone")
    }
}

/// Body of `POST /moves/quotes`.
public struct MoverQuoteRequest: Codable, Sendable, Hashable {
    public var volumeM3: Double
    public var truckSize: String
    public var trucks: Int
    public var crew: Int
    public var hours: Double
    public var miles: Int?
    public var roomId: String?

    public init(truck: TruckSize, trucks: Int, crew: Int, hours: Double, volumeM3: Double, miles: Int? = nil, roomId: String? = nil) {
        self.truckSize = truck.rawValue
        self.trucks = max(1, trucks)
        self.crew = min(max(1, crew), 8)
        // Same normalization as the worker: quarter hours, 0.5 h to 24 h.
        self.hours = min(max(0.5, (hours * 4).rounded() / 4), 24)
        self.volumeM3 = min(max(0, (volumeM3 * 10).rounded() / 10), 500)
        self.miles = miles
        self.roomId = roomId
    }

    /// From the Pack screen's truck estimate.
    public init(estimate e: TruckEstimate, roomId: String? = nil) {
        self.init(truck: e.truck, trucks: e.trucks, crew: e.movers, hours: e.moverHours, volumeM3: e.loadM3, roomId: roomId)
    }

    public var truck: TruckSize { TruckSize(rawValue: truckSize) ?? .ft15 }
}

public struct MoverQuote: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case estimate
        case listedRate = "listed rate"
    }
    public struct Source: Codable, Sendable, Hashable {
        public var name: String
        public var url: String?
        public init(name: String, url: String?) {
            self.name = name
            self.url = url
        }
    }

    public var id: String
    public var kind: Kind
    public var moverType: String
    public var provider: String
    public var lowCents: Int64
    public var highCents: Int64
    public var includes: [String]
    public var assumptions: [String]
    /// True for everything Moove shows: none of these is a booked or binding quote.
    public var estimate: Bool
    public var simulated: Bool
    public var source: Source

    public init(id: String, kind: Kind, moverType: String, provider: String, lowCents: Int64, highCents: Int64,
                includes: [String], assumptions: [String], estimate: Bool = true, simulated: Bool = false, source: Source) {
        self.id = id
        self.kind = kind
        self.moverType = moverType
        self.provider = provider
        self.lowCents = lowCents
        self.highCents = highCents
        self.includes = includes
        self.assumptions = assumptions
        self.estimate = estimate
        self.simulated = simulated
        self.source = source
    }

    /// The tag on the card: "Estimate" or "Listed rate".
    public var tag: String { kind == .listedRate ? "Listed rate" : "Estimate" }
}

/// 200 body of `POST /moves/quotes` (or `MoverRates.onDevice`).
public struct MoverQuotesResult: Codable, Sendable, Hashable {
    public struct Step: Codable, Sendable, Hashable {
        public var kind: String
        public var message: String
    }
    public var quotes: [MoverQuote]
    public var steps: [Step]?
    public var note: String
    public var ratesAsOf: String
    /// "worker" or "phone".
    public var computedBy: String

    public init(quotes: [MoverQuote], steps: [Step]?, note: String, ratesAsOf: String, computedBy: String) {
        self.quotes = quotes
        self.steps = steps
        self.note = note
        self.ratesAsOf = ratesAsOf
        self.computedBy = computedBy
    }

    public var onPhone: Bool { computedBy == "phone" }
}
