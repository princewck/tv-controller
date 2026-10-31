import XCTest
import SwiftUI
@testable import FamilyTV

/// Exports clearly labeled artwork. These images do not certify TV hardware behavior.
final class TVIllustrationExports: XCTestCase {
    @MainActor func testExportLabeled4KTVIllustrations() throws {
        for example in TVExample.allCases {
            let artwork = VStack(spacing: 28) {
                HStack {
                    Text("观有度 · 电视界面示意").font(.system(size: 70, weight: .semibold))
                    Spacer()
                    Text(example.title).font(.system(size: 60))
                }.frame(width: 3200)
                TVIllustrationView(example: example).frame(width: 3200, height: 1800)
                Text("示例数据 · 非电视实拍 · 不作为执行验证")
                    .font(.system(size: 46)).foregroundStyle(.secondary)
            }
            .frame(width: 3840, height: 2160)
            .foregroundStyle(.primary).background(Color(.systemBackground))
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: artwork)
            renderer.scale = 1; renderer.isOpaque = true
            renderer.proposedSize = ProposedViewSize(width: 3840, height: 2160)
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, CGSize(width: 3840, height: 2160))
            let attachment = XCTAttachment(image: image)
            attachment.name = "tv-example-\(example.rawValue)-4k"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
