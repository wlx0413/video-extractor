import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

actor AppLogger {
    static let shared = AppLogger()

    private let maxLogSize: UInt64 = 2_000_000
    private let fileManager = FileManager.default

    func log(_ message: String, level: LogLevel = .info) {
        let sanitized = sanitize(message)
        let line = "[\(Self.timestamp())] [\(level.rawValue)] \(sanitized)\n"
        append(line, to: logFileURL)
    }

    func command(_ executable: URL, arguments: [String]) {
        let redacted = arguments.map(redactArgument).joined(separator: " ")
        log("执行命令：\(executable.path) \(redacted)")
    }

    func commandError(_ stderr: String) {
        guard stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        log("命令错误输出：\(sanitize(stderr))", level: .error)
    }

    func fileOperation(source: URL, destination: URL, reason: String) {
        let line = "[\(Self.timestamp())] source=\(source.path) destination=\(destination.path) reason=\(sanitize(reason))\n"
        append(line, to: fileOperationsLogURL)
    }

    func readRecentLines(limit: Int = 200) -> [String] {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: false).suffix(limit).map(String.init))
    }

    private var logFileURL: URL {
        logsDirectory.appendingPathComponent("app.log")
    }

    private var fileOperationsLogURL: URL {
        logsDirectory.appendingPathComponent("file_operations.log")
    }

    private var logsDirectory: URL {
        FileManagerService.defaultWorkDirectory().appendingPathComponent("Logs", isDirectory: true)
    }

    private var deleteDirectory: URL {
        FileManagerService.defaultWorkDirectory().appendingPathComponent("要删除的", isDirectory: true)
    }

    private func append(_ line: String, to fileURL: URL) {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try rotateIfNeeded(fileURL)

            if fileManager.fileExists(atPath: fileURL.path) == false {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
            try handle.close()
        } catch {
            NSLog("AppLogger failed: %@", error.localizedDescription)
        }
    }

    private func rotateIfNeeded(_ fileURL: URL) throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard size > maxLogSize else {
            return
        }

        try fileManager.createDirectory(at: deleteDirectory, withIntermediateDirectories: true)
        let target = SafePath.uniqueDestination(
            in: deleteDirectory,
            preserving: fileURL.lastPathComponent
        )
        try fileManager.moveItem(at: fileURL, to: target)
        fileOperation(source: fileURL, destination: target, reason: "日志轮转，旧日志移动保留")
    }

    private func sanitize(_ text: String) -> String {
        var value = text
        let patterns = [
            #"(?i)(password|passwd|token|cookie|authorization)\s*[:=]\s*[^ \n\r]+"#,
            #"(?i)(--cookies-from-browser)\s+\S+"#,
            #"(?i)(--cookies)\s+\S+"#
        ]

        for pattern in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: "$1 [REDACTED]",
                options: .regularExpression
            )
        }

        return value
    }

    private func redactArgument(_ argument: String) -> String {
        let lowercased = argument.lowercased()
        if lowercased.contains("cookie") ||
            lowercased.contains("token") ||
            lowercased.contains("password") ||
            lowercased.contains("authorization") {
            return "[REDACTED]"
        }
        return argument
    }

    private static func timestamp(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
