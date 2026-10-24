import XCTest

/// Simulator smoke tests: tap through the screens on the offline demo backend
/// (`moove.backendKind = fixture`, no network). RoomPlan and Object Capture
/// need a LiDAR device, so the live scan flow is not covered here.
///
/// Every launch starts from a fresh install's defaults (`MOOVE_UI_TEST_RESET`),
/// and each test attaches screenshots of the screens it reaches.
@MainActor
final class MooveSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    // MARK: Tests

    func testLoginThenContinueAsGuest() {
        launch(guest: false)
        let guest = app.buttons["login.guest"]
        XCTAssertTrue(guest.waitForExistence(timeout: 10), "login screen")
        XCTAssertTrue(app.staticTexts["Moove"].exists)
        snap("01-login")
        guest.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10), "tab bar after guest login")
        snap("01-tabs")
        // A fresh install opens on the Scan tab.
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: 5), "starts on Scan")
    }

    func testReviewNeedsYouFirstAndSwipeToKeep() {
        launch()
        openTab("Review")
        let needsYou = sectionHeader("Needs you · 2")
        let keep = sectionHeader("Keep · 3")
        XCTAssertTrue(needsYou.waitForExistence(timeout: 10), "Needs you section")
        XCTAssertTrue(keep.exists, "Keep section")
        XCTAssertLessThan(needsYou.frame.minY, keep.frame.minY, "Needs you comes first")
        snap("02-review")

        let quilt = row(startingWith: "Grandma")
        XCTAssertTrue(quilt.exists)
        quilt.swipeRight()
        let keepAction = app.buttons["Keep"].firstMatch
        XCTAssertTrue(keepAction.waitForExistence(timeout: 5), "Keep swipe action")
        snap("02-swipe")
        keepAction.tap()
        XCTAssertTrue(sectionHeader("Needs you · 1").waitForExistence(timeout: 5))
        XCTAssertTrue(sectionHeader("Keep · 4").waitForExistence(timeout: 5), "quilt rack moved to Keep")
        let movedQuilt = row(startingWith: "Grandma")
        XCTAssertGreaterThan(movedQuilt.frame.minY, sectionHeader("Keep · 4").frame.minY, "quilt rack is under Keep")
        snap("02-kept")

        row(startingWith: "Framed photos").tap()
        let picker = app.descendants(matching: .any)["item.disposition"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "disposition picker on item detail")
        XCTAssertTrue(app.navigationBars["Framed photos"].exists)
        snap("02-item-detail")
        picker.tap()
        XCTAssertTrue(app.buttons["Donate"].waitForExistence(timeout: 5), "disposition menu opens")
        snap("02-disposition-menu")
    }

    func testLoadDemoScanShowsRoomInInventory() {
        launch()
        openTab("Scan")
        let load = app.buttons["Load demo scan"]
        XCTAssertTrue(load.waitForExistence(timeout: 10))
        snap("03-scan")
        load.tap()
        // The app switches to Inventory once the import lands.
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: 10), "jumped to Inventory")
        XCTAssertTrue(scrollTo(text(matching: "Demo bedroom")), "new room in Inventory")
        snap("03-inventory")
    }

    func testRoomIn3DAndPlan() {
        launch()
        openTab("Inventory")
        let view3D = app.buttons["View room in 3D"].firstMatch
        XCTAssertTrue(view3D.waitForExistence(timeout: 10))
        view3D.tap()

        let model = app.descendants(matching: .any)["room.model"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 15), "3D model view")
        sleep(2)  // let RealityKit draw a frame
        snap("04-room-3d")

        app.buttons["Plan"].firstMatch.tap()
        let plan = app.descendants(matching: .any)["room.plan"].firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 5), "floor plan view")
        snap("04-room-plan")

        // Tap around the plan until a piece of furniture is selected.
        let card = app.descendants(matching: .any)["room.selection"].firstMatch
        search: for y in stride(from: 0.25, through: 0.75, by: 0.1) {
            for x in stride(from: 0.25, through: 0.75, by: 0.1) {
                plan.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
                if card.waitForExistence(timeout: 1) { break search }
            }
        }
        XCTAssertTrue(card.exists, "tapping the plan selects furniture")
        snap("04-room-plan-selected")

        app.descendants(matching: .any)["room.display"].firstMatch.tap()
        let labels = app.buttons["Labels"].firstMatch
        XCTAssertTrue(labels.waitForExistence(timeout: 5), "display menu")
        snap("04-display-menu")
        labels.tap()
        XCTAssertTrue(plan.waitForExistence(timeout: 5))
        snap("04-room-plan-no-labels")
    }

    func testShareAndJoinRoom() {
        launch()
        openTab("Inventory")
        let share = app.buttons["Share room"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        let code = app.staticTexts["share.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5), "join code shown")
        let shown = code.label.replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(shown.count, 6, "6-character code, got \(code.label)")
        snap("05-share")
        app.buttons["Done"].firstMatch.tap()

        join("DEMO42")
        XCTAssertTrue(scrollTo(text(containing: "Shared by Sam")), "roommate's room appears")
        XCTAssertTrue(text(matching: "Living room").exists)
        snap("05-joined")

        join("WRONG9", expectDismiss: false)
        let error = app.descendants(matching: .any)["join.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), "wrong code shows an error")
        XCTAssertTrue(error.label.contains("No room has that code"), error.label)
        snap("05-join-error")
    }

    func testSettingsShowsDataSourceAndSignsOut() {
        launch()
        let settings = app.navigationBars.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(text(containing: "Offline demo (fixtures)").exists, "data source shown")
        XCTAssertTrue(text(containing: "Guest").exists)
        snap("06-settings")
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["login.guest"].waitForExistence(timeout: 10), "back to login")
        snap("06-signed-out")
    }

    // MARK: Helpers

    private func launch(guest: Bool = true) {
        continueAfterFailure = false
        app = XCUIApplication()
        // UserDefaults argument domain: overrides what the app has stored.
        app.launchArguments += ["-moove.backendKind", "fixture"]
        if guest { app.launchArguments += ["-moove.auth.guest", "YES"] }
        app.launchEnvironment["MOOVE_UI_TEST_RESET"] = "1"
        app.launch()
        if guest {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15), "tab bar")
        }
    }

    /// Tabs past the first four live under "More" on iPhone.
    private func openTab(_ name: String) {
        let tabBar = app.tabBars.firstMatch
        let tab = tabBar.buttons[name]
        if tab.exists {
            tab.tap()
        } else {
            tabBar.buttons["More"].tap()
            if !app.navigationBars[name].waitForExistence(timeout: 1) {
                app.staticTexts[name].firstMatch.tap()
            }
        }
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5), "\(name) tab")
    }

    private func join(_ code: String, expectDismiss: Bool = true) {
        app.buttons["Join a room"].firstMatch.tap()
        let field = app.textFields["join.code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(code)
        XCTAssertTrue(app.buttons["join.submit"].isEnabled, "Join enabled for a 6-character code")
        snap("05-join-\(code)")
        field.typeText("\n")  // submits, same as the Join button
        if expectDismiss {
            XCTAssertTrue(field.waitForNonExistence(timeout: 5), "join sheet closes")
        }
    }

    /// Swipes up until `element` is on screen (lists below the fold aren't loaded yet).
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        _ = element.waitForExistence(timeout: 2)
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) { app.swipeUp() }
        return element.exists && element.isHittable
    }

    private func sectionHeader(_ title: String) -> XCUIElement { text(matching: title) }

    private func text(matching s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", s)).firstMatch
    }

    private func text(containing s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch
    }

    private func row(startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
