import SwiftUI

struct TodayView: View {
    @Environment(FamilyStore.self) private var store
    @State private var showGrant = false
    @State private var confirmPause = false
    var body: some View {
        List {
            if store.demo {
                Section {
                    DemoBanner()
                    NavigationLink {
                        TVGuideView()
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            TVIllustrationView(example: store.usage?.state.status == "lock" ? .paused : (store.usage?.state.override_seconds ?? 0) > 0 ? .extraTime : .watching)
                            Label(L10n.tr("看看电视上的变化（示例）"), systemImage: "tv")
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("demoTVGuide")
                }
            }
            if let notice = store.notice {
                Section { Label(notice, systemImage: "info.circle").font(.subheadline).accessibilityIdentifier("operationNotice") }
            }
            if let failure = store.loadState.failure {
                Section {
                    Label(L10n.tr("未能更新状态"), systemImage: "exclamationmark.triangle")
                    Text(failure).font(.subheadline).foregroundStyle(Color("SupportingText"))
                    if let last = store.lastRefresh { Text(L10n.tr("以下为上次获取的数据：\(last.formatted(.dateTime.locale(L10n.locale).year().month().day().hour().minute()))")).font(.footnote) }
                    Button(L10n.tr("重新获取")) { Task { await store.refresh() } }
                }
            }
            if !store.devices.isEmpty {
                Section {
                    Picker(L10n.tr("当前电视"), selection: Binding(get: { store.selectedID ?? "" }, set: { id in Task { await store.select(id) } })) {
                        ForEach(store.devices) { device in Text(device.label).tag(device.id) }
                    }.disabled(store.busy)
                    if !store.demo, store.capabilities?.lan == true {
                        NavigationLink { LocalNetworkView() } label: {
                            Label(store.lan.localOnline ? L10n.tr("局域网直连在线") : L10n.tr("局域网连接"), systemImage: "network")
                        }
                    }
                    if let device = store.selected {
                        TimelineView(.periodic(from: .now, by: 10)) { context in
                            Label(device.isOnline(at: context.date) ? L10n.tr("最近在线") : L10n.tr("离线或尚未连接"), systemImage: device.isOnline(at: context.date) ? "wifi" : "wifi.slash")
                                .foregroundStyle(device.isOnline(at: context.date) ? Color.accentColor : Color("SupportingText"))
                        }
                        if let ms = device.last_heartbeat_ms {
                            LabeledContent(L10n.tr("上次电视连接")) { Text(Date(timeIntervalSince1970: ms / 1000), style: .relative).foregroundStyle(Color("SupportingText")) }
                        }
                    }
                }
            }
            if let usage = store.usage {
                Section(L10n.tr("今天的观看")) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(usage.todaySeconds.durationText).font(.largeTitle.bold()).monospacedDigit().minimumScaleFactor(0.7)
                        Spacer()
                    }.padding(.vertical, 12).accessibilityIdentifier("todayDuration")
                    LabeledContent(L10n.tr("剩余观看时间"), value: usage.state.remaining_seconds.durationText)
                    LabeledContent(store.lan.localOnline ? L10n.tr("电视当前规则状态") : store.loadState.failure == nil ? L10n.tr("云端规则状态") : L10n.tr("上次云端规则状态"), value: usage.state.status == "lock" ? L10n.tr("需要休息") : L10n.tr("允许观看"))
                    if let limit = store.policy.daily_limit_seconds {
                        LabeledContent(L10n.tr("每日观看上限"), value: limit.durationText)
                    }
                    if usage.state.control_revision != nil {
                        Text(usage.state.executionText).font(.subheadline).foregroundStyle(Color("SupportingText"))
                    }
                    if (usage.state.override_seconds ?? 0) > 0 {
                        LabeledContent(L10n.tr("临时额度"), value: (usage.state.override_seconds ?? 0).durationText)
                    }
                }
                Section {
                    if store.capabilities?.pause == true {
                        Button { confirmPause = true } label: {
                            Label(usage.state.paused == true ? L10n.tr("解除家长暂停") : L10n.tr("让电视休息一下"), systemImage: usage.state.paused == true ? "play" : "pause")
                        }.disabled(store.busy).accessibilityIdentifier("pauseTV")
                    }
                    Button { showGrant = true } label: { Label(L10n.tr("给予临时观看时间"), systemImage: "gift") }
                        .disabled(store.busy || store.selected?.enabled != 1).accessibilityIdentifier("grantTime")
                    NavigationLink { RulesView() } label: { Label(L10n.tr("调整观看规则"), systemImage: "slider.horizontal.3") }
                } footer: {
                    Text(L10n.tr("临时额度会替换上次额度，并优先于休息时段。云端允许观看不代表电视已执行。"))
                }
                Section(L10n.tr("受管应用")) {
                    let rows = usage.daily.filter { $0.day == usage.today && $0.seconds > 0 }
                    if rows.isEmpty { Text(L10n.tr("今天还没有观看记录")).foregroundStyle(Color("SupportingText")) }
                    ForEach(rows) { row in LabeledContent(row.appName, value: row.seconds.durationText) }
                }
            } else if store.devices.isEmpty && store.loadState == .loaded {
                Section {
                    ContentUnavailableView(L10n.tr("还没有电视"), systemImage: "tv", description: Text(L10n.tr("跟着四步引导，让你的 Agent 助手完成配置。")))
                    NavigationLink(L10n.tr("添加电视")) { InstallationView() }
                }
            } else if store.loadState.failure == nil {
                Section { ProgressView(L10n.tr("正在获取观看情况…")) }
            }
            Section {
                if let last = store.lastRefresh { LabeledContent(L10n.tr("本页更新于")) { Text(last, style: .time) } }
                Button(L10n.tr("刷新状态")) { Task { await store.refresh() } }
                Text(L10n.tr("统计日期按北京时间计算；仅包含受管应用的播放采样。"))
                    .font(.footnote).foregroundStyle(Color("SupportingText"))
            }
        }
        .navigationTitle(L10n.tr("今天"))
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showGrant) { GrantView() }
        .confirmationDialog(store.usage?.state.paused == true ? L10n.tr("解除家长暂停？") : L10n.tr("暂停受管视频播放？"), isPresented: $confirmPause, titleVisibility: .visible) {
            Button(L10n.tr("确认")) { Task { await store.setPaused(store.usage?.state.paused != true) } }
            Button(L10n.tr("取消"), role: .cancel) {}
        } message: { Text(L10n.tr("指令只作用于当前电视。解除暂停后，观看额度和休息时段仍然有效。")) }
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
                    Picker(L10n.tr("观看时间"), selection: $minutes) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { Text(L10n.tr("\($0) 分钟")).tag($0) }
                    }.pickerStyle(.wheel)
                } header: { Text(store.selected?.label ?? L10n.tr("电视")) } footer: {
                    Text(L10n.tr("这会替换已有临时额度，并在休息时段内放行。离线电视需要重新连接后才能获取。"))
                }
                Section {
                    Button { Task { await store.grant(minutes: minutes); if store.error == nil { dismiss() } } } label: {
                        HStack { Text(L10n.tr("确认给予 \(minutes) 分钟")); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(store.busy).accessibilityIdentifier("confirmGrant")
                }
            }
            .navigationTitle(L10n.tr("多一点观看时间")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("取消")) { dismiss() }.disabled(store.busy) } }
        }.presentationDetents([.medium, .large]).interactiveDismissDisabled(store.busy)
            .familyErrorAlert(inModal: true)
    }
}
