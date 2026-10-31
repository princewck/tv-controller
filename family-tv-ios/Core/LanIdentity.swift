import Foundation
import CryptoKit
import Security

struct LanPairing: Codable {
    var device: String
    var key_id: String
    var expires_ms: Double
    var certificate_sha256: String
    var service_type: String
    var protocol_version: Int
}
struct LanIdentity: Codable {
    var keyID: String
    var privateKey: Data
    var pairing: LanPairing?
    var publicKeyDER: Data { get throws { try P256.Signing.PrivateKey(rawRepresentation: privateKey).publicKey.derRepresentation } }
    func envelope(device: String, revision: Int, payload: [String: Any], requestID: String = UUID().uuidString.lowercased(), now: Date = .now) throws -> LanEnvelope {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        var envelope = LanEnvelope(v: 1, device: device, key_id: keyID, request_id: requestID, issued_ms: Int64(now.timeIntervalSince1970 * 1000), base_revision: revision, payload: data.base64EncodedString(), signature: "")
        envelope.signature = try P256.Signing.PrivateKey(rawRepresentation: privateKey).signature(for: Data(envelope.signingText.utf8)).derRepresentation.base64EncodedString()
        return envelope
    }
}
struct LanEnvelope: Codable {
    var v: Int; var device: String; var key_id: String; var request_id: String
    var issued_ms: Int64; var base_revision: Int; var payload: String; var signature: String
    var signingText: String { ["FamilyTV-LAN/1", device, key_id, request_id, String(issued_ms), String(base_revision), payload].joined(separator: "\n") }
    var object: [String: Any] { ["v": v, "device": device, "key_id": key_id, "request_id": request_id, "issued_ms": issued_ms, "base_revision": base_revision, "payload": payload, "signature": signature] }
}
enum LanIdentityVault {
    private static func query(_ auth: SavedSession, _ device: String) -> [String: Any] {
        let scope = auth.origin.absoluteString + "|" + auth.identity.tenant_id + "|" + device
        let account = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "wang.chengkai.familytv.lan", kSecAttrAccount as String: account]
    }
    static func read(_ auth: SavedSession, device: String) -> LanIdentity? {
        var q = query(auth, device); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(LanIdentity.self, from: data)
    }
    static func save(_ identity: LanIdentity, auth: SavedSession, device: String) throws {
        let q = query(auth, device), data = try JSONEncoder().encode(identity)
        let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var value = q; value[kSecValueData as String] = data
            value[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(value as CFDictionary, nil) == errSecSuccess else { throw TVError.message(L10n.tr("无法安全保存局域网配对，请重试。")) }
        } else if status != errSecSuccess { throw TVError.message(L10n.tr("无法更新局域网配对。")) }
    }
    static func remove(auth: SavedSession, device: String) { SecItemDelete(query(auth, device) as CFDictionary) }
    static func generate() -> LanIdentity { LanIdentity(keyID: UUID().uuidString.lowercased(), privateKey: P256.Signing.PrivateKey().rawRepresentation, pairing: nil) }
}
