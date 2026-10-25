import Foundation
import Testing
@testable import MooveKit

@Suite struct SummaryPayoffTests {
    private let demo = DemoFixtures.demo(owner: "me")

    private func item(_ id: UInt64, _ d: Disposition, category: String = "chair", sentimental: Bool = false,
                      source: DispositionSource = .auto) -> Item {
        Item(id: id, owner: "me", roomId: 1, scanObjectId: "s\(id)", name: "Item \(id)", category: category,
             widthM: 0.6, heightM: 0.9, depthM: 0.6, estValueCents: 1_000, disposition: d,
             dispositionSource: source, maybeSentimental: sentimental)
    }

    // MARK: Story

    @Test func demoStoryMatchesTheFigures() throws {
        let s = MoveSummary(snapshot: demo)
        // docs/demo-commerce.md Step 6: Kept 7, Selling 4 (the bean bag sold), ~49 kg.
        #expect(s.soldItems == 1)
        let kg = Int(s.divertedKg.rounded())
        #expect(kg == 49)
        #expect(SummaryPayoff.story(s) == "7 things kept, 1 sold, 3 still selling — and ~49 kg kept out of landfill.")
    }

    @Test func storySkipsEmptyPartsAndPluralizes() {
        let items = [item(1, .donate), item(2, .trash), item(3, .trash)]
        let s = MoveSummary(items: items, sales: [], spend: [], events: [])
        let story = SummaryPayoff.story(s)
        #expect(story?.hasPrefix("1 thing donated, 2 trashed — and ~") == true)
        #expect(story?.hasSuffix(" kg kept out of landfill.") == true)

        let trashOnly = MoveSummary(items: [item(1, .trash)], sales: [], spend: [], events: [])
        #expect(SummaryPayoff.story(trashOnly) == "1 thing trashed.")

        let undecided = MoveSummary(items: [item(1, .undecided), item(2, .undecided)], sales: [], spend: [], events: [])
        #expect(SummaryPayoff.story(undecided) == "2 things to decide.")
        #expect(SummaryPayoff.story(MoveSummary(items: [], sales: [], spend: [], events: [])) == nil)
    }

    // MARK: Segments

    @Test func demoSegmentsMatchReviewsPiles() {
        let segments = SummaryPayoff.segments(demo.items)
        #expect(segments.map(\.label) == ["Keep", "Sell", "Needs you"])
        #expect(segments.map(\.count) == [7, 4, 1])
        #expect(abs(segments.map(\.fraction).reduce(0, +) - 1) < 1e-9)
        let piles = Review.piles(demo.items)
        for seg in segments where seg.destination != nil {
            #expect(piles.first { $0.destination == seg.destination }?.count == seg.count)
        }
        #expect(SummaryPayoff.spokenSegments(segments) == "Keep 7, Sell 4, Needs you 1")
    }

    @Test func sentimentalAutoKeptCountsAsNeedsYou() {
        let items = [item(1, .keep, sentimental: true), item(2, .keep, sentimental: true, source: .user), item(3, .trash)]
        let segments = SummaryPayoff.segments(items)
        #expect(segments.map(\.id) == ["keep", "trash", "needsYou"])
        #expect(segments.map(\.count) == [1, 1, 1])
        #expect(SummaryPayoff.segments([]).isEmpty)
    }

    // MARK: Meters

    @Test func metersUseTheSummaryFigures() {
        let s = MoveSummary(snapshot: demo)
        // Sold $18 of $488 expected.
        #expect(abs(SummaryPayoff.soldShare(s) - 1_800.0 / 48_800.0) < 1e-9)
        // $180.015 spent, all but the real $0.01 simulated.
        #expect(abs(SummaryPayoff.simulatedShare(s) - 180_005_000.0 / 180_015_000.0) < 1e-9)
        let inflow = 48_800.0 * 10_000
        #expect(abs(SummaryPayoff.inShare(s) - inflow / (inflow + 180_015_000)) < 1e-9)
        #expect(SummaryPayoff.share(5, of: 0) == 0)
        #expect(SummaryPayoff.share(-5, of: 10) == 0)
        #expect(SummaryPayoff.share(50, of: 10) == 1)
    }

    @Test func leavesAndDivertedShare() {
        #expect(SummaryPayoff.leaves(kg: 0) == 0)
        #expect(SummaryPayoff.leaves(kg: 1) == 1)
        #expect(SummaryPayoff.leaves(kg: 49) == 10)
        #expect(SummaryPayoff.leaves(kg: 900) == SummaryPayoff.maxLeaves)

        #expect(SummaryPayoff.divertedShare(demo.items) == 1)
        #expect(SummaryPayoff.divertedShare([item(1, .keep)]) == nil)
        let half = SummaryPayoff.divertedShare([item(1, .sell), item(2, .trash)])
        #expect(half.map { abs($0 - 0.5) < 1e-9 } == true)
    }

    // MARK: Key steps

    @Test func keyStepsPreferOutcomesAndReadOldestFirst() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        let events = SummaryDemo.events(endingAt: end)
        let s = MoveSummary(items: [], sales: [], spend: [], events: events)
        let (key, rest) = SummaryPayoff.keySteps(s.timeline)
        #expect(key.count == 4)
        #expect(key.count + rest.count == s.timeline.count)
        #expect(key.allSatisfy { ["payment", "approval", "result"].contains($0.kind) })
        #expect(key.map(\.createdAt) == key.map(\.createdAt).sorted())
        #expect(rest.map(\.createdAt) == rest.map(\.createdAt).sorted())
        // The newest payment and approval make the cut.
        #expect(key.contains { $0.message == "Bought a dining table for $89.99 (Visa)" })
        #expect(key.contains { $0.message == "Asked you to approve a $410 listing" })

        let few = SummaryPayoff.keySteps(Array(s.timeline.prefix(2)))
        #expect(few.key.count == 2 && few.rest.isEmpty)
    }

    // MARK: Safety receipt

    @Test func safetyStampAndBarcode() {
        let lines = SafetySummary(snapshot: demo).lines
        #expect(SummaryPayoff.safetyStamp(lines) == "SIM LINES: SIMULATED — NO MONEY MOVED")
        #expect(SummaryPayoff.safetyStamp(lines.filter { !$0.simulated }) == nil)
        #expect(SummaryPayoff.safetyStamp(lines.filter(\.simulated)) == "SIMULATED — NO MONEY MOVED")
        let bars = SummaryPayoff.safetyBarcode(lines)
        #expect(bars == SummaryPayoff.safetyBarcode(lines))
        #expect(bars.count == 36 && bars.allSatisfy { (1...3).contains($0) })
    }

    // MARK: Figures unchanged

    @Test func headlineFiguresMatchTheDocs() {
        let s = MoveSummary(snapshot: demo)
        #expect(s.soldCents == 1_800)
        #expect(s.pendingSalesCents == 47_000)
        #expect(s.spentMicros == 180_015_000)
    }
}
