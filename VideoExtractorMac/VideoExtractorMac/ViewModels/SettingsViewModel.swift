import AppKit
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            AppSettingsStore.save(settings)
        }
    }

    @Published var ytdlpVersion: String = "未检查"
    @Published var ffmpegVersion: String = "未检查"
    @Published var toolCheckError: String?

    private let ytdlpService: YTDLPService
    private let ffmpegService: FFmpegService

    init(
        ytdlpService: YTDLPService = YTDLPService(),
        ffmpegService: FFmpegService = FFmpegService()
    ) {
        self.ytdlpService = ytdlpService
        self.ffmpegService = ffmpegService
        self.settings = AppSettingsStore.load()
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"

        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultDownloadDirectoryPath = url.path
        }
    }

    func chooseYTDLPPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"

        if panel.runModal() == .OK, let url = panel.url {
            settings.ytdlpPathMode = .custom
            settings.customYTDLPPath = url.path
        }
    }

    func chooseFFmpegPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"

        if panel.runModal() == .OK, let url = panel.url {
            settings.ffmpegPathMode = .custom
            settings.customFFmpegPath = url.path
        }
    }

    func checkTools() {
        toolCheckError = nil

        Task {
            do {
                async let ytdlp = ytdlpService.checkYTDLPAvailable()
                async let ffmpeg = ffmpegService.checkFFmpegAvailable()
                ytdlpVersion = try await ytdlp
                ffmpegVersion = try await ffmpeg
            } catch {
                let appError = AppError.friendly(from: error)
                toolCheckError = appError.localizedDescription
            }
        }
    }
}
