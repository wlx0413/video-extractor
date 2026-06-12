import AppKit
import Foundation

@MainActor
final class MainViewModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var selectedMetadata: MediaMetadata?
    @Published var formats: [MediaFormat] = []
    @Published var selectedTaskID: UUID?
    @Published var selectedMode: DownloadMode = AppSettingsStore.load().defaultVideoQuality.downloadMode
    @Published var selectedAudioFormat: AudioOutputFormat = AppSettingsStore.load().defaultAudioFormat
    @Published var selectedFormatID: String?
    @Published var selectedSubtitleCount: Int = 0
    @Published var selectedSubtitleTrackIDs: [String] = []
    @Published var selectedSubtitleOutputFormats: Set<SubtitleOutputFormat> = Set(SubtitleOutputFormat.allCases)
    @Published var tasks: [DownloadTask] = []
    @Published var isAnalyzing: Bool = false
    @Published var errorMessage: String?

    var subtitleValidationMessage: String? {
        guard selectedSubtitleCount > 0 else {
            return nil
        }

        let tracks = selectedMetadata?.subtitleTracks ?? []
        guard tracks.isEmpty == false else {
            return "当前视频没有可用字幕。"
        }

        if selectedSubtitleOutputFormats.isEmpty {
            return "请选择至少一种字幕格式。"
        }

        let selectedIDs = Array(selectedSubtitleTrackIDs.prefix(selectedSubtitleCount))
        if selectedIDs.count < selectedSubtitleCount || selectedIDs.contains(where: { $0.isEmpty }) {
            return "请选择字幕语言。"
        }

        if Set(selectedIDs).count != selectedIDs.count {
            return "字幕语言不能重复。"
        }

        let availableIDs = Set(tracks.map(\.id))
        if selectedIDs.contains(where: { availableIDs.contains($0) == false }) {
            return "请选择有效的字幕语言。"
        }

        return nil
    }

    var canDownloadVideo: Bool {
        subtitleValidationMessage == nil
    }

    private let ytdlpService: YTDLPService
    private let ffmpegService: FFmpegService
    private let fileService: FileManagerService
    private let historyService: HistoryService

    init(
        ytdlpService: YTDLPService = YTDLPService(),
        ffmpegService: FFmpegService = FFmpegService(),
        fileService: FileManagerService = .shared,
        historyService: HistoryService = HistoryService()
    ) {
        self.ytdlpService = ytdlpService
        self.ffmpegService = ffmpegService
        self.fileService = fileService
        self.historyService = historyService
    }

    func analyzeLinks() async {
        errorMessage = nil
        isAnalyzing = true
        defer { isAnalyzing = false }

        let rawURLs = URLDetector.urls(from: urlText)
        guard rawURLs.isEmpty == false else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }

        for rawURL in rawURLs {
            await analyzeSingleURL(rawURL)
        }
    }

    func selectTask(_ id: UUID) {
        selectedTaskID = id
        guard let task = tasks.first(where: { $0.id == id }) else {
            return
        }

        selectedMetadata = task.metadata
        formats = task.metadata?.formats ?? []
        selectedFormatID = task.selectedFormatID
        selectedMode = task.selectedMode
        selectedSubtitleTrackIDs = task.selectedSubtitleTrackIDs
        selectedSubtitleCount = task.selectedSubtitleTrackIDs.count
        selectedSubtitleOutputFormats = task.selectedSubtitleOutputFormats.isEmpty
            ? Set(SubtitleOutputFormat.allCases)
            : task.selectedSubtitleOutputFormats
        normalizeSubtitleTrackIDs()
    }

    func downloadSelectedVideo() async {
        guard let taskID = selectedTaskID ?? tasks.first(where: { $0.status == .ready })?.id else {
            errorMessage = "请先分析一个有效链接。"
            return
        }

        await startVideoDownload(taskID: taskID)
    }

    func downloadSelectedAudio() async {
        guard let taskID = selectedTaskID ?? tasks.first(where: { $0.status == .ready })?.id else {
            errorMessage = "请先分析一个有效链接。"
            return
        }

        await startAudioDownload(taskID: taskID)
    }

    func downloadSelectedImages() async {
        guard let taskID = selectedTaskID ?? tasks.first(where: { $0.status == .ready })?.id else {
            errorMessage = "请先分析一个有效的小红书图文链接。"
            return
        }

        await startImageDownload(taskID: taskID)
    }

    func cancelTask(_ id: UUID) {
        ytdlpService.cancelDownload(taskID: id)
        updateTask(id: id) { task in
            task.status = .cancelled
            task.errorMessage = AppError.cancelled.localizedDescription
        }
    }

    func pauseTask(_ id: UUID) {
        guard ytdlpService.pauseDownload(taskID: id) else {
            errorMessage = "当前任务暂时无法暂停。"
            return
        }

        updateTask(id: id) { task in
            task.status = .paused
        }
    }

    func resumeTask(_ id: UUID) {
        guard ytdlpService.resumeDownload(taskID: id) else {
            errorMessage = "当前任务暂时无法继续。"
            return
        }

        updateTask(id: id) { task in
            task.status = .downloading
        }
    }

    private func analyzeSingleURL(_ rawURL: String) async {
        do {
            let url = try URLDetector.validatedURL(from: rawURL)
            let platform = URLDetector.detectPlatform(for: url)
            let taskID = UUID()
            let task = DownloadTask(id: taskID, url: url.absoluteString, platform: platform, status: .analyzing)
            tasks.insert(task, at: 0)
            selectedTaskID = taskID

            _ = try await ytdlpService.checkYTDLPAvailable()
            let metadata = try await ytdlpService.fetchMetadata(url: url)

            updateTask(id: taskID) { task in
                task.title = metadata.title
                task.platform = metadata.platform
                task.status = .ready
                task.metadata = metadata
            }

            selectedMetadata = metadata
            formats = metadata.formats.sorted { lhs, rhs in
                (lhs.height ?? 0, lhs.totalBitrate ?? 0) > (rhs.height ?? 0, rhs.totalBitrate ?? 0)
            }
            resetSubtitleSelection(for: metadata)
        } catch {
            let appError = AppError.friendly(from: error)
            errorMessage = appError.localizedDescription

            if let url = try? URLDetector.validatedURL(from: rawURL) {
                let failedTask = DownloadTask(
                    url: url.absoluteString,
                    title: "分析失败",
                    platform: URLDetector.detectPlatform(for: url),
                    status: .failed,
                    errorMessage: appError.localizedDescription
                )
                tasks.insert(failedTask, at: 0)
                await writeHistory(for: failedTask, formatDescription: "分析失败")
            }

            await AppLogger.shared.log("分析失败：\(rawURL) \(appError.localizedDescription)", level: .error)
        }
    }

    private func startVideoDownload(taskID: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let url = URL(string: task.url) else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }

        do {
            let subtitleSelection = try selectedSubtitleSelection()
            _ = try await ytdlpService.checkYTDLPAvailable()
            _ = try await ffmpegService.checkFFmpegAvailable()

            let settings = AppSettingsStore.load()
            let outputDirectory = fileService.resolvedDownloadDirectory(from: settings)
            try fileService.ensureWritableDirectory(outputDirectory)

            updateTask(id: taskID) { task in
                task.status = .downloading
                task.selectedMode = selectedMode
                task.selectedFormatID = selectedMode == .custom ? selectedFormatID : nil
                task.selectedSubtitleTrackIDs = Array(selectedSubtitleTrackIDs.prefix(selectedSubtitleCount))
                task.selectedSubtitleOutputFormats = selectedSubtitleOutputFormats
                task.errorMessage = nil
                task.progress = .empty
            }

            let outputURL = try await ytdlpService.downloadVideo(
                url: url,
                selectedFormat: selectedMode,
                customFormatID: selectedMode == .custom ? selectedFormatID : nil,
                subtitleSelection: subtitleSelection,
                outputDirectory: outputDirectory,
                taskID: taskID
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateProgress(taskID: taskID, progress: progress)
                }
            }

            updateTask(id: taskID) { task in
                task.status = .completed
                task.progress = DownloadProgress(fraction: 1, percentText: "100%", speed: nil, eta: nil)
                task.outputPath = outputURL?.path ?? outputDirectory.path
            }

            if let completed = tasks.first(where: { $0.id == taskID }) {
                await writeHistory(for: completed, formatDescription: videoFormatDescription(subtitleSelection: subtitleSelection))
            }

            if settings.shouldOpenFolderWhenFinished {
                NSWorkspace.shared.open(outputDirectory)
            }
        } catch {
            await handleDownloadError(error, taskID: taskID, formatDescription: selectedMode.displayName)
        }
    }

    private func startAudioDownload(taskID: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let url = URL(string: task.url) else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }

        do {
            _ = try await ytdlpService.checkYTDLPAvailable()
            _ = try await ffmpegService.checkFFmpegAvailable()

            let settings = AppSettingsStore.load()
            let outputDirectory = fileService.resolvedDownloadDirectory(from: settings)
            try fileService.ensureWritableDirectory(outputDirectory)

            updateTask(id: taskID) { task in
                task.status = .downloading
                task.selectedMode = .audioOnly
                task.errorMessage = nil
                task.progress = .empty
            }

            let outputURL = try await ytdlpService.extractAudio(
                url: url,
                audioFormat: selectedAudioFormat,
                outputDirectory: outputDirectory,
                taskID: taskID
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateProgress(taskID: taskID, progress: progress)
                }
            }

            updateTask(id: taskID) { task in
                task.status = .completed
                task.progress = DownloadProgress(fraction: 1, percentText: "100%", speed: nil, eta: nil)
                task.outputPath = outputURL?.path ?? outputDirectory.path
            }

            if let completed = tasks.first(where: { $0.id == taskID }) {
                await writeHistory(for: completed, formatDescription: "仅音频 \(selectedAudioFormat.displayName)")
            }

            if settings.shouldOpenFolderWhenFinished {
                NSWorkspace.shared.open(outputDirectory)
            }
        } catch {
            await handleDownloadError(error, taskID: taskID, formatDescription: "仅音频 \(selectedAudioFormat.displayName)")
        }
    }

    private func startImageDownload(taskID: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let url = URL(string: task.url) else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }

        do {
            _ = try await ytdlpService.checkYTDLPAvailable()

            let settings = AppSettingsStore.load()
            let outputDirectory = fileService.resolvedDownloadDirectory(from: settings)
            try fileService.ensureWritableDirectory(outputDirectory)

            updateTask(id: taskID) { task in
                task.status = .downloading
                task.selectedMode = .custom
                task.errorMessage = nil
                task.progress = .empty
            }

            let outputURL = try await ytdlpService.downloadImages(
                url: url,
                outputDirectory: outputDirectory,
                taskID: taskID
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.updateProgress(taskID: taskID, progress: progress)
                }
            }

            updateTask(id: taskID) { task in
                task.status = .completed
                task.progress = DownloadProgress(fraction: 1, percentText: "100%", speed: nil, eta: nil)
                task.outputPath = outputURL?.path ?? outputDirectory.path
            }

            if let completed = tasks.first(where: { $0.id == taskID }) {
                await writeHistory(for: completed, formatDescription: "小红书图文图片")
            }

            if settings.shouldOpenFolderWhenFinished {
                NSWorkspace.shared.open(outputDirectory)
            }
        } catch {
            await handleDownloadError(error, taskID: taskID, formatDescription: "小红书图文图片")
        }
    }

    private func updateProgress(taskID: UUID, progress: DownloadProgress) {
        updateTask(id: taskID) { task in
            guard task.status != .paused else {
                return
            }
            task.progress = progress
            task.status = progress.fraction >= 1 ? .converting : .downloading
        }
    }

    private func handleDownloadError(_ error: Error, taskID: UUID, formatDescription: String) async {
        let appError = AppError.friendly(from: error)
        errorMessage = appError.localizedDescription

        updateTask(id: taskID) { task in
            task.status = appError == .cancelled ? .cancelled : .failed
            task.errorMessage = appError.localizedDescription
        }

        if let failed = tasks.first(where: { $0.id == taskID }) {
            await writeHistory(for: failed, formatDescription: formatDescription)
        }

        await AppLogger.shared.log("下载任务失败：\(appError.localizedDescription)", level: .error)
    }

    private func updateTask(id: UUID, mutate: (inout DownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&tasks[index])
        tasks[index].updatedAt = Date()

        if selectedTaskID == id {
            selectedMetadata = tasks[index].metadata
            formats = tasks[index].metadata?.formats ?? formats
            selectedFormatID = tasks[index].selectedFormatID
            selectedSubtitleTrackIDs = tasks[index].selectedSubtitleTrackIDs
            selectedSubtitleCount = tasks[index].selectedSubtitleTrackIDs.count
            selectedSubtitleOutputFormats = tasks[index].selectedSubtitleOutputFormats.isEmpty
                ? selectedSubtitleOutputFormats
                : tasks[index].selectedSubtitleOutputFormats
        }
    }

    func setSubtitleTrackCount(_ count: Int) {
        selectedSubtitleCount = max(0, min(3, count))
        normalizeSubtitleTrackIDs()
        syncSubtitleSelectionToSelectedTask()
    }

    func selectedSubtitleTrackID(at index: Int) -> String {
        guard selectedSubtitleTrackIDs.indices.contains(index) else {
            return ""
        }
        return selectedSubtitleTrackIDs[index]
    }

    func setSubtitleTrackID(_ id: String, at index: Int) {
        guard index >= 0 else {
            return
        }
        while selectedSubtitleTrackIDs.count <= index {
            selectedSubtitleTrackIDs.append("")
        }
        selectedSubtitleTrackIDs[index] = id
        syncSubtitleSelectionToSelectedTask()
    }

    func toggleSubtitleOutputFormat(_ format: SubtitleOutputFormat, enabled: Bool) {
        if enabled {
            selectedSubtitleOutputFormats.insert(format)
        } else {
            selectedSubtitleOutputFormats.remove(format)
        }
        syncSubtitleSelectionToSelectedTask()
    }

    private func resetSubtitleSelection(for metadata: MediaMetadata) {
        selectedSubtitleCount = 0
        selectedSubtitleTrackIDs = []
        selectedSubtitleOutputFormats = Set(SubtitleOutputFormat.allCases)

        guard metadata.subtitleTracks.isEmpty == false else {
            return
        }

        normalizeSubtitleTrackIDs()
        syncSubtitleSelectionToSelectedTask()
    }

    private func normalizeSubtitleTrackIDs() {
        let tracks = selectedMetadata?.subtitleTracks ?? []
        let availableIDs = tracks.map(\.id)

        if selectedSubtitleCount == 0 {
            selectedSubtitleTrackIDs = []
            return
        }

        while selectedSubtitleTrackIDs.count < selectedSubtitleCount {
            let nextID = availableIDs.first { selectedSubtitleTrackIDs.contains($0) == false } ?? ""
            selectedSubtitleTrackIDs.append(nextID)
        }

        selectedSubtitleTrackIDs = Array(selectedSubtitleTrackIDs.prefix(selectedSubtitleCount))

        for index in selectedSubtitleTrackIDs.indices {
            if availableIDs.contains(selectedSubtitleTrackIDs[index]) == false {
                selectedSubtitleTrackIDs[index] = availableIDs.first { selectedSubtitleTrackIDs.contains($0) == false } ?? ""
            }
        }
    }

    private func syncSubtitleSelectionToSelectedTask() {
        guard let selectedTaskID,
              let index = tasks.firstIndex(where: { $0.id == selectedTaskID }) else {
            return
        }

        tasks[index].selectedSubtitleTrackIDs = Array(selectedSubtitleTrackIDs.prefix(selectedSubtitleCount))
        tasks[index].selectedSubtitleOutputFormats = selectedSubtitleOutputFormats
        tasks[index].updatedAt = Date()
    }

    private func selectedSubtitleSelection() throws -> SubtitleSelection? {
        guard selectedSubtitleCount > 0 else {
            return nil
        }

        if let validationMessage = subtitleValidationMessage {
            throw AppError.downloadFailed(validationMessage)
        }

        let tracks = selectedMetadata?.subtitleTracks ?? []
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let selectedTracks = Array(selectedSubtitleTrackIDs.prefix(selectedSubtitleCount)).compactMap { byID[$0] }
        return SubtitleSelection(tracks: selectedTracks, outputFormats: selectedSubtitleOutputFormats)
    }

    private func videoFormatDescription(subtitleSelection: SubtitleSelection?) -> String {
        guard let subtitleSelection, subtitleSelection.isEmpty == false else {
            return selectedMode.displayName
        }

        let languages = subtitleSelection.tracks.map(\.languageCode).joined(separator: "+")
        let formats = subtitleSelection.outputFormats
            .sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: "+")
        return "\(selectedMode.displayName) · 字幕 \(languages) · \(formats)"
    }

    private func writeHistory(for task: DownloadTask, formatDescription: String) async {
        let record = DownloadHistoryRecord(
            title: task.title,
            url: task.url,
            platform: task.platform,
            outputPath: task.outputPath,
            formatDescription: formatDescription,
            status: task.status
        )
        await historyService.append(record)
    }
}
