import Foundation

@MainActor
final class MobileMainViewModel: ObservableObject {
    @Published var serverAddress: String {
        didSet {
            UserDefaults.standard.set(serverAddress, forKey: Self.serverAddressKey)
        }
    }

    @Published var urlText = ""
    @Published var selectedKind: RemoteDownloadKind = .video
    @Published var selectedMode: DownloadMode = .best
    @Published var selectedAudioFormat: AudioOutputFormat = .m4a
    @Published var selectedFormatID: String?
    @Published var selectedTaskID: UUID?
    @Published var selectedMetadata: MediaMetadata?
    @Published var tasks: [MobileDownloadItem] = []
    @Published var isWorking = false
    @Published var isServerOnline = false
    @Published var serverMessage = "未连接"
    @Published var errorMessage: String?

    private static let serverAddressKey = "VideoExtractoriOS.serverAddress"

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.serverAddressKey) ?? "http://127.0.0.1:8765"
    }

    func checkServer() async {
        do {
            let health = try await client().health()
            isServerOnline = health.ok
            serverMessage = health.message
        } catch {
            isServerOnline = false
            serverMessage = AppError.friendly(from: error).localizedDescription
        }
    }

    func analyzeLinks() async {
        let rawURLs = URLDetector.urls(from: urlText)
        guard rawURLs.isEmpty == false else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }

        isWorking = true
        defer { isWorking = false }

        for rawURL in rawURLs {
            await analyzeSingleURL(rawURL)
        }
    }

    func downloadSelected() async {
        guard let id = selectedTaskID ?? tasks.first(where: { $0.canDownload })?.id else {
            errorMessage = "请先分析一个有效链接。"
            return
        }

        await startDownload(taskID: id)
    }

    func selectTask(_ id: UUID) {
        selectedTaskID = id
        guard let task = tasks.first(where: { $0.id == id }) else {
            return
        }
        selectedMetadata = task.metadata
        selectedMode = task.selectedMode
    }

    private func analyzeSingleURL(_ rawURL: String) async {
        do {
            let url = try URLDetector.validatedURL(from: rawURL)
            let taskID = UUID()
            let task = MobileDownloadItem(
                id: taskID,
                url: url.absoluteString,
                title: "正在分析",
                platform: URLDetector.detectPlatform(for: url),
                kind: selectedKind,
                status: .analyzing,
                progress: .empty,
                selectedMode: selectedMode
            )
            tasks.insert(task, at: 0)
            selectedTaskID = taskID

            let metadata = try await client().analyze(url: url)
            updateTask(id: taskID) { task in
                task.title = metadata.title
                task.platform = metadata.platform
                task.kind = selectedKind
                task.status = .ready
                task.metadata = metadata
                task.errorMessage = nil
            }
            selectedMetadata = metadata
        } catch {
            let friendly = AppError.friendly(from: error)
            errorMessage = friendly.localizedDescription
        }
    }

    private func startDownload(taskID: UUID) async {
        guard let task = tasks.first(where: { $0.id == taskID }),
              let url = URL(string: task.url) else {
            errorMessage = AppError.invalidURL.localizedDescription
            return
        }

        do {
            isWorking = true
            defer { isWorking = false }

            let kind = selectedKind
            let mode = kind == .audio ? DownloadMode.audioOnly : selectedMode
            updateTask(id: taskID) { task in
                task.kind = kind
                task.selectedMode = mode
                task.status = .waiting
                task.errorMessage = nil
                task.progress = .empty
            }

            let response = try await client().startDownload(
                url: url,
                kind: kind,
                mode: mode,
                customFormatID: selectedFormatID,
                audioFormat: selectedAudioFormat
            )

            updateTask(id: taskID) { task in
                task.remoteJobID = response.jobID
                task.status = .downloading
            }

            try await poll(jobID: response.jobID, taskID: taskID)
        } catch {
            let friendly = AppError.friendly(from: error)
            updateTask(id: taskID) { task in
                task.status = .failed
                task.errorMessage = friendly.localizedDescription
            }
            errorMessage = friendly.localizedDescription
        }
    }

    private func poll(jobID: String, taskID: UUID) async throws {
        while true {
            let status = try await client().jobStatus(jobID: jobID)
            updateTask(id: taskID) { task in
                task.title = status.title ?? task.title
                task.status = status.status
                task.progress = status.progress
                task.errorMessage = status.errorMessage
            }

            switch status.status {
            case .completed:
                let fileURL = try await client().downloadFile(jobID: jobID, fileName: status.fileName)
                updateTask(id: taskID) { task in
                    task.outputFileURL = fileURL
                    task.progress = DownloadProgress(fraction: 1, percentText: "100%", speed: nil, eta: nil)
                }
                return
            case .failed, .cancelled:
                return
            default:
                try await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
    }

    private func updateTask(id: UUID, mutate: (inout MobileDownloadItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&tasks[index])
        tasks[index].updatedAt = Date()

        if selectedTaskID == id {
            selectedMetadata = tasks[index].metadata
        }
    }

    private func client() throws -> DownloadServerClient {
        try DownloadServerClient(serverAddress: serverAddress)
    }
}
