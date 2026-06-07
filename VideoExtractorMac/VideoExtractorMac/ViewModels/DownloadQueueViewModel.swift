import Foundation

@MainActor
final class DownloadQueueViewModel: ObservableObject {
    @Published var tasks: [DownloadTask] = []

    var activeTasks: [DownloadTask] {
        tasks.filter { $0.status == .analyzing || $0.status == .downloading || $0.status == .converting }
    }

    var finishedTasks: [DownloadTask] {
        tasks.filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }
}
