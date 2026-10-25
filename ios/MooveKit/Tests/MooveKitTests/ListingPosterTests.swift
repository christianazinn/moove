import Foundation
import Testing
@testable import MooveKit

@Suite struct ListingPosterTests {
    private func listing(_ id: UInt64, _ status: ListingStatus, simulated: Bool = true, platform: String = "ebay",
                         price: Int64 = 1_000, externalId: String? = nil) -> Listing {
        Listing(id: id, owner: "me", itemId: 1, platform: platform, title: "Thing \(id)", description: "",
                priceCents: price, status: status, externalId: externalId, simulated: simulated)
    }

    @Test func styleIsDeterministicPerListing() {
        for id in UInt64(0)..<200 {
            #expect(PosterWall.style(forListingId: id) == PosterWall.style(forListingId: id))
        }
    }

    @Test func consecutiveListingsGetDifferentColors() {
        let palette = PosterPalette.current
        for id in UInt64(190)..<210 {
            #expect(PosterWall.style(forListingId: id).swatch != PosterWall.style(forListingId: id + 1).swatch)
        }
        // The demo's six listings use all six swatches.
        let names = Set((UInt64(198)...203).map { PosterWall.style(forListingId: $0).swatch.name })
        #expect(names.count == palette.swatches.count)
    }

    @Test func everyTreatmentAndHeadlineShowsUp() {
        let styles = (UInt64(0)..<300).map { PosterWall.style(forListingId: $0) }
        #expect(Set(styles.map(\.treatment)) == Set(PosterTreatment.allCases))
        #expect(Set(styles.map(\.headline)) == Set(PosterWall.headlines))
        #expect(Set(styles.map(\.fastener)) == Set(PosterFastener.allCases))
    }

    @Test func tiltIsSmallButVisible() {
        var signs = Set<Bool>()
        for id in UInt64(0)..<500 {
            let t = PosterWall.tilt(forListingId: id)
            #expect(abs(t) >= 0.3 - 1e-9 && abs(t) <= PosterWall.maxTilt + 1e-9, "tilt \(t) for \(id)")
            #expect(abs(t * 10 - (t * 10).rounded()) < 1e-9)
            signs.insert(t > 0)
        }
        #expect(signs.count == 2)
    }

    @Test func straightWallHasNoTilt() {
        for id in UInt64(0)..<50 {
            #expect(PosterWall.style(forListingId: id, straight: true).tiltDegrees == 0)
        }
    }

    @Test func stampsPerStatus() {
        #expect(PosterWall.stamp(for: .sold, simulated: true).text == "SOLD")
        #expect(PosterWall.stamp(for: .sold, simulated: true).isBig)
        #expect(PosterWall.stamp(for: .awaitingApproval, simulated: true).text == "NEEDS YOUR OK")
        #expect(PosterWall.stamp(for: .draft, simulated: true).isSketch)
        #expect(PosterWall.stamp(for: .posting, simulated: true).isSketch)
        #expect(PosterWall.stamp(for: .failed, simulated: true).isTorn)
        #expect(PosterWall.stamp(for: .rejected, simulated: true).isCrossedOut)
        #expect(PosterWall.stamp(for: .rejected, simulated: true).text == "DENIED")
        // Only one stamp is big, and only one treatment flag at a time.
        for status in ListingStatus.allCases {
            let s = PosterWall.stamp(for: status, simulated: false)
            #expect(s.isBig == (status == .sold))
            #expect([s.isSketch, s.isTorn, s.isCrossedOut].filter { $0 }.count <= 1)
        }
    }

    @Test func simulatedPostIsNeverStampedLive() {
        #expect(PosterWall.stamp(for: .posted, simulated: true).text == "POSTED")
        #expect(PosterWall.stamp(for: .posted, simulated: true).kind == .posted)
        #expect(PosterWall.stamp(for: .posted, simulated: false).text == "LIVE")
        for status in ListingStatus.allCases {
            #expect(!PosterWall.stamp(for: status, simulated: true).text.contains("LIVE"))
        }
    }

    @Test func tearOffTabsSaySimulated() {
        #expect(PosterWall.tabText(for: listing(1, .posted)) == "eBay · simulated")
        #expect(PosterWall.tabText(for: listing(1, .posted, platform: "fb")) == "FB Marketplace · simulated")
        // A simulated listing's made-up item number is never shown.
        #expect(PosterWall.tabText(for: listing(1, .posted, externalId: "123")) == "eBay · simulated")
        #expect(PosterWall.tabText(for: listing(1, .posted, simulated: false, externalId: "395718204163")) == "eBay #395718204163")
        #expect(PosterWall.tabText(for: listing(1, .draft, simulated: false)) == "eBay")
    }

    @Test func columnsFollowWidthAndTextSize() {
        #expect(PosterWall.columns(regularWidth: false, accessibilitySize: false) == 2)
        #expect(PosterWall.columns(regularWidth: true, accessibilitySize: false) == 3)
        #expect(PosterWall.columns(regularWidth: true, accessibilitySize: true) == 1)
        #expect(PosterWall.columns(regularWidth: false, accessibilitySize: true) == 1)
    }

    @Test func masonryDealsToTheShortestColumn() {
        let cols = PosterWall.deal([1, 2, 3, 4, 5], columns: 2) { $0 == 1 ? 2 : 1 }
        #expect(cols == [[1, 4], [2, 3, 5]])
        #expect(PosterWall.deal([1, 2], columns: 3) == [[1], [2]])
        #expect(PosterWall.deal([Int](), columns: 2).isEmpty)
        #expect(PosterWall.deal([1, 2, 3], columns: 0) == [[1, 2, 3]])
    }

    @Test func demoTotalsMatchTheFlyer() {
        let totals = PosterWall.totals(DemoFixtures.inventory(owner: "me").listings)
        let listings = DemoFixtures.inventory(owner: "me").listings
        let live = listings.filter { $0.status == .posted }
        #expect(totals.liveCount == live.count)
        #expect(totals.listedCents == live.map(\.priceCents).reduce(0, +))
        #expect(totals.soldCents == listings.filter { $0.status == .sold }.map(\.priceCents).reduce(0, +))
        let mixed = [listing(1, .posted, price: 3_000), listing(2, .sold, price: 1_800), listing(3, .draft, price: 999)]
        #expect(PosterWall.totals(mixed) == PosterWall.Totals(liveCount: 1, listedCents: 3_000, soldCents: 1_800))
    }

    @Test func paletteTextIsReadable() {
        let p = PosterPalette.current
        #expect(PosterPalette.contrast(p.paperInk, p.paper) >= 7)
        for s in p.swatches {
            #expect(PosterPalette.contrast(s.color, s.onColor) >= 4.5, "\(s.name) text")
            // The big price on cream paper is large text (3:1).
            let style = PosterStyle(swatch: s, treatment: .paper, headline: "", fastener: .pin, tiltDegrees: 0)
            #expect(PosterPalette.contrast(style.priceInk(paperInk: p.paperInk), p.paper) >= 3, "\(s.name) price")
        }
        // Stamps sit on a cream plate.
        for kind in PosterStamp.Kind.allCases {
            #expect(PosterPalette.contrast(p.ink(for: kind), p.paper) >= 4.5, "\(kind) stamp")
        }
    }

    @Test func swappingThePaletteRestylesPosters() {
        var other = PosterPalette.current
        other.swatches = [.init(name: "black", color: 0x000000, onColor: 0xFFFFFF, accent: 0xFF0000)]
        #expect(PosterWall.style(forListingId: 7, palette: other).swatch.name == "black")
        other.swatches = []
        #expect(!PosterWall.style(forListingId: 7, palette: other).swatch.name.isEmpty)
    }
}
