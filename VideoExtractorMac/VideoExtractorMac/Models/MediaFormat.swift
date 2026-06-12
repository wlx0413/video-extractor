import Foundation

enum SubtitleSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case automatic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual:
            return "普通字幕"
        case .automatic:
            return "自动字幕"
        }
    }
}

enum SubtitleOutputFormat: String, Codable, CaseIterable, Identifiable, Hashable {
    case srt
    case ass

    var id: String { rawValue }

    var displayName: String {
        rawValue.uppercased()
    }

    var fileExtension: String {
        rawValue
    }
}

struct SubtitleTrack: Identifiable, Codable, Hashable {
    var languageCode: String
    var languageName: String
    var source: SubtitleSource
    var isOriginalLanguage: Bool
    var downloadURL: URL?
    var extensionName: String?

    var id: String {
        "\(source.rawValue):\(languageCode)"
    }

    var displayName: String {
        let sourceText = source.displayName
        let originalText = isOriginalLanguage ? " · 原始语言" : ""
        if languageName == languageCode {
            return "\(languageCode) · \(sourceText)\(originalText)"
        }
        return "\(languageName) (\(languageCode)) · \(sourceText)\(originalText)"
    }

    var subtitleLineLabel: String {
        if isOriginalLanguage {
            return "原声 \(languageCode)"
        }
        if languageName == languageCode {
            return languageCode
        }
        return "\(languageName) \(languageCode)"
    }
}

struct SubtitleSelection: Codable, Hashable {
    var tracks: [SubtitleTrack]
    var outputFormats: Set<SubtitleOutputFormat>

    var isEmpty: Bool {
        tracks.isEmpty
    }

    var languageSuffix: String {
        tracks
            .map { SafePath.sanitizedFileName($0.languageCode, fallbackPrefix: "sub") }
            .joined(separator: "+")
    }
}

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
    var subtitleTracks: [SubtitleTrack]

    init(
        id: String,
        sourceURL: String,
        platform: PlatformType,
        title: String,
        author: String?,
        duration: Double?,
        thumbnailURL: URL?,
        imageURLs: [URL],
        formats: [MediaFormat],
        subtitleTracks: [SubtitleTrack] = []
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.platform = platform
        self.title = title
        self.author = author
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.imageURLs = imageURLs
        self.formats = formats
        self.subtitleTracks = subtitleTracks
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceURL
        case platform
        case title
        case author
        case duration
        case thumbnailURL
        case imageURLs
        case formats
        case subtitleTracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        platform = try container.decode(PlatformType.self, forKey: .platform)
        title = try container.decode(String.self, forKey: .title)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        imageURLs = try container.decodeIfPresent([URL].self, forKey: .imageURLs) ?? []
        formats = try container.decodeIfPresent([MediaFormat].self, forKey: .formats) ?? []
        subtitleTracks = try container.decodeIfPresent([SubtitleTrack].self, forKey: .subtitleTracks) ?? []
    }

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
