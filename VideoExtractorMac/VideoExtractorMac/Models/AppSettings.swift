import Foundation

enum ToolPathMode: String, Codable, CaseIterable, Identifiable {
    case bundled
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bundled:
            return "使用内置工具"
        case .custom:
            return "手动选择路径"
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色模式"
        case .dark:
            return "深色模式"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var defaultDownloadDirectoryPath: String
    var defaultVideoQuality: VideoQuality
    var defaultAudioFormat: AudioOutputFormat
    var shouldOpenFolderWhenFinished: Bool
    var appearanceMode: AppearanceMode
    var ytdlpPathMode: ToolPathMode
    var customYTDLPPath: String
    var ffmpegPathMode: ToolPathMode
    var customFFmpegPath: String

    static let defaults = AppSettings(
        defaultDownloadDirectoryPath: "",
        defaultVideoQuality: .best,
        defaultAudioFormat: .m4a,
        shouldOpenFolderWhenFinished: false,
        appearanceMode: .system,
        ytdlpPathMode: .bundled,
        customYTDLPPath: "",
        ffmpegPathMode: .bundled,
        customFFmpegPath: ""
    )
}
