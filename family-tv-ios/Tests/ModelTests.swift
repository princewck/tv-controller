import XCTest
@testable import FamilyTV

final class ModelTests: XCTestCase {
    func testRejectInsecureAndCredentialOrigins() throws {
        for value in ["http://tv.example.com", "https://user:pass@tv.example.com", "https://tv.example.com/path", "https://tv.example.com?token=x", "https://tv.example.com/#secret", "garbage"] {
            XCTAssertThrowsError(try TVAPI.validateOrigin(value), value)
        }
        XCTAssertEqual(try TVAPI.validateOrigin(" https://tv.example.com/ ").absoluteString, "https://tv.example.com")
    }
    func testOnlineStateExpiresAndDisabledIsOffline() {
        let now = Date(timeIntervalSince1970: 100)
        var device = TVDevice(device_name: "a", label: "TV", enabled: 1, last_heartbeat_ms: 90_000)
        XCTAssertTrue(device.isOnline(at: now))
        XCTAssertFalse(device.isOnline(at: now.addingTimeInterval(40)))
        device.enabled = 0
        XCTAssertFalse(device.isOnline(at: now))
    }
    func testPolicyRejectsEmptyDaysBadTimesAndBudget() {
        var policy = ViewingPolicy()
        XCTAssertTrue(policy.isValid)
        policy.banned_windows = [QuietWindow(days: [])]
        XCTAssertFalse(policy.isValid)
        policy.banned_windows = [QuietWindow(start: "24:00")]
        XCTAssertFalse(policy.isValid)
        policy.banned_windows = []
        policy.initial_seconds = 0
        XCTAssertFalse(policy.isValid)
    }
    func testWeeklySummaryFillsMissingDaysAndUsesServerDay() {
        let usage = UsageResponse(today: "2026-10-31", daily: [DailyUsage(day: "2026-10-31", app_package: "app", seconds: 60), DailyUsage(day: "2026-10-31", app_package: "app2", seconds: 120), DailyUsage(day: "2026-10-01", app_package: "app", seconds: 900)], state: PlaybackState(status: "allow", stage: 0, remaining_seconds: 100), server_now_ms: 0)
        XCTAssertEqual(usage.todaySeconds, 180)
        XCTAssertEqual(usage.week.count, 7)
        XCTAssertEqual(usage.week.first?.day, "2026-10-25")
        XCTAssertEqual(usage.week.reduce(0) { $0 + $1.seconds }, 180)
    }
    @MainActor func testDemoDoesNotModifySavedAuthenticationAndGrantIsReplacement() async {
        let store = FamilyStore()
        let existing = store.auth
        store.enterDemo()
        XCTAssertEqual(store.auth?.token, existing?.token)
        await store.grant(minutes: 15)
        await store.grant(minutes: 5)
        XCTAssertEqual(store.usage?.state.remaining_seconds, 300)
        XCTAssertTrue(store.notice?.contains("演示") == true)
        await store.setPaused(true)
        await store.grant(minutes: 5)
        XCTAssertEqual(store.usage?.state.status, "lock")
        XCTAssertEqual(store.usage?.state.lock_reason, "parent_paused")
        await store.logout()
        XCTAssertFalse(store.demo)
        XCTAssertTrue(store.devices.isEmpty)
    }
    func testThirtyDayHistoryAndApplicationTotalsExcludeOutsideRange() {
        let usage = UsageResponse(today: "2026-10-31", daily: [DailyUsage(day: "2026-10-31", app_package: "a", seconds: 60), DailyUsage(day: "2026-10-05", app_package: "b", seconds: 120), DailyUsage(day: "2026-10-01", app_package: "a", seconds: 999)], state: PlaybackState(status: "allow", stage: 0, remaining_seconds: 100), server_now_ms: 0)
        XCTAssertEqual(usage.days(30).first?.day, "2026-10-02")
        XCTAssertEqual(usage.days(30).reduce(0) { $0 + $1.seconds }, 180)
        XCTAssertEqual(usage.appTotals(days: 30).map(\.app), ["b", "a"])
        XCTAssertEqual(usage.appTotals(days: 7).map(\.seconds), [60])
    }

}
