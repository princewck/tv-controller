import Foundation

/// Labels are presentation only; authentication remains bound to the exact HTTPS origin.
enum ServiceEndpoint {
    static let officialOrigin = "https://familytv-api.princewck.workers.dev"
    static func isOfficial(_ origin: String) -> Bool {
        guard let url = try? TVAPI.validateOrigin(origin) else { return false }
        return url.absoluteString == officialOrigin
    }
    static func label(for origin: String) -> String { isOfficial(origin) ? "官方服务" : "自定义部署" }
}
enum ServiceSelection: String, CaseIterable, Identifiable {
    case official, custom
    var id: String { rawValue }
    var title: String { self == .official ? "官方服务" : "自定义部署" }
    func origin(custom: String) -> String {
        self == .official ? ServiceEndpoint.officialOrigin : custom.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
