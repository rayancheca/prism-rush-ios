import XCTest

/// Real interaction tests — they drive the actual UI (tap buttons, assert state transitions). This
/// is the coverage gap that let the reported bugs ship: screenshots proved rendering, not behavior.
final class InteractionUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    private func launch(_ env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }

    /// A1 — dying must offer a way back to the menu, and it must actually return there.
    func testBackToMenuFromGameOver() {
        let app = launch(["PR_DEMO": "1"])   // autoplay, then force-die ~6s
        let back = app.buttons["backToMenuButton"]
        XCTAssertTrue(back.waitForExistence(timeout: 25), "BACK TO MENU should appear on game over")
        back.tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 6),
                      "the menu PLAY button should appear after BACK TO MENU")
    }

    /// A3 — equipping a skin must reflect as equipped immediately (no close/reopen).
    func testEquipSkinUpdatesImmediately() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        app.buttons["charactersButton"].tap()
        let ember = app.buttons["skin_ember"]
        XCTAssertTrue(ember.waitForExistence(timeout: 6), "characters grid should appear")
        XCTAssertEqual(app.buttons["skin_default"].value as? String, "equipped", "default starts equipped")

        ember.tap()
        var emberEquipped = false
        for _ in 0..<25 {
            if (app.buttons["skin_ember"].value as? String) == "equipped" { emberEquipped = true; break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(emberEquipped, "ember should show as equipped immediately after tapping")
        XCTAssertNotEqual(app.buttons["skin_default"].value as? String, "equipped",
                          "default should no longer be equipped after switching to ember")
    }

    /// Navigation — every hub button opens its screen, and back returns to the menu (covers B8/Worlds).
    func testHubNavigation() {
        let app = launch(["PR_DEMOPROFILE": "1"])
        let routes: [(String, String)] = [
            ("worldsButton", "Worlds"),
            ("charactersButton", "Characters"),
            ("shopButton", "Shop"),
            ("profileButton", "Profile"),
        ]
        for (button, title) in routes {
            XCTAssertTrue(app.buttons[button].waitForExistence(timeout: 6), "\(button) should exist on the menu")
            app.buttons[button].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 6), "\(button) should open the \(title) screen")
            app.buttons["closeSheetButton"].tap()
            XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 6), "back should return to the menu from \(title)")
        }
    }
}
