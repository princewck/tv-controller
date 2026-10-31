import Foundation
import Security

// No passwords are retained. The server-issued session lives in the device-only Keychain.
enum SessionVault {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "wang.chengkai.familytv.session", kSecAttrAccount as String: "parent"]
    static func read() -> SavedSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SavedSession.self, from: data)
    }
    static func write(_ value: SavedSession) throws {
        let data = try JSONEncoder().encode(value)
        let changes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            changes.forEach { q[$0.key] = $0.value }
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw TVError.message(L10n.tr("无法安全保存登录，请重试。")) }
        } else if status != errSecSuccess { throw TVError.message(L10n.tr("无法安全保存登录，请重试。")) }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

actor TVAPI {
    private let session: URLSession
    init(configuration: URLSessionConfiguration = .ephemeral) {
        let config = configuration
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    static func validateOrigin(_ input: String) throws -> URL {
        guard let url = URL(string: input.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host,
              url.scheme == "https", !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw TVError.message(L10n.tr("请填写完整的 HTTPS 服务地址，例如 https://tv.chengkai.wang。"))
        }
        return URL(string: "https://\(host)\(url.port.map { ":\($0)" } ?? "")")!
    }
    func login(origin: URL, username: String, password: String) async throws -> SavedSession {
        let (data, response) = try await send(origin: origin, path: "/admin/login", body: ["username": username, "password": password])
        let value = try JSONDecoder().decode(SessionResponse.self, from: data)
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
        guard let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: origin).first(where: { $0.name == "__Host-tv_admin" }) else {
            throw TVError.message(L10n.tr("服务没有返回登录凭证，请检查服务版本。"))
        }
        return SavedSession(origin: origin, token: cookie.value, csrf: value.csrf, identity: value.identity, expires: value.expires_ms)
    }
    func register(origin: URL, username: String, password: String) async throws -> (SavedSession, String) {
        let (data, response) = try await send(origin: origin, path: "/admin/register", body: ["username": username, "password": password])
        let value = try JSONDecoder().decode(SessionResponse.self, from: data)
        let recovery = try JSONDecoder().decode(RecoveryResponse.self, from: data)
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
        guard let token = HTTPCookie.cookies(withResponseHeaderFields: headers, for: origin).first(where: { $0.name == "__Host-tv_admin" })?.value else { throw TVError.message(L10n.tr("服务没有返回登录凭证，请重试。")) }
        return (SavedSession(origin: origin, token: token, csrf: value.csrf, identity: value.identity, expires: value.expires_ms), recovery.recovery_code)
    }
    func recover(origin: URL, username: String, recoveryCode: String, password: String) async throws -> String {
        let (data, _) = try await send(origin: origin, path: "/admin/recover", body: ["username": username, "recovery_code": recoveryCode, "password": password])
        return try JSONDecoder().decode(RecoveryResponse.self, from: data).recovery_code
    }
    func request<T: Decodable>(_ path: String, auth: SavedSession, device: String? = nil, body: [String: Any]? = nil, timeout: TimeInterval? = nil) async throws -> T {
        let (data, _) = try await send(origin: auth.origin, path: path, auth: auth, device: device, body: body, timeout: timeout)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw TVError.message(L10n.tr("服务返回的数据不兼容，请更新服务或稍后重试。")) }
    }
    private func send(origin: URL, path: String, auth: SavedSession? = nil, device: String? = nil, body: [String: Any]? = nil, timeout: TimeInterval? = nil) async throws -> (Data, HTTPURLResponse) {
        var parts = URLComponents(url: origin.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false)!
        if let device { parts.queryItems = [URLQueryItem(name: "device", value: device)] }
        var request = URLRequest(url: parts.url!)
        request.httpMethod = body == nil ? "GET" : "POST"
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
        if let auth {
            request.setValue("__Host-tv_admin=\(auth.token)", forHTTPHeaderField: "Cookie")
            request.setValue(auth.csrf, forHTTPHeaderField: "X-CSRF-Token")
        }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, raw) = try await session.data(for: request)
        guard let response = raw as? HTTPURLResponse else { throw TVError.message(L10n.tr("无法连接服务。")) }
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 401: throw TVError.message(L10n.tr("账号或密码不正确，或登录已过期，请重新登录。"))
        case 403: throw TVError.message(L10n.tr("没有操作权限，请重新登录后再试。"))
        case 409 where path == "/admin/installation_ticket": throw TVError.message(L10n.tr("安装码可能已被助手兑换，请继续查看连接健康检查；如需重新安装，请联系支持。"))
        case 429: throw TVError.message(L10n.tr("操作过于频繁，请稍后再试。"))
        case 500...599: throw TVError.message(L10n.tr("服务暂时不可用，请稍后重试。"))
        default: throw TVError.message(L10n.tr("操作未完成（\(response.statusCode)），请检查输入并重试。"))
        }
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
