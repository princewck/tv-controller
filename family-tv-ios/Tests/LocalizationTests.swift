import XCTest
@testable import FamilyTV

final class LocalizationTests: XCTestCase {
    func testLanguageResolutionUsesSupportedPreferenceOrder() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["fr-FR", "ko-KR", "en-US"]), .korean)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["zh-Hant-TW"]), .chinese)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["de-DE"]), .english)
        XCTAssertEqual(AppLanguage.resolve(.japanese, preferred: ["en-US"]), .japanese)
    }

    func testTemplatesKeepRuntimeValuesOpaque() {
        let template: LocalizedTemplate = "\("{p1}") / \("family")"
        XCTAssertEqual(template.key, "{p0} / {p1}")
        XCTAssertEqual(L10n.tr(template), "{p1} / family")
    }

    func testAllLanguagesHaveMatchingNonemptyKeysAndArguments() throws {
        let bundle = Bundle.main
        var baseline: [String: String] = [:]
        let token = try NSRegularExpression(pattern: #"\{p[0-9]+\}"#)
        func arguments(_ value: String) -> [String] {
            let string = value as NSString
            return token.matches(in: value, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }.sorted()
        }
        for language in ["zh-Hans", "en", "ko", "ja"] {
            let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"))
            let data = try Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings"))
            let values = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            if baseline.isEmpty { baseline = values; XCTAssertGreaterThan(values.count, 400) }
            XCTAssertEqual(Set(values.keys), Set(baseline.keys), language)
            for (key, value) in values {
                XCTAssertFalse(value.isEmpty, "\(language): \(key)")
                XCTAssertEqual(arguments(key), arguments(value), "\(language): \(key)")
            }
        }
    }

    func testSteadyPresetPreservesOtherFamilyRulesAndOriginal() {
        var original = ViewingPolicy()
        original.daily_limit_seconds = 5400
        original.banned_windows = [QuietWindow()]
        let adjusted = BreakDesign.steadyIntervals(original)
        XCTAssertTrue(BreakDesign.hasShortIntervals(original))
        XCTAssertFalse(BreakDesign.hasShortIntervals(adjusted))
        XCTAssertEqual(adjusted.initial_seconds, max(original.initial_seconds, 1200))
        XCTAssertEqual(adjusted.first_reward_seconds, 1200)
        XCTAssertEqual(adjusted.second_reward_seconds, 1200)
        XCTAssertEqual(adjusted.repeat_seconds, 1200)
        var restored = adjusted
        restored.initial_seconds = original.initial_seconds
        restored.first_reward_seconds = original.first_reward_seconds
        restored.second_reward_seconds = original.second_reward_seconds
        restored.repeat_seconds = original.repeat_seconds
        XCTAssertEqual(restored, original)
    }
}
