import SwiftUI

struct InstallationView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var showLogin = false
    @State private var health: InstallationHealth?
    @State private var checkError: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(step + 1) / 4").font(.subheadline).monospacedDigit().foregroundStyle(Color("SupportingText"))
                Spacer()
                if store.demo { Text(L10n.tr("演示")).font(.subheadline).foregroundStyle(Color("SupportingText")) }
            }.padding(.horizontal, 24).padding(.top, 12)
            TabView(selection: Binding(get: { step }, set: { target in
                if canNavigate(to: target) { step = target }
            })) {
                slide(icon: "wifi", title: L10n.tr("先连上同一个 Wi-Fi"), subtitle: L10n.tr("请确保电视和运行 Codex、Cursor 等 Agent 助手的电脑，在同一个 Wi-Fi 下。")) {
                    Text(L10n.tr("准备好电视和电脑，就可以继续。")).foregroundStyle(Color("SupportingText"))
                }.tag(0)
                slide(icon: "camera.viewfinder", title: L10n.tr("截图，交给你的助手"), subtitle: L10n.tr("请截图本页并发给你的 Agent 助手。")) {
                    if let ticket = store.setupTicket {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(ticket.agentPrompt).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            Divider()
                            LabeledContent(L10n.tr("服务"), value: ServiceEndpoint.isOfficial(ticket.origin) ? L10n.tr("官方服务") : ticket.origin).font(.footnote)
                            Text(L10n.tr("设备：\(ticket.device)")).font(.caption.monospaced()).textSelection(.enabled)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.tr("安装码 · 15 分钟内有效")).font(.footnote).foregroundStyle(Color("SupportingText"))
                                Text(ticket.displayCode).font(.title3.monospaced().bold()).textSelection(.enabled)
                            }
                            if ticket.expired {
                                Button(L10n.tr("安装码已过期，重新生成")) { Task { await store.prepareInstallation() } }
                            }
                        }.padding(20).background(.background, in: .rect(cornerRadius: 16))
                    } else {
                        Button(store.connected ? L10n.tr("生成安装码") : L10n.tr("登录家庭，生成安装码")) {
                            if store.connected { Task { await store.prepareInstallation() } } else { showLogin = true }
                        }.buttonStyle(.borderedProminent).disabled(store.busy).frame(minHeight: 44)
                        if store.busy { ProgressView(L10n.tr("正在准备安装页…")) }
                    }
                }.tag(1)
                if store.setupTicket != nil {
                slide(icon: "checkmark.shield", title: L10n.tr("看看连接是否健康"), subtitle: L10n.tr("助手完成测试后，这里会自动更新。")) {
                    VStack(spacing: 16) {
                        check(L10n.tr("电视已连接"), verifiedHealth?.checks.connected == true)
                        check(L10n.tr("播放拦截与恢复已验证"), verifiedHealth?.checks.playback_test == true)
                        check(L10n.tr("必要权限正常"), verifiedHealth?.checks.permissions == true)
                        check(L10n.tr("ADB 已关闭"), verifiedHealth?.checks.adb_closed == true)
                        check(L10n.tr("完整重启后重新连接"), verifiedHealth?.checks.rebooted == true)
                    }.padding(20).background(.background, in: .rect(cornerRadius: 16))
                    Text(L10n.tr("最后请执行系统重启，不要点“关机”；关机可能只是熄屏。"))
                        .font(.subheadline).foregroundStyle(.primary)
                    if let checkError { Text(checkError).font(.footnote).foregroundStyle(Color("SupportingText")) }
                    if store.demo {
                        Button(L10n.tr("演示检查通过的效果")) {
                            health = InstallationHealth(device: "demo-install", checks: InstallationChecks(connected: true, playback_test: true, adb_closed: true, rebooted: true, permissions: true), complete: true)
                        }.frame(minHeight: 44).accessibilityIdentifier("demoInstallationPass")
                    } else { Button(L10n.tr("重新检查")) { Task { await refreshHealth() } }.frame(minHeight: 44) }
                }.tag(2)
                }
                if verifiedHealth?.complete == true {
                slide(icon: verifiedHealth?.complete == true ? "checkmark.circle" : "hourglass", title: verifiedHealth?.complete == true ? L10n.tr("配置完成") : L10n.tr("还差最后的检查"), subtitle: verifiedHealth?.complete == true ? L10n.tr("电视已经准备好，现在可以约定观看与休息时间了。") : L10n.tr("请回到上一步，等待健康检查通过。")) {
                    if verifiedHealth?.complete == true { Text(store.demo ? L10n.tr("这是演示结果，没有配置真实电视。") : L10n.tr("接下来，交给观有度。")).foregroundStyle(Color("SupportingText")) }
                }.tag(3)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                if step > 0 { Button(L10n.tr("上一步")) { withAnimation { step -= 1 } }.frame(minHeight: 44) }
                Button(buttonTitle) {
                    if step == 3, verifiedHealth?.complete == true { store.setupTicket = nil; dismiss() }
                    else { withAnimation { step += 1 } }
                }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
                    .disabled((step == 1 && store.setupTicket == nil) || (step >= 2 && verifiedHealth?.complete != true))
                    .accessibilityIdentifier("installationNext")
            }.padding(.horizontal, 24).padding(.bottom, 12).background(.bar)
        }
        .navigationTitle(L10n.tr("添加电视")).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLogin) { LoginView() }
        .task(id: step) {
            guard step == 2, !store.demo else { return }
            while !Task.isCancelled {
                await refreshHealth()
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }
    private var verifiedHealth: InstallationHealth? {
        guard health?.device == store.setupTicket?.device else { return nil }
        return health
    }
    private func canNavigate(to target: Int) -> Bool {
        if target <= step { return true }
        guard target == step + 1 else { return false }
        if step == 1 { return store.setupTicket != nil }
        if step >= 2 { return verifiedHealth?.complete == true }
        return true
    }
    private var buttonTitle: String {
        switch step {
        case 0: L10n.tr("已在同一 Wi-Fi，下一步")
        case 1: L10n.tr("已交给助手，查看检查")
        case 2: verifiedHealth?.complete == true ? L10n.tr("检查通过，下一步") : L10n.tr("等待检查通过")
        default: verifiedHealth?.complete == true ? L10n.tr("完成") : L10n.tr("等待检查通过")
        }
    }
    private func check(_ title: String, _ passed: Bool) -> some View {
        HStack { Image(systemName: passed ? "checkmark.circle.fill" : "circle").foregroundStyle(passed ? Color.accentColor : .secondary); Text(title); Spacer(); Text(passed ? L10n.tr("通过") : L10n.tr("等待")).foregroundStyle(Color("SupportingText")).font(.footnote) }.accessibilityElement(children: .combine)
    }
    private func slide<Content: View>(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: icon).font(.largeTitle).foregroundStyle(Color.accentColor).accessibilityHidden(true)
                Text(title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                content()
            }.padding(24).padding(.top, 16).frame(maxWidth: 600)
        }
    }
    private func refreshHealth() async {
        guard let ticket = store.setupTicket else { checkError = L10n.tr("先生成安装码并交给助手。"); return }
        do {
            let result = try await store.installationHealth(device: ticket.device)
            guard store.setupTicket?.device == ticket.device else { return }
            health = result; checkError = nil
        }
        catch { health = nil; checkError = L10n.tr("暂时未能获取检查结果，请稍后重试。") }
    }
}
