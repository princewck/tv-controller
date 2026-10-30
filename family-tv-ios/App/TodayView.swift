import SwiftUI

struct TodayView: View {
    @Environment(FamilyStore.self) private var store
    @State private var showGrant = false
    @State private var confirmPause = false
    var body: some View {
        List {
            if store.demo { Section { DemoBanner() } }
            if let notice = store.notice {
                Section { Label(notice, systemImage: "info.circle").font(.subheadline).accessibilityIdentifier("operationNotice") }
            }
            if let failure = store.loadState.failure {
                Section {
                    Label("未能更新状态", systemImage: "exclamationmark.triangle")
                    Text(failure).font(.subheadline).foregroundStyle(Color("SupportingText"))
                    if let last = store.lastRefresh { Text("以下为上次获取的数据：\(last.formatted(date: .abbreviated, time: .shortened))").font(.footnote) }
                    Button("重新获取") { Task { await store.refresh() } }
                }
            }
            if !store.devices.isEmpty {
                Section {
                    Picker("当前电视", selection: Binding(get: { store.selectedID ?? "" }, set: { id in Task { await store.select(id) } })) {
                        ForEach(store.devices) { device in Text(device.label).tag(device.id) }
                    }
                    if let device = store.selected {
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            Label(device.isOnline(at: context.date) ? "最近在线" : "离线或尚未连接", systemImage: device.isOnline(at: context.date) ? "wifi" : "wifi.slash")
                                .foregroundStyle(device.isOnline(at: context.date) ? Color.accentColor : Color("SupportingText"))
                        }
                        if let ms = device.last_heartbeat_ms {
                            LabeledContent("上次电视连接") { Text(Date(timeIntervalSince1970: ms / 1000), style: .relative).foregroundStyle(Color("SupportingText")) }
                        }
                    }
                }
            }
            if let usage = store.usage {
                Section("今天的观看") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(usage.todaySeconds.durationText).font(.largeTitle.bold()).monospacedDigit().minimumScaleFactor(0.7)
                        Spacer()
                    }.padding(.vertical, 12).accessibilityIdentifier("todayDuration")
                    LabeledContent("剩余观看时间", value: usage.state.remaining_seconds.durationText)
                    LabeledContent(store.loadState.failure == nil ? "云端规则状态" : "上次云端规则状态", value: usage.state.status == "lock" ? "需要休息" : "允许观看")
                    if let limit = store.policy.daily_limit_seconds {
                        LabeledContent("每日观看上限", value: limit.durationText)
                    }
                    if usage.state.control_revision != nil {
                        Text(usage.state.executionText).font(.subheadline).foregroundStyle(Color("SupportingText"))
                    }
                    if (usage.state.override_seconds ?? 0) > 0 {
                        LabeledContent("临时额度", value: (usage.state.override_seconds ?? 0).durationText)
                    }
                }
                Section {
                    if store.capabilities?.pause == true {
                        Button { confirmPause = true } label: {
                            Label(usage.state.paused == true ? "解除家长暂停" : "让电视休息一下", systemImage: usage.state.paused == true ? "play" : "pause")
                        }.disabled(store.busy).accessibilityIdentifier("pauseTV")
                    }
                    Button { showGrant = true } label: { Label("给予临时观看时间", systemImage: "gift") }
                        .disabled(store.busy || store.selected?.enabled != 1).accessibilityIdentifier("grantTime")
                    NavigationLink { RulesView() } label: { Label("调整观看规则", systemImage: "slider.horizontal.3") }
                } footer: {
                    Text("临时额度会替换上次额度，并优先于休息时段。云端允许观看不代表电视已执行。")
                }
                Section("受管应用") {
                    let rows = usage.daily.filter { $0.day == usage.today && $0.seconds > 0 }
                    if rows.isEmpty { Text("今天还没有观看记录").foregroundStyle(Color("SupportingText")) }
                    ForEach(rows) { row in LabeledContent(row.appName, value: row.seconds.durationText) }
                }
            } else if store.devices.isEmpty && store.loadState == .loaded {
                Section {
                    ContentUnavailableView("还没有电视", systemImage: "tv", description: Text("跟着四步引导，让你的 Agent 助手完成配置。"))
                    NavigationLink("添加电视") { InstallationView() }
                }
            } else if store.loadState.failure == nil {
                Section { ProgressView("正在获取观看情况…") }
            }
            Section {
                if let last = store.lastRefresh { LabeledContent("本页更新于") { Text(last, style: .time) } }
                Button("刷新状态") { Task { await store.refresh() } }
                Text("统计日期按北京时间计算；仅包含受管应用的播放采样。")
                    .font(.footnote).foregroundStyle(Color("SupportingText"))
            }
        }
        .navigationTitle("今天")
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showGrant) { GrantView() }
        .confirmationDialog(store.usage?.state.paused == true ? "解除家长暂停？" : "暂停受管视频播放？", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("确认") { Task { await store.setPaused(store.usage?.state.paused != true) } }
            Button("取消", role: .cancel) {}
        } message: { Text("指令只作用于当前电视。解除暂停后，观看额度和休息时段仍然有效。") }
    }
}
struct GrantView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 15
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("观看时间", selection: $minutes) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) 分钟").tag($0) }
                    }.pickerStyle(.wheel)
                } header: { Text(store.selected?.label ?? "电视") } footer: {
                    Text("这会替换已有临时额度，并在休息时段内放行。离线电视需要重新连接后才能获取。")
                }
                Section {
                    Button { Task { await store.grant(minutes: minutes); if store.error == nil { dismiss() } } } label: {
                        HStack { Text("确认给予 \(minutes) 分钟"); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(store.busy).accessibilityIdentifier("confirmGrant")
                }
            }
            .navigationTitle("多一点观看时间").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.busy) } }
        }.presentationDetents([.medium, .large]).interactiveDismissDisabled(store.busy)
    }
}
