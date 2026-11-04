import SwiftUI

struct BetterBreaksView: View {
    @Environment(FamilyStore.self) private var store
    @State private var confirm = false
    var body: some View {
        List {
            Section {
                Text(L10n.tr("少一些打断，多一些约定")).font(.title2.bold())
                Text(L10n.tr("先与孩子约好什么时候结束，尽量保持规则稳定。频繁停止、答题再播放，可能让人烦躁或受挫。"))
            }
            Section(L10n.tr("设置建议")) {
                Label(L10n.tr("优先用每日上限和固定休息时段"), systemImage: "calendar")
                Text(L10n.tr("在开始观看前讲清安排，结束时准备一个孩子愿意参与的线下活动。"))
                Label(L10n.tr("避免越看越短的循环"), systemImage: "clock")
                Text(L10n.tr("如果使用答题服务，可让后续每段时长保持一致，避免每两分钟就重新打断一次。答题不用于训练或评估注意力。"))
                Label(L10n.tr("先观察，再调整"), systemImage: "person.2")
                Text(L10n.tr("如果孩子明显烦躁、焦虑或与你发生冲突，先暂停使用这类提醒，一起重新商量安排。"))
            }
            if store.capabilities?.staged_rules != false, store.policyLoaded {
                Section {
                    Button(L10n.tr("预览稳定间隔设置")) { confirm = true }.disabled(store.busy)
                        .accessibilityIdentifier("steadyBreakPreset")
                } footer: {
                    Text(L10n.tr("模板将首次观看设为至少20分钟，之后每段均为20分钟。保留每日上限、休息时段、休息重置时间及临时观看默认时长；不会关闭当前服务的答题功能。只有确认保存后才改变家庭规则。"))
                }
            } else if store.capabilities?.staged_rules == false {
                Section {
                    Text(L10n.tr("当前服务按每日上限和休息时段执行，不使用循环答题。"))
                    NavigationLink(L10n.tr("调整观看规则")) { RulesView() }
                }
            } else {
                Section { ProgressView(L10n.tr("正在获取家庭规则…")) }
            }
            Section(L10n.tr("使用说明")) {
                Text(L10n.tr("20分钟模板和短间隔提示只是产品设置示例，不是适合所有儿童的时长，也不是健康安全阈值。请根据家庭作息和孩子的反应调整。"))
                Text(L10n.tr("这是家庭管理工具，不是医疗产品，不用于诊断、预防或治疗疾病，也不能替代家长陪伴或专业建议。我们尚未验证本工具对长期注意力或情绪发展的影响。"))
            }
        }
        .navigationTitle(L10n.tr("少打扰的休息安排")).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L10n.tr("将稳定间隔用于本家庭全部电视？"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L10n.tr("确认保存稳定间隔")) { Task { _ = await store.savePolicy(BreakDesign.steadyIntervals(store.policy)) } }
            Button(L10n.tr("取消"), role: .cancel) {}
        } message: {
            Text(L10n.tr("首次至少20分钟，之后每段20分钟。其他观看限制保持原值，每台电视仍分别计时。"))
        }
        .familyErrorAlert()
    }
}
