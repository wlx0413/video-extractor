import Foundation

enum PlatformType: String, Codable, CaseIterable, Identifiable {
    case youtube
    case bilibili
    case xiaohongshu
    case douyin
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .youtube:
            return "YouTube"
        case .bilibili:
            return "Bilibili"
        case .xiaohongshu:
            return "小红书"
        case .douyin:
            return "抖音"
        case .unknown:
            return "未知 / 通用"
        }
    }

    var symbolName: String {
        switch self {
        case .youtube:
            return "play.rectangle.fill"
        case .bilibili:
            return "tv.fill"
        case .xiaohongshu:
            return "book.pages.fill"
        case .douyin:
            return "music.note.tv.fill"
        case .unknown:
            return "globe"
        }
    }
}
