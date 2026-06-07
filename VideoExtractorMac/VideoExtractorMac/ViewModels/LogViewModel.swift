import Foundation

@MainActor
final class LogViewModel: ObservableObject {
    @Published var lines: [String] = []

    func refresh() {
        Task {
            lines = await AppLogger.shared.readRecentLines(limit: 200)
        }
    }
}
