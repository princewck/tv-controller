import Foundation
import Observation

enum DataLoadState: Equatable {
    case idle, loading, loaded, failed(String)
    var failure: String? { if case let .failed(message) = self { return message }; return nil }
}

@MainActor @Observable final class FamilyStore {
    var auth: SavedSession?
    var demo = false
    var devices: [TVDevice] = []
    var selectedID: String?
    var policy = ViewingPolicy()
    var capabilities: MobileCapabilities?
    var policyLoaded = false
    var loadState = DataLoadState.idle
    var usage: UsageResponse?
    var busy = false
    var error: String?
    var notice: String?
    var premium = CloudSubscription(active: false)
    var subscriptionSyncError: String?
    var pendingRecoveryCode: String?
    var premiumActive: Bool { premium.active && (premium.expires_ms ?? 0) > Date.now.timeIntervalSince1970 * 1000 }
    var setupTicket: InstallationTicket?
    var lastRefresh: Date?
    private let api: TVAPI
    private var refreshVersion = 0
    var connected: Bool { auth != nil || demo }
    var selected: TVDevice? { devices.first { $0.id == selectedID } }
    init(api: TVAPI = TVAPI(), restoreSession: Bool = true) {
        self.api = api
        if restoreSession, let saved = SessionVault.read(), saved.expires > Date.now.timeIntervalSince1970 * 1000 { auth = saved }
        if ProcessInfo.processInfo.arguments.contains("--demo") { enterDemo() }
    }
    func enterDemo() {
        refreshVersion += 1
        demo = true; error = nil; notice = nil; policyLoaded = true; loadState = .loaded
        devices = [TVDevice(device_name: "demo-living", label: "客厅电视", enabled: 1, last_heartbeat_ms: Date.now.timeIntervalSince1970 * 1000), TVDevice(device_name: "demo-bedroom", label: "卧室电视", enabled: 1, last_heartbeat_ms: nil)]
        selectedID = devices.first?.id
        policy = ViewingPolicy(banned_windows: [QuietWindow()], daily_limit_seconds: 5400)
        capabilities = MobileCapabilities(version: 1, pause: true, daily_limit: true, execution_receipts: true, staged_rules: false)
        usage = DemoData.usage()
        lastRefresh = .now
    }
    func login(origin: String, username: String, password: String) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let url = try TVAPI.validateOrigin(origin)
            let saved = try await api.login(origin: url, username: username, password: password)
            try SessionVault.write(saved)
            premium = CloudSubscription(active: false); subscriptionSyncError = nil; setupTicket = nil
            auth = saved; demo = false; devices = []; selectedID = nil; usage = nil; notice = nil; policyLoaded = false; capabilities = nil
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard connected else { return }
        refreshVersion += 1
        let version = refreshVersion
        loadState = .loading
        if demo {
            let sampleTime = Date.now.timeIntervalSince1970 * 1000
            devices = devices.map { device in
                var sample = device
                if sample.id == "demo-living" { sample.last_heartbeat_ms = sampleTime }
                return sample
            }
            if selectedID == "demo-bedroom" { usage = DemoData.usage(watched: 0) }
            else if usage == nil { usage = DemoData.usage() }
            lastRefresh = .now
            loadState = .loaded
            return
        }
        guard let auth else { return }
        do {
            let response: DevicesResponse = try await api.request("/admin/devices", auth: auth)
            guard version == refreshVersion else { return }
            devices = response.devices
            if !devices.contains(where: { $0.id == selectedID }) { selectedID = devices.first?.id }
            let config: PolicyResponse = try await api.request("/admin/config", auth: auth)
            guard version == refreshVersion else { return }
            policy = config.policy
            policyLoaded = true
            let supported: MobileCapabilities? = try? await api.request("/admin/mobile_capabilities", auth: auth)
            guard version == refreshVersion else { return }
            capabilities = supported
            if supported?.paid_history == true {
                let status: CloudSubscription = (try? await api.request("/admin/subscription", auth: auth)) ?? CloudSubscription(active: false)
                guard version == refreshVersion else { return }
                premium = status
            }
            if let selectedID {
                let stats: UsageResponse = try await api.request("/admin/stats", auth: auth, device: selectedID)
                guard version == refreshVersion else { return }
                usage = stats
            } else { usage = nil }
            lastRefresh = .now
            loadState = .loaded
        } catch { if version == refreshVersion { loadState = .failed(error.localizedDescription) } }
    }
    func select(_ id: String) async { selectedID = id; usage = nil; await refresh() }
    func savePolicy(_ value: ViewingPolicy) async -> Bool {
        guard policyLoaded, value.isValid, !busy else { return false }
        busy = true; defer { busy = false }
        do {
            if !demo {
                guard let auth else { return false }
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
                if capabilities?.staged_rules == false, value.daily_limit_seconds == nil { object["daily_limit_seconds"] = NSNull() }
                let _: PolicyResponse = try await api.request("/admin/config", auth: auth, body: ["policy": object])
            }
            policy = value
            notice = demo ? "演示规则已更新，不影响真实电视。" : "规则已保存到服务；电视将在下次连接时获取。"
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func grant(minutes: Int) async {
        guard let selectedID, (1...120).contains(minutes), !busy else { return }
        busy = true; defer { busy = false }
        do {
            if demo {
                if var value = usage {
                    value.state.remaining_seconds = value.state.paused == true ? 0 : minutes * 60
                    value.state.override_seconds = minutes * 60
                    value.state.status = value.state.paused == true ? "lock" : "allow"
                    usage = value
                }
            } else {
                guard let auth else { return }
                let state: PlaybackState = try await api.request("/admin/grant", auth: auth, device: selectedID, body: ["seconds": minutes * 60, "request_id": UUID().uuidString])
                usage?.state = state
            }
            notice = demo ? "演示：已给予 \(minutes) 分钟临时额度。" : "\(minutes) 分钟临时额度已保存，等待电视获取。尚未确认电视执行。"
        } catch { self.error = error.localizedDescription }
    }
    func setPaused(_ paused: Bool) async {
        guard let selectedID, capabilities?.pause == true, !busy else { return }
        busy = true; defer { busy = false }
        do {
            if demo {
                if var value = usage {
                    value.state.paused = paused
                    value.state.status = paused ? "lock" : "allow"
                    let remaining = (value.state.override_seconds ?? 0) > 0 ? (value.state.override_seconds ?? 0) : max(0, (policy.daily_limit_seconds ?? 86400) - value.todaySeconds)
                    value.state.remaining_seconds = paused ? 0 : remaining
                    value.state.lock_reason = paused ? "parent_paused" : nil
                    value.state.enforcement_result = paused ? "stopped" : "allowed"
                    value.state.control_revision = (value.state.control_revision ?? 0) + 1
                    value.state.applied_revision = value.state.control_revision
                    usage = value
                }
            } else {
                guard let auth else { return }
                let state: PlaybackState = try await api.request("/admin/control", auth: auth, device: selectedID, body: ["paused": paused, "request_id": UUID().uuidString])
                usage?.state = state
            }
            notice = demo ? "演示：\(paused ? "已暂停" : "已解除暂停")，不影响真实电视。" : "\(paused ? "暂停" : "解除暂停")指令已保存，等待电视执行回执。"
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func syncSubscriptions(_ receipts: [String], signedAppTransaction: String? = nil) async -> Set<String> {
        guard !demo, let auth, capabilities?.paid_history == true else { return [] }
        let previouslyActive = premiumActive
        var acknowledged = Set<String>()
        var failed = false
        for receipt in receipts {
            do {
                var body = ["signed_transaction": receipt]
                if let signedAppTransaction { body["signed_app_transaction"] = signedAppTransaction }
                let value: CloudSubscription = try await api.request("/admin/subscription", auth: auth, body: body)
                guard self.auth?.token == auth.token, !demo else { return [] }
                if let id = value.transaction_id { acknowledged.insert(id) }
                premium = value
            } catch { failed = true }
        }
        do {
            let status: CloudSubscription = try await api.request("/admin/subscription", auth: auth)
            guard self.auth?.token == auth.token, !demo else { return [] }
            premium = status
        } catch { failed = true }
        if self.auth?.token == auth.token { subscriptionSyncError = failed ? "Apple 凭证尚未同步到家庭云，请稍后重试。" : nil }
        if !previouslyActive, premiumActive, self.auth?.token == auth.token { await refresh() }
        return acknowledged
    }
    func register(origin: String, username: String, password: String) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let value = try await api.register(origin: TVAPI.validateOrigin(origin), username: username, password: password)
            try SessionVault.write(value.0)
            premium = CloudSubscription(active: false); subscriptionSyncError = nil; setupTicket = nil; selectedID = nil
            auth = value.0; demo = false; policyLoaded = false; devices = []; usage = nil; capabilities = nil
            pendingRecoveryCode = value.1
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func recover(origin: String, username: String, recoveryCode: String, password: String) async -> String? {
        guard !busy else { return nil }
        busy = true; defer { busy = false }
        do { return try await api.recover(origin: TVAPI.validateOrigin(origin), username: username, recoveryCode: recoveryCode, password: password) }
        catch { self.error = "恢复未完成，请核对家庭用户名和恢复码后重试。"; return nil }
    }
    func deleteHousehold(password: String) async -> Bool {
        guard !busy, !demo, let auth else { return false }
        busy = true; defer { busy = false }
        do {
            let _: SuccessResponse = try await api.request("/admin/delete_household", auth: auth, body: ["password": password, "confirmation": "DELETE"])
            SessionVault.clear(); self.auth = nil; devices = []; usage = nil; selectedID = nil; setupTicket = nil; policyLoaded = false; capabilities = nil; premium = CloudSubscription(active: false)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func prepareInstallation() async {
        guard !busy else { return }
        if let setupTicket, !setupTicket.expired { return }
        busy = true; defer { busy = false }
        do {
            if demo {
                setupTicket = InstallationTicket(code: "DEMO1234DEMO5678", device: "demo-install", label: "新电视", origin: "演示环境 · 不可用于真实安装", expires_ms: Date.now.addingTimeInterval(900).timeIntervalSince1970 * 1000)
            } else {
                guard let auth else { return }
                var body: [String: Any] = ["label": "家庭电视"]
                if let setupTicket, setupTicket.origin == auth.origin.absoluteString { body["device"] = setupTicket.device }
                let ticket: InstallationTicket = try await api.request("/admin/installation_ticket", auth: auth, body: body)
                setupTicket = ticket
            }
        } catch { self.error = error.localizedDescription }
    }
    func installationHealth(device: String) async throws -> InstallationHealth {
        guard !demo, let auth else { throw TVError.message("演示模式不会连接真实电视。") }
        return try await api.request("/admin/installation_status", auth: auth, device: device)
    }
    func logout() async {
        if !demo, let auth {
            do { let _: SuccessResponse = try await api.request("/admin/logout", auth: auth, body: [:]) }
            catch { self.error = "本机已退出；服务端会话撤销失败。请在服务后台撤销会话。" }
        }
        refreshVersion += 1
        if !demo { SessionVault.clear(); auth = nil }
        demo = false; devices = []; usage = nil; selectedID = nil; notice = nil; policyLoaded = false; loadState = .idle; capabilities = nil; setupTicket = nil; premium = CloudSubscription(active: false)
        if auth != nil { await refresh() }
    }
}

enum DemoData {
    static func usage(watched: Int = 1320) -> UsageResponse {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600); formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: .now)
        var daily = [DailyUsage(day: today, app_package: "com.ktcp.video", seconds: watched), DailyUsage(day: today, app_package: "com.xiaodianshi.tv.yst", seconds: watched == 0 ? 0 : 480)]
        for (offset, seconds) in [2400, 1800, 3600, 1500, 2700, 2100].enumerated() {
            daily.append(DailyUsage(day: formatter.string(from: Date.now.addingTimeInterval(Double(-6 + offset) * 86400)), app_package: "com.ktcp.video", seconds: seconds))
        }
        return UsageResponse(today: today, daily: daily, state: PlaybackState(status: "allow", stage: 0, remaining_seconds: max(0, 5400 - watched - (watched == 0 ? 0 : 480)), stage_used_seconds: watched, stage_budget_seconds: 5400, override_seconds: 0, paused: false, control_revision: 1, applied_revision: 1, enforcement_result: "allowed"), server_now_ms: Date.now.timeIntervalSince1970 * 1000)
    }
}
