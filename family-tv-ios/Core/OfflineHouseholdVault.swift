import Foundation
import Security
import CryptoKit

/// Last server snapshot, isolated by origin and household, for an already paired
/// parent's cold launch during an outage. Always presented as cached cloud data.
struct OfflineHousehold: Codable {
    var devices: [TVDevice]
    var selectedID: String?
    var policy: ViewingPolicy
    var capabilities: MobileCapabilities?
    var usage: UsageResponse?
    var capturedAt: Date
}
enum OfflineHouseholdVault {
    private static func query(_ auth: SavedSession) -> [String: Any] {
        let account = SHA256.hash(data: Data((auth.origin.absoluteString + "|" + auth.identity.tenant_id).utf8)).map { String(format: "%02x", $0) }.joined()
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "wang.chengkai.familytv.offline", kSecAttrAccount as String: account]
    }
    static func read(_ auth: SavedSession) -> OfflineHousehold? {
        var q = query(auth); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(OfflineHousehold.self, from: data)
    }
    static func save(_ value: OfflineHousehold, auth: SavedSession) {
        guard let data = try? JSONEncoder().encode(value), data.count <= 262144 else { return }
        let q = query(auth)
        if SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = q; item[kSecValueData as String] = data; item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
    static func remove(_ auth: SavedSession) { SecItemDelete(query(auth) as CFDictionary) }
}
