import Foundation

final class HistoryService {
    private let fileService: FileManagerService
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileService: FileManagerService = .shared) {
        self.fileService = fileService
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    private var historyURL: URL {
        fileService.historyDirectory.appendingPathComponent("history.json")
    }

    func loadHistory() async -> [DownloadHistoryRecord] {
        guard let data = try? Data(contentsOf: historyURL) else {
            return []
        }
        return (try? decoder.decode([DownloadHistoryRecord].self, from: data)) ?? []
    }

    func append(_ record: DownloadHistoryRecord) async {
        do {
            try fileService.prepareDirectories()
            var records = await loadHistory()
            records.insert(record, at: 0)
            let data = try encoder.encode(records)
            try data.write(to: historyURL)
        } catch {
            await AppLogger.shared.log("写入历史记录失败：\(error.localizedDescription)", level: .error)
        }
    }

    func clearHistory() async throws {
        try fileService.prepareDirectories()

        if FileManager.default.fileExists(atPath: historyURL.path) {
            _ = try fileService.moveToDeleteFolder(historyURL, reason: "用户清理下载历史，旧 history.json 移动保留")
        }

        let data = try encoder.encode([DownloadHistoryRecord]())
        try data.write(to: historyURL)
    }
}
