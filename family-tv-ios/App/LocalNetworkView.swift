import SwiftUI

struct LocalNetworkView: View {
    @Environment(FamilyStore.self) private var store
    @State private var confirmDisconnect = false
    var body: some View {
        List {
            Section {
                Text(L10n.tr("在家里，直接连接电视")).font(.title2.bold())
                Text(L10n.tr("同一局域网时优先加密直连；找不到电视就使用云端。首次配对需要手机和电视联网，之后在有效配对期内可离线控制。"))
            }
            if let device = store.selected {
                Section {
                    LabeledContent(L10n.tr("当前电视"), value: device.label)
                    LabeledContent(L10n.tr("本机配对"), value: store.lan.paired ? L10n.tr("已配对") : L10n.tr("未配对"))
                    Text(store.lan.status).font(.subheadline).foregroundStyle(Color("SupportingText"))
                    if let receipt = store.lan.lastReceipt {
                        LabeledContent(L10n.tr("等待同步的本地指令"), value: String(receipt.pending_sync ?? 0))
                        LabeledContent(L10n.tr("电视执行报告"), value: execution(receipt.execution_result))
                        Text(L10n.tr("已接收不等于已停止播放；停止回执仍需实际画面和声音验证。"))
                            .font(.footnote).foregroundStyle(Color("SupportingText"))
                    }
                }
                Section {
                    Button(store.lan.paired ? L10n.tr("刷新配对授权") : L10n.tr("启用局域网直连")) { Task { await store.pairLocal() } }
                        .disabled(store.busy).accessibilityIdentifier("pairLocalTV")
                    if store.lan.paired {
                        Button(L10n.tr("关闭本机直连"), role: .destructive) { confirmDisconnect = true }.disabled(store.busy)
                    }
                    if store.busy { ProgressView(L10n.tr("正在处理…")) }
                } footer: {
                    Text(L10n.tr("配对仅授权本家庭、本台电视和这部手机，最长 30 天。电视在收到首个有效授权后才开放接收端；离线期间无法立即获知云端撤销。"))
                }
            } else {
                ContentUnavailableView(L10n.tr("先添加并选中电视"), systemImage: "tv", description: Text(L10n.tr("电视需使用支持局域网的配套新版。")))
            }
            Section(L10n.tr("连接与隐私")) {
                Text(L10n.tr("点击启用后，iPhone 会请求本地网络权限，用于发现和连接你的电视。拒绝授权仍可使用云端。"))
                Button(L10n.tr("打开本 App 设置")) { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Text(L10n.tr("手机只在 App 前台发现电视，不借用后台音频或定位常驻。直连仅支持暂停、恢复、临时额度和观看规则，不提供任意命令或远程桌面。"))
                Text(L10n.tr("云端若在断网期间已有新规则，旧本地指令会被拒绝，电视采用云端更新。修改家庭规则仍会在同步后影响家庭内其他电视。"))
            }
        }
        .navigationTitle(L10n.tr("局域网连接")).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L10n.tr("关闭这部手机的直连？"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button(L10n.tr("关闭本机直连"), role: .destructive) { Task { await store.disconnectLocal() } }
            Button(L10n.tr("取消"), role: .cancel) {}
        }
    }
    private func execution(_ value: String?) -> String {
        switch value {
        case "stopped": L10n.tr("已报告停止受管播放")
        case "allowed": L10n.tr("已允许观看，请手动恢复播放")
        case "observing": L10n.tr("观察模式，不执行拦截")
        case "failed": L10n.tr("执行失败，请检查电视权限")
        case "superseded": L10n.tr("同步冲突，已采用云端更新")
        default: L10n.tr("等待电视执行确认")
        }
    }
}
