import SwiftUI

struct ServiceSelectionView: View {
    @Binding var selection: ServiceSelection
    @Binding var customOrigin: String
    @FocusState private var editingAddress: Bool
    var body: some View {
        Section {
            Picker(L10n.tr("连接方式"), selection: $selection) {
                ForEach(ServiceSelection.allCases) { choice in Text(choice.title).tag(choice) }
            }.pickerStyle(.menu).accessibilityIdentifier("serviceSelection")
            if selection == .custom {
                TextField(L10n.tr("https://你的服务域名"), text: $customOrigin)
                    .keyboardType(.URL).textContentType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editingAddress).submitLabel(.done).onSubmit { editingAddress = false }
                    .accessibilityIdentifier("customServiceOrigin")
            }
        } header: { Text(L10n.tr("连接服务")) } footer: {
            Text(selection == .official ? L10n.tr("由观有度提供，无需填写服务器地址。") : L10n.tr("填写你自行部署的兼容服务地址。账号凭证会发送到此地址，请确认由你或信任的人维护。"))
        }
    }
}
