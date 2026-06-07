import Foundation

enum MediaKind: String, Codable {
    case videoOnly
    case audioOnly
    case muxed
    case unknown

    var displayName: String {
        switch self {
        case .videoOnly:
            return "视频流"
        case .audioOnly:
            return "音频流"
        case .muxed:
            return "音视频"
        case .unknown:
            return "未知"
        }
    }
}

struct MediaFormat: Identifiable, Codable, Hashable {
    var formatID: String
    var extensionName: String
    var resolution: String?
    var width: Int?
    var height: Int?
    var fps: Double?
    var fileSize: Int64?
    var approxFileSize: Int64?
    var videoCodec: String?
    var audioCodec: String?
    var audioBitrate: Double?
    var totalBitrate: Double?
    var formatNote: String?

    var id: String { formatID }

    var kind: MediaKind {
        let hasVideo = videoCodec.map { $0 != "none" } ?? false
        let hasAudio = audioCodec.map { $0 != "none" } ?? false

        switch (hasVideo, hasAudio) {
        case (true, true):
            return .muxed
        case (true, false):
            return .videoOnly
        case (false, true):
            return .audioOnly
        default:
            return .unknown
        }
    }

    var displayResolution: String {
        if let resolution, resolution.isEmpty == false {
            return resolution
        }

        if let width, let height {
            return "\(width)x\(height)"
        }

        if let height {
            return "\(height)p"
        }

        return "未知"
    }

    var displaySize: String {
        let size = fileSize ?? approxFileSize
        guard let size else {
            return "未知"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var displayFPS: String {
        guard let fps else {
            return "-"
        }
        return fps == floor(fps) ? String(Int(fps)) : String(format: "%.1f", fps)
    }

    var summary: String {
        let note = formatNote.map { " · \($0)" } ?? ""
        return "\(formatID) · \(extensionName) · \(displayResolution)\(note)"
    }
}

struct MediaMetadata: Identifiable, Codable, Hashable {
    var id: String
    var sourceURL: String
    var platform: PlatformType
    var title: String
    var author: String?
    var duration: Double?
    var thumbnailURL: URL?
    var imageURLs: [URL]
    var formats: [MediaFormat]

    var displayDuration: String {
        guard let duration else {
            return "未知"
        }

        let seconds = Int(duration.rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
