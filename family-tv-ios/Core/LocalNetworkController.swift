import Foundation
import Network
import Observation

struct LanReceipt: Decodable {
    var accepted: Bool
    var device: String?
    var state: PlaybackState?
    var last_request_id: String?
    var execution_result: String?
    var pending_sync: Int?
    var sync_outcome: String?
    var error: String?
}
struct LanDelivery {
    var state: PlaybackState
    var viaLocal: Bool
    var cloudSynced: Bool
    var message: String
}

@MainActor @Observable final class LocalNetworkController {
    private(set) var paired = false
    private(set) var busy = false
    private var statusTemplate: LocalizedTemplate = "尚未启用局域网直连"
    var status: String { L10n.tr(statusTemplate) }
    private(set) var lastReceipt: LanReceipt?
    private var browser: NWBrowser?
    private var endpoints: [NWEndpoint] = []
    private var boundDevice: String?
    private var boundHousehold: String?
    private var boundOrigin: String?
    private(set) var lastVerified: Date?
    var localOnline: Bool { lastVerified.map { Date.now.timeIntervalSince($0) < 45 } ?? false }
    private var identity: LanIdentity?
    var discovered: Bool { !endpoints.isEmpty }

    func restore(auth: SavedSession, device: String) {
        if boundDevice != device || boundHousehold != auth.identity.tenant_id || boundOrigin != auth.origin.absoluteString {
            suspend(); identity = LanIdentityVault.read(auth, device: device)
            boundDevice = device; boundHousehold = auth.identity.tenant_id; boundOrigin = auth.origin.absoluteString; lastReceipt = nil; lastVerified = nil
        }
        paired = identity?.pairing.map { $0.device == device && $0.expires_ms > Date.now.timeIntervalSince1970 * 1000 } ?? false
        if paired { startDiscovery(device: device) }
    }
    func pair(auth: SavedSession, device: String, api: TVAPI) async throws {
        guard !busy else { return }; busy = true; defer { busy = false }
        var key = LanIdentityVault.read(auth, device: device) ?? LanIdentityVault.generate()
        try LanIdentityVault.save(key, auth: auth, device: device)
        let response: LanPairing = try await api.request("/admin/lan/pair", auth: auth, device: device, body: ["key_id": key.keyID, "public_key_der": try key.publicKeyDER.base64EncodedString()])
        guard response.device == device, response.key_id == key.keyID, response.protocol_version == 1,
              response.service_type == "_familytv._tcp", response.certificate_sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw TVError.message(L10n.tr("配对信息不匹配，请重试。")) }
        key.pairing = response; try LanIdentityVault.save(key, auth: auth, device: device)
        suspend(); identity = key; boundDevice = device; boundHousehold = auth.identity.tenant_id; boundOrigin = auth.origin.absoluteString; paired = true
        statusTemplate = "已授权本机，正在寻找电视；电视同步配对可能需要约 10 秒。"
        startDiscovery(device: device)
    }
    func disconnect(auth: SavedSession, device: String, api: TVAPI) async {
        let key = LanIdentityVault.read(auth, device: device)
        suspend(); paired = false; identity = nil; lastReceipt = nil
        LanIdentityVault.remove(auth: auth, device: device)
        if let key {
            do { let _: SuccessResponse = try await api.request("/admin/lan/revoke", auth: auth, device: device, body: ["key_id": key.keyID]); statusTemplate = "已关闭本机直连。电视联网同步后会撤销此授权。" }
            catch { statusTemplate = "本机配对密钥已删除；云端撤销未确认，原公开授权会到期。" }
        }
    }
    func forgetAll(auth: SavedSession, devices: [TVDevice], api: TVAPI) async {
        let keys = devices.compactMap { device -> String? in
            let key = LanIdentityVault.read(auth, device: device.id)
            LanIdentityVault.remove(auth: auth, device: device.id)
            return key?.keyID
        }
        clearMemory()
        if !keys.isEmpty { let _: SuccessResponse? = try? await api.request("/admin/lan/revoke_all", auth: auth, body: ["key_ids": keys], timeout: 3) }
    }
    func suspend() { browser?.cancel(); browser = nil; endpoints = [] }
    func clearMemory() { suspend(); paired = false; identity = nil; boundDevice = nil; boundHousehold = nil; boundOrigin = nil; lastReceipt = nil; lastVerified = nil; statusTemplate = "尚未启用局域网直连" }

    private func startDiscovery(device: String) {
        guard browser == nil, paired else { return }
        let browser = NWBrowser(for: .bonjour(type: "_familytv._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let suffix = String(device.suffix(12))
            let matches = results.compactMap { result -> NWEndpoint? in
                guard case let .service(name, _, _, _) = result.endpoint, name.hasPrefix("FamilyTV-" + suffix) else { return nil }
                return result.endpoint
            }.prefix(3)
            Task { @MainActor [weak self] in
                guard let self, self.boundDevice == device else { return }
                self.endpoints = Array(matches)
                self.statusTemplate = matches.isEmpty ? "已配对，未在当前局域网发现电视；仍可使用云端。" : "已发现配对电视，操作时优先尝试加密直连。"
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .waiting:
                Task { @MainActor [weak self] in self?.statusTemplate = "本地发现暂不可用，请检查同一网络和本地网络权限；云端仍可使用。" }
            default: break
            }
        }
        browser.start(queue: DispatchQueue(label: "familytv.local.discovery"))
    }
    private func local(_ envelope: LanEnvelope) async throws -> LanReceipt {
        guard let pairing = identity?.pairing, pairing.device == envelope.device, paired else { throw TVError.message(L10n.tr("尚未配对本地电视。")) }
        let data = try JSONEncoder().encode(envelope)
        let began = Date.now
        for endpoint in endpoints {
            let remaining = 4 - Date.now.timeIntervalSince(began); if remaining <= 0 { break }
            do {
                let raw = try await LanTLSExchange().request(endpoint: endpoint, certificateSHA256: pairing.certificate_sha256, data: data, timeout: min(3, remaining))
                let receipt = try JSONDecoder().decode(LanReceipt.self, from: raw)
                guard receipt.accepted, receipt.device == envelope.device, receipt.state != nil else { continue }
                lastReceipt = receipt; lastVerified = .now; return receipt
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        throw TVError.message(L10n.tr("本地电视未响应，将尝试云端。"))
    }
    func refreshState(device: String, revision: Int) async -> LanReceipt? {
        guard paired, boundDevice == device, let identity else { return nil }
        do {
            let envelope = try identity.envelope(device: device, revision: max(1, revision), payload: ["kind": "status"])
            let receipt = try await local(envelope)
            if receipt.sync_outcome == "conflict" { statusTemplate = "离线指令与云端更新冲突，电视已采用云端规则。" }
            else { statusTemplate = "局域网加密连接正常" }
            return receipt
        } catch { return nil }
    }
    func deliver(payload: [String: Any], device: String, revision: Int, auth: SavedSession, api: TVAPI) async throws -> LanDelivery {
        guard paired, boundDevice == device, let identity else { throw TVError.message(L10n.tr("请先配对本地电视。")) }
        let envelope = try identity.envelope(device: device, revision: max(1, revision), payload: payload)
        let localReceipt = try? await local(envelope)
        try Task.checkCancellation()
        do {
            let cloud: PlaybackState = try await api.request("/admin/lan/command", auth: auth, device: device, body: ["envelope": envelope.object], timeout: localReceipt == nil ? 20 : 3)
            statusTemplate = localReceipt == nil ? "本次已回退云端，等待电视获取。" : "指令已本地送达并同步云端，等待电视执行确认。"
            return LanDelivery(state: cloud, viaLocal: localReceipt != nil, cloudSynced: true, message: status)
        } catch {
            guard let state = localReceipt?.state else { throw error }
            statusTemplate = "指令已由本地电视接收，云端同步尚未确认。联网后若有冲突，云端更新优先。"
            return LanDelivery(state: state, viaLocal: true, cloudSynced: false, message: status)
        }
    }
}
