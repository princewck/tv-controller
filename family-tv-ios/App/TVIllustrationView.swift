import SwiftUI

/// An illustration, not a stream or screenshot of a connected TV.
struct TVIllustrationView: View {
    let example: TVExample
    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack {
                Rectangle().fill(Color(red: 0.071, green: 0.247, blue: 0.204))
                if example.showsBreak {
                    VStack(spacing: height * 0.075) {
                        Text(L10n.tr("电视该休息一下了")).font(.system(size: height * 0.115, weight: .medium))
                        VStack(spacing: height * 0.04) {
                            Text(L10n.tr("请家长在手机上调整观看时间。"))
                            Text(L10n.tr("允许观看后，返回视频应用，再手动继续播放。"))
                        }.font(.system(size: height * 0.058))
                    }.foregroundStyle(.white).multilineTextAlignment(.center).padding(.horizontal, height * 0.08)
                } else {
                    SamplePlaybackScene()
                    VStack(spacing: height * 0.055) {
                        Image(systemName: "play.circle.fill").font(.system(size: height * 0.25)).symbolRenderingMode(.hierarchical)
                        Text(L10n.tr("视频播放示意")).font(.system(size: height * 0.07, weight: .medium))
                    }.foregroundStyle(.white)
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(example.showsBreak ? Text(L10n.tr("电视休息页示意。提示孩子请家长在手机上调整观看时间，允许观看后再手动继续播放。")) : Text(L10n.tr("视频应用播放画面示意。")))
    }
}

private struct SamplePlaybackScene: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color(red: 0.13, green: 0.32, blue: 0.37)
                Circle().fill(Color(red: 0.96, green: 0.77, blue: 0.37))
                    .frame(width: size.height * 0.27, height: size.height * 0.27)
                    .position(x: size.width * 0.77, y: size.height * 0.26)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height * 0.82))
                    p.addLine(to: CGPoint(x: size.width * 0.32, y: size.height * 0.24))
                    p.addLine(to: CGPoint(x: size.width * 0.7, y: size.height))
                    p.addLine(to: CGPoint(x: 0, y: size.height))
                }.fill(Color(red: 0.18, green: 0.43, blue: 0.36))
                Path { p in
                    p.move(to: CGPoint(x: size.width * 0.38, y: size.height))
                    p.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.5))
                    p.addLine(to: CGPoint(x: size.width, y: size.height * 0.78))
                    p.addLine(to: CGPoint(x: size.width, y: size.height))
                }.fill(Color(red: 0.085, green: 0.25, blue: 0.23))
            }
        }.accessibilityHidden(true)
    }
}
