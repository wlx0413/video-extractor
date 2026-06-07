import SwiftUI

struct HistoryView: View {
    @State private var records: [DownloadHistoryRecord] = []
    @State private var showingClearConfirmation = false
    @State private var errorMessage: String?

    private let historyService = HistoryService()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("历史记录")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    Task {
                        await loadRecords()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }

                Button {
                    showingClearConfirmation = true
                } label: {
                    Label("清理记录", systemImage: "archivebox")
                }
                .disabled(records.isEmpty)
            }

            VECard {
                if records.isEmpty {
                    EmptyStateView(
                        title: "暂无历史",
                        systemImage: "clock",
                        description: "完成或失败的任务会记录在这里。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(records) { record in
                                historyRow(record)
                            }
                        }
                    }
                    .frame(minHeight: 520)
                }
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadRecords()
        }
        .confirmationDialog("清理历史记录", isPresented: $showingClearConfirmation) {
            Button("清理历史记录", role: .destructive) {
                Task {
                    await clearHistory()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清理历史数据，不会删除任何下载文件；旧 history.json 会移动到“要删除的”。")
        }
        .alert("提示", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if $0 == false { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func historyRow(_ record: DownloadHistoryRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: record.platform.symbolName)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 5) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(record.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let outputPath = record.outputPath {
                    Text(outputPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                StatusBadge(status: record.status)
                Text(record.formatDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(record.downloadedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadRecords() async {
        records = await historyService.loadHistory()
    }

    private func clearHistory() async {
        do {
            try await historyService.clearHistory()
            await loadRecords()
        } catch {
            errorMessage = AppError.friendly(from: error).localizedDescription
        }
    }
}
