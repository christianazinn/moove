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
        XCTAssertTrue(guest.waitForExistence(timeout: slow), "login screen")
        snap("01-login")
        guest.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: slow), "tab bar after guest login")
        for tab in ["Scan", "Items", "Sell & Buy", "Move", "Summary"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "\(tab) tab")
        }
        // A fresh install opens on the Scan tab.
        XCTAssertTrue(app.navigationBars["Scan"].waitForExistence(timeout: slow), "starts on Scan")
        snap("01-tabs")
    }

    func testReviewNeedsYouFirstAndSwipeToKeep() {
        launch()
        open(tab: "Items", segment: "Review")
        let needsYou = text(matching: "Needs you")
        let keep = text(matching: "Keep")
        XCTAssertTrue(needsYou.waitForExistence(timeout: slow), "Needs you section")
        XCTAssertTrue(keep.exists, "Keep section")
        XCTAssertLessThan(needsYou.frame.minY, keep.frame.minY, "Needs you comes first")
        snap("02-review")

        let quilt = row(startingWith: "Grandma")
        XCTAssertTrue(quilt.exists)
        XCTAssertLessThan(quilt.frame.minY, keep.frame.minY, "quilt rack starts in Needs you")
        quilt.swipeRight()
        let keepAction = app.buttons["Keep"].firstMatch
        XCTAssertTrue(keepAction.waitForExistence(timeout: slow), "Keep swipe action")
        snap("02-swipe")
        keepAction.tap()

        // Moved: now below the Keep header, and marked as the user's call.
        sleep(1)  // list animation
        XCTAssertTrue(text(containing: "Need you, 1").exists, "one item still needs you")
        let moved = row(startingWith: "Grandma")
        XCTAssertTrue(scrollTo(moved), "quilt rack still listed")
        XCTAssertTrue(moved.label.contains("Keep") && moved.label.contains("You decided"), moved.label)
        let keepHeader = text(matching: "Keep")
        if keepHeader.exists {
            XCTAssertGreaterThan(moved.frame.minY, keepHeader.frame.minY, "quilt rack moved under Keep")
        }
        snap("02-kept")
        // Back to the top for the next row.
        for _ in 0..<4 { app.swipeDown() }

        row(startingWith: "Framed photos").tap()
        let picker = app.descendants(matching: .any)["item.disposition"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: slow), "disposition picker on item detail")
        XCTAssertTrue(app.navigationBars["Framed photos"].exists)
        for choice in ["Keep", "Sell", "Donate", "Trash"] {
            XCTAssertTrue(picker.buttons[choice].exists, "\(choice) choice")
        }
        // Demo items have no photo yet, so the detail offers one (vision runs on it).
        XCTAssertTrue(app.buttons["Add photo"].exists, "Add photo on an item without a photo")
        snap("02-item-detail")
    }

    /// #180: objects the import skipped are reported on the finished screen.
    func testFinishedScreenReportsSkippedObjects() {
        launch(environment: ["MOOVE_DEMO_BAD_OBJECTS": "1"])
        open(tab: "Scan")
        let load = app.buttons["Load demo scan"]
        XCTAssertTrue(scrollTo(load), "Load demo scan button")
        load.tap()
        XCTAssertTrue(app.buttons["See inventory"].waitForExistence(timeout: slow), "scan finished screen")
        let notice = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "2 objects looked wrong")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: slow), "skipped-objects notice")
        notice.tap()
        XCTAssertTrue(text(containing: "width 40 m").waitForExistence(timeout: slow), "skip reasons listed")
        snap("03-scan-skipped")
    }

    func testLoadDemoScanShowsRoomInInventory() {
        launch()
        open(tab: "Scan")
        let load = app.buttons["Load demo scan"]
        XCTAssertTrue(scrollTo(load), "Load demo scan button")
        snap("03-scan")
        load.tap()
        // Same finished screen as a real scan, then on to Inventory.
        let done = app.buttons["See inventory"]
        XCTAssertTrue(done.waitForExistence(timeout: slow), "scan finished screen")
        snap("03-scan-finished")
        done.tap()
        XCTAssertTrue(app.navigationBars["Inventory"].waitForExistence(timeout: slow), "jumped to Inventory")
        XCTAssertTrue(scrollTo(text(matching: "Demo bedroom")), "new room in Inventory")
        snap("03-inventory")
        // Offline photo sweep (#181): the room photos "find" a guitar RoomPlan missed.
        let guitar = text(matching: "Acoustic guitar")
        XCTAssertTrue(guitar.waitForExistence(timeout: slow) || scrollTo(guitar), "item added by the photo sweep")
        snap("03-inventory-sweep")
    }

    func testRoomIn3DAndPlan() {
        launch()
        open(tab: "Items", segment: "Inventory")
        let view3D = app.buttons["View room in 3D"].firstMatch
        XCTAssertTrue(view3D.waitForExistence(timeout: slow))
        view3D.tap()

        let model = app.descendants(matching: .any)["room.model"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: slow), "3D model view")
        sleep(2)  // let RealityKit draw a frame
        snap("04-room-3d")

        app.buttons["Plan"].firstMatch.tap()
        let plan = app.descendants(matching: .any)["room.plan"].firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: slow), "floor plan view")
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
        XCTAssertTrue(labels.waitForExistence(timeout: slow), "display menu")
        snap("04-display-menu")
        labels.tap()
        XCTAssertTrue(plan.waitForExistence(timeout: slow))
        snap("04-room-plan-no-labels")
    }

    func testShareAndJoinRoom() {
        launch()
        open(tab: "Items", segment: "Inventory")
        let share = app.buttons["Share Bedroom"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: slow))
        share.tap()
        let code = app.staticTexts["share.code"]
        XCTAssertTrue(code.waitForExistence(timeout: slow), "join code shown")
        let shown = code.label.replacingOccurrences(of: "Join code", with: "").replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(shown.count, 6, "6-character code, got \(code.label)")
        snap("05-share")
        app.buttons["Done"].firstMatch.tap()

        join("DEMO42")
        XCTAssertTrue(scrollTo(text(containing: "Shared by Sam")), "roommate's room appears")
        XCTAssertTrue(text(matching: "Living room").exists)
        snap("05-joined")

        join("WRONG9", expectDismiss: false)
        let error = app.descendants(matching: .any)["join.error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: slow), "wrong code shows an error")
        XCTAssertTrue(error.label.contains("No room has that code"), error.label)
        snap("05-join-error")
    }

    func testSettingsShowsDataSourceAndSignsOut() {
        launch()
        let settings = app.navigationBars.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: slow))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: slow))
        let fixture = app.buttons["settings.dataSource.fixture"]
        XCTAssertTrue(scrollTo(fixture), "data source shown")
        XCTAssertTrue(fixture.label.contains("Offline demo"), fixture.label)
        XCTAssertTrue(fixture.isSelected, "offline demo is the selected data source")
        snap("06-settings")
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(scrollTo(signOut, down: false), "Sign out button")
        XCTAssertTrue(text(containing: "Guest").exists)
        signOut.tap()
        XCTAssertTrue(app.buttons["login.guest"].waitForExistence(timeout: slow), "back to login")
        snap("06-signed-out")
    }

    // MARK: Helpers

    /// Generous waits: the CI Simulator runner takes ~12 s to go idle after launch and is
    /// slower per screen (#155). `waitForExistence` returns as soon as the element shows up.
    private let slow: TimeInterval = 30

    private func launch(guest: Bool = true, environment: [String: String] = [:]) {
        continueAfterFailure = false
        app = XCUIApplication()
        // UserDefaults argument domain: overrides what the app has stored.
        app.launchArguments += ["-moove.backendKind", "fixture"]
        if guest { app.launchArguments += ["-moove.auth.guest", "YES"] }
        app.launchEnvironment["MOOVE_UI_TEST_RESET"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        if guest {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: slow), "tab bar")
        }
    }

    /// Picks a tab, then (for grouped tabs) a segment of its pill picker.
    private func open(tab: String, segment: String? = nil) {
        app.tabBars.buttons[tab].tap()
        if let segment {
            let pill = app.buttons[segment].firstMatch
            XCTAssertTrue(pill.waitForExistence(timeout: slow), "\(segment) segment")
            pill.tap()
        }
        let title = segment ?? tab
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: slow), "\(title) screen")
    }

    private func join(_ code: String, expectDismiss: Bool = true) {
        app.buttons["Join a room"].firstMatch.tap()
        let field = app.textFields["join.code"]
        XCTAssertTrue(field.waitForExistence(timeout: slow))
        field.tap()
        field.typeText(code)
        XCTAssertTrue(app.buttons["join.submit"].isEnabled, "Join enabled for a 6-character code")
        snap("05-join-\(code)")
        field.typeText("\n")  // submits, same as the Join button
        if expectDismiss {
            XCTAssertTrue(field.waitForNonExistence(timeout: slow), "join sheet closes")
        }
    }

    /// Swipes until `element` is on screen (lazy lists don't load rows below the fold).
    private func scrollTo(_ element: XCUIElement, down: Bool = true, maxSwipes: Int = 8) -> Bool {
        _ = element.waitForExistence(timeout: 2)
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            if down { app.swipeUp() } else { app.swipeDown() }
        }
        return element.exists && element.isHittable
    }

    private func text(matching s: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", s)).firstMatch
    }

    private func text(containing s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", s)).firstMatch
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
