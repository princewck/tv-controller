import SwiftUI

struct WelcomeView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(SubscriptionStore.self) private var subscription
    @State private var showLogin = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "tv.and.mediabox").font(.largeTitle).foregroundStyle(Color.accentColor).padding(.top, 32).accessibilityHidden(true)
                    Text("好好看，\n也好好休息。")
                        .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("观有度，让电视时间有商有量。")
                        .font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 24) {
                        intro("看得明白", "了解受管应用的观看时长。", "chart.bar")
                        intro("休息有约定", "设置观看额度和休息时段。", "moon")
                        intro("家长来决定", "需要时，给予一段额外观看时间。", "hand.raised")
                    }.padding(.vertical, 8)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("需要先准备一台兼容的 Android TV")
                            .font(.headline)
                        Text("电视需安装并配置配套客户端；iPhone 不能直接管理未安装客户端的电视、Apple TV 或 HDMI 设备。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink("如何添加电视") { InstallationView() }.frame(minHeight: 44)
                    }
                    Button { showLogin = true } label: { Text("连接我的家庭").frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("connectFamily")
                    Button("先体验演示模式") { store.enterDemo() }
                        .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("enterDemo")
                    if subscription.hasPurchaseIntent { Text("你从 App Store 发起了订阅，请先连接购买要使用的家庭，再继续。").font(.footnote).foregroundStyle(.secondary) }
                    Text("演示无需账号，不连接真实电视。")
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(24).frame(maxWidth: 600)
            }
            .navigationTitle("观有度").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showLogin) { LoginView() }
        }
    }
    private func intro(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).foregroundStyle(.secondary) }
        }
    }
}
struct LoginView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var origin = Bundle.main.object(forInfoDictionaryKey: "FamilyTVServiceOrigin") as? String ?? "https://tv.chengkai.wang"
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    enum Field { case username, password }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("用户名", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .username)
                    SecureField("密码", text: $password).textContentType(.password).focused($focus, equals: .password).onSubmit { connect() }
                } header: { Text("家庭账号") } footer: { Text("使用你的家庭账号登录。首次使用可在下方创建家庭。请勿输入 Apple 账号密码。") }
                Section("服务地址") {
                    TextField("HTTPS 服务地址", text: $origin).keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("登录凭证将发送到此地址，请仅连接你信任的服务。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button { connect() } label: {
                        HStack { Text("连接家庭"); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || store.busy)
                }
                Section {
                    NavigationLink("创建新家庭") { RegistrationView(origin: origin) }
                    NavigationLink("忘记密码，用恢复码找回") { AccountRecoveryView(origin: origin) }
                }
                Section { NavigationLink("安装与账号说明") { InstallationView() } }
            }
            .navigationTitle("连接家庭").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.busy) } }
        }.interactiveDismissDisabled(store.busy)
    }
    private func connect() {
        focus = nil
        Task {
            await store.login(origin: origin, username: username.trimmingCharacters(in: .whitespaces), password: password)
            password = ""
            if store.auth != nil { dismiss() }
        }
    }
}
