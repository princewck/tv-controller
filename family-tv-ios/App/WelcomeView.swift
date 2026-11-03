import SwiftUI

struct WelcomeView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(SubscriptionStore.self) private var subscription
    @State private var showLogin = false
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Spacer(minLength: 24)
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .center, spacing: 20) {
                                Text(L10n.tr("好好看，\n也好好休息。"))
                                    .font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "tv.and.mediabox.fill")
                                    .font(.system(size: 44, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 76, height: 76)
                                    .background(Color.accentColor.opacity(0.09), in: .rect(cornerRadius: 22))
                                    .accessibilityHidden(true)
                            }.accessibilityElement(children: .combine).accessibilityIdentifier("welcomeHero")
                            Text(L10n.tr("观有度，让电视时间有商有量。"))
                                .font(.subheadline).foregroundStyle(Color("SupportingText"))
                                .accessibilityIdentifier("welcomeTagline")
                        }
                        Spacer(minLength: 28)
                        VStack(alignment: .leading, spacing: 24) {
                            intro(L10n.tr("看得明白"), L10n.tr("了解受管应用的观看时长。"), "chart.bar.fill", .blue)
                            intro(L10n.tr("休息有约定"), L10n.tr("设置观看额度和休息时段。"), "moon.fill", .orange)
                            intro(L10n.tr("家长来决定"), L10n.tr("需要时，给予一段额外观看时间。"), "hand.raised.fill", .purple)
                        }
                        Spacer(minLength: 28)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr("首次配置需配套 Android TV 客户端和电脑；不支持 Apple TV 或 HDMI 设备。"))
                                .font(.footnote).foregroundStyle(Color("SupportingText"))
                                .accessibilityIdentifier("welcomeCompatibility")
                            HStack(alignment: .firstTextBaseline, spacing: 16) {
                                NavigationLink(L10n.tr("如何添加电视")) { InstallationView() }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                NavigationLink(L10n.tr("电视上会发生什么？")) { TVGuideView() }
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .accessibilityIdentifier("welcomeTVGuide")
                            }.font(.subheadline)
                        }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 600)
                    .frame(minHeight: geometry.size.height, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        FormActionButton(title: L10n.tr("连接我的家庭")) { showLogin = true }
                            .accessibilityIdentifier("connectFamily")
                        demoAction
                    }
                    if subscription.hasPurchaseIntent {
                        Text(L10n.tr("你从 App Store 发起了订阅，请先连接购买要使用的家庭，再继续。"))
                            .font(.footnote).foregroundStyle(Color("SupportingText"))
                    }
                    Text(L10n.tr("演示无需账号，不连接真实电视。"))
                        .font(.caption).foregroundStyle(Color("SupportingText"))
                }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity).background(.background)
            }
            .navigationTitle(L10n.tr("观有度")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { LanguageSettingsView() } label: { Image(systemName: "globe") }
                        .accessibilityLabel(L10n.tr("语言"))
                        .accessibilityIdentifier("welcomeLanguageSettings")
                }
            }
            .sheet(isPresented: $showLogin) { LoginView() }
        }
    }
    private var demoButton: some View {
        Button { store.enterDemo() } label: {
            Text(L10n.tr("先体验演示模式"))
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 28).padding(.vertical, 4)
        }
        .controlSize(.large).buttonBorderShape(.roundedRectangle(radius: 14))
        .accessibilityIdentifier("enterDemo")
    }
    @ViewBuilder private var demoAction: some View {
        if #available(iOS 26, *) { demoButton.buttonStyle(.glass) }
        else { demoButton.buttonStyle(.bordered) }
    }
    private func intro(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon).font(.title3.weight(.semibold)).foregroundStyle(color)
                .frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).accessibilityIdentifier("welcomeFeatureTitle." + icon)
                Text(subtitle).font(.subheadline).foregroundStyle(Color("SupportingText"))
                    .accessibilityIdentifier("welcomeFeatureDetail." + icon)
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct LoginView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var serviceSelection: ServiceSelection = .official
    @State private var customOrigin = ""
    private var origin: String { serviceSelection.origin(custom: customOrigin) }
    private var validOrigin: Bool { (try? TVAPI.validateOrigin(origin)) != nil }
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    enum Field { case username, password, origin }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.tr("用户名"), text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .username)
                        .submitLabel(.next).onSubmit { focus = .password }
                    SecureField(L10n.tr("密码"), text: $password).textContentType(.password).focused($focus, equals: .password).submitLabel(.go).onSubmit { connect() }
                } header: { Text(L10n.tr("家庭账号")) } footer: { Text(L10n.tr("使用你的家庭账号登录。首次使用可在下方创建家庭。请勿输入 Apple 账号密码。")) }
                ServiceSelectionView(selection: $serviceSelection, customOrigin: $customOrigin)
                    .disabled(store.busy)
                Section {
                    FormActionButton(title: L10n.tr("连接家庭"), busy: store.busy, action: connect)
                        .accessibilityIdentifier("loginHousehold")
                }
                Section {
                    NavigationLink(L10n.tr("创建新家庭")) { RegistrationView(origin: origin) }.disabled(!validOrigin || store.busy)
                    NavigationLink(L10n.tr("忘记密码，用恢复码找回")) { AccountRecoveryView(origin: origin) }.disabled(!validOrigin || store.busy)
                }
                Section { NavigationLink(L10n.tr("安装与账号说明")) { InstallationView() } }
            }
            .navigationTitle(L10n.tr("连接家庭")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() }.disabled(store.busy) } }
        }.interactiveDismissDisabled(store.busy)
            .familyErrorAlert(inModal: true)
    }
    private func connect() {
        guard !store.busy else { return }
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty else {
            store.error = L10n.tr("请输入家庭用户名和密码。")
            return
        }
        focus = nil
        Task {
            await store.login(origin: origin, username: username.trimmingCharacters(in: .whitespaces), password: password)
            if store.auth != nil { password = ""; dismiss() }
        }
    }
}
