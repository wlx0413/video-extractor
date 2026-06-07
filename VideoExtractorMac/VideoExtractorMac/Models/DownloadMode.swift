import Foundation

enum DownloadMode: String, Codable, CaseIterable, Identifiable {
    case best
    case video1080p
    case video720p
    case video480p
    case audioOnly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .best:
            return "最佳质量"
        case .video1080p:
            return "1080p 或更低"
        case .video720p:
            return "720p 或更低"
        case .video480p:
            return "480p 或更低"
        case .audioOnly:
            return "仅音频"
        case .custom:
            return "自定义格式"
        }
    }

    func ytDLPFormatSelector(customFormatID: String? = nil) -> String {
        switch self {
        case .best:
            return "bv*+ba/b"
        case .video1080p:
            return "bv*[height<=1080]+ba/b[height<=1080]/bv*+ba/b"
        case .video720p:
            return "bv*[height<=720]+ba/b[height<=720]/bv*+ba/b"
        case .video480p:
            return "bv*[height<=480]+ba/b[height<=480]/bv*+ba/b"
        case .audioOnly:
            return "bestaudio/b"
        case .custom:
            guard let customFormatID, customFormatID.isEmpty == false else {
                return "bv*+ba/b"
            }
            return "\(customFormatID)+ba/\(customFormatID)/b"
        }
    }
}

enum VideoQuality: String, Codable, CaseIterable, Identifiable {
    case best
    case p1080
    case p720
    case p480

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .best:
            return "Best"
        case .p1080:
            return "1080p"
        case .p720:
            return "720p"
        case .p480:
            return "480p"
        }
    }

    var downloadMode: DownloadMode {
        switch self {
        case .best:
            return .best
        case .p1080:
            return .video1080p
        case .p720:
            return .video720p
        case .p480:
            return .video480p
        }
    }
}

enum AudioOutputFormat: String, Codable, CaseIterable, Identifiable {
    case m4a
    case mp3
    case wav

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .m4a:
            return "m4a"
        case .mp3:
            return "mp3"
        case .wav:
            return "wav"
        }
    }
}
