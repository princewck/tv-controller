import Foundation

struct TVDevice: Codable, Identifiable, Equatable {
    var device_name: String
    var label: String
    var enabled: Int
    var last_heartbeat_ms: Double?
    var id: String { device_name }
    func isOnline(at now: Date = .now) -> Bool {
        guard enabled == 1, let last_heartbeat_ms else { return false }
        let age = now.timeIntervalSince1970 * 1000 - last_heartbeat_ms
        return age >= -5000 && age < 45_000
    }
}
struct QuietWindow: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var label: String = L10n.tr("睡前休息")
    var days: [Int] = Array(0...6)
    var start = "20:30"
    var end = "07:00"
    var enabled = true
}
struct ViewingPolicy: Codable, Equatable {
    var initial_seconds = 1800
    var first_reward_seconds = 1200
    var second_reward_seconds = 300
    var repeat_seconds = 120
    var rest_reset_seconds = 18000
    var default_grant_seconds = 900
    var banned_windows: [QuietWindow] = []
    var daily_limit_seconds: Int? = nil
    var isValid: Bool {
        [initial_seconds, first_reward_seconds, second_reward_seconds, repeat_seconds, rest_reset_seconds, default_grant_seconds].allSatisfy { (60...86400).contains($0) } && (daily_limit_seconds.map { (60...86400).contains($0) } ?? true) && banned_windows.count <= 32 && banned_windows.allSatisfy {
            !$0.days.isEmpty && $0.days.allSatisfy { (0...6).contains($0) } && Self.validTime($0.start) && Self.validTime($0.end)
        }
    }
    static func validTime(_ value: String) -> Bool {
        value.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil
    }
}
struct PlaybackState: Codable {
    var status: String
    var lock_reason: String?
    var stage: Int
    var remaining_seconds: Int
    var stage_used_seconds: Int?
    var stage_budget_seconds: Int?
    var override_seconds: Int?
    var paused: Bool?
    var control_revision: Int?
    var applied_revision: Int?
    var enforcement_result: String?
    var applied_ms: Double?
    var executionText: String {
        guard let revision = control_revision, let applied = applied_revision else { return L10n.tr("此电视尚未提供执行回执") }
        guard applied == revision else { return L10n.tr("等待电视获取最新指令") }
        switch enforcement_result {
        case "stopped": return L10n.tr("电视报告已停止受管播放")
        case "allowed": return L10n.tr("电视报告已恢复允许观看")
        case "observing": return L10n.tr("电视仅处于观察模式，未执行拦截")
        case "failed": return L10n.tr("电视执行失败，请检查权限")
        default: return L10n.tr("等待电视确认执行结果")
        }
    }
}
struct MobileCapabilities: Codable {
    var version: Int
    var pause: Bool
    var daily_limit: Bool
    var execution_receipts: Bool
    var staged_rules: Bool?
    var registration: Bool?
    var household_delete: Bool?
    var paid_history: Bool?
    var lan: Bool?
}
struct DailyUsage: Codable, Identifiable {
    var day: String
    var app_package: String
    var seconds: Int
    var id: String { day + app_package }
    var appName: String { Self.name(app_package) }
    static func name(_ package: String) -> String {
        switch package {
        case "com.ktcp.video": L10n.tr("腾讯视频")
        case "com.xiaodianshi.tv.yst": L10n.tr("哔哩哔哩 TV")
        case "com.google.android.youtube.tv": "YouTube"
        case "com.hunantv.license": L10n.tr("芒果 TV")
        default: package
        }
    }
}
struct UsageResponse: Codable {
    var today: String
    var daily: [DailyUsage]
    var state: PlaybackState
    var server_now_ms: Double
    var todaySeconds: Int { daily.filter { $0.day == today }.reduce(0) { $0 + $1.seconds } }
    var week: [(day: String, seconds: Int)] { days(7) }
    func days(_ count: Int) -> [(day: String, seconds: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        guard let date = formatter.date(from: today) else { return [] }
        return (0..<count).compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: offset - count + 1, to: date) else { return nil }
            let day = formatter.string(from: d)
            return (day, daily.filter { $0.day == day }.reduce(0) { $0 + $1.seconds })
        }
    }
    func appTotals(days count: Int) -> [(app: String, seconds: Int)] {
        guard let first = days(count).first?.day else { return [] }
        let grouped = Dictionary(grouping: daily.filter { $0.day >= first && $0.day <= today }, by: \.app_package)
        return grouped.map { (app: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { a, b in a.seconds == b.seconds ? a.app < b.app : a.seconds > b.seconds }
    }

}
struct DevicesResponse: Codable { var devices: [TVDevice] }
struct PolicyResponse: Codable { var policy: ViewingPolicy }
struct Identity: Codable { var username: String; var role: String; var tenant_id: String }
struct SessionResponse: Codable { var csrf: String; var identity: Identity; var expires_ms: Double }
struct SuccessResponse: Codable { var success: Bool }
struct SavedSession: Codable { var origin: URL; var token: String; var csrf: String; var identity: Identity; var expires: Double }
struct ProvisionResponse: Codable { var device: String; var token: String; var label: String; var origin: String }

enum TVError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}
extension Int {
    var durationText: String {
        let minutes = Swift.max(0, self) / 60
        return minutes >= 60 ? L10n.tr("\(minutes / 60) 小时 \(minutes % 60) 分钟") : L10n.tr("\(minutes) 分钟")
    }
}

struct InstallationTicket: Codable {
    var code: String
    var device: String
    var label: String
    var origin: String
    var expires_ms: Double
    var expired: Bool { Date.now.timeIntervalSince1970 * 1000 >= expires_ms }
    var displayCode: String { String(code.prefix(8)) + "-" + String(code.suffix(8)) }
    var agentPrompt: String {
        L10n.tr("请下载 https://familytv-api.princewck.workers.dev/downloads/install/1.0.2/family-tv-setup.zip，解压并先读 SKILL.md，按要求配置本页电视并完成手机健康检查。")
    }
}
struct InstallationChecks: Codable {
    var connected: Bool
    var playback_test: Bool
    var adb_closed: Bool
    var rebooted: Bool
    var permissions: Bool
}
struct InstallationHealth: Codable {
    var device: String
    var checks: InstallationChecks
    var complete: Bool
    var updated_ms: Double?
}

struct CloudSubscription: Codable { var active: Bool; var expires_ms: Double?; var transaction_id: String?; var original_ids: [String]? }
struct RecoveryResponse: Codable { var recovery_code: String }
