import Foundation
import Testing
@testable import MooveKit

@Suite struct ListingURLTests {
    let current = URL(string: "https://new-tunnel-words.trycloudflare.com")!
    let old = "https://manufacture-albany-slot-lows.trycloudflare.com/files/listing-1.html"

    @Test func oldTunnelListingPageMovesToCurrentBase() {
        let u = ListingURL.resolve(old, simulated: true, uploadBase: current)
        #expect(u?.absoluteString == "https://new-tunnel-words.trycloudflare.com/files/listing-1.html")
    }

    @Test func listingExtensionUsesTheSameRule() {
        let l = Listing(id: 1, owner: "me", itemId: 1, title: "Mesh chair", description: "", priceCents: 4_000,
                        status: .posted, url: old, simulated: true)
        #expect(l.viewURL(uploadBase: current)?.absoluteString == "https://new-tunnel-words.trycloudflare.com/files/listing-1.html")
    }

    @Test func currentHostIsLeftAlone() {
        let raw = "https://new-tunnel-words.trycloudflare.com/files/listing-3.html"
        #expect(ListingURL.resolve(raw, simulated: true, uploadBase: current)?.absoluteString == raw)
    }

    @Test func noCurrentBaseKeepsTheStoredLink() {
        #expect(ListingURL.resolve(old, simulated: true, uploadBase: nil)?.absoluteString == old)
    }

    @Test func realEbayURLsAreNeverRewritten() {
        for raw in ["https://sandbox.ebay.com/itm/110554321234", "https://www.ebay.com/itm/1234",
                    "https://sandbox.ebay.com/files/listing-1.html"] {
            #expect(ListingURL.resolve(raw, simulated: false, uploadBase: current)?.absoluteString == raw)
            #expect(ListingURL.resolve(raw, simulated: true, uploadBase: current)?.absoluteString == raw)
        }
    }

    @Test func nonSimulatedFilesLinkOnAnUnknownHostIsLeftAlone() {
        let raw = "https://example.com/files/listing-1.html"
        #expect(ListingURL.resolve(raw, simulated: false, uploadBase: current)?.absoluteString == raw)
    }

    @Test func simulatedLocalhostPageMovesToCurrentBase() {
        let u = ListingURL.resolve("http://localhost:8787/files/listing-12.html", simulated: true, uploadBase: current)
        #expect(u?.absoluteString == "https://new-tunnel-words.trycloudflare.com/files/listing-12.html")
    }

    @Test func previousUploadHostMovesEvenWhenNotAListingPage() {
        let raw = "https://old.example.net/files/photo-abc.jpg"
        #expect(ListingURL.resolve(raw, simulated: false, uploadBase: current)?.absoluteString == raw)
        let u = ListingURL.resolve(raw, simulated: false, uploadBase: current, previousUploadHosts: ["old.example.net"])
        #expect(u?.absoluteString == "https://new-tunnel-words.trycloudflare.com/files/photo-abc.jpg")
    }

    @Test func quickTunnelHostCountsAsAPreviousUploadHost() {
        let raw = "https://dead-tunnel.trycloudflare.com/files/listing-2.html"
        let u = ListingURL.resolve(raw, simulated: false, uploadBase: current)
        #expect(u?.absoluteString == "https://new-tunnel-words.trycloudflare.com/files/listing-2.html")
    }

    @Test func nonFilesPathsAreLeftAlone() {
        let raw = "https://dead-tunnel.trycloudflare.com/healthz"
        #expect(ListingURL.resolve(raw, simulated: true, uploadBase: current)?.absoluteString == raw)
    }

    @Test func relativeFilesLinkResolvesAgainstBase() {
        #expect(ListingURL.resolve("/files/listing-4.html", simulated: true, uploadBase: current)?.absoluteString
            == "https://new-tunnel-words.trycloudflare.com/files/listing-4.html")
        #expect(ListingURL.resolve("/files/listing-4.html", simulated: true, uploadBase: nil) == nil)
    }

    @Test func baseWithPortAndPathPrefixIsKept() {
        let base = URL(string: "http://192.168.1.20:8787/moove/")!
        let u = ListingURL.resolve(old, simulated: true, uploadBase: base)
        #expect(u?.absoluteString == "http://192.168.1.20:8787/moove/files/listing-1.html")
        // Same host, different port: still a different upload origin.
        let u2 = ListingURL.resolve("http://192.168.1.20:9999/files/listing-1.html", simulated: true, uploadBase: base)
        #expect(u2?.absoluteString == "http://192.168.1.20:8787/moove/files/listing-1.html")
    }

    @Test func emptyOrMissingIsNil() {
        #expect(ListingURL.resolve(nil, simulated: true, uploadBase: current) == nil)
        #expect(ListingURL.resolve("  ", simulated: true, uploadBase: current) == nil)
    }
}
