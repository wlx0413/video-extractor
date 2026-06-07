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
        var language: String?
        var subtitles: [String: [SubtitleFormatDTO]]?
        var automaticCaptions: [String: [SubtitleFormatDTO]]?

        enum CodingKeys: String, CodingKey {
            case id
            case webpageURL = "webpage_url"
            case title
            case uploader
            case channel
            case duration
            case thumbnail
            case formats
            case language
            case subtitles
            case automaticCaptions = "automatic_captions"
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

    private struct SubtitleFormatDTO: Decodable {
        var extensionName: String?
        var name: String?
        var url: String?

        enum CodingKeys: String, CodingKey {
            case extensionName = "ext"
            case name
            case url
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
            let subtitleTracks = Self.collectSubtitleTracks(
                subtitles: dto.subtitles,
                automaticCaptions: dto.automaticCaptions,
                originalLanguageCode: dto.language
            )

            return MediaMetadata(
                id: metadataID,
                sourceURL: dto.webpageURL ?? url.absoluteString,
                platform: platform,
                title: title?.isEmpty == false ? title! : "video_\(SafePath.timestampForFileName())",
                author: dto.uploader ?? dto.channel,
                duration: dto.duration,
                thumbnailURL: dto.thumbnail.flatMap(URL.init(string:)),
                imageURLs: imageURLs,
                formats: formats,
                subtitleTracks: subtitleTracks
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
        subtitleSelection: SubtitleSelection? = nil,
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
        let subtitleSelection = subtitleSelection?.isEmpty == false ? subtitleSelection : nil
        let mediaOutputDirectory: URL

        if subtitleSelection != nil {
            mediaOutputDirectory = outputDirectory.appendingPathComponent(baseName, isDirectory: true)
            try FileManager.default.createDirectory(at: mediaOutputDirectory, withIntermediateDirectories: true)
        } else {
            mediaOutputDirectory = outputDirectory
        }

        var arguments = baseArguments(outputDirectory: mediaOutputDirectory, outputBaseName: baseName)
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

        guard let videoURL = finalOutputURL(from: result, outputDirectory: mediaOutputDirectory) else {
            if subtitleSelection != nil {
                throw AppError.downloadFailed("下载完成但没有找到输出视频文件。")
            }
            return nil
        }

        if let subtitleSelection {
            progressHandler(DownloadProgress(fraction: 1, percentText: "100%", speed: nil, eta: nil))
            try await downloadAndComposeSubtitles(
                url: url,
                selection: subtitleSelection,
                outputDirectory: mediaOutputDirectory,
                outputBaseName: videoURL.deletingPathExtension().lastPathComponent,
                taskID: taskID
            )
            return mediaOutputDirectory
        }

        return videoURL
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

    private static func collectSubtitleTracks(
        subtitles: [String: [SubtitleFormatDTO]]?,
        automaticCaptions: [String: [SubtitleFormatDTO]]?,
        originalLanguageCode: String?
    ) -> [SubtitleTrack] {
        var tracks: [SubtitleTrack] = []
        var seen = Set<String>()

        func addTracks(from sourceMap: [String: [SubtitleFormatDTO]]?, source: SubtitleSource) {
            let sortedItems = (sourceMap ?? [:])
                .filter { key, value in
                    key != "live_chat" && value.isEmpty == false
                }
                .sorted { left, right in
                    left.key.localizedCaseInsensitiveCompare(right.key) == .orderedAscending
                }

            for (languageCode, formats) in sortedItems {
                let cleanedCode = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
                guard cleanedCode.isEmpty == false else {
                    continue
                }

                let track = SubtitleTrack(
                    languageCode: cleanedCode,
                    languageName: subtitleLanguageName(for: cleanedCode, formats: formats),
                    source: source,
                    isOriginalLanguage: isSameLanguage(cleanedCode, originalLanguageCode)
                )

                guard seen.contains(track.id) == false else {
                    continue
                }
                seen.insert(track.id)
                tracks.append(track)
            }
        }

        addTracks(from: subtitles, source: .manual)
        addTracks(from: automaticCaptions, source: .automatic)

        return tracks.sorted { left, right in
            if left.isOriginalLanguage != right.isOriginalLanguage {
                return left.isOriginalLanguage
            }
            if left.source != right.source {
                return left.source == .manual
            }
            return left.languageName.localizedCaseInsensitiveCompare(right.languageName) == .orderedAscending
        }
    }

    private static func subtitleLanguageName(for languageCode: String, formats: [SubtitleFormatDTO]) -> String {
        let candidate = formats
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false && $0.lowercased() != "none" }

        if let candidate {
            return candidate
        }

        let normalizedCode = languageCode.replacingOccurrences(of: "_", with: "-")
        if let localized = Locale.current.localizedString(forIdentifier: normalizedCode) {
            return localized
        }

        let languagePart = normalizedCode.split(separator: "-").first.map(String.init) ?? normalizedCode
        return Locale.current.localizedString(forLanguageCode: languagePart) ?? languageCode
    }

    private static func isSameLanguage(_ languageCode: String, _ originalLanguageCode: String?) -> Bool {
        guard let originalLanguageCode, originalLanguageCode.isEmpty == false else {
            return false
        }

        func normalized(_ value: String) -> String {
            value
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
        }

        let language = normalized(languageCode)
        let original = normalized(originalLanguageCode)
        return language == original ||
            language.split(separator: "-").first == original.split(separator: "-").first
    }

    private func downloadAndComposeSubtitles(
        url: URL,
        selection: SubtitleSelection,
        outputDirectory: URL,
        outputBaseName: String,
        taskID: UUID
    ) async throws {
        guard selection.outputFormats.isEmpty == false else {
            throw AppError.downloadFailed("请选择至少一种字幕格式。")
        }

        let temporaryDirectory = outputDirectory.appendingPathComponent(
            ".subtitle_source_\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        var inputs: [SubtitleComposer.TrackInput] = []
        for (index, track) in selection.tracks.enumerated() {
            let subtitleURL = try await downloadSubtitleFile(
                url: url,
                track: track,
                index: index,
                temporaryDirectory: temporaryDirectory,
                taskID: taskID
            )
            let cues = try SubtitleComposer.parse(fileURL: subtitleURL)
            inputs.append(SubtitleComposer.TrackInput(track: track, cues: cues))
        }

        try SubtitleComposer.write(
            inputs: inputs,
            outputFormats: selection.outputFormats,
            outputDirectory: outputDirectory,
            outputBaseName: "\(outputBaseName).\(selection.languageSuffix)"
        )
    }

    private func downloadSubtitleFile(
        url: URL,
        track: SubtitleTrack,
        index: Int,
        temporaryDirectory: URL,
        taskID: UUID
    ) async throws -> URL {
        let outputBaseName = "subtitle_\(index + 1)_\(track.source.rawValue)_\(SafePath.sanitizedFileName(track.languageCode, fallbackPrefix: "sub"))"
        var arguments = [
            "--no-playlist",
            "--skip-download",
            "--windows-filenames",
            "--trim-filenames", "180",
            "--sub-langs", track.languageCode,
            "--sub-format", "srt/vtt/best",
            "--convert-subs", "srt",
            "-P", temporaryDirectory.path,
            "-o", "\(outputBaseName).%(ext)s"
        ]

        switch track.source {
        case .manual:
            arguments.insert("--write-subs", at: 2)
        case .automatic:
            arguments.insert("--write-auto-subs", at: 2)
        }

        if let ffmpegLocation = try? ffmpegService.ffmpegExecutableURL().deletingLastPathComponent().path {
            arguments += ["--ffmpeg-location", ffmpegLocation]
        }

        arguments.append(url.absoluteString)

        let result = try await runner.run(
            id: taskID,
            executableURL: try ytdlpExecutableURL(),
            arguments: arguments
        )

        guard result.succeeded else {
            if result.exitCode == 15 {
                throw AppError.cancelled
            }
            throw AppError.fromCommandFailure(
                stderr: result.stderr + "\n" + result.stdout,
                fallback: "\(track.displayName) 下载失败。"
            )
        }

        if let subtitleURL = newestSubtitleFile(in: temporaryDirectory, baseName: outputBaseName) {
            return subtitleURL
        }

        throw AppError.downloadFailed("没有找到 \(track.displayName) 的字幕文件。")
    }

    private func newestSubtitleFile(in directory: URL, baseName: String) -> URL? {
        let allowedExtensions = Set(["srt", "vtt"])
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []

        return contents
            .filter { url in
                url.lastPathComponent.hasPrefix(baseName) &&
                    allowedExtensions.contains(url.pathExtension.lowercased())
            }
            .sorted { left, right in
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }
            .first
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

private enum SubtitleComposer {
    struct Cue: Hashable {
        var startMilliseconds: Int
        var endMilliseconds: Int
        var text: String
    }

    struct TrackInput {
        var track: SubtitleTrack
        var cues: [Cue]
    }

    private struct Segment {
        var startMilliseconds: Int
        var endMilliseconds: Int
        var lines: [String]
    }

    static func parse(fileURL: URL) throws -> [Cue] {
        let rawText = try String(contentsOf: fileURL, encoding: .utf8)
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var cues: [Cue] = []
        var index = 0

        while index < lines.count {
            var line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty || line == "WEBVTT" || line.hasPrefix("NOTE") || line.hasPrefix("STYLE") {
                index += 1
                continue
            }

            if line.contains("-->") == false,
               index + 1 < lines.count,
               lines[index + 1].contains("-->") {
                index += 1
                line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let timing = parseTimingLine(line) else {
                index += 1
                continue
            }

            index += 1
            var textLines: [String] = []
            while index < lines.count {
                let textLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                if textLine.isEmpty {
                    break
                }
                textLines.append(cleanSubtitleText(textLine))
                index += 1
            }

            let text = textLines
                .filter { $0.isEmpty == false }
                .joined(separator: "\n")

            if text.isEmpty == false && timing.end > timing.start {
                cues.append(Cue(
                    startMilliseconds: timing.start,
                    endMilliseconds: timing.end,
                    text: text
                ))
            }

            index += 1
        }

        return cues
    }

    static func write(
        inputs: [TrackInput],
        outputFormats: Set<SubtitleOutputFormat>,
        outputDirectory: URL,
        outputBaseName: String
    ) throws {
        let segments = composeSegments(from: inputs)
        guard segments.isEmpty == false else {
            throw AppError.downloadFailed("字幕内容为空，无法合成外挂字幕。")
        }

        for format in outputFormats {
            let fileURL = outputDirectory.appendingPathComponent("\(outputBaseName).\(format.fileExtension)")
            switch format {
            case .srt:
                try srtText(from: segments).write(to: fileURL, atomically: true, encoding: .utf8)
            case .ass:
                try assText(from: segments).write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func composeSegments(from inputs: [TrackInput]) -> [Segment] {
        let boundaries = Set(inputs.flatMap { input in
            input.cues.flatMap { [$0.startMilliseconds, $0.endMilliseconds] }
        })
        .sorted()

        guard boundaries.count > 1 else {
            return []
        }

        var segments: [Segment] = []

        for offset in 0..<(boundaries.count - 1) {
            let start = boundaries[offset]
            let end = boundaries[offset + 1]
            guard start < end else {
                continue
            }

            let lines = inputs.compactMap { input -> String? in
                guard let cue = input.cues.first(where: { $0.startMilliseconds < end && $0.endMilliseconds > start }) else {
                    return nil
                }
                return "[\(input.track.subtitleLineLabel)] \(cue.text.replacingOccurrences(of: "\n", with: " / "))"
            }

            guard lines.isEmpty == false else {
                continue
            }

            if let last = segments.last,
               last.endMilliseconds == start,
               last.lines == lines {
                segments[segments.count - 1].endMilliseconds = end
            } else {
                segments.append(Segment(startMilliseconds: start, endMilliseconds: end, lines: lines))
            }
        }

        return segments
    }

    private static func parseTimingLine(_ line: String) -> (start: Int, end: Int)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2,
              let start = parseTimestamp(parts[0]),
              let end = parseTimestamp(parts[1]) else {
            return nil
        }
        return (start, end)
    }

    private static func parseTimestamp(_ rawValue: String) -> Int? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)?
            .replacingOccurrences(of: ",", with: ".")

        guard let value else {
            return nil
        }

        let parts = value.split(separator: ":").map(String.init)
        let hours: Double
        let minutes: Double
        let seconds: Double

        if parts.count == 3 {
            guard let parsedHours = Double(parts[0]),
                  let parsedMinutes = Double(parts[1]),
                  let parsedSeconds = Double(parts[2]) else {
                return nil
            }
            hours = parsedHours
            minutes = parsedMinutes
            seconds = parsedSeconds
        } else if parts.count == 2 {
            guard let parsedMinutes = Double(parts[0]),
                  let parsedSeconds = Double(parts[1]) else {
                return nil
            }
            hours = 0
            minutes = parsedMinutes
            seconds = parsedSeconds
        } else {
            return nil
        }

        return Int(((hours * 3600) + (minutes * 60) + seconds) * 1000)
    }

    private static func cleanSubtitleText(_ value: String) -> String {
        let withoutTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func srtText(from segments: [Segment]) -> String {
        segments.enumerated().map { index, segment in
            """
            \(index + 1)
            \(srtTimestamp(segment.startMilliseconds)) --> \(srtTimestamp(segment.endMilliseconds))
            \(segment.lines.joined(separator: "\n"))
            """
        }
        .joined(separator: "\n\n") + "\n"
    }

    private static func assText(from segments: [Segment]) -> String {
        let header = """
        [Script Info]
        ScriptType: v4.00+
        WrapStyle: 0
        ScaledBorderAndShadow: yes
        PlayResX: 1920
        PlayResY: 1080

        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,48,&H00FFFFFF,&H00FFFFFF,&H00000000,&H96000000,0,0,0,0,100,100,0,0,1,2,1,2,70,70,70,1

        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        """

        let events = segments.map { segment in
            "Dialogue: 0,\(assTimestamp(segment.startMilliseconds)),\(assTimestamp(segment.endMilliseconds)),Default,,0,0,0,,\(assEscaped(segment.lines.joined(separator: "\n")))"
        }
        .joined(separator: "\n")

        return header + "\n" + events + "\n"
    }

    private static func srtTimestamp(_ milliseconds: Int) -> String {
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1_000
        let millis = milliseconds % 1_000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    private static func assTimestamp(_ milliseconds: Int) -> String {
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let seconds = (milliseconds % 60_000) / 1_000
        let centiseconds = (milliseconds % 1_000) / 10
        return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }

    private static func assEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "\n", with: "\\N")
    }
}
