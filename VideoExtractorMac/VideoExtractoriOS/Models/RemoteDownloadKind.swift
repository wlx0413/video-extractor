import Foundation

enum RemoteDownloadKind: String, Codable, CaseIterable, Identifiable {
    case video
    case audio
    case images

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .video:
            return "视频"
        case .audio:
            return "音频"
        case .images:
            return "图片"
        }
    }

    var symbolName: String {
        switch self {
        case .video:
            return "film"
        case .audio:
            return "waveform"
        case .images:
            return "photo.on.rectangle"
        }
    }
}

struct ServerHealth: Codable, Hashable {
    var ok: Bool
    var ytdlpAvailable: Bool
    var ffmpegAvailable: Bool
    var message: String
}

struct MobileDownloadItem: Identifiable, Hashable {
    var id = UUID()
    var remoteJobID: String?
    var url: String
    var title: String
    var platform: PlatformType
    var kind: RemoteDownloadKind
    var status: DownloadStatus
    var progress: DownloadProgress
    var outputFileURL: URL?
    var selectedMode: DownloadMode
    var errorMessage: String?
    var createdAt = Date()
    var updatedAt = Date()
    var metadata: MediaMetadata?

    var canDownload: Bool {
        status == .ready || status == .failed
    }
}
