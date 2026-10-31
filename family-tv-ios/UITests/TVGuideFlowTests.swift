import XCTest

final class TVGuideFlowTests: XCTestCase {
    @MainActor func testDemoExplainsFourTVStatesWithoutARealTV() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launchEnvironment["FAMILYTV_UI_LANGUAGE"] = "zh-Hans"; app.launch()
        XCTAssertTrue(app.buttons["demoTVGuide"].waitForExistence(timeout: 8))
        capture("store-tv-01-today-with-illustration")
        app.buttons["demoTVGuide"].tap()
        XCTAssertTrue(app.pickers["tvExamplePicker"].exists || app.buttons["tvExamplePicker"].exists)
        capture("store-tv-02-watching")
        for name in ["store-tv-03-break", "store-tv-04-extra-time", "store-tv-05-parent-pause"] {
            let next = app.buttons["advanceTVExample"]
            for _ in 0..<4 where !next.isHittable { app.swipeUp() }
            XCTAssertTrue(next.isHittable)
            next.tap()
            for _ in 0..<3 where !app.descendants(matching: .any)["tvIllustration"].isHittable { app.swipeDown() }
            capture(name)
        }
        XCTAssertTrue(app.buttons["advanceTVExample"].exists)
    }

    @MainActor func testWelcomeHasTVGuideBeforeAccountSetup() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launchEnvironment["FAMILYTV_UI_LANGUAGE"] = "zh-Hans"; app.launch()
        app.tabBars.buttons["我的"].tap()
        let exit = app.buttons["退出演示模式"]
        for _ in 0..<5 where !exit.isHittable { app.swipeUp() }
        exit.tap(); app.buttons["确认退出"].tap()
        let guide = app.buttons["welcomeTVGuide"]
        for _ in 0..<4 where !guide.isHittable { app.swipeUp() }
        XCTAssertTrue(guide.isHittable)
        guide.tap()
        XCTAssertTrue(app.buttons["advanceTVExample"].waitForExistence(timeout: 5))
        capture("store-tv-06-introduction")
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
