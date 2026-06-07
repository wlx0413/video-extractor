import SwiftUI

struct FormatSelectionView: View {
    @ObservedObject var viewModel: MainViewModel

    private var visibleFormats: [MediaFormat] {
        FormatSelectionViewModel.preferredFormats(from: viewModel.formats)
    }

    var body: some View {
        VECard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("格式选择", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                }

                if let metadata = viewModel.selectedMetadata {
                    metadataView(metadata)
                    controls
                    formatList
                    actionBar
                } else {
                    EmptyStateView(
                        title: "等待分析",
                        systemImage: "video.badge.magnifyingglass",
                        description: "输入链接并点击分析后，会在这里显示标题、平台和可用格式。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
        }
    }

    private func metadataView(_ metadata: MediaMetadata) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: metadata.thumbnailURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 168, height: 94)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Text(metadata.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Label(metadata.platform.displayName, systemImage: metadata.platform.symbolName)
                    if let author = metadata.author, author.isEmpty == false {
                        Label(author, systemImage: "person.crop.circle")
                    }
                    Label(metadata.displayDuration, systemImage: "timer")
                    if metadata.imageURLs.isEmpty == false {
                        Label("\(metadata.imageURLs.count) 张图片", systemImage: "photo.on.rectangle")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                Text("视频规格")
                    .foregroundStyle(.secondary)
                Picker("视频规格", selection: $viewModel.selectedMode) {
                    ForEach(DownloadMode.allCases.filter { $0 != .audioOnly }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Text("音频格式")
                    .foregroundStyle(.secondary)
                Picker("音频格式", selection: $viewModel.selectedAudioFormat) {
                    ForEach(AudioOutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
        }
    }

    private var formatList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("可用格式")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(visibleFormats.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List(selection: $viewModel.selectedFormatID) {
                ForEach(visibleFormats) { format in
                    FormatRow(format: format)
                        .tag(format.formatID)
                }
            }
            .frame(minHeight: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .opacity(viewModel.selectedMode == .custom ? 1 : 0.55)
    }

    private var actionBar: some View {
        HStack {
            Spacer()

            if viewModel.selectedMetadata?.platform == .xiaohongshu {
                Button {
                    Task {
                        await viewModel.downloadSelectedImages()
                    }
                } label: {
                    Label("下载图片", systemImage: "photo.on.rectangle.angled")
                }
            }

            Button {
                Task {
                    await viewModel.downloadSelectedAudio()
                }
            } label: {
                Label("仅音频", systemImage: "waveform")
            }

            Button {
                Task {
                    await viewModel.downloadSelectedVideo()
                }
            } label: {
                Label("下载视频", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct FormatRow: View {
    var format: MediaFormat

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(format.summary)
                    .font(.subheadline.weight(.semibold))
                Text(FormatSelectionViewModel.codecSummary(for: format))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(format.kind.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            Text(format.displayFPS)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Text(format.displaySize)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
