import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(FamilyStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 190
    @State private var range = 7
    var body: some View {
        List {
            if store.demo { Section { DemoBanner() } }
            if let failure = store.loadState.failure { Section { Label(failure, systemImage: "wifi.exclamationmark").font(.subheadline); Text(L10n.tr("以下记录可能尚未更新。")).font(.footnote).foregroundStyle(Color("SupportingText")) } }
            if !store.premiumActive && !store.demo {
                Section {
                    ContentUnavailableView(L10n.tr("看见更长远的变化"), systemImage: "chart.bar.xaxis", description: Text(L10n.tr("订阅家庭云 Plus，保存云端观看历史并查看趋势分析。")))
                    NavigationLink(L10n.tr("了解家庭云 Plus")) { SubscriptionView() }
                }
            } else if let usage = store.usage {
                Section {
                    Picker(L10n.tr("记录范围"), selection: $range) { Text(L10n.tr("7 天")).tag(7); Text(L10n.tr("30 天")).tag(30) }.pickerStyle(.segmented)
                }
                Section(L10n.tr("最近 \(range) 天")) {
                    Chart(usage.days(range), id: \.day) { item in
                        BarMark(x: .value(L10n.tr("日期"), Self.dayFormatter.date(from: item.day) ?? .distantPast, unit: .day), y: .value(L10n.tr("分钟"), item.seconds / 60))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel(item.day).accessibilityValue(item.seconds.durationText)
                    }
                    .chartXAxis {
                        AxisMarks(values: dateLabels(usage)) { value in
                            AxisGridLine(); AxisTick()
                            AxisValueLabel { if let date = value.as(Date.self) { Text(Self.axisFormatter.string(from: date)).foregroundStyle(Color.primary) } }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 3 : 4)) { _ in
                            AxisGridLine(); AxisTick(); AxisValueLabel().foregroundStyle(Color.primary)
                        }
                    }
                    .chartYAxisLabel { Text(L10n.tr("分钟")).foregroundStyle(Color.primary) }
                    .environment(\.calendar, Self.chartCalendar)
                    .frame(height: chartHeight).padding(.vertical, 12)
                    durationRow(range == 7 ? L10n.tr("近 7 天合计") : L10n.tr("近 30 天合计"), seconds: usage.days(range).reduce(0) { $0 + $1.seconds })
                    durationRow(L10n.tr("平均每天"), seconds: usage.days(range).reduce(0) { $0 + $1.seconds } / range)
                }
                Section(L10n.tr("应用分析")) {
                    ForEach(usage.appTotals(days: range), id: \.app) { item in
                        durationRow(DailyUsage.name(item.app), seconds: item.seconds)
                    }
                    if usage.appTotals(days: range).isEmpty { Text(L10n.tr("这段时间尚无采集记录。")).foregroundStyle(Color("SupportingText")) }
                }
                Section(L10n.tr("每日观看")) {
                    ForEach(usage.days(range).reversed(), id: \.day) { item in durationRow(item.day, seconds: item.seconds) }
                }
                Section { Text(L10n.tr("仅统计所选电视的受管应用播放采样，存在采样误差；日期按北京时间。未采集到记录不等于没有观看。"))
                        .font(.footnote).foregroundStyle(Color.primary) }
            } else {
                ContentUnavailableView(L10n.tr("还没有观看记录"), systemImage: "chart.bar", description: Text(L10n.tr("连接电视后，受管应用的观看记录会显示在这里。")))
            }
        }.navigationTitle(L10n.tr("观看记录")).refreshable { await store.refresh() }
    }
    private func durationRow(_ title: String, seconds: Int) -> some View {
        LabeledContent(title) { Text(seconds.durationText).foregroundStyle(Color.primary) }
    }
    private static let chartCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let axisFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "MM-dd"
        return formatter
    }()
    private func dateLabels(_ usage: UsageResponse) -> [Date] {
        let days = usage.days(range)
        let step = dynamicTypeSize.isAccessibilitySize ? (range == 7 ? 3 : 14) : (range == 7 ? 1 : 7)
        return days.enumerated().filter { $0.offset % step == 0 }.compactMap { Self.dayFormatter.date(from: $0.element.day) }
    }
}
