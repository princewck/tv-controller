import SwiftUI

struct TVGuideView: View {
    @State private var example: TVExample = .watching

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("电视上会发生什么？")).font(.title2.bold())
                    Text(L10n.tr("从观看到休息，再到继续播放。切换下方示例，了解手机和电视怎样配合。"))
                        .foregroundStyle(Color("SupportingText"))
                    Label(L10n.tr("这是示例界面和数据，不是电视实时画面。模拟操作只改变本页示例，不会控制你的电视。"), systemImage: "play.rectangle")
                        .font(.footnote).foregroundStyle(Color("SupportingText"))
                }.padding(.vertical, 4)
            }
            Section {
                TVIllustrationView(example: example)
                    .accessibilityIdentifier("tvIllustration")
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                Picker(L10n.tr("切换示例"), selection: $example) {
                    ForEach(TVExample.allCases) { item in Text(item.title).tag(item) }
                }.accessibilityIdentifier("tvExamplePicker")
                Text(example.explanation).accessibilityIdentifier("tvExampleExplanation")
                LabeledContent(L10n.tr("手机上可以做什么"), value: example.phoneAction)
                Button(example.nextAction) { example = example.next }
                    .accessibilityIdentifier("advanceTVExample")
            } header: { Text(L10n.tr("电视画面示意")) } footer: {
                Text(L10n.tr("示例采用每日上限90分钟、临时观看15分钟。实际以你的设置为准，电视界面也可能因设备不同而有所差异。"))
            }
            Section(L10n.tr("先约定，再观看")) {
                Label(L10n.tr("手机设置规则，查看电视反馈"), systemImage: "slider.horizontal.3")
                Text(L10n.tr("观看规则由本家庭的电视共享，每台分别计时。家长暂停和临时观看时间只影响选中的电视。"))
                Label(L10n.tr("在家可直连，外出用云端"), systemImage: "network")
                Text(L10n.tr("支持家庭网络直连的新版电视配套应用，可在配对后优先直连，连不上再尝试云端。使用此新版时，电视没有互联网也会继续使用已保存的规则。"))
                Label(L10n.tr("允许观看后，仍需手动继续播放"), systemImage: "play")
                Text(L10n.tr("手机会区分设置已保存和电视报告的结果。允许观看不会自动开始播放；电视权限被关闭或配套应用停止运行时，限制可能无法执行。"))
            }
            Section(L10n.tr("准备连接你的电视")) {
                Text(L10n.tr("需要兼容的 Android TV、电视配套应用，以及用于首次配置的电脑和 AI 编程助手。"))
                NavigationLink(L10n.tr("查看安装引导")) { InstallationView() }
            }
        }
        .navigationTitle(L10n.tr("电视使用说明")).navigationBarTitleDisplayMode(.inline)
    }
}
