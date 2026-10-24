import Foundation
import Testing
@testable import MooveKit

/// Same golden numbers as agents/test/mover-quotes.test.ts, so the phone and the worker agree.
@Suite struct MoverRatesTests {
    @Test func testFifteenFootTwoMoversFourHours() {
        let r = MoverQuoteRequest(truck: .ft15, trucks: 1, crew: 2, hours: 4, volumeM3: 14)
        let t = MoverRates.truckCostCents(r)
        #expect(t.low == 7_345)
        #expect(t.high == 11_220)
        let q = MoverRates.quotes(for: r)
        #expect(q.map(\.id) == ["estimate-diy", "estimate-labor", "estimate-full"])
        #expect(q.map(\.lowCents) == [7_000, 35_000, 60_000])
        #expect(q.map(\.highCents) == [12_000, 52_000, 90_000])
        for x in q {
            #expect(x.kind == .estimate)
            #expect(x.tag == "Estimate")
            #expect(x.estimate)
            #expect(!x.simulated)
            #expect(x.source.url != nil)
        }
        #expect(q[0].assumptions[0].contains("25 miles of driving (assumed"))
    }

    @Test func testMinimumHoursSeveralTrucksGivenMiles() {
        let r = MoverQuoteRequest(truck: .ft26, trucks: 2, crew: 3, hours: 1, volumeM3: 60, miles: 10)
        let q = MoverRates.quotes(for: r)
        #expect(q.map(\.lowCents) == [13_000, 34_000, 54_000])
        #expect(q.map(\.highCents) == [19_000, 49_000, 81_000])
        #expect(q[0].includes[0].contains("2 × 26 ft truck"))
        #expect(q[1].includes[0].contains("~2 h"))
        #expect(q[2].includes[0].contains("~3 h with travel"))
    }

    @Test func testRequestFromTruckEstimateNormalizes() throws {
        let e = TruckEstimate(loadM3: 12.34, truck: .ft15, trucks: 1, moverHours: 3.4, movers: 2, costLowCents: 0, costHighCents: 0)
        let r = MoverQuoteRequest(estimate: e)
        #expect(r.truckSize == "ft15")
        #expect(r.hours == 3.5)
        #expect(r.volumeM3 == 12.3)
        let json = String(data: try JSONEncoder().encode(r), encoding: .utf8)!
        #expect(json.contains("\"truckSize\":\"ft15\""))
        #expect(!json.contains("miles"))
    }

    @Test func testOnDeviceIsLabeled() {
        let res = MoverRates.onDevice(MoverQuoteRequest(truck: .ft10, trucks: 1, crew: 2, hours: 2, volumeM3: 5))
        #expect(res.onPhone)
        #expect(res.note == "Estimates from published rates. Call to book.")
        #expect(res.quotes.count == 3)
    }

    @Test func testDecodesWorkerResponseWithListedRate() throws {
        let json = """
        {"quotes":[{"id":"listed-1","kind":"listed rate","moverType":"full","provider":"2 movers $90/hr","lowCents":36000,"highCents":45000,
          "includes":["Advertised $90/h for 2 movers"],"assumptions":[],"estimate":true,"simulated":false,
          "source":{"name":"Craigslist ad","url":"https://sfbay.craigslist.org/eby/lbs/d/x/1.html"}}],
         "steps":[{"kind":"plan","message":"Requested quotes for a 15' truck, 2 movers, ~4 h"}],
         "note":"Estimates from published rates. Call to book.","ratesAsOf":"2026-10-24","computedBy":"worker"}
        """
        let res = try JSONDecoder().decode(MoverQuotesResult.self, from: Data(json.utf8))
        #expect(!res.onPhone)
        #expect(res.quotes[0].kind == .listedRate)
        #expect(res.quotes[0].tag == "Listed rate")
        #expect(res.steps?.count == 1)
    }
}
