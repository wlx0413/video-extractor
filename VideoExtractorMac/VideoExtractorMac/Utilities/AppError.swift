import Foundation

enum AppError: LocalizedError, Equatable {
    case invalidURL
    case toolUnavailable(String)
    case loginRequired
    case unsupportedPlatform
    case permissionDenied
    case outputDirectoryNotWritable(String)
    case networkFailure
    case downloadFailed(String)
    case conversionFailed(String)
    case fileOperationDenied(String)
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "链接格式无效。请粘贴 http 或 https 开头的视频链接。"
        case .toolUnavailable(let name):
            return "\(name) 未安装、路径错误或没有执行权限。请在设置中检查工具路径。"
        case .loginRequired:
            return "当前视频可能需要登录、会员、地区权限或额外授权，应用不会尝试绕过这些限制。"
        case .unsupportedPlatform:
            return "当前版本暂不支持该链接，或平台规则可能已变化。"
        case .permissionDenied:
            return "没有权限访问该内容或输出目录。"
        case .outputDirectoryNotWritable(let path):
            return "输出目录不可写：\(path)"
        case .networkFailure:
            return "网络连接失败，请检查网络后重试。"
        case .downloadFailed(let message):
            return "下载失败：\(message)"
        case .conversionFailed(let message):
            return "转换失败：\(message)"
        case .fileOperationDenied(let message):
            return "文件操作被拒绝：\(message)"
        case .cancelled:
            return "任务已取消。"
        case .unknown(let message):
            return message
        }
    }

    static func friendly(from error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .unknown(error.localizedDescription)
    }

    static func fromCommandFailure(stderr: String, fallback: String) -> AppError {
        let lowercased = stderr.lowercased()

        let publicAccessChallenge = [
            "confirm you're not a bot",
            "confirm you’re not a bot",
            "login_required",
            "fresh cookies",
            "too many requests",
            "http error 429",
            "http error 403",
            "cloudflare"
        ]
        if publicAccessChallenge.contains(where: lowercased.contains) {
            return .downloadFailed("平台暂时限制了公开访问，应用已自动重试，请稍后再试。")
        }

        if lowercased.contains("private video") ||
            lowercased.contains("members-only") ||
            lowercased.contains("premium-only") ||
            lowercased.contains("subscribers-only") ||
            lowercased.contains("authentication required") ||
            lowercased.contains("login required") ||
            lowercased.contains("confirm your age") ||
            lowercased.contains("age-restricted") ||
            lowercased.contains("not available in your country") {
            return .loginRequired
        }

        if lowercased.contains("unsupported url") ||
            lowercased.contains("no suitable extractor") ||
            lowercased.contains("unable to extract") {
            return .unsupportedPlatform
        }

        if lowercased.contains("network") ||
            lowercased.contains("timed out") ||
            lowercased.contains("connection") ||
            lowercased.contains("temporary failure") {
            return .networkFailure
        }

        if lowercased.contains("permission denied") {
            return .permissionDenied
        }

        let trimmed = stderr
            .split(separator: "\n")
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .downloadFailed(trimmed?.isEmpty == false ? trimmed! : fallback)
    }
}
