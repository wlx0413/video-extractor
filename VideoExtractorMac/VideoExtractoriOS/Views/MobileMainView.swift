import SwiftUI

struct MobileMainView: View {
    @StateObject private var viewModel = MobileMainViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    serverSection
                    inputSection
                    optionsSection
                    metadataSection
                    taskSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("视频提取器")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.checkServer() }
                    } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    .accessibilityLabel("检查服务")
                }
            }
            .task {
                await viewModel.checkServer()
            }
            .alert("提示", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if $0 == false { viewModel.errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("下载服务", systemImage: viewModel.isServerOnline ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(viewModel.isServerOnline ? .green : .orange)
                .font(.headline)

            TextField("http://电脑IP:8765", text: $viewModel.serverAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            Text(viewModel.serverMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .sectionBox()
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("链接", systemImage: "link")
                .font(.headline)

            TextEditor(text: $viewModel.urlText)
                .frame(minHeight: 118)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator).opacity(0.35))
                )

            HStack {
                Button {
                    Task { await viewModel.analyzeLinks() }
                } label: {
                    Label("分析", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isWorking)

                Button {
                    Task { await viewModel.downloadSelected() }
                } label: {
                    Label("下载", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isWorking)
            }
        }
        .sectionBox()
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("类型", selection: $viewModel.selectedKind) {
                ForEach(RemoteDownloadKind.allCases) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.selectedKind == .video {
                Picker("清晰度", selection: $viewModel.selectedMode) {
                    ForEach([DownloadMode.best, .video1080p, .video720p, .video480p]) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            if viewModel.selectedKind == .audio {
                Picker("格式", selection: $viewModel.selectedAudioFormat) {
                    ForEach(AudioOutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .sectionBox()
    }

    @ViewBuilder
    private var metadataSection: some View {
        if let metadata = viewModel.selectedMetadata {
            VStack(alignment: .leading, spacing: 10) {
                Label(metadata.platform.displayName, systemImage: metadata.platform.symbolName)
                    .font(.headline)

                Text(metadata.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)

                HStack {
                    if let author = metadata.author, author.isEmpty == false {
                        Label(author, systemImage: "person")
                    }
                    Label(metadata.displayDuration, systemImage: "timer")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionBox()
        }
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("队列", systemImage: "tray.full")
                .font(.headline)

            if viewModel.tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("暂无任务")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.tasks) { task in
                        MobileTaskRow(task: task) {
                            viewModel.selectTask(task.id)
                        }
                    }
                }
            }
        }
        .sectionBox()
    }
}

private struct MobileTaskRow: View {
    var task: MobileDownloadItem
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(task.platform.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(task.status.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }

                ProgressView(value: task.progress.fraction)
                    .tint(statusColor)

                HStack {
                    Text(task.progress.percentText)
                    if let speed = task.progress.speed {
                        Text(speed)
                    }
                    if let eta = task.progress.eta {
                        Text("ETA \(eta)")
                    }
                    Spacer()
                    if let fileURL = task.outputFileURL {
                        ShareLink(item: fileURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let errorMessage = task.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch task.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .paused, .cancelled:
            return .orange
        case .analyzing, .downloading, .converting:
            return .blue
        default:
            return .secondary
        }
    }
}

private extension View {
    func sectionBox() -> some View {
        self
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator).opacity(0.2))
            )
    }
}
