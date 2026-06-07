import Foundation

final class FileManagerService {
    static let shared = FileManagerService()

    let projectRoot: URL
    let downloadsDirectory: URL
    let tempDirectory: URL
    let logsDirectory: URL
    let deleteDirectory: URL
    let historyDirectory: URL

    private let fileManager = FileManager.default

    init(projectRoot: URL = FileManagerService.defaultWorkDirectory()) {
        self.projectRoot = projectRoot
        self.downloadsDirectory = projectRoot.appendingPathComponent("Downloads", isDirectory: true)
        self.tempDirectory = projectRoot.appendingPathComponent("Temp", isDirectory: true)
        self.logsDirectory = projectRoot.appendingPathComponent("Logs", isDirectory: true)
        self.deleteDirectory = projectRoot.appendingPathComponent("要删除的", isDirectory: true)
        self.historyDirectory = projectRoot.appendingPathComponent("History", isDirectory: true)

        try? prepareDirectories()
    }

    static func defaultWorkDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (appSupport ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("VideoExtractorMac", isDirectory: true)
    }

    static func developmentProjectRoot() -> URL? {
        let sourceURL = URL(fileURLWithPath: #filePath)
        let root = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let expected = root.appendingPathComponent("Tools", isDirectory: true)
        if FileManager.default.fileExists(atPath: expected.path) {
            return root
        }

        return nil
    }

    func prepareDirectories() throws {
        for directory in [downloadsDirectory, tempDirectory, logsDirectory, deleteDirectory, historyDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func bundledYTDLPURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Tools/yt-dlp/yt-dlp")
            if fileManager.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        return projectRoot.appendingPathComponent("Tools/yt-dlp/yt-dlp")
    }

    func bundledFFmpegURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("Tools/ffmpeg/ffmpeg")
            if fileManager.fileExists(atPath: bundled.path) {
                return bundled
            }
        }
        return projectRoot.appendingPathComponent("Tools/ffmpeg/ffmpeg")
    }

    func resolvedDownloadDirectory(from settings: AppSettings) -> URL {
        if settings.defaultDownloadDirectoryPath.isEmpty {
            return downloadsDirectory
        }
        return URL(fileURLWithPath: settings.defaultDownloadDirectoryPath, isDirectory: true)
    }

    func ensureWritableDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        guard fileManager.isWritableFile(atPath: directory.path) else {
            throw AppError.outputDirectoryNotWritable(directory.path)
        }
    }

    func uniqueOutputBaseName(in directory: URL, preferredTitle: String) -> String {
        let sanitized = SafePath.sanitizedFileName(preferredTitle)

        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return sanitized
        }

        let existingNames = Set(contents.map { $0.deletingPathExtension().lastPathComponent })
        guard existingNames.contains(sanitized) else {
            return sanitized
        }

        let timestamped = "\(sanitized)_\(SafePath.timestampForFileName())"
        guard existingNames.contains(timestamped) else {
            return timestamped
        }

        return "\(timestamped)_\(UUID().uuidString.prefix(8))"
    }

    func moveToDeleteFolder(_ sourceURL: URL, reason: String) throws -> URL {
        guard SafePath.isChild(sourceURL, of: projectRoot) else {
            throw AppError.fileOperationDenied("只允许移动当前项目或应用工作目录内的文件。")
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AppError.fileOperationDenied("源文件不存在：\(sourceURL.path)")
        }

        try fileManager.createDirectory(at: deleteDirectory, withIntermediateDirectories: true)
        let destination = SafePath.uniqueDestination(in: deleteDirectory, preserving: sourceURL.lastPathComponent)
        try fileManager.moveItem(at: sourceURL, to: destination)

        Task {
            await AppLogger.shared.fileOperation(source: sourceURL, destination: destination, reason: reason)
        }

        return destination
    }
}
