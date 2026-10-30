import SwiftUI

struct RegistrationView: View {
    @Environment(FamilyStore.self) private var store
    let origin: String
    @State private var username = ""
    @State private var password = ""
    @State private var repeated = ""
    private var valid: Bool { username.range(of: "^[a-z0-9][a-z0-9_.-]{2,31}$", options: .regularExpression) != nil && password.count >= 12 && password.count <= 128 && password == repeated }
    var body: some View {
        Form {
            Section {
                TextField("家庭用户名", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("设置密码", text: $password).textContentType(.newPassword)
                SecureField("再次输入密码", text: $repeated).textContentType(.newPassword)
            } header: { Text("创建你的家庭") } footer: { Text("用户名使用 3–32 位小写字母、数字或 . _ -；密码至少 12 位。无需填写孩子的姓名或生日。") }
            Section {
                Button { Task { await store.register(origin: origin, username: username, password: password); password = ""; repeated = "" } } label: {
                    HStack { Text("创建家庭"); Spacer(); if store.busy { ProgressView() } }
                }.disabled(!valid || store.busy)
            }
            Section {
                NavigationLink("隐私与数据") { PrivacyView() }
                Link("使用条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text(origin).font(.footnote).foregroundStyle(Color("SupportingText"))
            }
        }.navigationTitle("创建家庭").navigationBarTitleDisplayMode(.inline)
    }
}
struct RecoveryCodeView: View {
    @Environment(FamilyStore.self) private var store
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("保存好家庭恢复码").font(.title2.bold())
                    Text("忘记密码时，可以用它找回家庭账号。恢复码只显示这一次，请保存在密码管理器等安全位置。")
                }
                if let code = store.pendingRecoveryCode {
                    Section {
                        Text(code).font(.body.monospaced()).textSelection(.enabled)
                        ShareLink("保存恢复码", item: code)
                    }
                }
                Section { Button("我已妥善保存") { store.pendingRecoveryCode = nil }.frame(minHeight: 44) }
            }.navigationTitle("家庭恢复码").navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
    }
}
struct DeleteHouseholdView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(SubscriptionStore.self) private var subscription
    @State private var password = ""
    @State private var confirm = false
    @State private var showManagement = false
    var body: some View {
        Form {
            Section {
                Text("删除后，家庭账号、设备绑定、观看记录和云端规则会从服务中删除，无法在 App 中恢复。电视联网后会解除本家庭的绑定；离线电视在再次连接前仍会沿用缓存规则。")
                Text("Apple 订阅需要单独取消，删除家庭不会停止 Apple 扣款。原家庭删除后，可在 App Store 登录购买时的 Apple 账号，再在 App 登录新家庭，进入家庭云页面恢复剩余订阅；已删除的数据无法恢复。你也可以先管理订阅。")
                Button("管理 Apple 订阅") { showManagement = true }
            }
            Section("确认身份") { SecureField("当前家庭密码", text: $password).textContentType(.password) }
            Section { Button("永久删除家庭", role: .destructive) { confirm = true }.disabled(password.isEmpty || store.busy) }
        }
        .navigationTitle("删除家庭").navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showManagement)
        .confirmationDialog("永久删除这个家庭？", isPresented: $confirm, titleVisibility: .visible) {
            Button("确认永久删除", role: .destructive) { Task { _ = await store.deleteHousehold(password: password); password = "" } }
            Button("取消", role: .cancel) {}
        }
    }
}

struct AccountRecoveryView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let origin: String
    @State private var username = ""
    @State private var recoveryCode = ""
    @State private var password = ""
    @State private var repeated = ""
    @State private var replacementCode: String?
    private var valid: Bool { !username.isEmpty && !recoveryCode.isEmpty && (12...128).contains(password.count) && password == repeated }
    var body: some View {
        Form {
            if let replacementCode {
                Section {
                    Text("家庭密码已更新").font(.title2.bold())
                    Text("旧恢复码已失效。请保存新的恢复码，再使用新密码登录。")
                    Text(replacementCode).font(.body.monospaced()).textSelection(.enabled)
                    ShareLink("保存新恢复码", item: replacementCode)
                    Button("我已保存，返回登录") { dismiss() }
                }
            } else {
                Section {
                    TextField("家庭用户名", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("家庭恢复码", text: $recoveryCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("设置新密码", text: $password).textContentType(.newPassword)
                    SecureField("再次输入新密码", text: $repeated).textContentType(.newPassword)
                } footer: { Text("恢复码是在创建家庭时保存的代码。密码至少 12 位；恢复成功后，所有设备上的家庭登录凭证都会失效。电视绑定保持有效。") }
                Section {
                    Button("重设家庭密码") { Task {
                        replacementCode = await store.recover(origin: origin, username: username, recoveryCode: recoveryCode, password: password)
                        password = ""; repeated = ""; recoveryCode = ""
                    } }.disabled(!valid || store.busy)
                    if store.busy { ProgressView() }
                }
            }
        }.navigationTitle("找回家庭账号").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(replacementCode != nil)
    }
}
