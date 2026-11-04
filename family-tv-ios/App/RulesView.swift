import SwiftUI

struct RulesView: View {
    @Environment(FamilyStore.self) private var store
    @State private var editing = false
    var body: some View {
        List {
            if store.demo { Section { DemoBanner() } }
            if !store.policyLoaded {
                Section {
                    if let failure = store.loadState.failure {
                        Label(L10n.tr("未能获取家庭规则"), systemImage: "exclamationmark.triangle")
                        Text(failure).font(.subheadline).foregroundStyle(Color("SupportingText"))
                        Button(L10n.tr("重新获取")) { Task { await store.refresh() } }
                    } else { ProgressView(L10n.tr("正在获取家庭规则…")) }
                }
            } else {
            if store.loadState.failure != nil {
                Section { Text(L10n.tr("显示上次获取的规则，尚未确认服务端是否已更新。")).font(.subheadline); Button(L10n.tr("重新获取")) { Task { await store.refresh() } } }
            }
            if let limit = store.policy.daily_limit_seconds {
                Section(L10n.tr("每日观看上限")) { LabeledContent(L10n.tr("每天"), value: limit.durationText); Text(L10n.tr("每日额度按北京时间午夜重置，临时额度可以额外放行。")).font(.footnote).foregroundStyle(Color("SupportingText")) }
            }
            if store.capabilities?.staged_rules != false {
            Section {
                LabeledContent(L10n.tr("首次观看"), value: store.policy.initial_seconds.durationText)
                LabeledContent(L10n.tr("首次挑战后"), value: store.policy.first_reward_seconds.durationText)
                LabeledContent(L10n.tr("第二次挑战后"), value: store.policy.second_reward_seconds.durationText)
                LabeledContent(L10n.tr("后续每次"), value: store.policy.repeat_seconds.durationText)
                LabeledContent(L10n.tr("连续休息后重置"), value: store.policy.rest_reset_seconds.durationText)
            } header: { Text(L10n.tr("观看与休息")) } footer: { Text(L10n.tr("当前服务按阶段执行；额度用完后显示电视端挑战页。跨午夜不会自动重置。家庭内电视各自计时。")).foregroundStyle(Color("SupportingText")) }
            }
            Section {
                if store.policy.banned_windows.isEmpty { Text(L10n.tr("尚未设置休息时段")).foregroundStyle(Color("SupportingText")) }
                ForEach(store.policy.banned_windows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(window.label).font(.headline); Spacer(); Text(window.enabled ? L10n.tr("已开启") : L10n.tr("已关闭")).foregroundStyle(Color("SupportingText")) }
                        Text("\(window.start) – \(window.end)").monospacedDigit()
                        Text(daysText(window.days)).font(.footnote).foregroundStyle(Color("SupportingText"))
                    }.padding(.vertical, 4)
                }
            } header: { Text(L10n.tr("休息时段 · 北京时间")) } footer: { Text(L10n.tr("跨午夜时段归属于开始的那一天；开始与结束相同表示全天。临时额度优先于休息时段。")).foregroundStyle(Color("SupportingText")) }
            Section { Button(L10n.tr("编辑规则")) { editing = true }.accessibilityIdentifier("editRules") }
            Section { NavigationLink(L10n.tr("少打扰的休息安排")) { BetterBreaksView() } }
            }
        }
        .navigationTitle(L10n.tr("观看规则"))
        .sheet(isPresented: $editing) { PolicyEditor(policy: store.policy).demoExitFloating(reservingSpace: true) }
    }
}
func daysText(_ days: [Int]) -> String {
    if Set(days) == Set(0...6) { return L10n.tr("每天") }
    let names = [L10n.tr("周日"), L10n.tr("周一"), L10n.tr("周二"), L10n.tr("周三"), L10n.tr("周四"), L10n.tr("周五"), L10n.tr("周六")]
    return days.sorted().filter { (0...6).contains($0) }.map { names[$0] }.joined(separator: "、")
}
struct PolicyEditor: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ViewingPolicy
    @State private var discard = false
    @State private var confirmShortIntervals = false
    private let original: ViewingPolicy
    init(policy: ViewingPolicy) { original = policy; _draft = State(initialValue: policy) }
    var body: some View {
        NavigationStack {
            Form {
                if store.capabilities?.daily_limit == true {
                    Section(L10n.tr("每日观看上限")) {
                        Toggle(L10n.tr("设置每日上限"), isOn: Binding(get: { draft.daily_limit_seconds != nil }, set: { draft.daily_limit_seconds = $0 ? 5400 : nil }))
                        if draft.daily_limit_seconds != nil {
                            minutes(L10n.tr("每天最多"), Binding(get: { draft.daily_limit_seconds ?? 5400 }, set: { draft.daily_limit_seconds = $0 }), range: 1...1440)
                        }
                        Text(store.capabilities?.staged_rules == false ? L10n.tr("按北京时间午夜重置。临时额度可以额外放行；家长暂停优先于临时额度。") : L10n.tr("按北京时间午夜重置；阶段额度同时生效。临时额度可额外放行，家长暂停优先于临时额度。")).font(.footnote).foregroundStyle(Color("SupportingText"))
                    }
                }
                if store.capabilities?.staged_rules != false {
                Section(L10n.tr("每阶段观看额度")) {
                    minutes(L10n.tr("首次观看"), $draft.initial_seconds, range: 1...240)
                    minutes(L10n.tr("首次挑战后"), $draft.first_reward_seconds, range: 1...240)
                    minutes(L10n.tr("第二次挑战后"), $draft.second_reward_seconds, range: 1...120)
                    minutes(L10n.tr("后续每次"), $draft.repeat_seconds, range: 1...120)
                    minutes(L10n.tr("连续休息后重置"), $draft.rest_reset_seconds, range: 1...1440)
                }
                if BreakDesign.hasShortIntervals(draft) {
                    Section {
                        Label(L10n.tr("当前设置可能频繁打断观看"), systemImage: "exclamationmark.bubble")
                        Text(L10n.tr("有观看间隔短于15分钟。短间隔可能带来烦躁或挫败；可考虑保持后续时长一致。15分钟仅为产品提示阈值，不是健康安全标准。"))
                    }
                }
                }
                Section(L10n.tr("休息时段 · 北京时间")) {
                    ForEach($draft.banned_windows) { $window in
                        NavigationLink {
                            WindowEditor(window: $window)
                        } label: {
                            VStack(alignment: .leading) { Text(window.label.isEmpty ? L10n.tr("休息时段") : window.label); Text("\(window.start) – \(window.end) · \(window.enabled ? L10n.tr("开启") : L10n.tr("关闭"))").font(.footnote).foregroundStyle(Color("SupportingText")) }
                        }
                    }.onDelete { draft.banned_windows.remove(atOffsets: $0) }
                    if draft.banned_windows.count < 32 {
                        Button(L10n.tr("添加休息时段"), systemImage: "plus") { draft.banned_windows.append(QuietWindow()) }
                    }
                }
                Section { Text(L10n.tr("保存后对家庭内所有电视生效。电视需要连接服务才能获取新规则。")) }
            }
            .navigationTitle(L10n.tr("编辑规则")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { if draft != original { discard = true } else { dismiss() } }.disabled(store.busy) }
                ToolbarItem(placement: .confirmationAction) { Button(L10n.tr("保存")) {
                    if store.capabilities?.staged_rules != false && BreakDesign.hasShortIntervals(draft) { confirmShortIntervals = true }
                    else { save() }
                }.disabled(!draft.isValid || store.busy).accessibilityIdentifier("saveRules") }
            }
            .confirmationDialog(L10n.tr("继续使用短间隔？"), isPresented: $confirmShortIntervals, titleVisibility: .visible) {
                Button(L10n.tr("按当前设置保存")) { save() }
                Button(L10n.tr("继续调整"), role: .cancel) {}
            } message: { Text(L10n.tr("频繁暂停和重新答题可能造成挫败。建议先与孩子商量，并观察实际反应。")) }
            .confirmationDialog(L10n.tr("放弃未保存的修改？"), isPresented: $discard, titleVisibility: .visible) { Button(L10n.tr("放弃修改"), role: .destructive) { dismiss() }; Button(L10n.tr("继续编辑"), role: .cancel) {} }
        }.interactiveDismissDisabled(draft != original || store.busy)
            .familyErrorAlert(inModal: true)
    }
    private func save() { Task { if await store.savePolicy(draft) { dismiss() } } }
    private func minutes(_ title: String, _ seconds: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: Binding(get: { seconds.wrappedValue / 60 }, set: { seconds.wrappedValue = $0 * 60 }), in: range) {
            VStack(alignment: .leading, spacing: 3) { Text(title); Text(seconds.wrappedValue.durationText).foregroundStyle(Color("SupportingText")).monospacedDigit() }
        }
    }
}
struct WindowEditor: View {
    @Binding var window: QuietWindow
    private let names = [L10n.tr("周日"), L10n.tr("周一"), L10n.tr("周二"), L10n.tr("周三"), L10n.tr("周四"), L10n.tr("周五"), L10n.tr("周六")]
    var body: some View {
        Form {
            Section {
                TextField(L10n.tr("名称"), text: $window.label).onChange(of: window.label) { _, value in window.label = String(value.prefix(64)) }
                Toggle(L10n.tr("开启此时段"), isOn: $window.enabled)
                DatePicker(L10n.tr("开始"), selection: time($window.start), displayedComponents: .hourAndMinute)
                DatePicker(L10n.tr("结束"), selection: time($window.end), displayedComponents: .hourAndMinute)
            }
            Section(L10n.tr("重复日期")) {
                ForEach(0..<7, id: \.self) { day in
                    Toggle(names[day], isOn: Binding(get: { window.days.contains(day) }, set: { enabled in
                        if enabled { window.days.append(day); window.days = Array(Set(window.days)).sorted() }
                        else if window.days.count > 1 { window.days.removeAll { $0 == day } }
                    }))
                }
            }
            Section { Text(L10n.tr("时间使用北京时间；至少保留一个重复日期。跨午夜时段归属于开始的那一天。")) }
        }.navigationTitle(L10n.tr("休息时段")).navigationBarTitleDisplayMode(.inline)
    }
    private func time(_ value: Binding<String>) -> Binding<Date> {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; formatter.timeZone = .current
        return Binding(get: { formatter.date(from: value.wrappedValue) ?? .now }, set: { value.wrappedValue = formatter.string(from: $0) })
    }
}
