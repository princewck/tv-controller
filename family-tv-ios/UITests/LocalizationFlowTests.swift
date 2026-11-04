import XCTest

final class LocalizationFlowTests: XCTestCase {
    @MainActor func testManualLanguageChoicePersistsAcrossLaunches() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        openLanguageSettings(app)
        app.buttons["English"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 8))
        openLanguageSettings(app)
        app.buttons["中文"].tap()
        XCTAssertTrue(app.tabBars.buttons["今天"].waitForExistence(timeout: 5))
    }

    @MainActor private func openLanguageSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["demoTVGuide"].waitForExistence(timeout: 8))
        app.tabBars.buttons.element(boundBy: 3).tap()
        let link = app.buttons["languageSettings"]
        for _ in 0..<5 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable); link.tap()
    }

    @MainActor func testFourLanguagesRenderDemoAndTVGuide() {
        for (language, today, settings, languageLabel, breaksLabel) in [
            ("zh-Hans", "今天", "我的", "语言", "少打扰的休息安排"),
            ("en", "Today", "My family", "Language", "Plan breaks with fewer interruptions"),
            ("ko", "오늘", "우리 가족", "언어", "방해를 줄이는 휴식 계획"),
            ("ja", "今日", "家族アカウント", "言語", "中断を減らす休憩の予定"),
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo"]
            app.launchEnvironment["FAMILYTV_UI_LANGUAGE"] = language
            app.launch()
            XCTAssertTrue(app.buttons["demoTVGuide"].waitForExistence(timeout: 8), language)
            XCTAssertTrue(app.tabBars.buttons[today].exists, language)
            capture("\(language)-today")
            app.buttons["demoTVGuide"].tap()
            XCTAssertTrue(app.buttons["advanceTVExample"].waitForExistence(timeout: 5))
            capture("\(language)-tv-guide")
            app.tabBars.buttons[settings].tap()
            let languageLink = app.buttons["languageSettings"]
            for _ in 0..<5 where !languageLink.isHittable { app.swipeUp() }
            XCTAssertTrue(languageLink.isHittable, language)
            languageLink.tap()
            XCTAssertTrue(app.navigationBars[languageLabel].exists, language)
            XCTAssertTrue(app.buttons["한국어"].exists)
            capture("\(language)-language")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let link = app.buttons[breaksLabel]
            for _ in 0..<5 where !link.isHittable { app.swipeUp() }
            if link.isHittable { link.tap(); capture("\(language)-breaks") }
            else { XCTFail("Missing breaks settings: \(language)") }
            app.terminate()
        }
    }

    @MainActor private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
