import XCTest

final class WelcomeLayoutTests: XCTestCase {
    @MainActor func testWelcomeFitsWithoutScrollingInAllFourLanguages() {
        for language in ["zh-Hans", "en", "ko", "ja"] {
            let app = XCUIApplication(); app.launchArguments = ["--demo"]
            app.launchEnvironment["FAMILYTV_UI_LANGUAGE"] = language; app.launch()
            app.buttons["globalDemoExit"].tap()
            XCTAssertTrue(app.buttons["connectFamily"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["enterDemo"].isHittable, language)
            XCTAssertTrue(app.buttons["welcomeTVGuide"].isHittable, language)
            XCTAssertTrue(app.buttons["welcomeLanguageSettings"].isHittable, language)
            XCTAssertEqual(app.buttons["connectFamily"].frame.minY, app.buttons["enterDemo"].frame.minY, accuracy: 2, language)
            let titles = ["chart.bar.fill", "moon.fill", "hand.raised.fill"].map { app.staticTexts["welcomeFeatureTitle." + $0] }
            XCTAssertEqual(titles[0].frame.minX, titles[1].frame.minX, accuracy: 1, language)
            XCTAssertEqual(titles[1].frame.minX, titles[2].frame.minX, accuracy: 1, language)
            XCTAssertEqual(app.staticTexts["welcomeTagline"].frame.minX, app.staticTexts["welcomeCompatibility"].frame.minX, accuracy: 1, language)
            XCTAssertGreaterThanOrEqual(titles[1].frame.minY - app.staticTexts["welcomeFeatureDetail.chart.bar.fill"].frame.maxY, 20, language)
            let scroll = app.scrollViews.firstMatch
            let before = app.buttons["welcomeTVGuide"].frame
            let hero = app.descendants(matching: .any)["welcomeHero"]
            let heroBefore = hero.frame
            scroll.swipeUp(velocity: .slow)
            XCTAssertEqual(before.minY, app.buttons["welcomeTVGuide"].frame.minY, accuracy: 2, language)
            XCTAssertEqual(heroBefore.minY, hero.frame.minY, accuracy: 2, language)
            XCTAssertGreaterThanOrEqual(hero.frame.minY, app.navigationBars.firstMatch.frame.maxY, language)
            if language == "en" {
                for line in ["Agree on TV time, together.", "Track time in supported apps.", "Set viewing limits and break times.", "Allow extra time when needed."] {
                    XCTAssertTrue(app.staticTexts[line].exists)
                    XCTAssertLessThan(app.staticTexts[line].frame.height, 26, line)
                }
                XCTAssertEqual(app.buttons["welcomeTVGuide"].label, "TV preview")
                XCTAssertEqual(app.buttons["connectFamily"].label, "Sign in")
            }
            capture("welcome-\(language)")
            app.terminate()
        }
    }

    @MainActor func testExitDemoIsAvailableAcrossTabsAndModalSheets() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        app.launchEnvironment["FAMILYTV_UI_LANGUAGE"] = "zh-Hans"; app.launch()
        for tab in ["今天", "规则", "记录", "我的"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.buttons["globalDemoExit"].isHittable, tab)
        }
        app.tabBars.buttons["今天"].tap()
        capture("demo-global-exit")
        for _ in 0..<4 where !app.buttons["grantTime"].isHittable { app.swipeUp() }
        app.buttons["grantTime"].tap()
        let exit = app.buttons.matching(identifier: "globalDemoExit").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(exit); capture("demo-sheet-exit"); exit?.tap()
        XCTAssertTrue(app.buttons["connectFamily"].waitForExistence(timeout: 5))
        app.buttons["enterDemo"].tap()
        app.tabBars.buttons["规则"].tap()
        for _ in 0..<4 where !app.buttons["editRules"].isHittable { app.swipeUp() }
        app.buttons["editRules"].tap()
        let ruleExit = app.buttons.matching(identifier: "globalDemoExit").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(ruleExit); ruleExit?.tap()
        XCTAssertTrue(app.buttons["connectFamily"].waitForExistence(timeout: 5))
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
