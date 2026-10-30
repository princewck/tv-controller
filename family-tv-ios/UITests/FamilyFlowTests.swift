import XCTest

final class FamilyFlowTests: XCTestCase {
    @MainActor func testDemoGrantAndRulesFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["演示模式 · 所有数据均为示例"].waitForExistence(timeout: 10))
        capture(app, name: "store-01-today")
        app.buttons["grantTime"].tap()
        app.buttons["confirmGrant"].tap()
        for _ in 0..<3 where !app.staticTexts["演示：已给予 15 分钟临时额度。"].exists { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["演示：已给予 15 分钟临时额度。"].waitForExistence(timeout: 5))
        app.tabBars.buttons["规则"].tap()
        XCTAssertTrue(app.navigationBars["观看规则"].waitForExistence(timeout: 5))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["演示模式 · 所有数据均为示例"].waitForExistence(timeout: 5))
        capture(app, name: "store-02-rules")
        for _ in 0..<3 where !app.buttons["editRules"].exists { app.swipeUp() }
        app.buttons["editRules"].tap()
        XCTAssertTrue(app.navigationBars["编辑规则"].waitForExistence(timeout: 5))
        app.buttons["saveRules"].tap()
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.staticTexts["本周合计"].waitForExistence(timeout: 5))
        revealDemoBanner(app)
        capture(app, name: "store-03-history-week")
        app.buttons["30 天"].tap()
        XCTAssertTrue(app.staticTexts["近 30 天合计"].waitForExistence(timeout: 5))
        revealDemoBanner(app)
        capture(app, name: "store-04-history-month")
    }
}

extension FamilyFlowTests {
    @MainActor private func revealDemoBanner(_ app: XCUIApplication) {
        let banner = app.staticTexts["演示模式 · 所有数据均为示例"]
        for _ in 0..<3 where !banner.isHittable { app.swipeDown() }
        XCTAssertTrue(banner.isHittable)
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor func testFourStepInstallationNeverFinishesBeforeHealthChecks() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.tabBars.buttons["我的"].tap()
        app.buttons["添加电视"].tap()
        XCTAssertTrue(app.staticTexts["先连上同一个 Wi-Fi"].waitForExistence(timeout: 5))
        capture(app, name: "setup-1-wifi")
        app.buttons["installationNext"].tap()
        XCTAssertTrue(app.staticTexts["截图，交给你的助手"].waitForExistence(timeout: 5))
        app.buttons["生成安装码"].tap()
        XCTAssertTrue(app.staticTexts["DEMO1234-DEMO5678"].waitForExistence(timeout: 5))
        capture(app, name: "setup-2-agent")
        app.buttons["installationNext"].tap()
        XCTAssertTrue(app.staticTexts["看看连接是否健康"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["installationNext"].isEnabled)
        app.swipeLeft()
        XCTAssertTrue(app.staticTexts["看看连接是否健康"].waitForExistence(timeout: 3))
        capture(app, name: "setup-3-health")
        for _ in 0..<3 where !app.buttons["demoInstallationPass"].isHittable { app.swipeUp() }
        app.buttons["demoInstallationPass"].tap()
        XCTAssertTrue(app.buttons["installationNext"].isEnabled)
        app.buttons["installationNext"].tap()
        XCTAssertTrue(app.staticTexts["配置完成"].waitForExistence(timeout: 5))
        capture(app, name: "setup-4-complete")
    }
}
