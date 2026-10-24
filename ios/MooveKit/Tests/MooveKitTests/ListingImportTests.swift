import Foundation
import Testing
@testable import MooveKit

@Suite struct ListingLinkTests {
    @Test func zillowHomeDetails() throws {
        let l = try #require(ListingLink.parse("https://www.zillow.com/homedetails/123-Main-St-Springfield-IL-62701/12345_zpid/"))
        #expect(l.site == "zillow")
        #expect(l.address == "123 Main St, Springfield, IL 62701")
        #expect(l.listingId == "12345")
        #expect(l.url == "https://www.zillow.com/homedetails/123-Main-St-Springfield-IL-62701/12345_zpid/")
    }

    @Test func zillowMessyPaste() throws {
        let text = "  check this out!! zillow.com/homedetails/456-Oak-Ave-APT-4B-San-Francisco-CA-94110/999_zpid/?utm_source=share&rtoken=abc#photos  "
        let l = try #require(ListingLink.parse(text))
        #expect(l.site == "zillow")
        #expect(l.address == "456 Oak Ave Apt 4B, San Francisco, CA 94110")
        #expect(l.listingId == "999")
        #expect(!l.url.contains("utm_source") && !l.url.contains("#"))
        #expect(l.url.hasPrefix("https://zillow.com/homedetails/"))
    }

    @Test func zillowCityWithoutStreetSuffix() throws {
        let l = try #require(ListingLink.parse("https://www.zillow.com/homedetails/10-Elm-Los-Angeles-CA-90001/1_zpid/"))
        #expect(l.address == "10 Elm, Los Angeles, CA 90001")
    }

    @Test func zillowIdOnly() throws {
        let l = try #require(ListingLink.parse("https://www.zillow.com/homedetails/12345_zpid/"))
        #expect(l.site == "zillow")
        #expect(l.address == nil)
        #expect(l.listingId == "12345")
    }

    @Test func zillowBuilding() throws {
        let l = try #require(ListingLink.parse("https://www.zillow.com/b/the-addison-seattle-wa-5XjVq9/"))
        #expect(l.address == "The Addison, Seattle, WA")
    }

    @Test func redfin() throws {
        let l = try #require(ListingLink.parse("https://www.redfin.com/IL/Springfield/123-Main-St-62701/home/12345"))
        #expect(l.site == "redfin")
        #expect(l.address == "123 Main St, Springfield, IL 62701")
        #expect(l.listingId == "12345")
    }

    @Test func redfinUnitAndTracking() throws {
        let l = try #require(ListingLink.parse("redfin.com/WA/Seattle/500-Pine-St-98101/unit-12A/home/777?utm_campaign=x"))
        #expect(l.address == "500 Pine St Unit 12A, Seattle, WA 98101")
        #expect(l.listingId == "777")
        #expect(!l.url.contains("utm"))
    }

    @Test func realtor() throws {
        let l = try #require(ListingLink.parse("https://www.realtor.com/realestateandhomes-detail/123-Main-St_Springfield_IL_62701_M12345-67890"))
        #expect(l.site == "realtor")
        #expect(l.address == "123 Main St, Springfield, IL 62701")
        #expect(l.listingId == "M12345-67890")
    }

    @Test func realtorIdOnly() throws {
        let l = try #require(ListingLink.parse("https://www.realtor.com/realestateandhomes-detail/M12345-67890"))
        #expect(l.site == "realtor")
        #expect(l.address == nil)
        #expect(l.listingId == "M12345-67890")
    }

    @Test func apartmentsBuilding() throws {
        let l = try #require(ListingLink.parse("https://www.apartments.com/the-addison-seattle-wa/abc123/"))
        #expect(l.site == "apartments")
        #expect(l.address == "The Addison, Seattle, WA")
        #expect(l.listingId == "abc123")
    }

    @Test func apartmentsStreetAddress() throws {
        let l = try #require(ListingLink.parse("https://www.apartments.com/123-main-st-austin-tx/xyz9/"))
        #expect(l.address == "123 Main St, Austin, TX")
    }

    @Test func streeteasyBuildingAndUnit() throws {
        let l = try #require(ListingLink.parse("https://streeteasy.com/building/123-west-50th-street-new_york/4b"))
        #expect(l.site == "streeteasy")
        #expect(l.address == "123 West 50th Street #4B, New York, NY")
    }

    @Test func streeteasyNamedBuildingInBrooklyn() throws {
        let l = try #require(ListingLink.parse("https://streeteasy.com/building/the-eugene-brooklyn/12a"))
        #expect(l.address == "The Eugene #12A, Brooklyn, NY")
    }

    @Test func streeteasyRentalIdOnly() throws {
        let l = try #require(ListingLink.parse("https://streeteasy.com/rental/1234567"))
        #expect(l.site == "streeteasy")
        #expect(l.address == nil)
        #expect(l.listingId == "1234567")
    }

    @Test func otherSitesAndNonLinks() throws {
        let l = try #require(ListingLink.parse("https://www.example.com/some/page?x=1"))
        #expect(l.site == "other")
        #expect(l.address == nil && l.listingId == nil)
        #expect(ListingLink.parse("") == nil)
        #expect(ListingLink.parse("   ") == nil)
        #expect(ListingLink.parse("123 Main St, Springfield") == nil)
    }
}

@Suite struct EstimatedFloorPlanTests {
    static let bathOptions: [Double] = [1, 1.5, 2, 3]

    @Test func validForEveryBedsAndBaths() {
        for beds in 0...6 {
            for baths in Self.bathOptions {
                let plan = EstimatedFloorPlan.build(beds: beds, baths: baths, sqft: nil)
                let label = "\(beds)bd/\(baths)ba"
                #expect(plan.issues().isEmpty, "\(label): \(plan.issues())")

                let kinds = plan.rooms.map(\.kind)
                func count(_ k: RoomKind) -> Int { kinds.filter { $0 == k }.count }
                let expectedBaths = Int(baths) + (baths - Double(Int(baths)) >= 0.5 ? 1 : 0)
                #expect(count(.bedroom) == beds, "\(label)")
                #expect(count(.bathroom) == expectedBaths, "\(label)")
                #expect(count(.kitchen) == 1 && count(.living) == 1 && count(.hallway) == 1, "\(label)")
                #expect(count(.dining) == (beds >= 3 ? 1 : 0), "\(label)")
                #expect(plan.room(named: "Living room") != nil && plan.room(named: "Kitchen") != nil)
                if beds > 0 { #expect(plan.room(named: "Bedroom") != nil) }
                if beds > 1 { #expect(plan.room(named: "Bedroom \(beds)") != nil) }

                let sqft = EstimatedFloorPlan.defaultSqft(beds: beds, baths: baths)
                let target = EstimatedFloorPlan.targetAreaM2(sqft: sqft)
                #expect(abs(plan.totalAreaM2 - target) <= 0.15 * target, "\(label): \(plan.totalAreaM2) vs \(target)")

                for r in plan.rooms where r.kind == .bedroom {
                    #expect(r.widthM >= 2.79 && r.depthM >= 2.59, "\(label) \(r.name) \(r.widthM)x\(r.depthM)")
                    #expect(!plan.windows(in: r).isEmpty, "\(label) \(r.name) has no window")
                }
                if let living = plan.room(named: "Living room") {
                    #expect(!plan.windows(in: living).isEmpty, "\(label) living has no window")
                }
                // Every room except the hallway has a door onto the hallway.
                let hall = plan.room(named: "Hallway")!
                for r in plan.rooms where r.kind != .hallway {
                    let onHall = plan.doors.contains { d in
                        r.edges.contains { FloorPlan.span(of: d, onEdge: $0.0, $0.1) != nil }
                            && hall.edges.contains { FloorPlan.span(of: d, onEdge: $0.0, $0.1) != nil }
                    }
                    #expect(onHall, "\(label) \(r.name) has no hallway door")
                }
            }
        }
    }

    @Test func respectsGivenSqft() {
        for (beds, baths, sqft) in [(2, 1.0, 900.0), (3, 2.0, 1600.0), (1, 1.0, 600.0), (4, 3.0, 2400.0), (0, 1.0, 400.0)] {
            let plan = EstimatedFloorPlan.build(beds: beds, baths: baths, sqft: sqft)
            let target = EstimatedFloorPlan.targetAreaM2(sqft: sqft)
            #expect(plan.issues().isEmpty)
            #expect(abs(plan.totalAreaM2 - target) <= 0.15 * target, "\(beds)/\(baths)/\(sqft): \(plan.totalAreaM2) vs \(target)")
        }
    }

    @Test func deterministic() throws {
        let a = EstimatedFloorPlan.build(beds: 3, baths: 2, sqft: 1400)
        let b = EstimatedFloorPlan.build(beds: 3, baths: 2, sqft: 1400)
        #expect(a == b)
        #expect(try a.jsonString() == b.jsonString())
    }

    @Test func defaultSqftMatchesMoveWise() {
        #expect(EstimatedFloorPlan.defaultSqft(beds: 0, baths: 1) == 520)
        #expect(EstimatedFloorPlan.defaultSqft(beds: 2, baths: 1) == 950)
        #expect(EstimatedFloorPlan.defaultSqft(beds: 2, baths: 3) == 1010)
        #expect(EstimatedFloorPlan.defaultSqft(beds: 6, baths: 4) == 2550)
    }

    @Test func badInputsStillMakeAPlan() {
        #expect(EstimatedFloorPlan.build(beds: -1, baths: 0, sqft: -5).issues().isEmpty)
        #expect(EstimatedFloorPlan.build(beds: 2, baths: .nan, sqft: .infinity).issues().isEmpty)
    }

    @Test func printExample() {
        let plan = EstimatedFloorPlan.build(beds: 2, baths: 1, sqft: 900)
        for r in plan.rooms {
            print("EXAMPLE \(r.name): " + String(format: "%.2f x %.2f = %.1f m2", r.widthM, r.depthM, r.areaM2))
        }
        print(String(format: "EXAMPLE total %.1f target %.1f doors %d windows %d", plan.totalAreaM2,
                     EstimatedFloorPlan.targetAreaM2(sqft: 900), plan.doors.count, plan.windows.count))
    }
}
