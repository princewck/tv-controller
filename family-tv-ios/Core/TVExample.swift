import Foundation

/// Read-only examples for the in-app guide. These never send a device command.
enum TVExample: String, CaseIterable, Identifiable {
    case watching, timeUp, extraTime, paused
    var id: String { rawValue }
    var showsBreak: Bool { self == .timeUp || self == .paused }
    var title: String {
        switch self {
        case .watching: L10n.tr("观看中")
        case .timeUp: L10n.tr("到点休息")
        case .extraTime: L10n.tr("临时观看")
        case .paused: L10n.tr("家长暂停")
        }
    }
    var explanation: String {
        switch self {
        case .watching: L10n.tr("在适用的视频应用中播放时，电视会估算观看时长。浏览菜单不计入观看。")
        case .timeUp: L10n.tr("达到每日上限，或进入休息时段后，电视会尝试停止适用应用的播放，并显示休息页。")
        case .extraTime: L10n.tr("家长在手机上设置临时观看时间，确认电视已允许观看后，孩子可返回视频应用，手动继续播放。")
        case .paused: L10n.tr("家长也可以随时暂停观看。临时观看时间不会解除家长暂停。")
        }
    }
    var phoneAction: String {
        switch self {
        case .watching: L10n.tr("在“今天”页查看观看情况")
        case .timeUp: L10n.tr("在手机上暂停观看，或设置临时观看时间")
        case .extraTime: L10n.tr("示例：临时允许观看15分钟")
        case .paused: L10n.tr("解除家长暂停后，其他观看规则仍然有效")
        }
    }
    var next: TVExample {
        switch self {
        case .watching: .timeUp
        case .timeUp: .extraTime
        case .extraTime: .paused
        case .paused: .extraTime
        }
    }
    var nextAction: String {
        switch self {
        case .watching: L10n.tr("模拟到点休息")
        case .timeUp: L10n.tr("模拟给予15分钟")
        case .extraTime: L10n.tr("模拟家长暂停")
        case .paused: L10n.tr("模拟解除家长暂停")
        }
    }
}
