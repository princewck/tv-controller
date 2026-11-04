import SwiftUI

struct LanguageSettingsView: View {
    @AppStorage(L10n.preferenceKey) private var selected = AppLanguage.system.rawValue
    var body: some View {
        Form {
            Section {
                Picker(L10n.tr("App 语言"), selection: $selected) {
                    ForEach(AppLanguage.allCases) { language in Text(language.nativeName).tag(language.rawValue) }
                }.pickerStyle(.inline).accessibilityIdentifier("appLanguagePicker")
            } footer: {
                Text(L10n.tr("默认跟随系统，也可为这个 App 单独选择语言。切换后返回首页，账号、观看规则与记录保持不变。"))
            }
        }.navigationTitle(L10n.tr("语言")).navigationBarTitleDisplayMode(.inline)
    }
}
