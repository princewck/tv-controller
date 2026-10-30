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
                        Label("未能获取家庭规则", systemImage: "exclamationmark.triangle")
                        Text(failure).font(.subheadline).foregroundStyle(Color("SupportingText"))
                        Button("重新获取") { Task { await store.refresh() } }
                    } else { ProgressView("正在获取家庭规则…") }
                }
            } else {
            if store.loadState.failure != nil {
                Section { Text("显示上次获取的规则，尚未确认服务端是否已更新。").font(.subheadline); Button("重新获取") { Task { await store.refresh() } } }
            }
            if let limit = store.policy.daily_limit_seconds {
                Section("每日观看上限") { LabeledContent("每天", value: limit.durationText); Text("每日额度按北京时间午夜重置，临时额度可以额外放行。").font(.footnote).foregroundStyle(Color("SupportingText")) }
            }
            if store.capabilities?.staged_rules != false {
            Section {
                LabeledContent("首次观看", value: store.policy.initial_seconds.durationText)
                LabeledContent("首次挑战后", value: store.policy.first_reward_seconds.durationText)
                LabeledContent("第二次挑战后", value: store.policy.second_reward_seconds.durationText)
                LabeledContent("后续每次", value: store.policy.repeat_seconds.durationText)
                LabeledContent("连续休息后重置", value: store.policy.rest_reset_seconds.durationText)
            } header: { Text("观看与休息") } footer: { Text("当前服务按阶段执行；额度用完后显示电视端挑战页。跨午夜不会自动重置。家庭内电视各自计时。").foregroundStyle(Color("SupportingText")) }
            }
            Section {
                if store.policy.banned_windows.isEmpty { Text("尚未设置休息时段").foregroundStyle(Color("SupportingText")) }
                ForEach(store.policy.banned_windows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(window.label).font(.headline); Spacer(); Text(window.enabled ? "已开启" : "已关闭").foregroundStyle(Color("SupportingText")) }
                        Text("\(window.start) – \(window.end)").monospacedDigit()
                        Text(daysText(window.days)).font(.footnote).foregroundStyle(Color("SupportingText"))
                    }.padding(.vertical, 4)
                }
            } header: { Text("休息时段 · 北京时间") } footer: { Text("跨午夜时段归属于开始的那一天；开始与结束相同表示全天。临时额度优先于休息时段。").foregroundStyle(Color("SupportingText")) }
            Section { Button("编辑规则") { editing = true }.accessibilityIdentifier("editRules") }
            }
        }
        .navigationTitle("观看规则")
        .sheet(isPresented: $editing) { PolicyEditor(policy: store.policy) }
    }
}
func daysText(_ days: [Int]) -> String {
    if Set(days) == Set(0...6) { return "每天" }
    let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    return days.sorted().filter { (0...6).contains($0) }.map { names[$0] }.joined(separator: "、")
}
struct PolicyEditor: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ViewingPolicy
    @State private var discard = false
    private let original: ViewingPolicy
    init(policy: ViewingPolicy) { original = policy; _draft = State(initialValue: policy) }
    var body: some View {
        NavigationStack {
            Form {
                if store.capabilities?.daily_limit == true {
                    Section("每日观看上限") {
                        Toggle("设置每日上限", isOn: Binding(get: { draft.daily_limit_seconds != nil }, set: { draft.daily_limit_seconds = $0 ? 5400 : nil }))
                        if draft.daily_limit_seconds != nil {
                            minutes("每天最多", Binding(get: { draft.daily_limit_seconds ?? 5400 }, set: { draft.daily_limit_seconds = $0 }), range: 1...1440)
                        }
                        Text(store.capabilities?.staged_rules == false ? "按北京时间午夜重置。临时额度可以额外放行；家长暂停优先于临时额度。" : "按北京时间午夜重置；阶段额度同时生效。临时额度可额外放行，家长暂停优先于临时额度。").font(.footnote).foregroundStyle(Color("SupportingText"))
                    }
                }
                if store.capabilities?.staged_rules != false {
                Section("每阶段观看额度") {
                    minutes("首次观看", $draft.initial_seconds, range: 1...240)
                    minutes("首次挑战后", $draft.first_reward_seconds, range: 1...240)
                    minutes("第二次挑战后", $draft.second_reward_seconds, range: 1...120)
                    minutes("后续每次", $draft.repeat_seconds, range: 1...120)
                    minutes("连续休息后重置", $draft.rest_reset_seconds, range: 1...1440)
                }
                }
                Section("休息时段 · 北京时间") {
                    ForEach($draft.banned_windows) { $window in
                        NavigationLink {
                            WindowEditor(window: $window)
                        } label: {
                            VStack(alignment: .leading) { Text(window.label.isEmpty ? "休息时段" : window.label); Text("\(window.start) – \(window.end) · \(window.enabled ? "开启" : "关闭")").font(.footnote).foregroundStyle(Color("SupportingText")) }
                        }
                    }.onDelete { draft.banned_windows.remove(atOffsets: $0) }
                    if draft.banned_windows.count < 32 {
                        Button("添加休息时段", systemImage: "plus") { draft.banned_windows.append(QuietWindow()) }
                    }
                }
                Section { Text("保存后对家庭内所有电视生效。电视需要连接服务才能获取新规则。") }
            }
            .navigationTitle("编辑规则").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { if draft != original { discard = true } else { dismiss() } }.disabled(store.busy) }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { if await store.savePolicy(draft) { dismiss() } } }.disabled(!draft.isValid || store.busy).accessibilityIdentifier("saveRules") }
            }
            .confirmationDialog("放弃未保存的修改？", isPresented: $discard, titleVisibility: .visible) { Button("放弃修改", role: .destructive) { dismiss() }; Button("继续编辑", role: .cancel) {} }
        }.interactiveDismissDisabled(draft != original || store.busy)
            .familyErrorAlert(inModal: true)
    }
    private func minutes(_ title: String, _ seconds: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: Binding(get: { seconds.wrappedValue / 60 }, set: { seconds.wrappedValue = $0 * 60 }), in: range) {
            VStack(alignment: .leading, spacing: 3) { Text(title); Text(seconds.wrappedValue.durationText).foregroundStyle(Color("SupportingText")).monospacedDigit() }
        }
    }
}
struct WindowEditor: View {
    @Binding var window: QuietWindow
    private let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    var body: some View {
        Form {
            Section {
                TextField("名称", text: $window.label).onChange(of: window.label) { _, value in window.label = String(value.prefix(64)) }
                Toggle("开启此时段", isOn: $window.enabled)
                DatePicker("开始", selection: time($window.start), displayedComponents: .hourAndMinute)
                DatePicker("结束", selection: time($window.end), displayedComponents: .hourAndMinute)
            }
            Section("重复日期") {
                ForEach(0..<7, id: \.self) { day in
                    Toggle(names[day], isOn: Binding(get: { window.days.contains(day) }, set: { enabled in
                        if enabled { window.days.append(day); window.days = Array(Set(window.days)).sorted() }
                        else if window.days.count > 1 { window.days.removeAll { $0 == day } }
                    }))
                }
            }
            Section { Text("时间使用北京时间；至少保留一个重复日期。跨午夜时段归属于开始的那一天。") }
        }.navigationTitle("休息时段").navigationBarTitleDisplayMode(.inline)
    }
    private func time(_ value: Binding<String>) -> Binding<Date> {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; formatter.timeZone = .current
        return Binding(get: { formatter.date(from: value.wrappedValue) ?? .now }, set: { value.wrappedValue = formatter.string(from: $0) })
    }
}
