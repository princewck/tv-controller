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
    @MainActor func testAccountInputValidationAndErrorRecovery() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        for _ in 0..<3 where !app.buttons["connectFamily"].isHittable { app.swipeUp() }
        app.buttons["connectFamily"].tap()
        XCTAssertTrue(app.navigationBars["连接家庭"].waitForExistence(timeout: 5))
        replace(app.textFields["HTTPS 服务地址"], with: "http://invalid.example")
        replace(app.textFields["用户名"], with: "keyboard_check")
        replace(app.secureTextFields["密码"], with: "UI-Test-Only-Password-123\n")
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "HTTPS")).firstMatch.exists)
        capture(app, name: "account-invalid-origin")
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.navigationBars["连接家庭"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["用户名"].value as? String, "keyboard_check")
        for _ in 0..<4 where !app.buttons["创建新家庭"].isHittable { app.collectionViews.firstMatch.swipeUp() }
        app.buttons["创建新家庭"].tap()
        XCTAssertTrue(app.navigationBars["创建家庭"].waitForExistence(timeout: 5))
        replace(app.textFields["家庭用户名"], with: "review_ui_check")
        replace(app.secureTextFields["设置密码"], with: "UI-Test-Only-Password-123")
        capture(app, name: "account-after-first-password")
        XCTAssertFalse(app.staticTexts["密码需为 12–128 位。"].exists)
        replace(app.secureTextFields["再次输入密码"], with: "UI-Test-Only-Password-123")
        capture(app, name: "account-registration-valid-inputs")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["创建家庭"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        replace(app.textFields["家庭用户名"], with: "UPPER")
        XCTAssertFalse(app.buttons["创建家庭"].isEnabled)
        replace(app.textFields["家庭用户名"], with: "review_ui_check")
        replace(app.secureTextFields["再次输入密码"], with: "different")
        XCTAssertFalse(app.buttons["创建家庭"].isEnabled)
        capture(app, name: "account-registration-keyboard")
        replace(app.secureTextFields["再次输入密码"], with: "UI-Test-Only-Password-123")
        XCTAssertTrue(app.buttons["创建家庭"].isEnabled)
        app.buttons["创建家庭"].tap()
        XCTAssertTrue(app.alerts["操作未完成"].waitForExistence(timeout: 5))
        capture(app, name: "account-registration-error")
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.navigationBars["创建家庭"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["家庭用户名"].value as? String, "review_ui_check")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["忘记密码，用恢复码找回"].tap()
        XCTAssertTrue(app.navigationBars["找回家庭账号"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["重设家庭密码"].isEnabled)
        capture(app, name: "account-recovery")
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        }
    }
    @MainActor func testAccountLargeTextLandscapeNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        for _ in 0..<5 where !app.buttons["connectFamily"].isHittable { app.swipeUp() }
        app.buttons["connectFamily"].tap()
        XCTAssertTrue(app.navigationBars["连接家庭"].waitForExistence(timeout: 5))
        for _ in 0..<8 where !app.buttons["创建新家庭"].isHittable { app.collectionViews.firstMatch.swipeUp() }
        app.buttons["创建新家庭"].tap()
        XCTAssertTrue(app.navigationBars["创建家庭"].waitForExistence(timeout: 5))
        capture(app, name: "account-landscape-large-text")
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .textClipped])
        }
    }
    @MainActor private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let app = XCUIApplication()
        if app.buttons["GenerateStrongPasswordButton"].exists {
            app.buttons["xmark"].tap()
            field.tap()
        }
        typeReplacing(field, with: value)
        // The system can offer a generated password after the first keystroke.
        // Exercise manual entry without changing AutoFill settings or saving credentials.
        if app.buttons["GenerateStrongPasswordButton"].exists {
            app.buttons["xmark"].tap()
            field.tap()
            typeReplacing(field, with: value)
        }
        XCTAssertFalse(app.buttons["GenerateStrongPasswordButton"].exists)
    }
    @MainActor private func typeReplacing(_ field: XCUIElement, with value: String) {
        let valueBeforeEditing = field.value as? String ?? ""
        let existing = valueBeforeEditing == field.placeholderValue ? "" : valueBeforeEditing
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + value)
    }
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
