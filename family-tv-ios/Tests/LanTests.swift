import XCTest
import CryptoKit
import Network
@testable import FamilyTV

final class LanTests: XCTestCase {
    func testPhoneSignatureHasCrossPlatformCanonicalForm() throws {
        let key = LanIdentityVault.generate()
        let e = try key.envelope(device: "tv_fixture", revision: 7, payload: ["kind": "pause", "paused": true], requestID: "00000000-0000-0000-0000-000000000001", now: Date(timeIntervalSince1970: 100))
        XCTAssertTrue(e.signingText.hasPrefix("FamilyTV-LAN/1\ntv_fixture\n"))
        XCTAssertEqual(e.issued_ms, 100000)
        let publicKey = try P256.Signing.PublicKey(derRepresentation: key.publicKeyDER)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: XCTUnwrap(Data(base64Encoded: e.signature)))
        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data(e.signingText.utf8)))
        var changed = e; changed.base_revision = 8
        XCTAssertFalse(publicKey.isValidSignature(signature, for: Data(changed.signingText.utf8)))
    }
    func testSharedSPKIFixtureSignatureVerifiesAndTamperDoesNot() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LanVector", withExtension: "json"))
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let envelope = try JSONDecoder().decode(LanEnvelope.self, from: JSONSerialization.data(withJSONObject: value["envelope"]!))
        let key = try P256.Signing.PublicKey(derRepresentation: XCTUnwrap(Data(base64Encoded: value["public_key_der"] as! String)))
        let sig = try P256.Signing.ECDSASignature(derRepresentation: XCTUnwrap(Data(base64Encoded: envelope.signature)))
        XCTAssertTrue(key.isValidSignature(sig, for: Data(envelope.signingText.utf8)))
        XCTAssertFalse(key.isValidSignature(sig, for: Data((envelope.signingText + "x").utf8)))
    }
    @MainActor func testPairingAndOfflineSnapshotCannotCrossOriginsOrHouseholds() throws {
        let family = UUID().uuidString
        let auth = SavedSession(origin: URL(string: "https://fixture.invalid")!, token: "ephemeral-fixture", csrf: "fixture-csrf", identity: Identity(username: "fixture", role: "user", tenant_id: family), expires: 9999999999999)
        let other = SavedSession(origin: URL(string: "https://another.invalid")!, token: auth.token, csrf: auth.csrf, identity: auth.identity, expires: auth.expires)
        let device = "tv_" + UUID().uuidString
        defer { LanIdentityVault.remove(auth: auth, device: device); OfflineHouseholdVault.remove(auth) }
        let identity = LanIdentityVault.generate(); try LanIdentityVault.save(identity, auth: auth, device: device)
        XCTAssertEqual(LanIdentityVault.read(auth, device: device)?.keyID, identity.keyID)
        XCTAssertNil(LanIdentityVault.read(other, device: device))
        let snapshot = OfflineHousehold(devices: [], selectedID: device, policy: ViewingPolicy(), capabilities: nil, usage: nil, capturedAt: .now)
        OfflineHouseholdVault.save(snapshot, auth: auth)
        XCTAssertEqual(OfflineHouseholdVault.read(auth)?.selectedID, device)
        XCTAssertNil(OfflineHouseholdVault.read(other))
    }
    @MainActor func testDiscoveryNeverStartsForAnUnpairedController() {
        let controller = LocalNetworkController()
        XCTAssertFalse(controller.paired); XCTAssertFalse(controller.discovered); XCTAssertFalse(controller.localOnline)
        controller.suspend(); controller.clearMemory()
        XCTAssertNil(controller.lastReceipt)
    }
    func testRealAndroidTLSFramingPinAndSignedLocalCommands() async throws {
        let env = ProcessInfo.processInfo.environment
        func setting(_ key: String) -> String? { env[key] ?? env["TEST_RUNNER_" + key] }
        guard let portText = setting("LAN_FIXTURE_PORT"), let number = UInt16(portText), let pin = setting("LAN_FIXTURE_PIN"), let raw = setting("LAN_FIXTURE_PRIVATE"), let keyID = setting("LAN_FIXTURE_KEY_ID"), let key = Data(base64Encoded: raw) else { throw XCTSkip("Explicit Android/iOS interop fixture not running") }
        let identity = LanIdentity(keyID: keyID, privateKey: key, pairing: nil)
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: number)!)
        let e = try identity.envelope(device: "tv_lan_fixture", revision: 1, payload: ["kind": "pause", "paused": true])
        let data = try JSONEncoder().encode(e)
        let result = try await LanTLSExchange().request(endpoint: endpoint, certificateSHA256: pin, data: data)
        let receipt = try JSONDecoder().decode(LanReceipt.self, from: result)
        XCTAssertTrue(receipt.accepted); XCTAssertEqual(receipt.state?.paused, true); XCTAssertEqual(receipt.pending_sync, 1)
        XCTAssertEqual(receipt.execution_result, "waiting", "A queued fixture must not fabricate actual playback execution")
        let duplicate = try JSONDecoder().decode(LanReceipt.self, from: await LanTLSExchange().request(endpoint: endpoint, certificateSHA256: pin, data: data))
        XCTAssertEqual(duplicate.pending_sync, 1)
        let resume = try identity.envelope(device: "tv_lan_fixture", revision: 1, payload: ["kind": "pause", "paused": false])
        let resumed = try JSONDecoder().decode(LanReceipt.self, from: await LanTLSExchange().request(endpoint: endpoint, certificateSHA256: pin, data: JSONEncoder().encode(resume)))
        XCTAssertEqual(resumed.state?.paused, false)
        do { _ = try await LanTLSExchange().request(endpoint: endpoint, certificateSHA256: String(repeating: "0", count: 64), data: data, timeout: 2); XCTFail("Wrong TLS identity accepted") } catch { }
        let stranger = try LanIdentityVault.generate().envelope(device: "tv_lan_fixture", revision: 1, payload: ["kind": "pause", "paused": true])
        let refused = try JSONDecoder().decode(LanReceipt.self, from: await LanTLSExchange().request(endpoint: endpoint, certificateSHA256: pin, data: JSONEncoder().encode(stranger)))
        XCTAssertFalse(refused.accepted)
    }
}
