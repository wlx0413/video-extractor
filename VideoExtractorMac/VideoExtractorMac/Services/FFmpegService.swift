import Foundation

final class FFmpegService {
    private let runner: CommandRunner
    private let fileService: FileManagerService

    init(
        runner: CommandRunner = .shared,
        fileService: FileManagerService = .shared
    ) {
        self.runner = runner
        self.fileService = fileService
    }

    func checkFFmpegAvailable() async throws -> String {
        let executableURL = try ffmpegExecutableURL()
        let result = try await runner.run(executableURL: executableURL, arguments: ["-version"])

        guard result.succeeded else {
            throw AppError.toolUnavailable("FFmpeg")
        }

        return result.stdout
            .split(separator: "\n")
            .first
            .map(String.init) ?? "FFmpeg 可用"
    }

    func ffmpegExecutableURL() throws -> URL {
        let settings = AppSettingsStore.load()

        if settings.ffmpegPathMode == .custom {
            let custom = URL(fileURLWithPath: settings.customFFmpegPath)
            guard FileManager.default.fileExists(atPath: custom.path) else {
                throw AppError.toolUnavailable("FFmpeg")
            }
            return custom
        }

        let bundled = fileService.bundledFFmpegURL()
        if FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        for candidate in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"] {
            if FileManager.default.fileExists(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return bundled
    }
}
