import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(FamilyStore.self) private var family
    @Environment(SubscriptionStore.self) private var subscription
    @State private var showManagement = false
    @State private var restoring = false
    private var accountToken: UUID? { family.auth.flatMap { UUID(uuidString: $0.identity.tenant_id) } }
    var body: some View {
        List {
            if family.demo { Section { DemoBanner() } }
            Section {
                Text(L10n.tr("家庭云 Plus")).font(.largeTitle.bold())
                Text(L10n.tr("把每一天，连成看得懂的变化。")).font(.title3).foregroundStyle(Color("SupportingText"))
            }
            Section(L10n.tr("订阅包含")) {
                Label(L10n.tr("云端保存最近 30 天观看历史"), systemImage: "icloud")
                Label(L10n.tr("跨设备同步观看记录"), systemImage: "arrow.triangle.2.circlepath")
                Label(L10n.tr("每周趋势与应用分析"), systemImage: "chart.bar.xaxis")
            }
            Section {
                if family.premiumActive {
                    Label(L10n.tr("订阅有效"), systemImage: "checkmark.circle")
                    if let ms = family.premium.expires_ms { let date = Date(timeIntervalSince1970: ms / 1000); LabeledContent(L10n.tr("当前周期至"), value: date.formatted(.dateTime.locale(L10n.locale).year().month().day())) }
                    Button(L10n.tr("管理订阅")) { showManagement = true }
                } else {
                    if let product = subscription.product {
                        Text(L10n.tr("\(product.displayPrice) / 月")).font(.title2.bold())
                        Button(L10n.tr("按月订阅")) {
                            if let accountToken { Task { await subscription.purchase(accountToken: accountToken) } }
                        }.buttonStyle(.borderedProminent).disabled(subscription.purchasing || restoring || subscription.entitled || family.demo || accountToken == nil || family.capabilities?.paid_history != true)
                    } else if subscription.loading { ProgressView(L10n.tr("正在获取 App Store 价格…")) }
                    else { Button(L10n.tr("重新获取订阅价格")) { Task { await subscription.load() } } }
                    if !family.demo && family.capabilities?.paid_history != true { Text(L10n.tr("当前家庭服务尚未支持家庭云订阅，请确认服务连接后重试。")).font(.footnote).foregroundStyle(Color("SupportingText")) }
                    if family.demo { Text(L10n.tr("演示模式不发起真实购买。")).font(.footnote).foregroundStyle(Color("SupportingText")) }
                    else if accountToken == nil { Text(L10n.tr("请先登录家庭账号，再订阅家庭云。")).font(.footnote).foregroundStyle(Color("SupportingText")) }
                }
                Button(L10n.tr("恢复购买")) {
                    Task {
                        guard let session = family.auth?.token else { return }
                        restoring = true; defer { restoring = false }
                        let proof = await subscription.restore()
                        guard family.auth?.token == session else { return }
                        let ids = await family.syncSubscriptions(subscription.signedTransactions, signedAppTransaction: proof)
                        guard family.auth?.token == session else { return }
                        await subscription.finishSyncedTransactions(transactionIDs: ids)
                        if family.premiumActive { subscription.message = L10n.tr("购买已恢复到当前家庭。") }
                    }
                }.disabled(subscription.purchasing || restoring || family.demo || accountToken == nil || family.capabilities?.paid_history != true)
                if subscription.purchasing || restoring { ProgressView(L10n.tr("正在处理订阅…")) }
                if subscription.hasAccess(for: family.auth?.identity.tenant_id) && !family.premiumActive && !family.demo {
                    Text(family.subscriptionSyncError ?? L10n.tr("Apple 订阅已验证，正在同步家庭云。")).font(.subheadline)
                    Button(L10n.tr("重新同步家庭云")) { Task { if let accountToken { let ids = await family.syncSubscriptions(subscription.receipts(for: accountToken, ownedOriginalIDs: Set(family.premium.original_ids ?? []))); await subscription.finishSyncedTransactions(transactionIDs: ids) } } }
                }
                if subscription.entitled && !family.premiumActive && !subscription.hasAccess(for: family.auth?.identity.tenant_id) && !family.demo { Text(L10n.tr("订阅关联其他家庭时，请登录原家庭。原家庭已永久删除的，可在这里恢复购买。")).font(.subheadline) }
                if let message = subscription.message { Text(message).font(.subheadline).foregroundStyle(Color("SupportingText")) }
            } footer: {
                Text(L10n.tr("月度自动续订。付款由 Apple 收取，续订价格以购买确认页为准；可随时在 Apple 订阅设置中取消，取消后可用至当前周期结束。订阅有效时保留最近 30 天云端历史；到期后停止保留往日记录。设备连接和基础控制可免费使用。")).foregroundStyle(Color("SupportingText"))
            }
            Section {
                NavigationLink(L10n.tr("隐私与数据")) { PrivacyView() }
                Link(L10n.tr("订阅使用条款"), destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link(L10n.tr("联系支持"), destination: URL(string: "mailto:contact@minnuo.net")!)
            }
        }
        .navigationTitle(L10n.tr("家庭云 Plus")).navigationBarTitleDisplayMode(.inline)
        .task { await subscription.load() }
        .manageSubscriptionsSheet(isPresented: $showManagement)
    }
}
