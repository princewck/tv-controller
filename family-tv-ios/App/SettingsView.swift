import SwiftUI

struct SettingsView: View {
    @Environment(FamilyStore.self) private var store
    @State private var leaving = false
    var body: some View {
        List {
            Section {
                if store.demo { DemoBanner() }
                else {
                    LabeledContent("家庭账号", value: store.auth?.identity.username ?? "")
                    LabeledContent("连接方式", value: ServiceEndpoint.label(for: store.auth?.origin.absoluteString ?? ""))
                    if let origin = store.auth?.origin, !ServiceEndpoint.isOfficial(origin.absoluteString) {
                        LabeledContent("服务地址", value: origin.absoluteString).font(.footnote)
                    }
                }
            }
            Section { NavigationLink("家庭云 Plus") { SubscriptionView() } }
            Section("家庭设备") {
                ForEach(store.devices) { device in
                    HStack {
                        Label(device.label, systemImage: "tv")
                        Spacer()
                        Text(device.isOnline() ? "最近在线" : "未连接").foregroundStyle(Color("SupportingText"))
                    }.accessibilityElement(children: .combine)
                }
                NavigationLink("添加电视") { InstallationView() }
            }
            Section("帮助与隐私") {
                Link("联系支持", destination: URL(string: "mailto:contact@minnuo.net")!)
                NavigationLink("设备安装助手") { InstallationView() }
                NavigationLink("隐私与数据") { PrivacyView() }
                NavigationLink("关于观有度") {
                    List {
                        Section { Text("观有度 / Family TV").font(.title2.bold()); Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"))"); Text("给电视时间留一点约定。") }
                        Section { Text("本 App 是 Android TV 的家长管理端，需要配套电视客户端和云端服务。演示模式完全在本机运行。") }
                        Section { Link("配套客户端与问题反馈", destination: URL(string: "https://github.com/princewck/tv-controller")!) }
                    }.navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
                }
            }
            if !store.demo, store.capabilities?.household_delete == true {
                Section { NavigationLink("删除家庭与云端数据") { DeleteHouseholdView() } }
            }
            Section { Button(store.demo ? "退出演示模式" : "退出登录", role: .destructive) { leaving = true }.disabled(store.busy) }
        }
        .navigationTitle("我的家庭")
        .confirmationDialog(store.demo ? "退出演示模式？" : "退出当前家庭？", isPresented: $leaving, titleVisibility: .visible) {
            Button("确认退出", role: .destructive) { Task { await store.logout() } }
            Button("取消", role: .cancel) {}
        } message: { Text("退出不会删除云端记录，也不会解除电视现有规则。") }
    }
}
struct PrivacyView: View {
    var body: some View {
        List {
            Section("本机保存") { Text("服务签发的登录会话保存在本机钥匙串，不同步到 iCloud。App 不保存你的密码，不接入广告或第三方行为分析。退出登录将清除本机凭证。") }
            Section("服务端处理") { Text("你选择的服务保存家庭账号、设备标识、规则、受管应用包名、观看时长和操作记录，用于认证与执行观看规则。服务会处理连接所需的网络地址。记录不包含视频画面、声音、联系人、位置或浏览内容。") }
            Section("演示模式") { Text("演示使用本机生成的示例数据，不发送电视指令，不需要真实账号。退出演示不会删除真实家庭数据。") }
            Section("查看与删除数据") { Text("家庭云 Plus 在订阅有效时保留最近 30 天观看记录；免费账号只可查看当天记录；往日数据会在每日清理时移除。可在“我的”中删除家庭与云端数据；退出登录只清除本机登录凭证。独立测试服务的数据请联系运营者处理。") }
            Section("请由家长使用") { Text("配置电视前，请向家庭成员说明统计范围和观看规则。不需要填写孩子姓名、生日或其他儿童档案。") }
        }.navigationTitle("隐私与数据").navigationBarTitleDisplayMode(.inline)
    }
}
