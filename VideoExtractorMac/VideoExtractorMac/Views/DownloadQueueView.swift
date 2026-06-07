import SwiftUI

struct DownloadQueueView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VECard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("下载队列", systemImage: "list.bullet.rectangle")
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.tasks.count) 个任务")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.tasks.isEmpty {
                    EmptyStateView(
                        title: "暂无任务",
                        systemImage: "tray",
                        description: "分析链接后，任务会加入队列。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(spacing: 10) {
                        ForEach(viewModel.tasks) { task in
                            QueueRow(
                                task: task,
                                isSelected: task.id == viewModel.selectedTaskID,
                                onSelect: { viewModel.selectTask(task.id) },
                                onPause: { viewModel.pauseTask(task.id) },
                                onResume: { viewModel.resumeTask(task.id) },
                                onCancel: { viewModel.cancelTask(task.id) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct QueueRow: View {
    var task: DownloadTask
    var isSelected: Bool
    var onSelect: () -> Void
    var onPause: () -> Void
    var onResume: () -> Void
    var onCancel: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: task.platform.symbolName)
                        .frame(width: 24)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(task.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    StatusBadge(status: task.status)

                    if task.canPause {
                        Button(action: onPause) {
                            Image(systemName: "pause.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("暂停任务")
                    }

                    if task.canResume {
                        Button(action: onResume) {
                            Image(systemName: "play.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("继续任务")
                    }

                    if task.canCancel {
                        Button(action: onCancel) {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("取消任务")
                    }
                }

                ProgressView(value: task.progress.fraction)
                    .progressViewStyle(.linear)

                HStack {
                    Text(task.progress.percentText)
                    if let speed = task.progress.speed {
                        Text(speed)
                    }
                    if let eta = task.progress.eta {
                        Text("剩余 \(eta)")
                    }
                    Spacer()
                    if let outputPath = task.outputPath {
                        Text(outputPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if let message = task.errorMessage, message.isEmpty == false {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
