import XCTest

/// Walks the Offline demo once and saves one screenshot per shot in `docs/devpost-media.md`
/// (#242), so the humans have Devpost images without a phone. Names start with the shot
/// number from that doc ("01-scan", "02-items", …). CI uploads them as `devpost-screenshots`.
/// Assertions only check that each screen opened; the other suites test behavior.
@MainActor
final class DevpostShotsTests: XCTestCase {
    private var app: XCUIApplication!
    private let slow: TimeInterval = 30

    func testDevpostShots() {
        continueAfterFailure = false
        launch()

        // 1. Scan: the turning voxel dollhouse hero.
        open(tab: "Scan")
        sleep(4)  // let the hero's dollhouse build and turn a little
        shot("01-scan")

        // 2. Items > Inventory.
        open(tab: "Items", segment: "Inventory")
        shot("02-items")

        // 4. Items > Review (before 3b, which opens an item from here): the flip cards (the
        // guitar, which needs you, on top; "1 of 12") over the Where it goes board.
        open(tab: "Items", segment: "Review")
        _ = byId("review.deck").waitForExistence(timeout: slow)
        shot("04-review")

        // 3b. Review > Sell > Office chair: the price and its comparable listings.
        let sell = byId("review.pile.sell")
        if scrollTo(sell) { sell.tap() }
        let chair = byId("review.item.11")
        if scrollTo(chair) {
            chair.tap()
            XCTAssertTrue(app.navigationBars["Office chair"].waitForExistence(timeout: slow), "Office chair detail")
            _ = scrollTo(app.staticTexts["Comparable listings"])
            shot("03b-item-comps")
            app.navigationBars.buttons.firstMatch.tap()
        }

        // 5. Sell & Buy > Agents, top: two requests wait for the user ("Needs your OK").
        open(tab: "Sell & Buy", segment: "Agents")
        XCTAssertTrue(app.navigationBars["Agents"].waitForExistence(timeout: slow))
        shot("05-approvals")

        // 3. Further down Agents: the x402 payments as receipts, with the Basescan row.
        _ = scrollTo(byId("spending.totals"))
        shot("03a-spending-top")
        // The headline image: the pricing agent's receipt with the real Base Sepolia line.
        // The receipts page sideways: Next until the pricing receipt is on screen.
        let basescan = byId("payment.basescan.500")
        let next = byId("receipts.next")
        if scrollTo(next) {
            for _ in 0..<6 where !(basescan.frame.minX >= 0 && basescan.frame.maxX <= app.windows.firstMatch.frame.maxX) && next.isEnabled {
                next.tap()
                sleep(1)
            }
        }
        _ = scrollTo(basescan)
        shot("03-spending")

        // 6. Sell & Buy > Shopping > Desk chair: the planted scam deal is blocked.
        open(tab: "Sell & Buy", segment: "Shopping")
        let deskChair = byId("shopping.item.52")
        if scrollTo(deskChair) {
            deskChair.tap()
            _ = scrollTo(byId("deal.blocked.76"))
            shot("06-desk-chair-deals")
        }

        // 7. Move > New Home > the demo house: what was kept, in the voxel house.
        open(tab: "Move", segment: "New Home")
        // The whole demo-house card is one button ("Demo house · 2 bed, 1 bath, …").
        let use = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Demo house'")).firstMatch
        if scrollTo(use) {
            use.tap()
            sleep(5)  // the fly-in
            shot("07-new-home")
        }

        // 8. Summary.
        open(tab: "Summary")
        shot("08-summary")

        // 1b. Scan > Load demo scan: the finished page. Last, since it adds a second room.
        open(tab: "Scan")
        let load = app.buttons["Load demo scan"]
        XCTAssertTrue(scrollTo(load), "Load demo scan button")
        load.tap()
        XCTAssertTrue(app.buttons["See inventory"].waitForExistence(timeout: slow), "scan finished screen")
        sleep(3)
        shot("01b-scan-finished")
    }

    // MARK: Helpers (as in MooveSmokeTests / CommerceUITests)

    private func launch() {
        app = XCUIApplication()
        app.launchArguments += ["-moove.backendKind", "fixture", "-moove.auth.guest", "YES"]
        app.launchEnvironment["MOOVE_UI_TEST_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: slow), "tab bar")
    }

    /// A tab, then (for grouped tabs) a segment of its pill picker. Segments may carry a count ("Agents · 2").
    private func open(tab: String, segment: String? = nil) {
        app.tabBars.buttons[tab].tap()
        guard let segment else { return }
        let pill = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", segment, "\(segment) ·")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: slow), "\(segment) segment")
        pill.tap()
        sleep(1)  // segment transition
    }

    private func byId(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 10) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable { return true }
        for up in [true, false] {
            for _ in 0..<swipes {
                if element.exists, element.isHittable { return true }
                // Near the left edge, in the gutter: a drag on Review's deck card would decide it.
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.7 : 0.35))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: up ? 0.35 : 0.7))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        return element.exists && element.isHittable
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
