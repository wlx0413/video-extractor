import Foundation

final class YTDLPService {
    private struct MetadataDTO: Decodable {
        var id: String?
        var webpageURL: String?
        var title: String?
        var uploader: String?
        var channel: String?
        var duration: Double?
        var thumbnail: String?
        var formats: [FormatDTO]?

        enum CodingKeys: String, CodingKey {
            case id
            case webpageURL = "webpage_url"
            case title
            case uploader
            case channel
            case duration
            case thumbnail
            case formats
        }
    }

    private struct FormatDTO: Decodable {
        var formatID: String?
        var extensionName: String?
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

        enum CodingKeys: String, CodingKey {
            case formatID = "format_id"
            case extensionName = "ext"
            case resolution
            case width
            case height
            case fps
            case fileSize = "filesize"
            case approxFileSize = "filesize_approx"
            case videoCodec = "vcodec"
            case audioCodec = "acodec"
            case audioBitrate = "abr"
            case totalBitrate = "tbr"
            case formatNote = "format_note"
        }
    }

    private let runner: CommandRunner
    private let fileService: FileManagerService
    private let ffmpegService: FFmpegService
    private let imageDownloadLock = NSLock()
    private var cancelledImageDownloads: Set<UUID> = []

    init(
        runner: CommandRunner = .shared,
        fileService: FileManagerService = .shared,
        ffmpegService: FFmpegService = FFmpegService()
    ) {
        self.runner = runner
        self.fileService = fileService
        self.ffmpegService = ffmpegService
    }

    func checkYTDLPAvailable() async throws -> String {
        let executableURL = try ytdlpExecutableURL()
        let result = try await runner.run(executableURL: executableURL, arguments: ["--version"])

        guard result.succeeded else {
            throw AppError.toolUnavailable("yt-dlp")
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchMetadata(url: URL) async throws -> MediaMetadata {
        let executableURL = try ytdlpExecutableURL()
        let result = try await runner.run(
            executableURL: executableURL,
            arguments: ["-J", "--no-playlist", url.absoluteString]
        )

        guard result.succeeded else {
            throw AppError.fromCommandFailure(stderr: result.stderr, fallback: "当前链接无法解析。")
        }

        do {
            let data = Data(result.stdout.utf8)
            let dto = try JSONDecoder().decode(MetadataDTO.self, from: data)
            let platform = URLDetector.detectPlatform(for: url)
            let formats = (dto.formats ?? []).compactMap(Self.mapFormat)
            let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let metadataID = dto.id ?? UUID().uuidString
            let imageURLs = Self.collectImageURLs(from: data, thumbnail: dto.thumbnail)

            return MediaMetadata(
                id: metadataID,
                sourceURL: dto.webpageURL ?? url.absoluteString,
                platform: platform,
                title: title?.isEmpty == false ? title! : "video_\(SafePath.timestampForFileName())",
                author: dto.uploader ?? dto.channel,
                duration: dto.duration,
                thumbnailURL: dto.thumbnail.flatMap(URL.init(string:)),
                imageURLs: imageURLs,
                formats: formats
            )
        } catch {
            await AppLogger.shared.log("解析 yt-dlp JSON 失败：\(error.localizedDescription)", level: .error)
            throw AppError.downloadFailed("当前链接返回的信息无法解析。")
        }
    }

    func fetchFormats(url: URL) async throws -> [MediaFormat] {
        try await fetchMetadata(url: url).formats
    }

    func downloadVideo(
        url: URL,
        selectedFormat: DownloadMode,
        customFormatID: String? = nil,
        outputDirectory: URL,
        taskID: UUID,
        progressHandler: @escaping (DownloadProgress) -> Void
    ) async throws -> URL? {
        try fileService.ensureWritableDirectory(outputDirectory)

        let metadata = try? await fetchMetadata(url: url)
        let baseName = fileService.uniqueOutputBaseName(
            in: outputDirectory,
            preferredTitle: metadata?.title ?? "video_\(SafePath.timestampForFileName())"
        )

        var arguments = baseArguments(outputDirectory: outputDirectory, outputBaseName: baseName)
        arguments += [
            "-f", selectedFormat.ytDLPFormatSelector(customFormatID: customFormatID),
            "--merge-output-format", "mp4"
        ]

        if let ffmpegLocation = try? ffmpegService.ffmpegExecutableURL().deletingLastPathComponent().path {
            arguments += ["--ffmpeg-location", ffmpegLocation]
        }

        arguments.append(url.absoluteString)

        let result = try await runner.run(
            id: taskID,
            executableURL: try ytdlpExecutableURL(),
            arguments: arguments
        ) { output in
            if let progress = Self.parseProgress(from: output.text) {
                progressHandler(progress)
            }
        }

        guard result.succeeded else {
            if result.exitCode == 15 {
                throw AppError.cancelled
            }
            throw AppError.fromCommandFailure(stderr: result.stderr, fallback: "视频下载失败。")
        }

        return finalOutputURL(from: result, outputDirectory: outputDirectory)
    }

    func downloadImages(
        url: URL,
        outputDirectory: URL,
        taskID: UUID,
        progressHandler: @escaping (DownloadProgress) -> Void
    ) async throws -> URL? {
        try fileService.ensureWritableDirectory(outputDirectory)
        setImageDownloadCancelled(false, taskID: taskID)

        let metadata = try await fetchMetadata(url: url)
        let imageURLs = metadata.imageURLs

        guard imageURLs.isEmpty == false else {
            throw AppError.downloadFailed("没有找到可下载图片。小红书图文目前只下载 yt-dlp 公开元数据里能识别到的图片。")
        }

        let folderName = fileService.uniqueOutputBaseName(
            in: outputDirectory,
            preferredTitle: "\(metadata.title)_图片"
        )
        let folderURL = outputDirectory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        var successCount = 0
        var lastFailure: String?

        for (index, imageURL) in imageURLs.enumerated() {
            if isImageDownloadCancelled(taskID: taskID) {
                throw AppError.cancelled
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: imageURL)
                if let httpResponse = response as? HTTPURLResponse,
                   (200..<300).contains(httpResponse.statusCode) == false {
                    throw AppError.downloadFailed("图片服务器返回 \(httpResponse.statusCode)")
                }

                let ext = Self.imageExtension(
                    from: response.url ?? imageURL,
                    mimeType: response.mimeType
                )
                let filename = String(format: "image_%03d.%@", index + 1, ext)
                let destination = SafePath.uniqueDestination(in: folderURL, preserving: filename)
                try data.write(to: destination, options: .atomic)
                successCount += 1

                let fraction = Double(index + 1) / Double(imageURLs.count)
                progressHandler(DownloadProgress(
                    fraction: fraction,
                    percentText: "\(Int((fraction * 100).rounded()))%",
                    speed: nil,
                    eta: nil
                ))
            } catch {
                lastFailure = error.localizedDescription
                await AppLogger.shared.log("图片下载失败：\(imageURL.absoluteString) \(error.localizedDescription)", level: .warning)
            }
        }

        setImageDownloadCancelled(false, taskID: taskID)

        guard successCount > 0 else {
            throw AppError.downloadFailed(lastFailure ?? "图片下载失败。")
        }

        return folderURL
    }

    func extractAudio(
        url: URL,
        audioFormat: AudioOutputFormat,
        outputDirectory: URL,
        taskID: UUID,
        progressHandler: @escaping (DownloadProgress) -> Void
    ) async throws -> URL? {
        try fileService.ensureWritableDirectory(outputDirectory)

        let metadata = try? await fetchMetadata(url: url)
        let baseName = fileService.uniqueOutputBaseName(
            in: outputDirectory,
            preferredTitle: metadata?.title ?? "audio_\(SafePath.timestampForFileName())"
        )

        var arguments = baseArguments(outputDirectory: outputDirectory, outputBaseName: baseName)
        arguments += [
            "-f", "bestaudio/b",
            "-x",
            "--audio-format", audioFormat.rawValue,
            "--audio-quality", "0"
        ]

        if let ffmpegLocation = try? ffmpegService.ffmpegExecutableURL().deletingLastPathComponent().path {
            arguments += ["--ffmpeg-location", ffmpegLocation]
        }

        arguments.append(url.absoluteString)

        let result = try await runner.run(
            id: taskID,
            executableURL: try ytdlpExecutableURL(),
            arguments: arguments
        ) { output in
            if let progress = Self.parseProgress(from: output.text) {
                progressHandler(progress)
            }
        }

        guard result.succeeded else {
            if result.exitCode == 15 {
                throw AppError.cancelled
            }
            throw AppError.fromCommandFailure(stderr: result.stderr, fallback: "音频提取失败。")
        }

        return finalOutputURL(from: result, outputDirectory: outputDirectory)
    }

    func cancelDownload(taskID: UUID) {
        setImageDownloadCancelled(true, taskID: taskID)
        runner.cancel(id: taskID)
    }

    @discardableResult
    func pauseDownload(taskID: UUID) -> Bool {
        runner.pause(id: taskID)
    }

    @discardableResult
    func resumeDownload(taskID: UUID) -> Bool {
        runner.resume(id: taskID)
    }

    func ytdlpExecutableURL() throws -> URL {
        let settings = AppSettingsStore.load()

        if settings.ytdlpPathMode == .custom {
            let custom = URL(fileURLWithPath: settings.customYTDLPPath)
            guard FileManager.default.fileExists(atPath: custom.path) else {
                throw AppError.toolUnavailable("yt-dlp")
            }
            return custom
        }

        let bundled = fileService.bundledYTDLPURL()
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        for candidate in ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"] {
            if FileManager.default.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return bundled
    }

    private func baseArguments(outputDirectory: URL, outputBaseName: String) -> [String] {
        [
            "--newline",
            "--no-playlist",
            "--windows-filenames",
            "--trim-filenames", "180",
            "--no-overwrites",
            "--print", "after_move:filepath",
            "-P", outputDirectory.path,
            "-o", "\(outputBaseName).%(ext)s"
        ]
    }

    private func finalOutputURL(from result: CommandResult, outputDirectory: URL) -> URL? {
        let lines = (result.stdout + "\n" + result.stderr)
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        return lines
            .compactMap { line -> URL? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix(outputDirectory.path) else {
                    return nil
                }
                return URL(fileURLWithPath: trimmed)
            }
            .last
    }

    private static func mapFormat(_ dto: FormatDTO) -> MediaFormat? {
        guard let formatID = dto.formatID else {
            return nil
        }

        return MediaFormat(
            formatID: formatID,
            extensionName: dto.extensionName ?? "-",
            resolution: dto.resolution,
            width: dto.width,
            height: dto.height,
            fps: dto.fps,
            fileSize: dto.fileSize,
            approxFileSize: dto.approxFileSize,
            videoCodec: dto.videoCodec,
            audioCodec: dto.audioCodec,
            audioBitrate: dto.audioBitrate,
            totalBitrate: dto.totalBitrate,
            formatNote: dto.formatNote
        )
    }

    private static func collectImageURLs(from data: Data, thumbnail: String?) -> [URL] {
        var ordered: [URL] = []
        var seen = Set<String>()

        func append(_ string: String) {
            guard let url = URL(string: string),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  isLikelyImageURL(url) else {
                return
            }

            let key = url.absoluteString
            guard seen.contains(key) == false else {
                return
            }

            seen.insert(key)
            ordered.append(url)
        }

        if let thumbnail {
            append(thumbnail)
        }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            walkJSON(object, append: append)
        }

        return Array(ordered.prefix(80))
    }

    private static func walkJSON(_ object: Any, append: (String) -> Void) {
        if let string = object as? String {
            append(string)
            return
        }

        if let array = object as? [Any] {
            for item in array {
                walkJSON(item, append: append)
            }
            return
        }

        if let dictionary = object as? [String: Any] {
            for value in dictionary.values {
                walkJSON(value, append: append)
            }
        }
    }

    private static func isLikelyImageURL(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "avif", "heic"].contains(pathExtension) {
            return true
        }

        let value = url.absoluteString.lowercased()
        return value.contains("imageview") ||
            value.contains("sns-img") ||
            value.contains("xhscdn") ||
            value.contains("xhs")
    }

    private static func imageExtension(from url: URL, mimeType: String?) -> String {
        if let mimeType = mimeType?.lowercased() {
            switch mimeType {
            case "image/jpeg":
                return "jpg"
            case "image/png":
                return "png"
            case "image/webp":
                return "webp"
            case "image/avif":
                return "avif"
            case "image/heic", "image/heif":
                return "heic"
            default:
                break
            }
        }

        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "webp", "avif", "heic"].contains(ext) {
            return ext == "jpeg" ? "jpg" : ext
        }

        return "jpg"
    }

    private func setImageDownloadCancelled(_ cancelled: Bool, taskID: UUID) {
        imageDownloadLock.lock()
        if cancelled {
            cancelledImageDownloads.insert(taskID)
        } else {
            cancelledImageDownloads.remove(taskID)
        }
        imageDownloadLock.unlock()
    }

    private func isImageDownloadCancelled(taskID: UUID) -> Bool {
        imageDownloadLock.lock()
        let value = cancelledImageDownloads.contains(taskID)
        imageDownloadLock.unlock()
        return value
    }

    private static func parseProgress(from text: String) -> DownloadProgress? {
        guard text.contains("[download]") else {
            return nil
        }

        guard let percent = firstMatch(in: text, pattern: #"(\d+(?:\.\d+)?)%"#),
              let value = Double(percent) else {
            return nil
        }

        let speed = firstMatch(in: text, pattern: #"at\s+([^\s]+/s)"#)
        let eta = firstMatch(in: text, pattern: #"ETA\s+([0-9:]+)"#)

        return DownloadProgress(
            fraction: min(max(value / 100, 0), 1),
            percentText: "\(percent)%",
            speed: speed,
            eta: eta
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[captureRange])
    }
}
