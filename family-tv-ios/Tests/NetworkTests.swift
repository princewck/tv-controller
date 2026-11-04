import XCTest
@testable import FamilyTV

private final class FixtureProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class NetworkTests: XCTestCase {
    private func api() -> TVAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        return TVAPI(configuration: config)
    }
    private var auth: SavedSession {
        SavedSession(origin: URL(string: "https://fixture.invalid")!, token: "fixture-session", csrf: "fixture-csrf", identity: Identity(username: "fixture", role: "user", tenant_id: "t"), expires: 9999999999999)
    }
    override func tearDown() { FixtureProtocol.handler = nil; super.tearDown() }
    func testRegistrationPostsCredentialsAndReadsSessionAndRecoveryCode() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/admin/register")
            let body: Data
            if let data = request.httpBody { body = data }
            else {
                let stream = try XCTUnwrap(request.httpBodyStream); stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096); var data = Data()
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
                body = data
            }
            let values = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(values["username"], "fixture_parent")
            XCTAssertEqual(values["password"], "test-only-password-123")
            let headers = ["Set-Cookie": "__Host-tv_admin=fixture-registration; Path=/; Secure; HttpOnly"]
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
            let data = Data(#"{"csrf":"fixture-csrf","expires_ms":4102444800000,"identity":{"username":"fixture_parent","role":"user","tenant_id":"fixture-household"},"recovery_code":"fixture-recovery"}"#.utf8)
            return (response, data)
        }
        let (session, code) = try await api().register(origin: URL(string: "https://fixture.invalid")!, username: "fixture_parent", password: "test-only-password-123")
        XCTAssertEqual(session.token, "fixture-registration")
        XCTAssertEqual(session.identity.username, "fixture_parent")
        XCTAssertEqual(code, "fixture-recovery")
    }
    func testAuthenticatedMutationSendsOriginCookieCSRFAndEscapedDevice() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Origin"), "https://fixture.invalid")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "__Host-tv_admin=fixture-session")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-CSRF-Token"), "fixture-csrf")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "tv+one&two")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"success":true}"#.utf8))
        }
        let result: SuccessResponse = try await api().request("/admin/logout", auth: auth, device: "tv+one&two", body: [:])
        XCTAssertTrue(result.success)
    }
    @MainActor func testFailedInitialRefreshCannotExposeOrSaveDefaultPolicy() async {
        FixtureProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let store = FamilyStore(api: api(), restoreSession: false)
        store.auth = auth
        await store.refresh()
        XCTAssertNotNil(store.loadState.failure)
        XCTAssertFalse(store.policyLoaded)
        let saved = await store.savePolicy(ViewingPolicy())
        XCTAssertFalse(saved)
    }
    @MainActor func testFailedRefreshRetainsCachedDataButMarksItStale() async {
        FixtureProtocol.handler = { _ in throw URLError(.timedOut) }
        let store = FamilyStore(api: api(), restoreSession: false)
        store.auth = auth
        store.policyLoaded = true
        store.usage = DemoData.usage()
        store.lastRefresh = Date(timeIntervalSince1970: 100)
        await store.refresh()
        XCTAssertNotNil(store.loadState.failure)
        XCTAssertEqual(store.lastRefresh, Date(timeIntervalSince1970: 100))
        XCTAssertNotNil(store.usage)
    }
    @MainActor func testSubscriptionSyncAcknowledgesOnlyAcceptedTransactionsAndUsesServerExpiry() async {
        let store = FamilyStore(api: api(), restoreSession: false)
        store.auth = auth
        store.capabilities = MobileCapabilities(version: 2, pause: true, daily_limit: true, execution_receipts: true, paid_history: true)
        FixtureProtocol.handler = { request in
            let text: String
            if request.httpMethod == "POST" {
                let data: Data
                if let body = request.httpBody { data = body }
                else if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
                    while true { let count = stream.read(&buffer, maxLength: buffer.count); if count == 0 { break }; guard count > 0 else { throw URLError(.cannotDecodeContentData) }; bytes.append(contentsOf: buffer.prefix(count)) }
                    data = bytes
                } else { throw URLError(.cannotDecodeContentData) }
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
                if body["signed_transaction"] == "invalid" { return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data("{}".utf8)) }
                text = #"{"active":true,"expires_ms":9999999999999,"transaction_id":"12345"}"#
            } else { text = #"{"active":false,"expires_ms":null}"# }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(text.utf8))
        }
        let ids = await store.syncSubscriptions(["invalid", "valid"])
        XCTAssertEqual(ids, ["12345"])
        XCTAssertFalse(store.premiumActive)
        XCTAssertNotNil(store.subscriptionSyncError)
    }
    @MainActor func testRestoreSendsAppleProofAndPreservesServerOwnership() async {
        let store = FamilyStore(api: api(), restoreSession: false)
        store.auth = auth
        store.capabilities = MobileCapabilities(version: 2, pause: true, daily_limit: true, execution_receipts: true, paid_history: true)
        FixtureProtocol.handler = { request in
            if request.httpMethod == "POST" {
                let data: Data
                if let body = request.httpBody { data = body }
                else if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var bytes = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
                    while true { let count = stream.read(&buffer, maxLength: buffer.count); if count == 0 { break }; guard count > 0 else { throw URLError(.cannotDecodeContentData) }; bytes.append(contentsOf: buffer.prefix(count)) }
                    data = bytes
                } else { throw URLError(.cannotDecodeContentData) }
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
                XCTAssertEqual(body["signed_transaction"], "purchase")
                XCTAssertEqual(body["signed_app_transaction"], "apple-account-proof")
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"active":true,"expires_ms":9999999999999,"transaction_id":"12345","original_ids":["original-123"]}"#.utf8))
        }
        store.premium = CloudSubscription(active: true, expires_ms: 9999999999999)
        let ids = await store.syncSubscriptions(["purchase"], signedAppTransaction: "apple-account-proof")
        XCTAssertEqual(ids, ["12345"])
        XCTAssertEqual(store.premium.original_ids, ["original-123"])
        XCTAssertNil(store.subscriptionSyncError)
    }

    @MainActor func testSubscriptionSyncCannotSetEntitlementAfterHouseholdChanges() async {
        let store = FamilyStore(api: api(), restoreSession: false)
        store.auth = auth
        store.capabilities = MobileCapabilities(version: 2, pause: true, daily_limit: true, execution_receipts: true, paid_history: true)
        FixtureProtocol.handler = { request in
            DispatchQueue.main.async { store.auth = nil }
            Thread.sleep(forTimeInterval: 0.05)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"active":true,"expires_ms":9999999999999,"transaction_id":"12345"}"#.utf8))
        }
        let ids = await store.syncSubscriptions(["valid"])
        XCTAssertTrue(ids.isEmpty)
        XCTAssertFalse(store.premiumActive)
    }

}
