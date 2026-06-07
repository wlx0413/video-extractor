import Foundation

enum DownloadStatus: String, Codable, CaseIterable, Identifiable {
    case waiting
    case analyzing
    case ready
    case downloading
    case converting
    case paused
    case completed
    case failed
    case cancelled

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .waiting:
            return "等待中"
        case .analyzing:
            return "正在分析"
        case .ready:
            return "可选择格式"
        case .downloading:
            return "下载中"
        case .converting:
            return "转换中"
        case .paused:
            return "已暂停"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        case .cancelled:
            return "已取消"
        }
    }
}

struct DownloadProgress: Codable, Hashable {
    var fraction: Double
    var percentText: String
    var speed: String?
    var eta: String?

    static let empty = DownloadProgress(
        fraction: 0,
        percentText: "0%",
        speed: nil,
        eta: nil
    )
}

struct DownloadTask: Identifiable, Codable, Hashable {
    var id: UUID
    var url: String
    var title: String
    var platform: PlatformType
    var status: DownloadStatus
    var progress: DownloadProgress
    var outputPath: String?
    var selectedMode: DownloadMode
    var selectedFormatID: String?
    var selectedSubtitleTrackIDs: [String]
    var selectedSubtitleOutputFormats: Set<SubtitleOutputFormat>
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var metadata: MediaMetadata?

    init(
        id: UUID = UUID(),
        url: String,
        title: String = "未命名任务",
        platform: PlatformType = .unknown,
        status: DownloadStatus = .waiting,
        progress: DownloadProgress = .empty,
        outputPath: String? = nil,
        selectedMode: DownloadMode = .best,
        selectedFormatID: String? = nil,
        selectedSubtitleTrackIDs: [String] = [],
        selectedSubtitleOutputFormats: Set<SubtitleOutputFormat> = Set(SubtitleOutputFormat.allCases),
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: MediaMetadata? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.platform = platform
        self.status = status
        self.progress = progress
        self.outputPath = outputPath
        self.selectedMode = selectedMode
        self.selectedFormatID = selectedFormatID
        self.selectedSubtitleTrackIDs = selectedSubtitleTrackIDs
        self.selectedSubtitleOutputFormats = selectedSubtitleOutputFormats
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    var canCancel: Bool {
        status == .analyzing || status == .downloading || status == .converting || status == .paused
    }

    var canPause: Bool {
        status == .downloading || status == .converting
    }

    var canResume: Bool {
        status == .paused
    }
}

struct DownloadHistoryRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var url: String
    var platform: PlatformType
    var downloadedAt: Date
    var outputPath: String?
    var formatDescription: String
    var status: DownloadStatus

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        platform: PlatformType,
        downloadedAt: Date = Date(),
        outputPath: String?,
        formatDescription: String,
        status: DownloadStatus
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.platform = platform
        self.downloadedAt = downloadedAt
        self.outputPath = outputPath
        self.formatDescription = formatDescription
        self.status = status
    }
}
