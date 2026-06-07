import Foundation

enum URLDetector {
    static func urls(from input: String) -> [String] {
        input
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    static func validatedURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false,
              let url = components.url else {
            throw AppError.invalidURL
        }

        return url
    }

    static func detectPlatform(for url: URL) -> PlatformType {
        let host = (url.host ?? "").lowercased()

        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        }

        if host.contains("bilibili.com") || host.contains("b23.tv") {
            return .bilibili
        }

        if host.contains("xiaohongshu.com") || host.contains("xhslink.com") {
            return .xiaohongshu
        }

        if host.contains("douyin.com") || host.contains("iesdouyin.com") {
            return .douyin
        }

        return .unknown
    }
}
