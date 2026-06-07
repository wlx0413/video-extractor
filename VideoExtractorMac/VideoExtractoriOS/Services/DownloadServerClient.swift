import Foundation

enum DownloadServerClientError: LocalizedError {
    case invalidServerAddress
    case badResponse(Int, String)
    case missingDownloadedFile

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            return "服务地址无效。"
        case .badResponse(let statusCode, let message):
            return "服务返回 \(statusCode)：\(message)"
        case .missingDownloadedFile:
            return "服务没有返回可保存的文件。"
        }
    }
}

struct DownloadServerClient {
    private struct AnalyzeRequest: Encodable {
        var url: String
    }

    private struct DownloadRequest: Encodable {
        var url: String
        var kind: RemoteDownloadKind
        var mode: DownloadMode
        var customFormatID: String?
        var audioFormat: AudioOutputFormat
    }

    struct StartDownloadResponse: Decodable {
        var jobID: String
    }

    struct JobStatusResponse: Decodable, Hashable {
        var jobID: String
        var status: DownloadStatus
        var title: String?
        var progress: DownloadProgress
        var errorMessage: String?
        var fileName: String?
    }

    private let baseURL: URL
    private let session: URLSession

    init(serverAddress: String, session: URLSession = .shared) throws {
        let normalized = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            throw DownloadServerClientError.invalidServerAddress
        }

        self.baseURL = url
        self.session = session
    }

    func health() async throws -> ServerHealth {
        try await get("/api/health")
    }

    func analyze(url: URL) async throws -> MediaMetadata {
        try await post("/api/analyze", body: AnalyzeRequest(url: url.absoluteString))
    }

    func startDownload(
        url: URL,
        kind: RemoteDownloadKind,
        mode: DownloadMode,
        customFormatID: String?,
        audioFormat: AudioOutputFormat
    ) async throws -> StartDownloadResponse {
        try await post("/api/downloads", body: DownloadRequest(
            url: url.absoluteString,
            kind: kind,
            mode: mode,
            customFormatID: customFormatID,
            audioFormat: audioFormat
        ))
    }

    func jobStatus(jobID: String) async throws -> JobStatusResponse {
        try await get("/api/downloads/\(jobID)")
    }

    func downloadFile(jobID: String, fileName: String?) async throws -> URL {
        let url = endpoint("/api/downloads/\(jobID)/file")
        let (temporaryURL, response) = try await session.download(from: url)
        try validate(response: response, data: nil)

        let resolvedFileName = safeFileName(fileName ?? "\(jobID).download")
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = uniqueDestination(
            in: documentsURL.appendingPathComponent("Downloads", isDirectory: true),
            preferredFileName: resolvedFileName
        )

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        let (data, response) = try await session.data(from: endpoint(path))
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func post<Response: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: endpoint(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func endpoint(_ path: String) -> URL {
        baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = data
                .flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DownloadServerClientError.badResponse(httpResponse.statusCode, message ?? "请求失败")
        }
    }

    private var encoder: JSONEncoder {
        JSONEncoder()
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func safeFileName(_ fileName: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = fileName
            .components(separatedBy: illegal)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : cleaned
    }

    private func uniqueDestination(in directoryURL: URL, preferredFileName: String) -> URL {
        var destination = directoryURL.appendingPathComponent(preferredFileName)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return destination
        }

        let base = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        let suffix = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let fileName = ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
        destination = directoryURL.appendingPathComponent(fileName)
        return destination
    }
}
