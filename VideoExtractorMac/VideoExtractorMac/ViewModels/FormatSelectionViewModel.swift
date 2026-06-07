import Foundation

final class FormatSelectionViewModel: ObservableObject {
    static func preferredFormats(from formats: [MediaFormat]) -> [MediaFormat] {
        formats
            .filter { $0.kind != .unknown }
            .sorted { lhs, rhs in
                (lhs.height ?? 0, lhs.totalBitrate ?? 0, lhs.formatID) >
                    (rhs.height ?? 0, rhs.totalBitrate ?? 0, rhs.formatID)
            }
    }

    static func codecSummary(for format: MediaFormat) -> String {
        let video = format.videoCodec ?? "none"
        let audio = format.audioCodec ?? "none"
        return "V: \(video)  A: \(audio)"
    }
}
