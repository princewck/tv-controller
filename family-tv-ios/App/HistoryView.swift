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
            if let failure = store.loadState.failure { Section { Label(failure, systemImage: "wifi.exclamationmark").font(.subheadline); Text("以下记录可能尚未更新。").font(.footnote).foregroundStyle(.secondary) } }
            if !store.premiumActive && !store.demo {
                Section {
                    ContentUnavailableView("看见更长远的变化", systemImage: "chart.bar.xaxis", description: Text("订阅家庭云 Plus，保存云端观看历史并查看趋势分析。"))
                    NavigationLink("了解家庭云 Plus") { SubscriptionView() }
                }
            } else if let usage = store.usage {
                Section {
                    Picker("记录范围", selection: $range) { Text("7 天").tag(7); Text("30 天").tag(30) }.pickerStyle(.segmented)
                }
                Section("最近 \(range) 天") {
                    Chart(usage.days(range), id: \.day) { item in
                        BarMark(x: .value("日期", Self.dayFormatter.date(from: item.day) ?? .distantPast, unit: .day), y: .value("分钟", item.seconds / 60))
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
                    .chartYAxisLabel { Text("分钟").foregroundStyle(Color.primary) }
                    .environment(\.calendar, Self.chartCalendar)
                    .frame(height: chartHeight).padding(.vertical, 12)
                    durationRow(range == 7 ? "本周合计" : "近 30 天合计", seconds: usage.days(range).reduce(0) { $0 + $1.seconds })
                    durationRow("平均每天", seconds: usage.days(range).reduce(0) { $0 + $1.seconds } / range)
                }
                Section("应用分析") {
                    ForEach(usage.appTotals(days: range), id: \.app) { item in
                        durationRow(DailyUsage.name(item.app), seconds: item.seconds)
                    }
                    if usage.appTotals(days: range).isEmpty { Text("这段时间尚无采集记录。").foregroundStyle(.secondary) }
                }
                Section("每日观看") {
                    ForEach(usage.days(range).reversed(), id: \.day) { item in durationRow(item.day, seconds: item.seconds) }
                }
                Section { Text("仅统计所选电视的受管应用播放采样，存在采样误差；日期按北京时间。未采集到记录不等于没有观看。")
                        .font(.footnote).foregroundStyle(Color.primary) }
            } else {
                ContentUnavailableView("还没有观看记录", systemImage: "chart.bar", description: Text("连接电视后，受管应用的观看记录会显示在这里。"))
            }
        }.navigationTitle("观看记录").refreshable { await store.refresh() }
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
