import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en", korean = "ko", japanese = "ja"
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: L10n.tr("跟随系统")
        case .chinese: "中文"
        case .english: "English"
        case .korean: "한국어"
        case .japanese: "日本語"
        }
    }
    static func resolve(_ preference: AppLanguage, preferred: [String]) -> AppLanguage {
        if preference != .system { return preference }
        for tag in preferred {
            if tag.hasPrefix("zh") { return .chinese }
            if tag.hasPrefix("en") { return .english }
            if tag.hasPrefix("ko") { return .korean }
            if tag.hasPrefix("ja") { return .japanese }
        }
        return .english
    }
}

/// A whole-sentence key with opaque argument tokens; runtime values are never used as lookup keys.
struct LocalizedTemplate: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    var key: String
    var arguments: [String]
    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation value: StringInterpolation) { key = value.key; arguments = value.arguments }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        mutating func appendLiteral(_ value: String) { key += value }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{p\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

enum L10n {
    static let preferenceKey = "familytv.appLanguage"
    static var language: AppLanguage {
        let override = ProcessInfo.processInfo.environment["FAMILYTV_UI_LANGUAGE"]
        let raw = override ?? UserDefaults.standard.string(forKey: preferenceKey) ?? AppLanguage.system.rawValue
        return AppLanguage.resolve(AppLanguage(rawValue: raw) ?? .system, preferred: Locale.preferredLanguages)
    }
    static var locale: Locale { Locale(identifier: language.rawValue) }
    static func message(for error: Error) -> String {
        if let error = error as? TVError { return error.localizedDescription }
        return tr("无法连接服务。")
    }
    static func tr(_ value: LocalizedTemplate) -> String {
        let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main
        let translated = bundle.localizedString(forKey: value.key, value: value.key, table: "Localizable")
        // One pass: a user/device name containing a token must never be interpolated again.
        let expression = try! NSRegularExpression(pattern: #"\{p([0-9]+)\}"#)
        let source = translated as NSString
        var result = "", end = 0
        for match in expression.matches(in: translated, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: end, length: match.range.location - end))
            let index = Int(source.substring(with: match.range(at: 1))) ?? -1
            result += value.arguments.indices.contains(index) ? value.arguments[index] : source.substring(with: match.range)
            end = NSMaxRange(match.range)
        }
        result += source.substring(from: end)
        return result
    }
}
