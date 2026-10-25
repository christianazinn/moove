import XCTest

/// Taps through the Sell & Buy tab on the offline demo backend, launched the same way as
/// `MooveSmokeTests` (`-moove.backendKind fixture -moove.auth.guest YES`, `MOOVE_UI_TEST_RESET`),
/// so a broken commerce screen fails CI. Every screen is saved as a screenshot attachment
/// (keepAlways) in the .xcresult that CI uploads.
///
/// Fixture ids come from MooveKit `DemoFixtures` / `ShoppingFixtures`: listing 201 (the mesh chair, posted, simulated),
/// approvals 300 (Aeron listing) and 85 (sofa purchase), payment 500 (the real Base Sepolia tx),
/// shopping item 52 (Desk chair) with deals 74 (Target task chair, $79.99, under the demo user's
/// $100 approval threshold) and 76 (the planted Craigslist Aeron scam, fraud 0.85).
@MainActor
final class CommerceUITests: XCTestCase {
    private var app: XCUIApplication!

    func testSellAndBuyFlowOnOfflineDemo() {
        launchOfflineDemo()

        // Sell & Buy tab and its four segments, in order.
        let sellBuy = app.tabBars.buttons["Sell & Buy"]
        XCTAssertTrue(sellBuy.waitForExistence(timeout: 10), "no Sell & Buy tab")
        select(tab: sellBuy)
        let listingsTab = segment("Listings")
        let shoppingTab = segment("Shopping")
        let approvalsTab = segment("Approvals")
        let spendingTab = segment("Spending")
        for s in [listingsTab, shoppingTab, approvalsTab, spendingTab] {
            XCTAssertTrue(s.waitForExistence(timeout: 10), "missing segment \(s)")
        }
        let xs = [listingsTab, shoppingTab, approvalsTab, spendingTab].map { $0.frame.minX }
        XCTAssertEqual(xs, xs.sorted(), "segments out of order: \(xs)")
        XCTAssertTrue(approvalsTab.label.contains("2"), "Approvals segment should show 2 pending: \(approvalsTab.label)")
        shot("0-sell-and-buy")

        // Spending: SIMULATED rows and the Basescan link for the one real payment.
        spendingTab.tap()
        XCTAssertTrue(app.navigationBars["Spending"].waitForExistence(timeout: 10))
        let simulated = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'payment.' AND label CONTAINS ', simulated,'")).firstMatch
        XCTAssertTrue(scrollTo(simulated), "no SIMULATED payment row")
        shot("1-spending")
        let basescan = byId("payment.basescan.500")
        XCTAssertTrue(scrollTo(basescan), "no Basescan link row")
        XCTAssertEqual(basescan.label, "View the transaction on Basescan")
        shot("1-spending-basescan")

        // Listings: posted listings say "Posted (simulated)", never "Live on eBay".
        listingsTab.tap()
        XCTAssertTrue(app.navigationBars["Listings"].waitForExistence(timeout: 10))
        let posted = byId("listing.201")
        XCTAssertTrue(scrollTo(posted), "no posted listing row")
        XCTAssertTrue(posted.label.localizedCaseInsensitiveContains("Posted (simulated)"), posted.label)
        shot("2-listings")
        assertNoLiveOnEbay()

        // Approvals: 2 pending; approving the Aeron listing moves it to History.
        approvalsTab.tap()
        XCTAssertTrue(app.navigationBars["Approvals"].waitForExistence(timeout: 10))
        XCTAssertTrue(byId("approval.pending.300").waitForExistence(timeout: 10), "no pending Aeron approval")
        XCTAssertTrue(scrollTo(byId("approval.pending.85")), "no pending sofa approval")
        XCTAssertEqual(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'approval.pending.'")).count, 2)
        scrollToTop()
        shot("3-approvals-pending")
        let approve = byId("approval.approve.300")
        XCTAssertTrue(scrollTo(approve), "no Approve button on the Aeron approval")
        approve.tap()
        let decided = byId("approval.decided.300")
        XCTAssertTrue(scrollTo(decided), "approved Aeron listing never showed up in History")
        XCTAssertTrue(decided.label.contains("approved"), decided.label)
        XCTAssertTrue(waitGone(byId("approval.pending.300")), "Aeron approval still pending")
        shot("3-approvals-history")

        // The approved listing is posted, still simulated.
        listingsTab.tap()
        let aeron = byId("listing.200")
        XCTAssertTrue(scrollTo(aeron), "no Aeron listing row")
        XCTAssertTrue(waitFor(aeron, label: "posted (simulated)"), aeron.label)
        assertNoLiveOnEbay()

        // Shopping > Desk chair: the Craigslist Aeron is blocked; the Target chair checks out (simulated).
        shoppingTab.tap()
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 10))
        shot("4-shopping")
        let deskChair = byId("shopping.item.52")
        XCTAssertTrue(scrollTo(deskChair), "no Desk chair on the shopping list")
        deskChair.tap()
        let craigslist = byId("deal.76")
        XCTAssertTrue(scrollTo(craigslist), "no Craigslist Aeron deal")
        XCTAssertTrue(craigslist.label.contains("Aeron") && craigslist.label.contains("craigslist"), craigslist.label)
        let blocked = byId("deal.blocked.76")
        XCTAssertTrue(scrollTo(blocked), "Craigslist Aeron isn't blocked")
        XCTAssertTrue(blocked.label.localizedCaseInsensitiveContains("likely fraud"), blocked.label)
        XCTAssertFalse(byId("deal.choose.76").exists, "a fraud-blocked deal can be chosen")
        shot("5-desk-chair-deals")
        let target = byId("deal.choose.74")
        XCTAssertTrue(scrollTo(target), "no Choose button on the Target chair")
        target.tap()
        // Under the limit, Choose pays right away, so it asks first (an action sheet on iPhone).
        let pay = app.buttons.matching(NSPredicate(format: "label == 'Pay $79.99 to target'")).firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 5), "no confirm before paying for the Target chair")
        let railNote = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'SIMULATED: no real card is charged.'")).firstMatch
        XCTAssertTrue(railNote.waitForExistence(timeout: 2), "the confirm doesn't say the rail is simulated")
        shot("5b-confirm")
        pay.tap()
        let paid = app.staticTexts["Paid through the simulated Visa rail. No real card was charged."]
        XCTAssertTrue(scrollTo(paid, up: false), "no paid simulated checkout")
        let visa = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'visa.payment.' AND label CONTAINS 'simulated'")).firstMatch
        XCTAssertTrue(visa.waitForExistence(timeout: 5), "no simulated Visa payment row")
        XCTAssertTrue(visa.label.localizedCaseInsensitiveContains("paid"), visa.label)
        shot("6-desk-chair-paid")

        // Back to Spending: the new simulated Visa payment is logged.
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(spendingTab.waitForExistence(timeout: 10))
        spendingTab.tap()
        let newRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'payment.' AND label CONTAINS 'Mesh task chair'")).firstMatch
        XCTAssertTrue(scrollTo(newRow), "the Target chair payment isn't in Spending")
        XCTAssertTrue(newRow.label.contains(", simulated,"), newRow.label)
        shot("7-spending-new-payment")
    }

    /// #140 claimed Dynamic Type support: the largest accessibility text size, one read-only pass.
    func testCommerceScreensAtLargestAccessibilityText() {
        launchOfflineDemo(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        tourCommerceScreens(prefix: "a11y-xxxl")
    }

    /// #140 claimed dark-mode contrast: the same read-only pass in dark mode.
    func testCommerceScreensInDarkMode() {
        // `-AppleInterfaceStyle Dark` is ignored on iOS, and this alone doesn't take on the CI Simulator,
        // so CI also runs this test by itself after `simctl ui appearance dark`.
        XCUIDevice.shared.appearance = .dark
        addTeardownBlock { @MainActor in XCUIDevice.shared.appearance = .light }
        launchOfflineDemo()
        tourCommerceScreens(prefix: "dark")
    }

    // MARK: Helpers

    private func launchOfflineDemo(_ extra: [String] = []) {
        app = XCUIApplication()
        // Same launch as MooveSmokeTests: UserDefaults argument domain + fresh-install reset.
        app.launchArguments += ["-moove.backendKind", "fixture", "-moove.auth.guest", "YES"] + extra
        app.launchEnvironment["MOOVE_UI_TEST_RESET"] = "1"
        launchRetryingOnce()
        continueAfterFailure = false
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30), "tab bar")
    }

    /// Screenshots every commerce screen ("<prefix>-<screen>") and checks the key controls exist and
    /// are hittable. Read-only: nothing is approved or bought, so it stays short.
    private func tourCommerceScreens(prefix: String) {
        let sellBuy = app.tabBars.buttons["Sell & Buy"]
        XCTAssertTrue(sellBuy.waitForExistence(timeout: 10), "no Sell & Buy tab")
        select(tab: sellBuy)
        let tabs = ["Listings", "Shopping", "Approvals", "Spending"].map(segment)
        for s in tabs { XCTAssertTrue(s.waitForExistence(timeout: 10), "missing segment \(s)") }
        let (listingsTab, shoppingTab, approvalsTab, spendingTab) = (tabs[0], tabs[1], tabs[2], tabs[3])
        shot("\(prefix)-0-sell-and-buy")

        tapSegment(listingsTab)
        XCTAssertTrue(app.navigationBars["Listings"].waitForExistence(timeout: 10))
        shot("\(prefix)-1-listings")
        let posted = byId("listing.201")
        XCTAssertTrue(scrollTo(posted), "listing row not hittable")
        XCTAssertTrue(posted.label.localizedCaseInsensitiveContains("simulated"), posted.label)
        shot("\(prefix)-1-listings-simulated")

        tapSegment(shoppingTab)
        XCTAssertTrue(app.navigationBars["Shopping"].waitForExistence(timeout: 10))
        shot("\(prefix)-2-shopping")
        let deskChair = byId("shopping.item.52")
        XCTAssertTrue(scrollTo(deskChair), "Desk chair not hittable")
        deskChair.tap()
        XCTAssertTrue(scrollTo(byId("deal.blocked.76")), "Blocked: likely fraud not hittable")
        shot("\(prefix)-2-desk-chair-blocked")
        XCTAssertTrue(scrollTo(byId("deal.choose.74")), "Choose not hittable")
        shot("\(prefix)-2-desk-chair-choose")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()

        XCTAssertTrue(approvalsTab.waitForExistence(timeout: 10))
        tapSegment(approvalsTab)
        XCTAssertTrue(app.navigationBars["Approvals"].waitForExistence(timeout: 10))
        shot("\(prefix)-3-approvals")
        XCTAssertTrue(scrollTo(byId("approval.approve.300")), "Approve not hittable")
        shot("\(prefix)-3-approvals-approve")

        tapSegment(spendingTab)
        XCTAssertTrue(app.navigationBars["Spending"].waitForExistence(timeout: 10))
        shot("\(prefix)-4-spending")
        let simulated = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'payment.' AND label CONTAINS ', simulated,'")).firstMatch
        XCTAssertTrue(scrollTo(simulated), "SIMULATED payment row not hittable")
        shot("\(prefix)-4-spending-simulated")
        XCTAssertTrue(scrollTo(byId("payment.basescan.500")), "Basescan link not hittable")
        shot("\(prefix)-4-spending-basescan")
    }

    /// CI's simulator sometimes fails the first launch with "Application 'app.moove.Moove' does not
    /// have a process ID" after a slow (~90 s) boot. Only that launch failure is tolerated, once; any
    /// other issue during the first launch, or a second failed launch, still fails the test.
    private func launchRetryingOnce() {
        continueAfterFailure = true  // so an expected launch failure doesn't end the test; set false after
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { $0.compactDescription.contains("does not have a process ID") }
        XCTExpectFailure("CI simulator launch flake, retried once", options: options) {
            app.launch()
        }
        if app.state != .runningForeground {
            app.terminate()
            app.launch()
        }
    }

    /// On the iOS 26 Liquid Glass tab bar, a tap that lands while the app is still settling after
    /// launch is sometimes dropped (CI showed the app still on Scan, the "Sell & Buy" tab unselected).
    /// Tap, wait for the tab to report Selected, and tap again if it didn't take.
    private func select(tab: XCUIElement) {
        let selected = NSPredicate(format: "isSelected == true")
        for _ in 0..<3 where !tab.isSelected {
            tab.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: selected, object: tab)], timeout: 5)
        }
        XCTAssertTrue(tab.isSelected, "\(tab.label) tab never got selected")
    }

    private func segment(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, "\(title) ·")).firstMatch
    }

    /// The segment picker scrolls sideways (at large text sizes "Spending" starts off screen), so swipe
    /// it until the segment is fully on screen, then tap. Frames, not `isHittable`: that fails outright
    /// for an element with no on-screen point.
    private func tapSegment(_ s: XCUIElement) {
        let screen = app.windows.firstMatch.frame
        for _ in 0..<4 where !(s.frame.minX >= screen.minX && s.frame.maxX <= screen.maxX) {
            let y = s.frame.midY
            let mid = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screen.midX, dy: y))
            let dx = s.frame.minX > screen.midX ? -screen.width * 0.4 : screen.width * 0.4
            mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: dx, dy: 0)))
        }
        XCTAssertTrue(s.isHittable, "segment \(s.label) not hittable")
        s.tap()
    }

    private func byId(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Lazy stacks only build rows near the screen, so swipe until the element is on screen.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, up: Bool = true, swipes: Int = 12) -> Bool {
        if element.waitForExistence(timeout: 1), element.isHittable { return true }
        for direction in [up, !up] {
            for _ in 0..<swipes {
                if element.exists, element.isHittable { return true }
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction ? 0.7 : 0.35))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: direction ? 0.35 : 0.7))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            if element.exists, element.isHittable { return true }
        }
        return element.exists && element.isHittable
    }

    private func scrollToTop() {
        for _ in 0..<6 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        }
    }

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    private func waitFor(_ element: XCUIElement, label text: String, timeout: TimeInterval = 10) -> Bool {
        let has = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS[c] %@", text), object: element)
        return XCTWaiter().wait(for: [has], timeout: timeout) == .completed
    }

    /// Scrolls the whole Listings screen: no row may say "Live on eBay" (every demo listing is simulated).
    private func assertNoLiveOnEbay() {
        let live = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'Live on eBay'"))
        scrollToTop()
        for _ in 0..<5 {
            XCTAssertEqual(live.count, 0, "a simulated listing says Live on eBay")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertEqual(live.count, 0, "a simulated listing says Live on eBay")
        scrollToTop()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
