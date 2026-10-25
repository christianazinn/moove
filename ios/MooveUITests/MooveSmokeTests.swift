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

    func testReviewDeckSwipeToKeepAndUndo() {
        launch()
        open(tab: "Items", segment: "Review")
        // The flip cards hold the whole move (12 demo items); the seeded Bedroom's one
        // sentimental item (#243) needs you, so it's on top.
        let deck = byId("review.deck")
        XCTAssertTrue(deck.waitForExistence(timeout: slow), "flip cards")
        XCTAssertTrue(byId("review.deck.progress").label.contains("1 of 12"), byId("review.deck.progress").label)
        let card = byId("review.card.18")
        XCTAssertTrue(card.exists, "guitar card on top")
        XCTAssertTrue(card.label.hasPrefix("Yamaha acoustic guitar, needs you"), card.label)
        let keepPile = byId("review.pile.keep")
        XCTAssertTrue(keepPile.exists, "Keep pile on the board")
        XCTAssertLessThan(deck.frame.minY, keepPile.frame.minY, "the cards lead")
        for d in ["keep", "sell", "donate", "trash"] {
            XCTAssertTrue(byId("review.deck.\(d)").exists, "\(d) button under the card")
        }
        snap("02-review")

        // Tap flips the card (the details side); swiping still works.
        card.tap()
        // Swipe right = Keep: the next card comes up.
        card.swipeRight()
        XCTAssertTrue(byId("review.deck.progress").waitForLabel(containing: "2 of 12", timeout: slow), byId("review.deck.progress").label)
        XCTAssertFalse(byId("review.card.18").exists, "guitar card gone")
        snap("02-swiped")

        // Undo puts it back on top; the Keep button decides it again.
        byId("review.undo").firstMatch.tap()
        XCTAssertTrue(byId("review.card.18").waitForExistence(timeout: slow), "Undo brings the card back")
        byId("review.deck.keep").tap()
        XCTAssertTrue(byId("review.deck.progress").waitForLabel(containing: "2 of 12", timeout: slow), "kept again")

        // On the board: under Keep, marked as the user's call.
        let keep = byId("review.pile.keep")
        XCTAssertTrue(scrollTo(keep), "Keep tile")
        XCTAssertTrue(keep.label.contains("8 items"), keep.label)
        keep.tap()
        let moved = byId("review.item.18")
        XCTAssertTrue(scrollTo(moved), "guitar listed under Keep")
        XCTAssertTrue(moved.label.contains("You decided"), moved.label)
        snap("02-kept")

        let lamp = byId("review.item.14")
        XCTAssertTrue(scrollTo(lamp), "Floor lamp under Keep")
        lamp.tap()
        let picker = app.descendants(matching: .any)["item.disposition"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: slow), "disposition picker on item detail")
        XCTAssertTrue(app.navigationBars["Floor lamp"].exists)
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

    /// An item nobody could name shows under Review's "Needs a name"; renaming it from Item
    /// detail's Fix it takes it off the list.
    func testNameAnUnidentifiedItemFromReview() {
        launch(environment: ["MOOVE_DEMO_UNNAMED": "1"])
        open(tab: "Scan")
        let load = app.buttons["Load demo scan"]
        XCTAssertTrue(scrollTo(load), "Load demo scan button")
        load.tap()
        XCTAssertTrue(app.buttons["See inventory"].waitForExistence(timeout: slow), "scan finished screen")
        app.buttons["See inventory"].tap()
        open(tab: "Items", segment: "Review")
        let header = text(matching: "Needs a name")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'review.unnamed.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: slow), "unnamed item row under Needs a name")
        XCTAssertTrue(header.exists, "Needs a name header")
        // The deck card takes drags in the middle of the screen, so scroll from the page title.
        let title = text(matching: "Your call.")
        for _ in 0..<4 where !row.isHittable && title.exists {
            let from = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)))
        }
        XCTAssertTrue(scrollTo(row), "unnamed item row on screen")
        XCTAssertTrue(row.label.contains("Other"), row.label)
        snap("07-needs-a-name")
        row.tap()

        let field = app.textFields["item.fix.name"]
        XCTAssertTrue(scrollTo(field), "Fix it name field on item detail")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Record crate")
        let save = app.buttons["item.fix.saveName"]
        XCTAssertTrue(save.waitForExistence(timeout: slow), "Save name")
        save.tap()
        XCTAssertTrue(app.navigationBars["Record crate"].waitForExistence(timeout: slow), "renamed on item detail")
        snap("07-renamed")
        app.navigationBars["Record crate"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Review"].waitForExistence(timeout: slow), "back on Review")
        XCTAssertTrue(header.waitForNonExistence(timeout: slow), "Needs a name is empty once it's named")
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
        // Offline photo sweep (#181): the room photos "find" a plant RoomPlan missed.
        let plant = text(matching: "Potted monstera")
        XCTAssertTrue(plant.waitForExistence(timeout: slow) || scrollTo(plant), "item added by the photo sweep")
        XCTAssertTrue(text(containing: "from room photos").exists, "sweep item is labeled as found in room photos")
        snap("03-inventory-sweep")
    }

    func testRoomIn3DAndPlan() {
        launch()
        open(tab: "Items", segment: "Inventory")
        let view3D = app.buttons["View room in 3D"].firstMatch
        XCTAssertTrue(view3D.waitForExistence(timeout: slow))
        view3D.tap()

        // Opens on the voxel dollhouse (#236), the app's one 3D look for items.
        let voxel = app.descendants(matching: .any)["room.voxel"].firstMatch
        XCTAssertTrue(voxel.waitForExistence(timeout: slow), "voxel dollhouse view")
        sleep(3)  // let RealityKit draw a frame
        snap("04-room-voxel")

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

    func testDeleteItemFromInventory() {
        launch()
        open(tab: "Items", segment: "Inventory")
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.item.'"))
        let first = rows.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: slow), "an item row")
        let id = first.identifier.replacingOccurrences(of: "inventory.item.", with: "")
        let name = first.label
        first.press(forDuration: 1.2)
        let delete = app.buttons["inventory.delete.\(id)"]
        XCTAssertTrue(delete.waitForExistence(timeout: slow), "Delete item in the long-press menu")
        snap("06-inventory-menu")
        delete.tap()
        let confirm = app.buttons["inventory.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: slow), "asks before deleting")
        snap("06-inventory-confirm")
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inventory.item.\(id)"].waitForNonExistence(timeout: slow),
                      "row gone after delete: \(name)")
        snap("06-inventory-deleted")
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
        // Appearance: System by default (UI-test reset); Dark sticks, then back to System.
        let system = app.buttons["settings.appearance.system"]
        XCTAssertTrue(scrollTo(system, down: false), "appearance choices shown")
        XCTAssertTrue(system.isSelected, "System is the default appearance")
        app.buttons["settings.appearance.dark"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected, "Dark selected")
        snap("06-settings-dark")
        system.tap()
        XCTAssertTrue(system.isSelected, "back to System")
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

    func testAddItemByHand() {
        launch()
        open(tab: "Items", segment: "Inventory")
        let add = app.buttons["inventory.addItem"]
        XCTAssertTrue(add.waitForExistence(timeout: slow), "Add item button")
        add.tap()
        let name = app.textFields["addItem.name"]
        XCTAssertTrue(name.waitForExistence(timeout: slow), "Add item sheet")
        name.tap()
        name.typeText("Road bike")
        snap("02-add-item")
        app.buttons["addItem.save"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: slow), "sheet closes")
        XCTAssertTrue(scrollTo(text(matching: "Road bike")), "new item in Inventory")
        snap("02-add-item-added")
    }

    func testInventoryFocusesOnPickedRooms() {
        launch()
        // A second room: the demo scan, whose photo sweep adds a potted monstera.
        open(tab: "Scan")
        let load = app.buttons["Load demo scan"]
        XCTAssertTrue(scrollTo(load), "Load demo scan button")
        load.tap()
        let done = app.buttons["See inventory"]
        XCTAssertTrue(done.waitForExistence(timeout: slow), "scan finished screen")
        done.tap()
        let plant = text(matching: "Potted monstera")
        XCTAssertTrue(plant.waitForExistence(timeout: slow) || scrollTo(plant), "sweep item in Inventory")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        // Focus on the original Bedroom (room 1): the demo bedroom's plant drops out.
        let bedroom = app.buttons["inventory.focus.1"]
        XCTAssertTrue(bedroom.waitForExistence(timeout: slow) || scrollTo(bedroom, down: false), "Bedroom card")
        bedroom.tap()
        XCTAssertTrue(app.buttons["inventory.showAllRooms"].waitForExistence(timeout: slow), "focus is on")
        XCTAssertTrue(plant.waitForNonExistence(timeout: slow), "other room's items are hidden")
        snap("02-inventory-focus")
        app.buttons["inventory.showAllRooms"].tap()
        XCTAssertTrue(plant.waitForExistence(timeout: slow) || scrollTo(plant), "every room again")
    }

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

    private func byId(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    /// Waits until the element's label contains `text` (e.g. the deck's "2 of 12").
    func waitForLabel(containing text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}
